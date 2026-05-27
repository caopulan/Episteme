import Foundation

public struct PiRuntimeAdapter: Sendable {
    public var executablePath: String

    public init(executablePath: String) {
        self.executablePath = executablePath
    }

    public static func findExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> String {
        try AgentRuntimeExecutableResolver.executablePath(
            named: "pi",
            additionalPaths: [
                "/opt/homebrew/bin/pi",
                "/usr/local/bin/pi",
                "~/.local/bin/pi"
            ],
            environment: environment,
            fileManager: fileManager
        )
    }

    public func nonInteractiveCommand(
        prompt: String,
        workspacePath: String,
        systemPrompt: String?,
        agentInstructionsPath: String?
    ) -> AgentRuntimeCommand {
        var arguments = [
            "-p",
            "--mode", "json",
            "--session-dir", URL(fileURLWithPath: workspacePath, isDirectory: true)
                .appendingPathComponent("agent-sessions", isDirectory: true)
                .appendingPathComponent("pi", isDirectory: true)
                .path
        ]
        if let systemPrompt = normalized(systemPrompt) {
            arguments += ["--system-prompt", systemPrompt]
        }
        if let agentInstructionsPath = normalized(agentInstructionsPath) {
            arguments += ["--append-system-prompt", agentInstructionsPath]
        }
        arguments.append(prompt)
        return AgentRuntimeCommand(
            executablePath: executablePath,
            arguments: arguments,
            currentDirectoryPath: workspacePath
        )
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
