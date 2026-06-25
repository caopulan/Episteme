import Foundation

public enum AgentRuntimeBackend: String, Codable, CaseIterable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case acp
    case hermes
    case kimiCLI = "kimi-cli"
    case openClawKimi = "openclaw-kimi"
    case pi
}

public enum AgentRuntimeMCPMode: String, Codable, CaseIterable, Sendable {
    case codexConfigOverrides = "codex-config-overrides"
    case mcpConfigFile = "mcp-config-file"
    case acpSession = "acp-session"
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

public struct AgentRuntimeProfileLoadResult: Equatable, Sendable {
    public var profiles: [AgentRuntimeProfile]
    public var configURL: URL
    public var warning: String?

    public init(profiles: [AgentRuntimeProfile], configURL: URL, warning: String? = nil) {
        self.profiles = profiles
        self.configURL = configURL
        self.warning = warning
    }
}

public enum AgentRuntimeProfileConfigError: Error, CustomStringConvertible, Equatable {
    case invalidRoot
    case emptyField(runtimeID: String, field: String)

    public var description: String {
        switch self {
        case .invalidRoot:
            "agent runtime profile config must be a JSON object with a profiles array or a top-level profile array"
        case let .emptyField(runtimeID, field):
            "agent runtime profile \(runtimeID) has an empty \(field)"
        }
    }
}

public struct AgentRuntimeProfile: Codable, Equatable, Identifiable, Sendable {
    public static let externalProfilesEnvironmentKey = "EPISTEME_AGENT_RUNTIMES_PATH"

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
    public var acpServerArguments: [String]

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
        promptInjectionModes: [AgentPromptInjectionMode],
        acpServerArguments: [String] = []
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
        self.acpServerArguments = acpServerArguments
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case backend
        case executableName
        case knownExecutablePaths
        case defaultModelID
        case supportsNonInteractiveRuns
        case supportsPTY
        case supportsResume
        case supportsStructuredOutput
        case supportsMCPConfig
        case mcpMode
        case promptInjectionModes
        case acpServerArguments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        backend = try container.decode(AgentRuntimeBackend.self, forKey: .backend)
        executableName = try container.decode(String.self, forKey: .executableName)
        knownExecutablePaths = try container.decodeIfPresent([String].self, forKey: .knownExecutablePaths) ?? []
        defaultModelID = try container.decodeIfPresent(String.self, forKey: .defaultModelID)
        supportsNonInteractiveRuns = try container.decode(Bool.self, forKey: .supportsNonInteractiveRuns)
        supportsPTY = try container.decode(Bool.self, forKey: .supportsPTY)
        supportsResume = try container.decode(Bool.self, forKey: .supportsResume)
        supportsStructuredOutput = try container.decode(Bool.self, forKey: .supportsStructuredOutput)
        supportsMCPConfig = try container.decode(Bool.self, forKey: .supportsMCPConfig)
        mcpMode = try container.decode(AgentRuntimeMCPMode.self, forKey: .mcpMode)
        promptInjectionModes = try container.decode([AgentPromptInjectionMode].self, forKey: .promptInjectionModes)
        acpServerArguments = try container.decodeIfPresent([String].self, forKey: .acpServerArguments) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(backend, forKey: .backend)
        try container.encode(executableName, forKey: .executableName)
        try container.encode(knownExecutablePaths, forKey: .knownExecutablePaths)
        try container.encodeIfPresent(defaultModelID, forKey: .defaultModelID)
        try container.encode(supportsNonInteractiveRuns, forKey: .supportsNonInteractiveRuns)
        try container.encode(supportsPTY, forKey: .supportsPTY)
        try container.encode(supportsResume, forKey: .supportsResume)
        try container.encode(supportsStructuredOutput, forKey: .supportsStructuredOutput)
        try container.encode(supportsMCPConfig, forKey: .supportsMCPConfig)
        try container.encode(mcpMode, forKey: .mcpMode)
        try container.encode(promptInjectionModes, forKey: .promptInjectionModes)
        try container.encode(acpServerArguments, forKey: .acpServerArguments)
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
            id: "kimi-acp",
            displayName: "Kimi ACP",
            backend: .acp,
            executableName: "kimi",
            knownExecutablePaths: [
                "/opt/homebrew/bin/kimi",
                "/usr/local/bin/kimi",
                "/Users/chunqiu/.local/bin/kimi"
            ],
            supportsNonInteractiveRuns: true,
            supportsPTY: false,
            supportsResume: false,
            supportsStructuredOutput: true,
            supportsMCPConfig: true,
            mcpMode: .acpSession,
            promptInjectionModes: [.argumentPrompt, .workspaceInstructions],
            acpServerArguments: ["acp"]
        ),
        AgentRuntimeProfile(
            id: "gemini-acp",
            displayName: "Gemini ACP",
            backend: .acp,
            executableName: "gemini",
            knownExecutablePaths: [
                "/opt/homebrew/bin/gemini",
                "/usr/local/bin/gemini",
                "/Users/chunqiu/.local/bin/gemini"
            ],
            supportsNonInteractiveRuns: true,
            supportsPTY: false,
            supportsResume: false,
            supportsStructuredOutput: true,
            supportsMCPConfig: true,
            mcpMode: .acpSession,
            promptInjectionModes: [.argumentPrompt, .workspaceInstructions],
            acpServerArguments: ["--experimental-acp"]
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

    public static func externalProfilesURL(supportRoot: URL) -> URL {
        supportRoot.appendingPathComponent("agent-runtimes.json")
    }

    public static func loadProfiles(
        supportRoot: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> AgentRuntimeProfileLoadResult {
        let configURL = externalProfilesConfigURL(supportRoot: supportRoot, environment: environment)
        guard fileManager.fileExists(atPath: configURL.path) else {
            return AgentRuntimeProfileLoadResult(profiles: defaultProfiles, configURL: configURL)
        }

        do {
            let data = try Data(contentsOf: configURL)
            let externalProfiles = try decodeExternalProfiles(from: data)
            try validate(externalProfiles)
            let profiles = mergedProfiles(defaultProfiles: defaultProfiles, externalProfiles: externalProfiles)
            return AgentRuntimeProfileLoadResult(profiles: profiles, configURL: configURL)
        } catch {
            return AgentRuntimeProfileLoadResult(
                profiles: defaultProfiles,
                configURL: configURL,
                warning: "Failed to load \(configURL.lastPathComponent): \(error)"
            )
        }
    }

    private static func externalProfilesConfigURL(
        supportRoot: URL,
        environment: [String: String]
    ) -> URL {
        if let override = environment[externalProfilesEnvironmentKey],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return externalProfilesURL(supportRoot: supportRoot)
    }

    private static func decodeExternalProfiles(from data: Data) throws -> [AgentRuntimeProfile] {
        let decoder = JSONDecoder()
        let root = try JSONSerialization.jsonObject(with: data)
        if root is [[String: Any]] {
            return try decoder.decode([AgentRuntimeProfile].self, from: data)
        }
        if root is [String: Any] {
            return try decoder.decode(AgentRuntimeProfileConfigFile.self, from: data).profiles
        }
        throw AgentRuntimeProfileConfigError.invalidRoot
    }

    private static func validate(_ profiles: [AgentRuntimeProfile]) throws {
        for profile in profiles {
            let runtimeID = profile.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if runtimeID.isEmpty {
                throw AgentRuntimeProfileConfigError.emptyField(runtimeID: "<empty>", field: "id")
            }
            if profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AgentRuntimeProfileConfigError.emptyField(runtimeID: runtimeID, field: "displayName")
            }
            if profile.executableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AgentRuntimeProfileConfigError.emptyField(runtimeID: runtimeID, field: "executableName")
            }
        }
    }

    private static func mergedProfiles(
        defaultProfiles: [AgentRuntimeProfile],
        externalProfiles: [AgentRuntimeProfile]
    ) -> [AgentRuntimeProfile] {
        var profiles = defaultProfiles
        var indicesByID = Dictionary(uniqueKeysWithValues: profiles.enumerated().map { ($0.element.id, $0.offset) })
        for profile in externalProfiles {
            if let index = indicesByID[profile.id] {
                profiles[index] = profile
            } else {
                indicesByID[profile.id] = profiles.count
                profiles.append(profile)
            }
        }
        return profiles
    }
}

private struct AgentRuntimeProfileConfigFile: Decodable {
    var profiles: [AgentRuntimeProfile]
}
