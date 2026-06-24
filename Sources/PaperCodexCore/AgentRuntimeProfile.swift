import Foundation

public enum AgentRuntimeBackend: String, Codable, CaseIterable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case hermes
    case kimiCLI = "kimi-cli"
    case openClawKimi = "openclaw-kimi"
    case pi
}

public enum AgentRuntimeMCPMode: String, Codable, CaseIterable, Sendable {
    case codexConfigOverrides = "codex-config-overrides"
    case mcpConfigFile = "mcp-config-file"
    case configuredExternally = "configured-externally"
    case workspaceOnly = "workspace-only"
}

public enum AgentPromptInjectionMode: String, Codable, CaseIterable, Sendable {
    case argumentPrompt = "argument-prompt"
    case systemPromptFlag = "system-prompt-flag"
    case appendSystemPromptFile = "append-system-prompt-file"
    case skill
    case workspaceInstructions = "workspace-instructions"
}

public struct AgentRuntimeProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var backend: AgentRuntimeBackend
    public var executableName: String
    public var knownExecutablePaths: [String]
    public var defaultModelID: String?
    public var supportsNonInteractiveRuns: Bool
    public var supportsPTY: Bool
    public var supportsResume: Bool
    public var supportsStructuredOutput: Bool
    public var supportsMCPConfig: Bool
    public var mcpMode: AgentRuntimeMCPMode
    public var promptInjectionModes: [AgentPromptInjectionMode]

    public init(
        id: String,
        displayName: String,
        backend: AgentRuntimeBackend,
        executableName: String,
        knownExecutablePaths: [String] = [],
        defaultModelID: String? = nil,
        supportsNonInteractiveRuns: Bool,
        supportsPTY: Bool,
        supportsResume: Bool,
        supportsStructuredOutput: Bool,
        supportsMCPConfig: Bool,
        mcpMode: AgentRuntimeMCPMode,
        promptInjectionModes: [AgentPromptInjectionMode]
    ) {
        self.id = id
        self.displayName = displayName
        self.backend = backend
        self.executableName = executableName
        self.knownExecutablePaths = knownExecutablePaths
        self.defaultModelID = defaultModelID
        self.supportsNonInteractiveRuns = supportsNonInteractiveRuns
        self.supportsPTY = supportsPTY
        self.supportsResume = supportsResume
        self.supportsStructuredOutput = supportsStructuredOutput
        self.supportsMCPConfig = supportsMCPConfig
        self.mcpMode = mcpMode
        self.promptInjectionModes = promptInjectionModes
    }

    public static let defaultProfiles: [AgentRuntimeProfile] = [
        AgentRuntimeProfile(
            id: "codex",
            displayName: "Codex",
            backend: .codex,
            executableName: "codex",
            knownExecutablePaths: [
                "/Applications/Codex.app/Contents/Resources/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex"
            ],
            supportsNonInteractiveRuns: true,
            supportsPTY: true,
            supportsResume: true,
            supportsStructuredOutput: true,
            supportsMCPConfig: true,
            mcpMode: .codexConfigOverrides,
            promptInjectionModes: [.argumentPrompt, .workspaceInstructions]
        ),
        AgentRuntimeProfile(
            id: "claude-code",
            displayName: "Claude Code",
            backend: .claudeCode,
            executableName: "claude",
            supportsNonInteractiveRuns: true,
            supportsPTY: true,
            supportsResume: true,
            supportsStructuredOutput: true,
            supportsMCPConfig: true,
            mcpMode: .mcpConfigFile,
            promptInjectionModes: [.systemPromptFlag, .appendSystemPromptFile, .workspaceInstructions]
        ),
        AgentRuntimeProfile(
            id: "hermes",
            displayName: "Hermes",
            backend: .hermes,
            executableName: "hermes",
            supportsNonInteractiveRuns: true,
            supportsPTY: true,
            supportsResume: true,
            supportsStructuredOutput: false,
            supportsMCPConfig: true,
            mcpMode: .configuredExternally,
            promptInjectionModes: [.argumentPrompt, .skill, .workspaceInstructions]
        ),
        AgentRuntimeProfile(
            id: "kimi-cli",
            displayName: "Kimi CLI",
            backend: .kimiCLI,
            executableName: "kimi",
            knownExecutablePaths: [
                "/opt/homebrew/bin/kimi",
                "/usr/local/bin/kimi",
                "/Users/chunqiu/.local/bin/kimi"
            ],
            supportsNonInteractiveRuns: true,
            supportsPTY: true,
            supportsResume: true,
            supportsStructuredOutput: true,
            supportsMCPConfig: true,
            mcpMode: .mcpConfigFile,
            promptInjectionModes: [.argumentPrompt, .skill, .workspaceInstructions]
        ),
        AgentRuntimeProfile(
            id: "openclaw-kimi",
            displayName: "OpenClaw Kimi",
            backend: .openClawKimi,
            executableName: "openclaw",
            knownExecutablePaths: [
                "/opt/homebrew/bin/openclaw",
                "/usr/local/bin/openclaw"
            ],
            defaultModelID: "kimi-coding/k2p5",
            supportsNonInteractiveRuns: true,
            supportsPTY: true,
            supportsResume: true,
            supportsStructuredOutput: true,
            supportsMCPConfig: false,
            mcpMode: .configuredExternally,
            promptInjectionModes: [.argumentPrompt, .workspaceInstructions]
        ),
        AgentRuntimeProfile(
            id: "pi",
            displayName: "pi",
            backend: .pi,
            executableName: "pi",
            knownExecutablePaths: [
                "/Users/chunqiu/.local/bin/pi"
            ],
            supportsNonInteractiveRuns: true,
            supportsPTY: true,
            supportsResume: true,
            supportsStructuredOutput: true,
            supportsMCPConfig: false,
            mcpMode: .workspaceOnly,
            promptInjectionModes: [.systemPromptFlag, .appendSystemPromptFile, .skill, .workspaceInstructions]
        )
    ]

    public static func defaultProfile(id: String) -> AgentRuntimeProfile? {
        defaultProfiles.first { $0.id == id }
    }
}
