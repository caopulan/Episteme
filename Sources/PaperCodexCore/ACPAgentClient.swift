import Foundation

public struct ACPAgentPromptResult: Sendable {
    public var finalText: String
    public var sessionID: String
    public var stopReason: String
    public var transcript: String

    public init(finalText: String, sessionID: String, stopReason: String, transcript: String) {
        self.finalText = finalText
        self.sessionID = sessionID
        self.stopReason = stopReason
        self.transcript = transcript
    }
}

public enum ACPAgentClientError: Error, CustomStringConvertible, Equatable {
    case processNotRunning
    case invalidJSON(String)
    case missingResult(String)
    case requestFailed(String)
    case protocolMismatch(returned: Int, expected: Int)
    case missingSessionID
    case requestTimedOut(String)
    case processExited(String)
    case unsupportedClientRequest(String)
    case invalidPath(String)
    case fileNotFound(String)
    case invalidTerminal(String)

    public var description: String {
        switch self {
        case .processNotRunning:
            "ACP subprocess is not running"
        case let .invalidJSON(detail):
            "ACP subprocess emitted invalid JSON: \(detail)"
        case let .missingResult(method):
            "ACP \(method) response did not include a result"
        case let .requestFailed(detail):
            detail
        case let .protocolMismatch(returned, expected):
            "ACP protocol version mismatch: returned \(returned), expected \(expected)"
        case .missingSessionID:
            "ACP session/new did not return a sessionId"
        case let .requestTimedOut(method):
            "ACP request timed out: \(method)"
        case let .processExited(stderr):
            "ACP subprocess exited before completing the request. Stderr tail: \(stderr)"
        case let .unsupportedClientRequest(method):
            "Unsupported ACP client request: \(method)"
        case let .invalidPath(detail):
            detail
        case let .fileNotFound(path):
            "ACP requested missing file: \(path)"
        case let .invalidTerminal(detail):
            detail
        }
    }
}

public final class ACPAgentClient: @unchecked Sendable {
    public static let protocolVersion = 1

    private let command: AgentRuntimeCommand
    private let workspaceURL: URL
    private let readRoots: [URL]
    private let writeRoots: [URL]
    private let mcpServers: [CodexMCPServerConfig]
    private let timeoutSeconds: TimeInterval
    private let runHandle: AgentRunHandle?
    private let fileManager: FileManager
    private let queue = ACPMessageQueue()
    private let stderrTail = ACPTailBuffer(limit: 4_000)
    private let transcript = ACPTailBuffer(limit: 2_000_000)
    private let writeLock = NSLock()
    private let stateLock = NSLock()
    private var process: Process?
    private var standardInput: Pipe?
    private var requestID = 0
    private var sessionID = ""
    private var finalText = ""
    private var terminals: [String: ACPTerminalProcess] = [:]
    private var terminalIndex = 0

    public init(
        command: AgentRuntimeCommand,
        workspaceURL: URL,
        readRoots: [URL] = [],
        writeRoots: [URL] = [],
        mcpServers: [CodexMCPServerConfig] = [],
        timeoutSeconds: TimeInterval = 120,
        runHandle: AgentRunHandle? = nil,
        fileManager: FileManager = .default
    ) {
        self.command = command
        self.workspaceURL = workspaceURL.standardizedFileURL
        self.readRoots = ([workspaceURL] + readRoots).map(\.standardizedFileURL)
        self.writeRoots = (writeRoots.isEmpty ? [workspaceURL] : writeRoots).map(\.standardizedFileURL)
        self.mcpServers = mcpServers
        self.timeoutSeconds = timeoutSeconds
        self.runHandle = runHandle
        self.fileManager = fileManager
    }

