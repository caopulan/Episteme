import Foundation

public struct CodexPluginInstallationStatus: Equatable, Sendable {
    public var installed: Bool
    public var current: Bool
    public var detail: String
    public var codexHomePath: String
    public var marketplaceRootPath: String
    public var pluginCachePath: String

    public init(
        installed: Bool,
        current: Bool,
        detail: String,
        codexHomePath: String,
        marketplaceRootPath: String,
        pluginCachePath: String
    ) {
        self.installed = installed
        self.current = current
        self.detail = detail
        self.codexHomePath = codexHomePath
        self.marketplaceRootPath = marketplaceRootPath
        self.pluginCachePath = pluginCachePath
    }
}

public struct CodexPluginInstaller {
    public static let marketplaceName = "paper-codex-local"
    public static let pluginName = "paper-codex"
    public static let pluginKey = "paper-codex@paper-codex-local"
    public static let pluginVersion = "local"

    private let codexHome: URL
    private let supportRoot: URL
    private let fileManager: FileManager

    public init(codexHome: URL, supportRoot: URL, fileManager: FileManager = .default) {
        self.codexHome = codexHome.standardizedFileURL
        self.supportRoot = supportRoot.standardizedFileURL
        self.fileManager = fileManager
    }

    public static func defaultCodexHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .standardizedFileURL
    }

    public var marketplaceRoot: URL {
        supportRoot.appendingPathComponent("codex-plugin-marketplace", isDirectory: true)
    }

    public var sourcePluginRoot: URL {
        marketplaceRoot
            .appendingPathComponent("plugins", isDirectory: true)
            .appendingPathComponent(Self.pluginName, isDirectory: true)
    }

    public var cachedPluginRoot: URL {
        codexHome
            .appendingPathComponent("plugins/cache", isDirectory: true)
            .appendingPathComponent(Self.marketplaceName, isDirectory: true)
            .appendingPathComponent(Self.pluginName, isDirectory: true)
            .appendingPathComponent(Self.pluginVersion, isDirectory: true)
    }

    public var configURL: URL {
        codexHome.appendingPathComponent("config.toml")
    }

    public func status(currentEndpoint endpoint: PaperCodexMCPEndpoint?) -> CodexPluginInstallationStatus {
        let config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let configEnabled = Self.configEnablesPlugin(config)
        let manifestExists = fileManager.fileExists(atPath: cachedPluginRoot.appendingPathComponent(".codex-plugin/plugin.json").path)
        let mcpConfig = (try? String(contentsOf: cachedPluginRoot.appendingPathComponent(".mcp.json"), encoding: .utf8)) ?? ""
        let hasCurrentEndpoint = endpoint.map { mcpConfig.contains($0.url) && mcpConfig.contains($0.authorizationHeader) } ?? false
        let installed = configEnabled && manifestExists
        let current = installed && hasCurrentEndpoint
        let detail: String
        if current {
            detail = "Installed · current endpoint"
        } else if installed {
            detail = "Installed · update needed"
        } else if configEnabled || manifestExists {
            detail = "Partial install · update needed"
        } else {
            detail = "Not installed"
        }
        return CodexPluginInstallationStatus(
            installed: installed,
            current: current,
            detail: detail,
            codexHomePath: codexHome.path,
            marketplaceRootPath: marketplaceRoot.path,
            pluginCachePath: cachedPluginRoot.path
        )
    }

    @discardableResult
    public func installOrUpdate(endpoint: PaperCodexMCPEndpoint, appVersion: String) throws -> CodexPluginInstallationStatus {
        try writeMarketplace()
        try writePluginBundle(at: sourcePluginRoot, endpoint: endpoint, appVersion: appVersion)
        try writePluginBundle(at: cachedPluginRoot, endpoint: endpoint, appVersion: appVersion)
        try updateCodexConfig()
        return status(currentEndpoint: endpoint)
    }

    @discardableResult
    public func refreshIfInstalled(endpoint: PaperCodexMCPEndpoint, appVersion: String) throws -> CodexPluginInstallationStatus {
        let currentStatus = status(currentEndpoint: endpoint)
        guard currentStatus.installed || currentStatus.detail.hasPrefix("Partial install") else {
            return currentStatus
        }
        return try installOrUpdate(endpoint: endpoint, appVersion: appVersion)
    }

    private func writeMarketplace() throws {
        let marketplaceManifestURL = marketplaceRoot
            .appendingPathComponent(".agents/plugins", isDirectory: true)
            .appendingPathComponent("marketplace.json")
        let manifest: [String: Any] = [
            "name": Self.marketplaceName,
            "interface": [
                "displayName": "Paper Codex"
            ],
            "plugins": [
                [
                    "name": Self.pluginName,
                    "source": [
                        "source": "local",
                        "path": "./plugins/\(Self.pluginName)"
                    ],
                    "policy": [
                        "installation": "AVAILABLE",
                        "authentication": "ON_USE"
                    ],
                    "category": "Research"
                ]
            ]
        ]
        try writeJSONObject(manifest, to: marketplaceManifestURL)
    }

    private func writePluginBundle(at root: URL, endpoint: PaperCodexMCPEndpoint, appVersion: String) throws {
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try writeJSONObject(pluginManifest(appVersion: appVersion), to: root.appendingPathComponent(".codex-plugin/plugin.json"))
        try writeJSONObject(mcpConfig(endpoint: endpoint), to: root.appendingPathComponent(".mcp.json"))
        try writeText(Self.mcpSkillMarkdown, to: root.appendingPathComponent("skills/papercodex-mcp/SKILL.md"))
        try writeText(Self.agentWorkspaceSkillMarkdown, to: root.appendingPathComponent("skills/papercodex-agent-workspace/SKILL.md"))
    }

    private func updateCodexConfig() throws {
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        var config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        config = Self.upsertTOMLKey(config, section: "features", key: "plugins", valueLine: "plugins = true")
        config = Self.upsertTOMLTable(
            config,
            header: "[marketplaces.\(Self.marketplaceName)]",
            body: [
                "last_updated = \(Self.tomlString(Self.iso8601(Date())))",
                "source_type = \"local\"",
                "source = \(Self.tomlString(marketplaceRoot.path))"
            ]
        )
        config = Self.upsertTOMLTable(
            config,
            header: "[plugins.\"\(Self.pluginKey)\"]",
            body: ["enabled = true"]
        )
        try config.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func writeJSONObject(_ object: Any, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: [.atomic])
    }

    private func writeText(_ text: String, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func pluginManifest(appVersion: String) -> [String: Any] {
        [
            "name": Self.pluginName,
            "version": appVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0.1.0" : appVersion,
            "description": "Expose the local Paper Codex app, paper library, notes, tags, folders, reading sessions, and citation-aware workspace skills to Codex.",
            "author": ["name": "Paper Codex"],
            "homepage": "https://local.paper-codex.app",
            "license": "Local",
            "keywords": ["paper-codex", "papers", "research", "mcp", "skills"],
            "skills": "./skills/",
            "mcpServers": "./.mcp.json",
            "interface": [
                "displayName": "Paper Codex",
                "shortDescription": "Use Paper Codex library and reading sessions",
                "longDescription": "Paper Codex lets Codex read local paper workspaces, manage paper metadata through MCP, and preserve exact citation markers back to the PDF.",
                "developerName": "Paper Codex",
                "category": "Research",
                "capabilities": ["Read", "Write"],
                "defaultPrompt": [
                    "Summarize the current Paper Codex paper with citations",
                    "Add tags and notes to papers in Paper Codex",
                    "Inspect my Paper Codex reading session workspace"
                ],
                "brandColor": "#2563EB",
                "screenshots": []
            ]
        ]
    }

    private func mcpConfig(endpoint: PaperCodexMCPEndpoint) -> [String: Any] {
        [
            "mcpServers": [
                "paper-codex": [
                    "type": "http",
                    "url": endpoint.url,
                    "http_headers": [
                        "Authorization": endpoint.authorizationHeader
                    ]
                ]
            ]
        ]
    }

    static func configEnablesPlugin(_ config: String) -> Bool {
        guard let range = tableRange(in: config, header: "[plugins.\"\(pluginKey)\"]") else {
            return false
        }
        return config[range].contains("enabled = true")
    }

    static func upsertTOMLKey(_ config: String, section: String, key: String, valueLine: String) -> String {
        let header = "[\(section)]"
        guard let range = tableRange(in: config, header: header) else {
            return appendBlock(to: config, block: "\(header)\n\(valueLine)\n")
        }
        let table = String(config[range])
        let lines = table.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var replaced = false
        let newLines = lines.map { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("\(key) =") {
                replaced = true
                return valueLine
            }
            return line
        }
        let replacement = (replaced ? newLines : newLines + [valueLine]).joined(separator: "\n")
        var output = config
        output.replaceSubrange(range, with: replacement.hasSuffix("\n") ? replacement : replacement + "\n")
        return output
    }

    static func upsertTOMLTable(_ config: String, header: String, body: [String]) -> String {
        let block = ([header] + body).joined(separator: "\n") + "\n"
        guard let range = tableRange(in: config, header: header) else {
            return appendBlock(to: config, block: block)
        }
        var output = config
        output.replaceSubrange(range, with: block)
        return output
    }

    private static func tableRange(in config: String, header: String) -> Range<String.Index>? {
        let lines = config.split(separator: "\n", omittingEmptySubsequences: false)
        var offset = config.startIndex
        var start: String.Index?
        var end: String.Index?
        for line in lines {
            let lineStart = offset
            let lineEnd = config.index(lineStart, offsetBy: line.count)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == header {
                start = lineStart
            } else if start != nil, trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                end = lineStart
                break
            }
            offset = lineEnd
            if offset < config.endIndex {
                offset = config.index(after: offset)
            }
        }
        guard let start else {
            return nil
        }
        return start..<(end ?? config.endIndex)
    }

    private static func appendBlock(to config: String, block: String) -> String {
        if config.isEmpty {
            return block
        }
        let separator = config.hasSuffix("\n\n") ? "" : (config.hasSuffix("\n") ? "\n" : "\n\n")
        return config + separator + block
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static let mcpSkillMarkdown = """
    ---
    name: papercodex-mcp
    description: Use when Codex needs to inspect or mutate the local Paper Codex library, paper notes, tags, folders, reading sessions, or citation-aware workspace state through Paper Codex MCP.
    ---

    # Paper Codex MCP

    Use the `paper-codex` MCP server for app state changes. Use resources for state views and tools for mutations.

    Useful resources:

    - `papercodex://app/active-context`
    - `papercodex://papers`
    - `papercodex://papers/{paper_id}/metadata`
    - `papercodex://papers/{paper_id}/notes`
    - `papercodex://sessions/{session_id}/workspace-manifest`
    - `papercodex://sessions/{session_id}/agent-runtime`
    - `papercodex://sessions/{session_id}/prompt-contract`
    - `papercodex://settings/prompt-templates`

    Use MCP tools for adding papers, tagging papers, moving papers between folders, creating notes, and navigating the app. Do not edit the Paper Codex SQLite store directly.

    Prompt templates are typed settings. Never invent a generic settings update; use prompt-template tools such as preview, validate, replace body, set variables, or set default for task.
    """

    public static let agentWorkspaceSkillMarkdown = """
    ---
    name: papercodex-agent-workspace
    description: Use when an agent is launched inside a Paper Codex reading-session workspace and must read paper files, follow citation contracts, or coordinate app/library changes through Paper Codex MCP.
    ---

    # Paper Codex Agent Workspace

    Use this skill when your current working directory is a Paper Codex session workspace.

    ## First Reads

    Read these local files before answering or changing anything:

    ```text
    workspace_manifest.json
    agent_instructions.md
    prompt_contract.md
    session.json
    ```

    Then read only the paper files needed for the task:

    ```text
    papers/{paper_id}/metadata.json
    papers/{paper_id}/full_text.txt
    papers/{paper_id}/pages.jsonl
    papers/{paper_id}/spans.jsonl
    papers/{paper_id}/anchors.jsonl
    ```

    ## Operating Boundary

    Use workspace files for source reading, drafts, and generated artifacts.

    Use MCP tools for app state changes:

    - notes, digests, folders, tags, and paper metadata
    - reader navigation or visual focus changes
    - prompt template changes
    - importing or deleting library items

    Do not edit the Paper Codex SQLite database or app support files directly.

    ## Citation Contract

    Ground paper claims with Paper Codex citation markers:

    ```text
    [[cite:paper:{paper_id}:p{page}:b{block_index}]]
    [[cite:paper:{paper_id}:p{page}:a{anchor_suffix}]]
    ```

    Prefer `spans.jsonl` for citation-ready claims. Use `anchors.jsonl` when the user selected or saved a source passage. If a claim cannot be grounded in the workspace, say that plainly.

    ## MCP Discovery

    When MCP is configured, discover live app state through:

    ```text
    papercodex://app/active-context
    papercodex://sessions/{session_id}/workspace-manifest
    papercodex://sessions/{session_id}/agent-runtime
    papercodex://sessions/{session_id}/prompt-contract
    ```

    If `mcp.json` exists, use it as the session-local MCP configuration. If not, rely on the workspace files and ask the user before attempting app mutations.
    """
}
