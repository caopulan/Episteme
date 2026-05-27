import Darwin
import Foundation

public struct PaperCodexMCPEndpoint: Codable, Equatable, Sendable {
    public var url: String
    public var healthURL: String
    public var host: String
    public var port: Int
    public var token: String
    public var authorizationHeader: String
    public var metadataPath: String

    public init(url: String, healthURL: String, host: String, port: Int, token: String, authorizationHeader: String, metadataPath: String) {
        self.url = url
        self.healthURL = healthURL
        self.host = host
        self.port = port
        self.token = token
        self.authorizationHeader = authorizationHeader
        self.metadataPath = metadataPath
    }
}

public enum PaperCodexMCPServerError: Error, CustomStringConvertible, Equatable {
    case couldNotBind
    case socketFailed(String)
    case invalidRequest
    case unauthorized

    public var description: String {
        switch self {
        case .couldNotBind:
            "Could not bind Paper Codex MCP server to a localhost port."
        case let .socketFailed(message):
            "Paper Codex MCP server socket failed: \(message)"
        case .invalidRequest:
            "Invalid HTTP request."
        case .unauthorized:
            "Missing or invalid Paper Codex MCP token."
        }
    }
}

public final class PaperCodexMCPServer: @unchecked Sendable {
    private let service: PaperCodexMCPService
    private let supportRoot: URL
    private let queue = DispatchQueue(label: "PaperCodexMCPServer", qos: .utility)
    private let clientQueue = DispatchQueue(label: "PaperCodexMCPServer.clients", qos: .utility, attributes: .concurrent)
    private let encoder = JSONEncoder()
    private var socketFD: Int32 = -1
    private var running = false
    private var endpoint: PaperCodexMCPEndpoint?

    public init(service: PaperCodexMCPService, supportRoot: URL) {
        self.service = service
        self.supportRoot = supportRoot
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    deinit {
        stop()
    }

    @discardableResult
    public func start(preferredPort: Int = 39427, token: String? = nil) throws -> PaperCodexMCPEndpoint {
        if let endpoint {
            return endpoint
        }
        let chosenToken = token ?? Self.makeToken()
        let (fd, port) = try bindSocket(preferredPort: preferredPort)
        socketFD = fd
        running = true

        let metadataURL = supportRoot.appendingPathComponent("mcp/server.json")
        let endpoint = PaperCodexMCPEndpoint(
            url: "http://127.0.0.1:\(port)/mcp",
            healthURL: "http://127.0.0.1:\(port)/health",
            host: "127.0.0.1",
            port: port,
            token: chosenToken,
            authorizationHeader: "Bearer \(chosenToken)",
            metadataPath: metadataURL.path
        )
        self.endpoint = endpoint
        try writeEndpointMetadata(endpoint)

        queue.async { [weak self] in
            self?.acceptLoop(token: chosenToken)
        }
        return endpoint
    }

    public func stop() {
        running = false
        if socketFD >= 0 {
            shutdown(socketFD, SHUT_RDWR)
            close(socketFD)
            socketFD = -1
        }
        endpoint = nil
    }

    private func bindSocket(preferredPort: Int) throws -> (Int32, Int) {
        for port in preferredPort..<(preferredPort + 20) {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw PaperCodexMCPServerError.socketFailed(String(cString: strerror(errno)))
            }

            var reuse: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = UInt16(port).bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0 else {
                close(fd)
                continue
            }
            guard listen(fd, SOMAXCONN) == 0 else {
                close(fd)
                continue
            }
            return (fd, port)
        }
        throw PaperCodexMCPServerError.couldNotBind
    }

    private func acceptLoop(token: String) {
        while running, socketFD >= 0 {
            var address = sockaddr()
            var length = socklen_t(MemoryLayout<sockaddr>.size)
            let client = Darwin.accept(socketFD, &address, &length)
            guard client >= 0 else {
                if running {
                    continue
                }
                return
            }
            clientQueue.async { [weak self] in
                self?.handleClient(client, token: token)
            }
        }
    }

