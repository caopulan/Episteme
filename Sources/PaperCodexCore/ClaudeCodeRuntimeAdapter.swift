import Foundation

public struct ClaudeCodeRuntimeAdapter: Sendable {
    public var executablePath: String

    public init(executablePath: String) {
        self.executablePath = executablePath
    }

    public static func findExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> String {
        try AgentRuntimeExecutableResolver.executablePath(
            named: "claude",
            additionalPaths: [
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude"
            ],
            environment: environment,
            fileManager: fileManager
        )
    }

    public func nonInteractiveCommand(
        prompt: String,
        workspacePath: String,
        systemPrompt: String,
        mcpConfigPath: String?
    ) -> AgentRuntimeCommand {
        var arguments = [
            "--print",
            "--output-format", "stream-json",
            "--system-prompt", systemPrompt,
            "--add-dir", workspacePath
        ]
        if let mcpConfigPath = normalized(mcpConfigPath) {
            arguments += ["--mcp-config", mcpConfigPath]
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
