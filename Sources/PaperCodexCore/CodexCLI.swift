import Foundation

public enum CodexCLIError: Error, CustomStringConvertible, Equatable {
    case executableNotFound
    case processFailed(status: Int32, stderr: String)

    public var description: String {
        switch self {
        case .executableNotFound:
            "Could not find the codex executable in PATH"
        case let .processFailed(status, stderr):
            "Codex process failed with status \(status): \(stderr)"
        }
    }
}

public struct CodexCLI: Sendable {
    public var executablePath: String

    public init(executablePath: String) {
        self.executablePath = executablePath
    }

    public static func findCodexExecutable(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        let pathValue = environment["PATH"] ?? ""
        let candidates = pathValue
            .split(separator: ":")
            .map { String($0) + "/codex" }
            + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw CodexCLIError.executableNotFound
    }

    public func startArguments(prompt: String, workspacePath: String) -> [String] {
        ["exec", "--json", "-C", workspacePath, prompt]
    }

    public func resumeArguments(sessionID: String, prompt: String) -> [String] {
        ["exec", "resume", "--json", sessionID, prompt]
    }

    public func run(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if process.terminationStatus != 0 {
            throw CodexCLIError.processFailed(status: process.terminationStatus, stderr: stderr)
        }
        return stdout
    }
}
