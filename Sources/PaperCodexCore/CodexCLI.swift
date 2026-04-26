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

public struct CodexCapabilities: Equatable, Sendable {
    public var supportsJSONOutput: Bool
    public var supportsOutputLastMessage: Bool
    public var supportsResume: Bool

    public init(supportsJSONOutput: Bool, supportsOutputLastMessage: Bool, supportsResume: Bool) {
        self.supportsJSONOutput = supportsJSONOutput
        self.supportsOutputLastMessage = supportsOutputLastMessage
        self.supportsResume = supportsResume
    }
}

public enum CodexDiagnosticSeverity: String, Codable, Equatable, Sendable {
    case ready
    case warning
    case blocked
}

public struct CodexDiagnostic: Equatable, Sendable {
    public var severity: CodexDiagnosticSeverity
    public var title: String
    public var detail: String
    public var executablePath: String?
    public var version: String?
    public var capabilities: CodexCapabilities?

    public static func ready(executablePath: String, version: String?, capabilities: CodexCapabilities) -> CodexDiagnostic {
        CodexDiagnostic(
            severity: .ready,
            title: "Codex ready",
            detail: "CLI \(version ?? "unknown version") supports Paper Codex sessions.",
            executablePath: executablePath,
            version: version,
            capabilities: capabilities
        )
    }

    public static func warning(
        executablePath: String,
        version: String?,
        capabilities: CodexCapabilities,
        missing: [String]
    ) -> CodexDiagnostic {
        CodexDiagnostic(
            severity: .warning,
            title: "Codex needs attention",
            detail: "CLI \(version ?? "unknown version") is missing: \(missing.joined(separator: ", ")).",
            executablePath: executablePath,
            version: version,
            capabilities: capabilities
        )
    }

    public static func blocked(_ detail: String) -> CodexDiagnostic {
        CodexDiagnostic(
            severity: .blocked,
            title: "Codex unavailable",
            detail: detail,
            executablePath: nil,
            version: nil,
            capabilities: nil
        )
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

    public func startArguments(prompt: String, workspacePath: String, outputLastMessagePath: String? = nil) -> [String] {
        var arguments = ["exec", "--json", "-C", workspacePath]
        if let outputLastMessagePath {
            arguments += ["--output-last-message", outputLastMessagePath]
        }
        arguments.append(prompt)
        return arguments
    }

    public func resumeArguments(sessionID: String, prompt: String, outputLastMessagePath: String? = nil) -> [String] {
        var arguments = ["exec", "resume", "--json"]
        if let outputLastMessagePath {
            arguments += ["--output-last-message", outputLastMessagePath]
        }
        arguments += [sessionID, prompt]
        return arguments
    }

    public func version() throws -> String? {
        try Self.parseVersion(from: run(arguments: ["--version"]))
    }

    public func capabilities() throws -> CodexCapabilities {
        try Self.parseCapabilities(fromExecHelp: run(arguments: ["exec", "--help"]))
    }

    public static func diagnose(environment: [String: String] = ProcessInfo.processInfo.environment) -> CodexDiagnostic {
        do {
            let executable = try findCodexExecutable(environment: environment)
            let cli = CodexCLI(executablePath: executable)
            let version = try cli.version()
            let capabilities = try cli.capabilities()
            var missing: [String] = []
            if !capabilities.supportsJSONOutput {
                missing.append("--json")
            }
            if !capabilities.supportsOutputLastMessage {
                missing.append("--output-last-message")
            }
            if !capabilities.supportsResume {
                missing.append("exec resume")
            }
            if missing.isEmpty {
                return .ready(executablePath: executable, version: version, capabilities: capabilities)
            }
            return .warning(executablePath: executable, version: version, capabilities: capabilities, missing: missing)
        } catch {
            return .blocked(String(describing: error))
        }
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

    public static func parseThreadID(from jsonl: String) -> String? {
        for line in jsonl.split(separator: "\n") {
            guard line.contains(#""type":"thread.started""#) || line.contains(#""type": "thread.started""#) else {
                continue
            }
            if let threadID = extractJSONStringValue(named: "thread_id", from: String(line)) {
                return threadID
            }
        }
        return nil
    }

    public static func parseVersion(from output: String) -> String? {
        let tokens = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
        return tokens.last
    }

    public static func parseCapabilities(fromExecHelp output: String) -> CodexCapabilities {
        CodexCapabilities(
            supportsJSONOutput: output.contains("--json"),
            supportsOutputLastMessage: output.contains("--output-last-message"),
            supportsResume: output.contains("resume")
        )
    }

    private static func extractJSONStringValue(named key: String, from line: String) -> String? {
        let compactPrefix = #""\#(key)":"#
        let spacedPrefix = #""\#(key)": "#
        guard let prefixRange = line.range(of: compactPrefix) ?? line.range(of: spacedPrefix) else {
            return nil
        }
        var cursor = prefixRange.upperBound
        guard cursor < line.endIndex, line[cursor] == "\"" else {
            return nil
        }
        cursor = line.index(after: cursor)
        guard let end = line[cursor...].firstIndex(of: "\"") else {
            return nil
        }
        return String(line[cursor..<end])
    }
}