    public func runPrompt(
        _ prompt: String,
        onEvent: @escaping @Sendable (AgentRunEvent) -> Void = { _ in }
    ) throws -> ACPAgentPromptResult {
        try startProcess()
        defer {
            close()
        }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        let initialize = try request(
            method: "initialize",
            params: [
                "protocolVersion": Self.protocolVersion,
                "clientCapabilities": [
                    "fs": [
                        "readTextFile": true,
                        "writeTextFile": true
                    ],
                    "terminal": true
                ],
                "clientInfo": [
                    "name": "episteme",
                    "title": "Episteme",
                    "version": "0.1.0"
                ]
            ],
            deadline: deadline,
            onEvent: onEvent
        )
        let returnedProtocol = initialize["protocolVersion"] as? Int
            ?? (initialize["protocolVersion"] as? NSNumber)?.intValue
            ?? 0
        guard returnedProtocol == Self.protocolVersion else {
            throw ACPAgentClientError.protocolMismatch(returned: returnedProtocol, expected: Self.protocolVersion)
        }

        let session = try request(
            method: "session/new",
            params: [
                "cwd": workspaceURL.path,
                "mcpServers": acpMCPServers()
            ],
            deadline: deadline,
            onEvent: onEvent
        )
        guard let newSessionID = session["sessionId"] as? String, !newSessionID.isEmpty else {
            throw ACPAgentClientError.missingSessionID
        }
        setSessionID(newSessionID)

        let response = try request(
            method: "session/prompt",
            params: [
                "sessionId": newSessionID,
                "prompt": [
                    [
                        "type": "text",
                        "text": prompt
                    ]
                ]
            ],
            deadline: deadline,
            onEvent: onEvent
        )
        let stopReason = response["stopReason"] as? String ?? ""
        return ACPAgentPromptResult(
            finalText: currentFinalText(),
            sessionID: newSessionID,
            stopReason: stopReason,
            transcript: transcript.text()
        )
    }

    public func close() {
        let currentSessionID = currentSessionID()
        if !currentSessionID.isEmpty {
            _ = try? request(
                method: "session/close",
                params: ["sessionId": currentSessionID],
                deadline: Date().addingTimeInterval(2),
                onEvent: { _ in }
            )
        }
        stateLock.lock()
        let process = self.process
        let terminals = self.terminals
        self.terminals.removeAll()
        stateLock.unlock()

        for terminal in terminals.values {
            terminal.terminate()
        }
        if let standardInput {
            try? standardInput.fileHandleForWriting.close()
        }
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        if let process {
            runHandle?.clearProcess(process)
        }
    }

    private func startProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments
        let workingDirectoryURL = command.currentDirectoryPath
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? workspaceURL
        process.currentDirectoryURL = workingDirectoryURL.standardizedFileURL
        process.environment = AgentRuntimeEnvironment.sanitizedProcessEnvironment(
            workingDirectoryURL: workingDirectoryURL.standardizedFileURL,
            executablePath: command.executablePath,
            environmentOverrides: command.environmentOverrides
        )

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        try process.run()
        runHandle?.setProcess(process)

