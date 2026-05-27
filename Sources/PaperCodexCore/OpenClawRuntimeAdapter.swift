import Foundation

public struct OpenClawRuntimeAdapter: Sendable {
    public var executablePath: String

    public init(executablePath: String) {
        self.executablePath = executablePath
    }

    public static func findExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> String {
        try AgentRuntimeExecutableResolver.executablePath(
            named: "openclaw",
            additionalPaths: [
                "/opt/homebrew/bin/openclaw",
                "/usr/local/bin/openclaw",
                "~/.local/bin/openclaw"
            ],
            environment: environment,
            fileManager: fileManager
        )
    }

    public func nonInteractiveCommand(
        prompt: String,
        workspacePath: String,
        sessionID: String?,
        modelID: String?
    ) -> AgentRuntimeCommand {
        var arguments = [
            "agent",
            "--local",
            "--json"
        ]
        if let sessionID = normalized(sessionID) {
            arguments += ["--session-id", sessionID]
        }
        arguments += ["--message", prompt]

        var environmentOverrides: [String: String] = [:]
        if let modelID = normalized(modelID) {
            environmentOverrides["OPENCLAW_MODEL"] = modelID
        }

        return AgentRuntimeCommand(
            executablePath: executablePath,
            arguments: arguments,
            currentDirectoryPath: workspacePath,
            environmentOverrides: environmentOverrides
        )
    }

    public func terminalCommand(
        workspacePath: String,
        sessionID: String?,
        modelID: String?
    ) -> AgentRuntimeCommand {
        var arguments = ["tui"]
        if let sessionID = normalized(sessionID) {
            arguments += ["--session-id", sessionID]
        }

        var environmentOverrides: [String: String] = [:]
        if let modelID = normalized(modelID) {
            environmentOverrides["OPENCLAW_MODEL"] = modelID
        }

        return AgentRuntimeCommand(
            executablePath: executablePath,
            arguments: arguments,
            currentDirectoryPath: workspacePath,
            environmentOverrides: environmentOverrides,
            launchMode: .pty
        )
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
