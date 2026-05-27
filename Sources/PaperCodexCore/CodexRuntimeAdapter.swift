import Foundation

public struct CodexRuntimeAdapter: Sendable {
    public var executablePath: String

    public init(executablePath: String) {
        self.executablePath = executablePath
    }

    public static func findExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferWorkspaceImageOutput: Bool = false
    ) throws -> String {
        try CodexCLI.findCodexExecutable(
            environment: environment,
            preferWorkspaceImageOutput: preferWorkspaceImageOutput
        )
    }

    public func startCommand(
        prompt: String,
        workspacePath: String,
        outputLastMessagePath: String?,
        modelOverride: String?,
        reasoningEffort: CodexReasoningEffort,
        mcpServers: [CodexMCPServerConfig] = []
    ) -> AgentRuntimeCommand {
        let cli = CodexCLI(executablePath: executablePath)
        return AgentRuntimeCommand(
            executablePath: executablePath,
            arguments: cli.startArguments(
                prompt: prompt,
                workspacePath: workspacePath,
                outputLastMessagePath: outputLastMessagePath,
                modelOverride: modelOverride,
                reasoningEffort: reasoningEffort,
                mcpServers: mcpServers
            ),
            currentDirectoryPath: workspacePath,
            environmentOverrides: Self.environmentOverrides(for: mcpServers)
        )
    }

    public func resumeCommand(
        sessionID: String,
        prompt: String,
        workspacePath: String,
        outputLastMessagePath: String?,
        modelOverride: String?,
        reasoningEffort: CodexReasoningEffort,
        mcpServers: [CodexMCPServerConfig] = []
    ) -> AgentRuntimeCommand {
        let cli = CodexCLI(executablePath: executablePath)
        return AgentRuntimeCommand(
            executablePath: executablePath,
            arguments: cli.resumeArguments(
                sessionID: sessionID,
                prompt: prompt,
                outputLastMessagePath: outputLastMessagePath,
                modelOverride: modelOverride,
                reasoningEffort: reasoningEffort,
                mcpServers: mcpServers
            ),
            currentDirectoryPath: workspacePath,
            environmentOverrides: Self.environmentOverrides(for: mcpServers)
        )
    }

    public func terminalCommand(
        workspacePath: String,
        modelOverride: String?,
        reasoningEffort: CodexReasoningEffort,
        mcpServers: [CodexMCPServerConfig] = []
    ) -> AgentRuntimeCommand {
        var arguments: [String] = []
        if let modelOverride = normalized(modelOverride) {
            arguments += ["--model", modelOverride]
        }
        if let reasoningEffort = reasoningEffort.codexConfigValue {
            arguments += ["-c", "model_reasoning_effort=\"\(reasoningEffort)\""]
        }
        arguments += Self.mcpConfigArguments(mcpServers)
        arguments += ["-C", workspacePath]
        return AgentRuntimeCommand(
            executablePath: executablePath,
            arguments: arguments,
            currentDirectoryPath: workspacePath,
            environmentOverrides: Self.environmentOverrides(for: mcpServers),
            launchMode: .pty
        )
    }

    private static func environmentOverrides(for mcpServers: [CodexMCPServerConfig]) -> [String: String] {
        mcpServers.reduce(into: [:]) { result, server in
            for (key, value) in server.environmentOverrides {
                result[key] = value
            }
        }
    }

    private static func mcpConfigArguments(_ servers: [CodexMCPServerConfig]) -> [String] {
        servers.flatMap { server in
            [
                "-c",
                "mcp_servers.\(server.name).url=\(tomlStringLiteral(server.url))",
                "-c",
                "mcp_servers.\(server.name).bearer_token_env_var=\(tomlStringLiteral(server.bearerTokenEnvironmentVariable))"
            ]
        }
    }

    private static func tomlStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