        self.process = process
        standardInput = input
        startReader(handle: output.fileHandleForReading)
        startStderrReader(handle: error.fileHandleForReading)
    }

    private func request(
        method: String,
        params: [String: Any],
        deadline: Date,
        onEvent: @escaping @Sendable (AgentRunEvent) -> Void
    ) throws -> [String: Any] {
        let requestID = nextRequestID()
        try send([
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": params
        ])
        while Date() < deadline {
            switch queue.pop(timeout: min(0.2, max(0.01, deadline.timeIntervalSinceNow))) {
            case .none:
                if process?.isRunning == false {
                    throw ACPAgentClientError.processExited(stderrTail.text())
                }
                continue
            case let .invalid(detail):
                throw ACPAgentClientError.invalidJSON(detail)
            case .eof:
                throw ACPAgentClientError.processExited(stderrTail.text())
            case let .message(message):
                if let messageMethod = message["method"] as? String {
                    if message["id"] != nil {
                        try handleAgentRequest(message, method: messageMethod, deadline: deadline, onEvent: onEvent)
                    } else {
                        handleNotification(message, method: messageMethod, onEvent: onEvent)
                    }
                    continue
                }
                guard idsEqual(message["id"], requestID) else {
                    continue
                }
                if let error = message["error"] as? [String: Any] {
                    let detail = error["message"] as? String ?? String(describing: error)
                    throw ACPAgentClientError.requestFailed("ACP \(method) failed: \(detail)")
                }
                guard let result = message["result"] else {
                    throw ACPAgentClientError.missingResult(method)
                }
                return result as? [String: Any] ?? [:]
            }
        }
        try? send([
            "jsonrpc": "2.0",
            "method": "session/cancel",
            "params": ["sessionId": currentSessionID()]
        ])
        throw ACPAgentClientError.requestTimedOut(method)
    }

    private func handleAgentRequest(
        _ message: [String: Any],
        method: String,
        deadline: Date,
        onEvent: @escaping @Sendable (AgentRunEvent) -> Void
    ) throws {
        let requestID = message["id"] ?? NSNull()
        let params = message["params"] as? [String: Any] ?? [:]
        do {
            let result: Any
            switch method {
            case "fs/read_text_file":
                result = try readTextFile(params)
            case "fs/write_text_file":
                result = try writeTextFile(params)
            case "session/request_permission":
                result = selectPermission(params)
            case "terminal/create":
                result = try createTerminal(params)
            case "terminal/output":
                result = try terminalOutput(params)
            case "terminal/wait_for_exit":
                result = try terminalWaitForExit(params, deadline: deadline)
            case "terminal/kill":
                result = try terminalKill(params)
            case "terminal/release":
                result = try terminalRelease(params)
            default:
                throw ACPAgentClientError.unsupportedClientRequest(method)
            }
            try send([
                "jsonrpc": "2.0",
                "id": requestID,
                "result": result
            ])
        } catch {
            try send([
                "jsonrpc": "2.0",
                "id": requestID,
                "error": [
                    "code": -32603,
                    "message": String(describing: error)
                ]
            ])
        }
    }

    private func handleNotification(
        _ message: [String: Any],
        method: String,
        onEvent: @escaping @Sendable (AgentRunEvent) -> Void
    ) {
        guard method == "session/update",
              let params = message["params"] as? [String: Any],
              let update = params["update"] as? [String: Any],
              let updateKind = update["sessionUpdate"] as? String else {
            return
        }
        switch updateKind {
        case "agent_message_chunk":
            let text = textContent(from: update["content"])
            appendFinalText(text)
            if !text.isEmpty {
                onEvent(CodexRunEvent(kind: .answer, title: "ACP", detail: text))
            }
        case "agent_thought_chunk":
            let text = textContent(from: update["content"])
            if !text.isEmpty {
                onEvent(CodexRunEvent(kind: .thinking, title: "ACP", detail: text))
            }
        case "tool_call", "tool_call_update":
            let title = update["title"] as? String ?? "ACP tool"
            let detail = compactJSONString(update) ?? updateKind
            onEvent(CodexRunEvent(kind: .tool, title: title, detail: detail))
        default:
            break
        }
    }

    private func readTextFile(_ params: [String: Any]) throws -> [String: String] {
        let url = try resolveAllowedPath(params["path"], roots: readRoots, operation: "read")
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw ACPAgentClientError.fileNotFound(url.path)
        }
        var content = try String(contentsOf: url, encoding: .utf8)
        if params["line"] != nil || params["limit"] != nil {
            let start = max(0, (intValue(params["line"]) ?? 1) - 1)
            let limit = intValue(params["limit"])
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let end = limit.map { min(lines.count, start + max(0, $0)) } ?? lines.count
            content = start < lines.count ? lines[start..<end].joined(separator: "\n") : ""
        }
        return ["content": content]
    }

    private func writeTextFile(_ params: [String: Any]) throws -> [String: Any] {
        let url = try resolveAllowedPath(params["path"], roots: writeRoots, operation: "write")
        guard let content = params["content"] as? String else {
            throw ACPAgentClientError.invalidPath("ACP write content must be a string")
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return [:]
    }

    private func selectPermission(_ params: [String: Any]) -> [String: Any] {
        let options = params["options"] as? [[String: Any]] ?? []
        let selected = options.first { option in
            (option["kind"] as? String)?.hasPrefix("allow") == true
        } ?? options.first
        guard let optionID = selected?["optionId"] as? String, !optionID.isEmpty else {
            return ["outcome": ["outcome": "cancelled"]]
        }
        return ["outcome": ["outcome": "selected", "optionId": optionID]]
    }

    private func createTerminal(_ params: [String: Any]) throws -> [String: String] {
        guard let command = params["command"] as? String, !command.isEmpty else {
            throw ACPAgentClientError.invalidTerminal("terminal/create command is required")
        }
        let args = params["args"] as? [String] ?? []
        let cwd = try resolveAllowedPath(params["cwd"] ?? workspaceURL.path, roots: readRoots, operation: "terminal cwd")
        let outputLimit = intValue(params["outputByteLimit"]) ?? 1_048_576
        let terminal = try ACPTerminalProcess(
            command: command,
            arguments: args,
            workingDirectoryURL: cwd,
            environment: terminalEnvironment(params["env"]),
            outputByteLimit: outputLimit
        )
        stateLock.lock()
        terminalIndex += 1
        let terminalID = "term_\(terminalIndex)"
        terminals[terminalID] = terminal
        stateLock.unlock()
        return ["terminalId": terminalID]
    }

    private func terminalOutput(_ params: [String: Any]) throws -> [String: Any] {
        let terminal = try requireTerminal(params)
        var result: [String: Any] = [
            "output": terminal.outputSnapshot().output,
            "truncated": terminal.outputSnapshot().truncated
        ]
        if let status = terminal.exitStatus() {
            result["exitStatus"] = status
        }
        return result
    }

    private func terminalWaitForExit(_ params: [String: Any], deadline: Date) throws -> [String: Any] {
        let terminal = try requireTerminal(params)
        while terminal.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard let status = terminal.exitStatus() else {
            throw ACPAgentClientError.requestTimedOut("terminal/wait_for_exit")
        }
        return status
    }

    private func terminalKill(_ params: [String: Any]) throws -> [String: Any] {
        try requireTerminal(params).terminate()
        return [:]
    }

    private func terminalRelease(_ params: [String: Any]) throws -> [String: Any] {
        let terminalID = try terminalID(from: params)
        stateLock.lock()
        let terminal = terminals.removeValue(forKey: terminalID)
        stateLock.unlock()
        guard let terminal else {
            throw ACPAgentClientError.invalidTerminal("unknown terminalId: \(terminalID)")
        }
        terminal.terminate()
        return [:]
    }

    private func requireTerminal(_ params: [String: Any]) throws -> ACPTerminalProcess {
        let terminalID = try terminalID(from: params)
        stateLock.lock()
        let terminal = terminals[terminalID]
        stateLock.unlock()
        guard let terminal else {
            throw ACPAgentClientError.invalidTerminal("unknown terminalId: \(terminalID)")
        }
        return terminal
    }

    private func terminalID(from params: [String: Any]) throws -> String {
        guard let terminalID = params["terminalId"] as? String, !terminalID.isEmpty else {
            throw ACPAgentClientError.invalidTerminal("terminalId is required")
        }
        return terminalID
    }

    private func terminalEnvironment(_ raw: Any?) -> [String: String] {
        let variables = raw as? [[String: Any]] ?? []
        return variables.reduce(into: [:]) { result, variable in
            guard let name = variable["name"] as? String, !name.isEmpty else {
                return
            }
            result[name] = variable["value"] as? String ?? ""
        }
    }

    private func send(_ payload: [String: Any]) throws {
        guard let process, process.isRunning, let standardInput else {
            throw ACPAgentClientError.processNotRunning
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        transcript.append("--> \(String(decoding: data, as: UTF8.self))\n")
        writeLock.lock()
        defer { writeLock.unlock() }
        standardInput.fileHandleForWriting.write(data)
        standardInput.fileHandleForWriting.write(Data("\n".utf8))
    }

    private func startReader(handle: FileHandle) {
        DispatchQueue.global(qos: .userInitiated).async { [queue, transcript] in
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    break
                }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 10) {
                    let lineData = buffer[..<newline]
                    buffer.removeSubrange(...newline)
                    guard !lineData.isEmpty else {
                        continue
                    }
                    let line = String(decoding: lineData, as: UTF8.self)
                    transcript.append("<-- \(line)\n")
                    guard let data = line.data(using: .utf8) else {
                        queue.push(.invalid(line))
                        continue
                    }
                    do {
                        guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            queue.push(.invalid(line))
                            continue
                        }
                        queue.push(.message(message))
                    } catch {
                        queue.push(.invalid("\(error): \(line)"))
                    }
                }
            }
            queue.push(.eof)
        }
    }

    private func startStderrReader(handle: FileHandle) {
        DispatchQueue.global(qos: .utility).async { [stderrTail, transcript] in
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    break
                }
                let text = String(decoding: chunk, as: UTF8.self)
                stderrTail.append(text)
                transcript.append("<e \(text)")
            }
        }
    }

    private func resolveAllowedPath(_ raw: Any?, roots: [URL], operation: String) throws -> URL {
        guard let pathValue = raw as? String, !pathValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ACPAgentClientError.invalidPath("ACP \(operation) path must be a string")
        }
        let expanded = expandHome(pathValue)
        let candidate = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : workspaceURL.appendingPathComponent(expanded)
        let standardized = candidate.standardizedFileURL
        guard roots.contains(where: { standardized.isInside($0) }) else {
            throw ACPAgentClientError.invalidPath("ACP \(operation) path is outside allowed roots: \(standardized.path)")
        }
        return standardized
    }

    private func acpMCPServers() -> [[String: Any]] {
        mcpServers.map { server in
            [
                "name": server.name,
                "type": "http",
                "url": server.url,
                "headers": [
                    [
                        "name": "Authorization",
                        "value": "Bearer \(server.bearerToken)"
                    ]
                ]
            ]
        }
    }

    private func nextRequestID() -> Int {
        stateLock.lock()
        requestID += 1
        let next = requestID
        stateLock.unlock()
        return next
    }

    private func setSessionID(_ value: String) {
        stateLock.lock()
        sessionID = value
        stateLock.unlock()
    }

    private func currentSessionID() -> String {
        stateLock.lock()
        let value = sessionID
        stateLock.unlock()
        return value
    }

    private func appendFinalText(_ text: String) {
        stateLock.lock()
        finalText += text
        stateLock.unlock()
    }

    private func currentFinalText() -> String {
        stateLock.lock()
        let value = finalText
        stateLock.unlock()
        return value
    }

    private func textContent(from raw: Any?) -> String {
        if let content = raw as? [String: Any], content["type"] as? String == "text" {
            return content["text"] as? String ?? ""
        }
        if let chunks = raw as? [[String: Any]] {
            return chunks.compactMap { textContent(from: $0) }.joined()
        }
        return ""
    }

    private func compactJSONString(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func idsEqual(_ lhs: Any?, _ rhs: Int) -> Bool {
        if let lhs = lhs as? Int {
            return lhs == rhs
        }
        if let lhs = lhs as? NSNumber {
            return lhs.intValue == rhs
        }
        if let lhs = lhs as? String {
            return lhs == String(rhs)
        }
        return false
    }

    private func intValue(_ raw: Any?) -> Int? {
        if let int = raw as? Int {
            return int
        }
        if let number = raw as? NSNumber {
            return number.intValue
        }
        if let string = raw as? String {
            return Int(string)
        }
        return nil
    }

    private func expandHome(_ path: String) -> String {
        guard path.hasPrefix("~/") else {
            return path
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(String(path.dropFirst(2)))
            .path
    }
}

private enum ACPInboundMessage {
    case message([String: Any])
    case invalid(String)
    case eof
}

private final class ACPMessageQueue: @unchecked Sendable {
    private let condition = NSCondition()
    private var messages: [ACPInboundMessage] = []

    func push(_ message: ACPInboundMessage) {
        condition.lock()
        messages.append(message)
        condition.signal()
        condition.unlock()
    }

    func pop(timeout: TimeInterval) -> ACPInboundMessage? {
        condition.lock()
        defer { condition.unlock() }
        if messages.isEmpty {
            condition.wait(until: Date().addingTimeInterval(timeout))
        }
        guard !messages.isEmpty else {
            return nil
        }
        return messages.removeFirst()
    }
}

private final class ACPTailBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var value = ""

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ text: String) {
        lock.lock()
        value += text
        if value.utf8.count > limit {
            value = String(value.suffix(limit))
        }
        lock.unlock()
    }

    func text() -> String {
        lock.lock()
        let snapshot = value
        lock.unlock()
        return snapshot
    }
}

