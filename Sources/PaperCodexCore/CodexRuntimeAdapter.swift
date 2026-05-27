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

    private static func environmentOverrides(for mcpServers: [CodexMCPServerConfig]) -> [String: String] {
        mcpServers.reduce(into: [:]) { result, server in
            for (key, value) in server.environmentOverrides {
                result[key] = value
            }
        }
    }
}