    private func handleClient(_ client: Int32, token: String) {
        defer { close(client) }
        do {
            let request = try readHTTPRequest(from: client)
            let response: HTTPResponse
            switch (request.method, request.path) {
            case ("GET", "/health"):
                response = try jsonResponse([
                    "status": "ok",
                    "server": "paper-codex",
                    "endpoint": endpoint?.url ?? ""
                ])
            case ("GET", "/mcp"):
                response = try jsonResponse([
                    "name": "paper-codex",
                    "transport": "streamable-http-compatible-json-rpc",
                    "method": "POST",
                    "authorization": "Bearer token required"
                ])
            case ("POST", "/mcp"):
                try authorize(request: request, token: token)
                let body = try service.handleJSONRPCData(request.body)
                response = HTTPResponse(status: "200 OK", contentType: "application/json", body: body)
            default:
                response = try jsonResponse(["error": "not_found"], status: "404 Not Found")
            }
            try write(response, to: client)
        } catch PaperCodexMCPServerError.unauthorized {
            try? write(jsonResponseNoThrow(["error": "unauthorized"], status: "401 Unauthorized"), to: client)
        } catch {
            try? write(jsonResponseNoThrow(["error": String(describing: error)], status: "500 Internal Server Error"), to: client)
        }
    }

    private func authorize(request: HTTPRequest, token: String) throws {
        let authorization = request.headers["authorization"] ?? ""
        let headerToken = request.headers["x-papercodex-mcp-token"] ?? ""
        guard authorization == "Bearer \(token)" || headerToken == token else {
            throw PaperCodexMCPServerError.unauthorized
        }
    }

    private func readHTTPRequest(from client: Int32) throws -> HTTPRequest {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var expectedBodyLength: Int?

        while true {
            let count = Darwin.read(client, &buffer, buffer.count)
            guard count > 0 else {
                break
            }
            data.append(buffer, count: count)
            if expectedBodyLength == nil,
               let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = data[..<headerEnd.lowerBound]
                let headerText = String(decoding: headerData, as: UTF8.self)
                let headers = parseHeaders(headerText)
                expectedBodyLength = Int(headers["content-length"] ?? "0") ?? 0
            }
            if let expectedBodyLength,
               let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) {
                let bodyStart = headerEnd.upperBound
                if data.count - bodyStart >= expectedBodyLength {
                    break
                }
            }
        }

        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            throw PaperCodexMCPServerError.invalidRequest
        }
        let headerText = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw PaperCodexMCPServerError.invalidRequest
        }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else {
            throw PaperCodexMCPServerError.invalidRequest
        }
        let headers = parseHeaders(headerText)
        let body = Data(data[headerEnd.upperBound...])
        return HTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
            body: body
        )
    }

    private func parseHeaders(_ headerText: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }
        return headers
    }

    private func write(_ response: HTTPResponse, to client: Int32) throws {
        var headers = Data()
        headers.append("HTTP/1.1 \(response.status)\r\n".data(using: .utf8)!)
        headers.append("Content-Type: \(response.contentType)\r\n".data(using: .utf8)!)
        headers.append("Content-Length: \(response.body.count)\r\n".data(using: .utf8)!)
        headers.append("Connection: close\r\n\r\n".data(using: .utf8)!)
        let payload = headers + response.body
        try payload.withUnsafeBytes { pointer in
            guard let base = pointer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }
            var written = 0
            while written < payload.count {
                let count = Darwin.write(client, base.advanced(by: written), payload.count - written)
                guard count > 0 else {
                    throw PaperCodexMCPServerError.socketFailed(String(cString: strerror(errno)))
                }
                written += count
            }
        }
    }

    private func jsonResponse(_ object: Any, status: String = "200 OK") throws -> HTTPResponse {
        let body = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return HTTPResponse(status: status, contentType: "application/json", body: body)
    }

    private func jsonResponseNoThrow(_ object: Any, status: String) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, contentType: "application/json", body: body)
    }

    private func writeEndpointMetadata(_ endpoint: PaperCodexMCPEndpoint) throws {
        let metadataURL = URL(fileURLWithPath: endpoint.metadataPath)
        try FileManager.default.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(endpoint)
        try data.write(to: metadataURL, options: [.atomic])
    }

    private static func makeToken() -> String {
        (0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }.joined()
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}

private struct HTTPResponse {
    var status: String
    var contentType: String
    var body: Data
}