private final class ACPTerminalProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let outputByteLimit: Int
    private var output = ""
    private var truncated = false

    init(
        command: String,
        arguments: [String],
        workingDirectoryURL: URL,
        environment: [String: String],
        outputByteLimit: Int
    ) throws {
        self.outputByteLimit = outputByteLimit
        process = Process()
        let executableAndArguments = Self.executableAndArguments(command: command, arguments: arguments)
        process.executableURL = URL(fileURLWithPath: executableAndArguments.executable)
        process.arguments = executableAndArguments.arguments
        process.currentDirectoryURL = workingDirectoryURL
        process.environment = AgentRuntimeEnvironment.sanitizedProcessEnvironment(
            workingDirectoryURL: workingDirectoryURL,
            executablePath: executableAndArguments.executable,
            environmentOverrides: environment
        )
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let data = outputPipe.fileHandleForReading.availableData
                if data.isEmpty {
                    break
                }
                self?.append(String(decoding: data, as: UTF8.self))
            }
        }
    }

    var isRunning: Bool {
        process.isRunning
    }

    func outputSnapshot() -> (output: String, truncated: Bool) {
        lock.lock()
        let snapshot = (output, truncated)
        lock.unlock()
        return snapshot
    }

    func exitStatus() -> [String: Any]? {
        guard !process.isRunning else {
            return nil
        }
        let status = process.terminationStatus
        if status < 0 {
            return ["exitCode": NSNull(), "signal": String(-status)]
        }
        return ["exitCode": Int(status), "signal": NSNull()]
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }

    private func append(_ text: String) {
        lock.lock()
        output += text
        if output.utf8.count > outputByteLimit {
            truncated = true
            output = String(output.suffix(outputByteLimit))
        }
        lock.unlock()
    }

    private static func executableAndArguments(command: String, arguments: [String]) -> (executable: String, arguments: [String]) {
        if arguments.isEmpty && command.range(of: #"\s|[;&|<>$`]"#, options: .regularExpression) != nil {
            return ("/bin/sh", ["-lc", command])
        }
        if command.hasPrefix("/") {
            return (command, arguments)
        }
        return ("/usr/bin/env", [command] + arguments)
    }
}

private extension URL {
    func isInside(_ root: URL) -> Bool {
        let path = standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}
