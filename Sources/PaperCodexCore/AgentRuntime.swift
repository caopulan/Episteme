import Foundation

public typealias AgentRunEvent = CodexRunEvent
public typealias AgentRunHandle = CodexRunHandle
public typealias AgentRuntimeRequest = AgentRunRequest
public typealias AgentRuntimeResult = AgentRunResult

public struct AgentRunRequest: Sendable {
    public var runtimeProfileID: String
    public var prompt: String
    public var workspacePath: String
    public var existingSessionID: String?
    public var outputFilePrefix: String
    public var modelOverride: String
    public var reasoningEffort: CodexReasoningEffort
    public var prefersWorkspaceImageOutput: Bool
    public var runModeDescription: String
    public var mcpServers: [CodexMCPServerConfig]

    public init(
        runtimeProfileID: String = "codex",
        prompt: String,
        workspacePath: String,
        existingSessionID: String?,
        outputFilePrefix: String = UUID().uuidString.lowercased(),
        modelOverride: String,
        reasoningEffort: CodexReasoningEffort,
        prefersWorkspaceImageOutput: Bool,
        runModeDescription: String,
        mcpServers: [CodexMCPServerConfig] = []
    ) {
        self.runtimeProfileID = runtimeProfileID
        self.prompt = prompt
        self.workspacePath = workspacePath
        self.existingSessionID = existingSessionID
        self.outputFilePrefix = outputFilePrefix
        self.modelOverride = modelOverride
        self.reasoningEffort = reasoningEffort
        self.prefersWorkspaceImageOutput = prefersWorkspaceImageOutput
        self.runModeDescription = runModeDescription
        self.mcpServers = mcpServers
    }

    public var mcpEnvironmentOverrides: [String: String] {
        mcpServers.reduce(into: [:]) { result, server in
            for (key, value) in server.environmentOverrides {
                result[key] = value
            }
        }
    }
}

public struct AgentRunResult: Sendable {
    public var stdout: String
    public var lastMessage: String
    public var threadID: String?
    public var generatedImages: [URL]
    public var tokenUsage: CodexTokenUsage?

    public init(
        stdout: String,
        lastMessage: String,
        threadID: String?,
        generatedImages: [URL],
        tokenUsage: CodexTokenUsage?
    ) {
        self.stdout = stdout
        self.lastMessage = lastMessage
        self.threadID = threadID
        self.generatedImages = generatedImages
        self.tokenUsage = tokenUsage
    }
}

public protocol AgentRuntime: Sendable {
    func runTurn(
        _ request: AgentRunRequest,
        runHandle: AgentRunHandle,
        onEvent: @escaping @Sendable (AgentRunEvent) -> Void
    ) async throws -> AgentRunResult
}

public extension AgentRuntime {
    func runCodexTurn(
        _ request: AgentRunRequest,
        runHandle: AgentRunHandle,
        onEvent: @escaping @Sendable (AgentRunEvent) -> Void
    ) async throws -> AgentRunResult {
        try await runTurn(request, runHandle: runHandle, onEvent: onEvent)
    }
}
