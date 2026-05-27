import Foundation

public struct PaperCodexMCPActiveContext: Codable, Equatable, Sendable {
    public var route: String
    public var paperID: String?
    public var paperTitle: String?
    public var sessionID: String?
    public var selectedText: String?
    public var selectedPage: Int?
    public var updatedAt: Date

    public init(
        route: String = "unknown",
        paperID: String? = nil,
        paperTitle: String? = nil,
        sessionID: String? = nil,
        selectedText: String? = nil,
        selectedPage: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.route = route
        self.paperID = paperID
        self.paperTitle = paperTitle
        self.sessionID = sessionID
        self.selectedText = selectedText
        self.selectedPage = selectedPage
        self.updatedAt = updatedAt
    }
}

public enum PaperCodexMCPServiceError: Error, CustomStringConvertible, Equatable {
    case invalidRequest(String)
    case methodNotFound(String)
    case resourceNotFound(String)
    case toolNotFound(String)
    case missingArgument(String)
    case invalidArgument(String)
    case operationRequiresConfirmation(String)

    public var description: String {
        switch self {
        case let .invalidRequest(message):
            "Invalid MCP request: \(message)"
        case let .methodNotFound(method):
            "MCP method was not found: \(method)."
        case let .resourceNotFound(uri):
            "MCP resource was not found: \(uri)."
        case let .toolNotFound(name):
            "MCP tool was not found: \(name)."
        case let .missingArgument(name):
            "Missing required argument: \(name)."
        case let .invalidArgument(message):
            "Invalid argument: \(message)."
        case let .operationRequiresConfirmation(message):
            "Operation requires confirmation: \(message)."
        }
    }
}

public struct PaperCodexMCPAppCommand: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: String
    public var arguments: [String: String]
    public var createdAt: Date

    public init(id: String = UUID().uuidString.lowercased(), type: String, arguments: [String: String], createdAt: Date = Date()) {
        self.id = id
        self.type = type
        self.arguments = arguments
        self.createdAt = createdAt
    }

    public static func commandLogURL(supportRoot: URL) -> URL {
        supportRoot.appendingPathComponent("mcp/commands.jsonl")
    }
}

public final class PaperCodexMCPService: @unchecked Sendable {
    private let repository: PaperRepository
    private let supportRoot: URL
    private let promptTemplateStore: PromptTemplateStore
    private let lock = NSLock()
    private let encoder = JSONEncoder()

    public init(repository: PaperRepository, supportRoot: URL) {
        self.repository = repository
        self.supportRoot = supportRoot
        self.promptTemplateStore = PromptTemplateStore(supportRoot: supportRoot)
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func handleJSONRPC(_ request: [String: Any]) throws -> [String: Any] {
        let id = request["id"] ?? NSNull()
        guard let method = request["method"] as? String else {
            return errorResponse(id: id, code: -32600, message: PaperCodexMCPServiceError.invalidRequest("method is required").description)
        }
        let params = request["params"] as? [String: Any] ?? [:]
        do {
            let result = try handle(method: method, params: params)
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": result
            ]
        } catch {
            return errorResponse(id: id, code: errorCode(for: error), message: String(describing: error))
        }
    }

    public func handleJSONRPCData(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let request = object as? [String: Any] else {
            throw PaperCodexMCPServiceError.invalidRequest("request body must be a JSON object")
        }
        let response = try handleJSONRPC(request)
        return try JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys])
    }

    public func writeActiveContextSnapshot(_ context: PaperCodexMCPActiveContext) throws {
        let snapshotURL = supportRoot.appendingPathComponent("mcp/active-context.json")
        try FileManager.default.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(context)
        try data.write(to: snapshotURL, options: [.atomic])
    }

    private func handle(method: String, params: [String: Any]) throws -> [String: Any] {
        switch method {
        case "initialize":
            return [
                "protocolVersion": "2025-06-18",
                "capabilities": [
                    "resources": ["listChanged": true],
                    "tools": ["listChanged": true],
                    "prompts": ["listChanged": true]
                ],
                "serverInfo": [
                    "name": "paper-codex",
                    "version": "1.0.0"
                ]
            ]
        case "ping":
            return [:]
        case "resources/list":
            return ["resources": try resourceList()]
        case "resources/templates/list":
            return ["resourceTemplates": resourceTemplates()]
        case "resources/read":
            guard let uri = params["uri"] as? String else {
                throw PaperCodexMCPServiceError.missingArgument("uri")
            }
            return [
                "contents": [[
                    "uri": uri,
                    "mimeType": "application/json",
                    "text": try readResource(uri: uri)
                ]]
            ]
        case "tools/list":
            return ["tools": tools()]
        case "tools/call":
            guard let name = params["name"] as? String else {
                throw PaperCodexMCPServiceError.missingArgument("name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let text = try callTool(name: name, arguments: arguments)
            return [
                "content": [[
                    "type": "text",
                    "text": text
                ]],
                "isError": false
            ]
        case "prompts/list":
            return ["prompts": promptsList()]
        case "prompts/get":
            guard let name = params["name"] as? String else {
                throw PaperCodexMCPServiceError.missingArgument("name")
            }
            let arguments = params["arguments"] as? [String: String] ?? [:]
            return try getPrompt(name: name, arguments: arguments)
        case "notifications/initialized":
            return [:]
        default:
            throw PaperCodexMCPServiceError.methodNotFound(method)
        }
    }

    private func resourceList() throws -> [[String: Any]] {
        var resources: [[String: Any]] = [
            resource(uri: "papercodex://papers", name: "Papers", description: "Saved Paper Codex papers."),
            resource(uri: "papercodex://folders", name: "Folders", description: "Paper Codex folder tree."),
            resource(uri: "papercodex://tags", name: "Tags", description: "Paper Codex tag list."),
            resource(uri: "papercodex://sessions/recent", name: "Recent sessions", description: "Recent Paper Codex reading sessions."),
            resource(uri: "papercodex://app/active-context", name: "Active app context", description: "Current Paper Codex route, paper, session, and selection snapshot."),
            resource(uri: "papercodex://settings/prompt-templates", name: "Prompt templates", description: "Typed prompt templates managed by Paper Codex MCP."),
            resource(uri: "papercodex://settings/prompt-templates/defaults", name: "Prompt template defaults", description: "Default prompt template id by task."),
            resource(uri: "papercodex://settings/prompt-templates/tasks", name: "Prompt template tasks", description: "Supported prompt-template task names."),
            resource(uri: "papercodex://settings/prompt-templates/variables", name: "Prompt template variables", description: "Variables used by all active prompt templates.")
        ]
        let papers = try withRepository { try repository.fetchPapers() }
        resources += papers.flatMap { paper in
            [
                resource(uri: "papercodex://papers/\(paper.id)/metadata", name: "\(paper.title) metadata", description: "Paper metadata, folders, and tags."),
                resource(uri: "papercodex://papers/\(paper.id)/notes", name: "\(paper.title) notes", description: "Paper notes."),
                resource(uri: "papercodex://papers/\(paper.id)/full-text", name: "\(paper.title) full text", description: "Extracted paper text.")
            ]
        }
        let sessions = try withRepository { try repository.fetchRecentSessions(limit: 20) }
        resources += sessions.flatMap { session in
            [
                resource(uri: "papercodex://sessions/\(session.id)/workspace-manifest", name: "\(session.title) workspace manifest", description: "Session agent workspace manifest."),
                resource(uri: "papercodex://sessions/\(session.id)/agent-runtime", name: "\(session.title) agent runtime", description: "Session runtime profile and runtime session links."),
                resource(uri: "papercodex://sessions/\(session.id)/prompt-contract", name: "\(session.title) prompt contract", description: "Session citation and output contract.")
            ]
        }
        return resources
    }

    private func resourceTemplates() -> [[String: Any]] {
        [
            resourceTemplate(uri: "papercodex://papers/{paper_id}", name: "Paper", description: "Paper metadata, folders, tags, and source paths."),
            resourceTemplate(uri: "papercodex://papers/{paper_id}/metadata", name: "Paper metadata", description: "Paper metadata with folder and tag names."),
            resourceTemplate(uri: "papercodex://papers/{paper_id}/full-text", name: "Paper full text", description: "Concatenated extracted page text."),
            resourceTemplate(uri: "papercodex://papers/{paper_id}/pages/{page}", name: "Paper page", description: "Extracted text for a single page."),
            resourceTemplate(uri: "papercodex://papers/{paper_id}/spans", name: "Paper spans", description: "Citation-ready extracted spans."),
            resourceTemplate(uri: "papercodex://papers/{paper_id}/anchors", name: "Paper anchors", description: "User-created source anchors."),
            resourceTemplate(uri: "papercodex://papers/{paper_id}/annotations", name: "Paper annotations", description: "PDF annotation records."),
            resourceTemplate(uri: "papercodex://papers/{paper_id}/notes", name: "Paper notes", description: "Markdown notes for a paper."),
            resourceTemplate(uri: "papercodex://papers/{paper_id}/digest", name: "Paper digest", description: "Durable structured digest stored as a Paper Codex note."),
            resourceTemplate(uri: "papercodex://folders/{folder_id}", name: "Folder", description: "Folder metadata."),
            resourceTemplate(uri: "papercodex://folders/{folder_id}/papers", name: "Folder papers", description: "Papers assigned to a folder."),
            resourceTemplate(uri: "papercodex://tags/{tag_id}", name: "Tag", description: "Tag metadata."),
            resourceTemplate(uri: "papercodex://tags/{tag_id}/papers", name: "Tag papers", description: "Papers assigned to a tag."),
            resourceTemplate(uri: "papercodex://sessions/{session_id}", name: "Session", description: "Reading session metadata."),
            resourceTemplate(uri: "papercodex://sessions/{session_id}/messages", name: "Session messages", description: "Chat messages in a reading session."),
            resourceTemplate(uri: "papercodex://sessions/{session_id}/workspace", name: "Session workspace", description: "Workspace path and expected files for a reading session."),
            resourceTemplate(uri: "papercodex://sessions/{session_id}/workspace-manifest", name: "Session workspace manifest", description: "Runtime-neutral workspace manifest for an agent session."),
            resourceTemplate(uri: "papercodex://sessions/{session_id}/agent-runtime", name: "Session agent runtime", description: "Selected runtime and runtime session links."),
            resourceTemplate(uri: "papercodex://sessions/{session_id}/prompt-contract", name: "Session prompt contract", description: "Citation and output contract for the workspace."),
            resourceTemplate(uri: "papercodex://settings/prompt-templates/{template_id}", name: "Prompt template", description: "A typed prompt template."),
            resourceTemplate(uri: "papercodex://app/active-context", name: "Active app context", description: "Current app context snapshot.")
        ]
    }

    private func readResource(uri: String) throws -> String {
        if uri == "papercodex://papers" {
            return try jsonText(paperSummaries())
        }
        if uri == "papercodex://folders" {
            return try jsonText(withRepository { try repository.fetchCategories().map(categoryDictionary) })
        }
        if uri == "papercodex://tags" {
            return try jsonText(withRepository { try repository.fetchTags().map(tagDictionary) })
        }
        if uri == "papercodex://sessions/recent" {
            return try jsonText(withRepository { try repository.fetchRecentSessions(limit: 20).map(codableDictionary) })
        }
        if uri == "papercodex://app/active-context" {
            return try jsonText(activeContextDictionary())
        }
        if uri == "papercodex://settings/prompt-templates" {
            return try jsonText(try promptTemplateStore.listTemplates().map(codableDictionary))
        }
        if uri == "papercodex://settings/prompt-templates/defaults" {
            return try jsonText(try promptTemplateStore.defaultsByTask())
        }
        if uri == "papercodex://settings/prompt-templates/tasks" {
            return try jsonText(PromptTemplateStore.supportedTasks)
        }
        if uri == "papercodex://settings/prompt-templates/variables" {
            let variables = try promptTemplateStore.listTemplates().reduce(into: [String: [String]]()) { partial, template in
                partial[template.id] = template.variables
            }
            return try jsonText(variables)
        }

        let components = pathComponents(uri: uri)
        guard !components.isEmpty else {
            throw PaperCodexMCPServiceError.resourceNotFound(uri)
        }
        switch components[0] {
        case "papers":
            return try readPaperResource(components: components, uri: uri)
        case "folders":
            return try readFolderResource(components: components, uri: uri)
        case "tags":
            return try readTagResource(components: components, uri: uri)
        case "sessions":
            return try readSessionResource(components: components, uri: uri)
        case "settings":
            return try readSettingsResource(components: components, uri: uri)
        default:
            throw PaperCodexMCPServiceError.resourceNotFound(uri)
        }
    }

    private func readPaperResource(components: [String], uri: String) throws -> String {
        guard components.count >= 2 else {
            throw PaperCodexMCPServiceError.resourceNotFound(uri)
        }
        let paperID = components[1]
        if components.count == 2 || components[safe: 2] == "metadata" {
            return try jsonText(paperMetadata(paperID: paperID))
        }
        switch components[2] {
        case "full-text":
            let pages = try withRepository { try repository.fetchPages(paperID: paperID) }
            return try jsonText([
                "paper_id": paperID,
                "text": pages.sorted { $0.page < $1.page }.map { $0.text }.joined(separator: "\n\n")
            ])
        case "pages":
            guard components.count >= 4, let page = Int(components[3]) else {
                throw PaperCodexMCPServiceError.resourceNotFound(uri)
            }
            guard let pageIndex = try withRepository({ try repository.fetchPages(paperID: paperID).first(where: { $0.page == page }) }) else {
                throw PaperCodexMCPServiceError.resourceNotFound(uri)
            }
            return try jsonText(codableDictionary(pageIndex))
        case "spans":
            return try jsonText(withRepository { try repository.fetchSpans(paperID: paperID).map(codableDictionary) })
        case "anchors":
            return try jsonText(withRepository { try repository.fetchAnchors(paperID: paperID).map(codableDictionary) })
        case "annotations":
            return try jsonText([
                "paper_id": paperID,
                "annotations": []
            ])
        case "notes":
            return try jsonText(withRepository { try repository.fetchNotes(paperID: paperID).map(codableDictionary) })
        case "digest":
            return try jsonText(digestDictionary(paperID: paperID))
        default:
            throw PaperCodexMCPServiceError.resourceNotFound(uri)
        }
    }

    private func readFolderResource(components: [String], uri: String) throws -> String {
        guard components.count >= 2 else {
            throw PaperCodexMCPServiceError.resourceNotFound(uri)
        }
        let folderID = components[1]
        let categories = try withRepository { try repository.fetchCategories() }
        guard let folder = categories.first(where: { $0.id == folderID }) else {
            throw PaperCodexMCPServiceError.resourceNotFound(uri)
        }
        if components.count == 2 {
            return try jsonText(categoryDictionary(folder))
        }
        if components.count == 3, components[2] == "papers" {
            return try jsonText(paperSummaries().filter { summary in
                (summary["folder_ids"] as? [String])?.contains(folderID) == true
            })
        }
        throw PaperCodexMCPServiceError.resourceNotFound(uri)
    }

    private func readTagResource(components: [String], uri: String) throws -> String {
        guard components.count >= 2 else {
            throw PaperCodexMCPServiceError.resourceNotFound(uri)
        }
        let tagID = components[1]
        let tags = try withRepository { try repository.fetchTags() }
        guard let tag = tags.first(where: { $0.id == tagID }) else {
            throw PaperCodexMCPServiceError.resourceNotFound(uri)
        }
        if components.count == 2 {
            return try jsonText(tagDictionary(tag))
        }
        if components.count == 3, components[2] == "papers" {
            return try jsonText(paperSummaries().filter { summary in
                (summary["tag_ids"] as? [String])?.contains(tagID) == true
            })
        }
        throw PaperCodexMCPServiceError.resourceNotFound(uri)
    }

    private func readSessionResource(components: [String], uri: String) throws -> String {
        guard components.count >= 2 else {
            throw PaperCodexMCPServiceError.resourceNotFound(uri)
        }
        let sessionID = components[1]
        guard let session = try withRepository({ try repository.fetchSession(id: sessionID) }) else {
            throw PaperCodexMCPServiceError.resourceNotFound(uri)
        }
        if components.count == 2 {
            return try jsonText(codableDictionary(session))
        }
        switch components[2] {
        case "messages":
            return try jsonText(withRepository { try repository.fetchMessages(sessionID: sessionID).map(codableDictionary) })
        case "workspace":
            return try jsonText([
                "session_id": sessionID,
                "workspace_path": session.workspacePath,
                "workspace_manifest_path": sessionWorkspaceURL(session).appendingPathComponent("workspace_manifest.json").path,
                "prompt_contract_path": sessionWorkspaceURL(session).appendingPathComponent("prompt_contract.md").path,
                "agent_instructions_path": sessionWorkspaceURL(session).appendingPathComponent("agent_instructions.md").path,
                "mcp_config_path": sessionWorkspaceURL(session).appendingPathComponent("mcp.json").path,
                "expected_files": [
                    "session.json",
                    "workspace_manifest.json",
                    "prompt_contract.md",
                    "agent_instructions.md",
                    "AGENTS.md",
                    "CLAUDE.md",
                    "papers/{paper_id}/metadata.json",
                    "papers/{paper_id}/original.pdf",
                    "papers/{paper_id}/full_text.txt",
                    "papers/{paper_id}/pages.jsonl",
                    "papers/{paper_id}/spans.jsonl",
                    "papers/{paper_id}/anchors.jsonl"
                ]
            ])
        case "workspace-manifest":
            return try readSessionWorkspaceManifest(session: session, uri: uri)
        case "agent-runtime":
            return try readSessionAgentRuntime(session: session)
        case "prompt-contract":
            return try readSessionPromptContract(session: session, uri: uri)
        default:
            throw PaperCodexMCPServiceError.resourceNotFound(uri)
        }
    }

    private func readSessionWorkspaceManifest(session: PaperSession, uri: String) throws -> String {
        let manifestURL = sessionWorkspaceURL(session).appendingPathComponent("workspace_manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PaperCodexMCPServiceError.resourceNotFound(uri)
        }
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONSerialization.jsonObject(with: data)
        return try jsonText([
            "session_id": session.id,
            "manifest_path": manifestURL.path,
            "manifest": manifest
        ])
    }

    private func readSessionAgentRuntime(session: PaperSession) throws -> String {
        let workspaceURL = sessionWorkspaceURL(session)
        return try jsonText([
            "session_id": session.id,
            "default_runtime_id": session.defaultRuntimeID as Any,
            "legacy_codex_session_id": session.codexSessionID as Any,
            "runtime_session_links": session.runtimeSessionLinks.map(runtimeSessionLinkDictionary),
            "workspace_materialization_mode": session.workspaceMaterializationMode.rawValue,
            "workspace_path": session.workspacePath,
            "workspace_manifest_path": workspaceURL.appendingPathComponent("workspace_manifest.json").path,
            "prompt_contract_path": workspaceURL.appendingPathComponent("prompt_contract.md").path,
            "agent_instructions_path": workspaceURL.appendingPathComponent("agent_instructions.md").path,
            "mcp_config_path": workspaceURL.appendingPathComponent("mcp.json").path
        ])
    }

    private func readSessionPromptContract(session: PaperSession, uri: String) throws -> String {
        let promptContractURL = sessionWorkspaceURL(session).appendingPathComponent("prompt_contract.md")
        guard FileManager.default.fileExists(atPath: promptContractURL.path) else {
            throw PaperCodexMCPServiceError.resourceNotFound(uri)
        }
        return try jsonText([
            "session_id": session.id,
            "prompt_contract_path": promptContractURL.path,
            "text": String(contentsOf: promptContractURL, encoding: .utf8)
        ])
    }

    private func readSettingsResource(components: [String], uri: String) throws -> String {
        if components.count == 3, components[1] == "prompt-templates" {
            let template = try promptTemplateStore.template(id: components[2])
            return try jsonText(codableDictionary(template))
        }
        throw PaperCodexMCPServiceError.resourceNotFound(uri)
    }

    private func tools() -> [[String: Any]] {
        [
            tool("paper.import_pdf", "Import a local PDF into the Paper Codex library.", ["source_path": "string", "title": "string", "authors": "array", "year": "integer", "source_url": "string", "folder_ids": "array", "tag_names": "array"], ["source_path"]),
            tool("paper.list", "List saved papers.", [:], []),
            tool("paper.get", "Get paper metadata.", ["paper_id": "string"], ["paper_id"]),
            tool("paper.search", "Search title, author, source, folder, tag, or extracted text.", ["query": "string", "limit": "integer"], ["query"]),
            tool("paper.update_metadata", "Update paper title/authors/year/source URL.", ["paper_id": "string", "title": "string", "authors": "array", "year": "integer", "source_url": "string"], ["paper_id"]),
            tool("paper.star", "Set a paper's starred state.", ["paper_id": "string", "is_starred": "boolean"], ["paper_id", "is_starred"]),
            tool("paper.delete", "Delete papers after explicit confirmation.", ["paper_ids": "array", "confirm": "boolean"], ["paper_ids"]),
            tool("paper.deduplicate", "Find likely duplicate papers by hash and source URL.", [:], []),
            tool("paper.add_to_folder", "Add a paper to a folder without removing existing folders.", ["paper_id": "string", "folder_id": "string"], ["paper_id", "folder_id"]),
            tool("paper.remove_from_folder", "Remove a paper from a folder.", ["paper_id": "string", "folder_id": "string"], ["paper_id", "folder_id"]),
            tool("paper.move_folder", "Move a paper from one folder context to another. Without from_folder_id, removes all current folders first.", ["paper_id": "string", "to_folder_id": "string", "from_folder_id": "string"], ["paper_id"]),
            tool("paper.copy_to_folder", "Copy a paper into another folder while preserving existing folders.", ["paper_id": "string", "folder_id": "string"], ["paper_id", "folder_id"]),
            tool("paper.add_tags", "Add tag names or ids to a paper, creating missing tag names.", ["paper_id": "string", "tags": "array"], ["paper_id", "tags"]),
            tool("paper.remove_tags", "Remove tag names or ids from a paper.", ["paper_id": "string", "tags": "array"], ["paper_id", "tags"]),
            tool("paper.set_tags", "Replace a paper's tags with the provided tag names or ids.", ["paper_id": "string", "tags": "array"], ["paper_id", "tags"]),
            tool("paper.digest_get", "Read a paper's durable digest note.", ["paper_id": "string"], ["paper_id"]),
            tool("paper.digest_upsert", "Create or update a paper's durable digest note.", ["paper_id": "string", "body_markdown": "string"], ["paper_id", "body_markdown"]),
            tool("folder.list", "List folders.", [:], []),
            tool("folder.create", "Create a folder.", ["name": "string", "parent_id": "string"], ["name"]),
            tool("folder.rename", "Rename a folder.", ["folder_id": "string", "name": "string"], ["folder_id", "name"]),
            tool("folder.delete", "Delete a folder after explicit confirmation.", ["folder_id": "string", "confirm": "boolean"], ["folder_id"]),
            tool("folder.move", "Move a folder in the folder tree.", ["folder_id": "string", "parent_id": "string"], ["folder_id"]),
            tool("tag.list", "List tags.", [:], []),
            tool("tag.create", "Create a tag.", ["name": "string"], ["name"]),
            tool("tag.rename", "Rename a tag.", ["tag_id": "string", "name": "string"], ["tag_id", "name"]),
            tool("tag.delete", "Delete a tag after explicit confirmation.", ["tag_id": "string", "confirm": "boolean"], ["tag_id"]),
            tool("tag.suggest", "Suggest tags from a title, abstract, or goal without applying them.", ["paper_id": "string", "text": "string"], []),
            tool("note.list", "List notes for a paper.", ["paper_id": "string"], ["paper_id"]),
            tool("note.get", "Get a note by id.", ["note_id": "string", "paper_id": "string"], ["note_id"]),
            tool("note.create", "Create a Markdown note.", ["paper_id": "string", "title": "string", "body_markdown": "string", "anchor_id": "string"], ["paper_id", "body_markdown"]),
            tool("note.update", "Update a Markdown note.", ["paper_id": "string", "note_id": "string", "title": "string", "body_markdown": "string"], ["paper_id", "note_id"]),
            tool("note.delete", "Delete a note after explicit confirmation.", ["paper_id": "string", "note_id": "string", "confirm": "boolean"], ["paper_id", "note_id"]),
            tool("note.create_from_anchor", "Create a note attached to an anchor.", ["anchor_id": "string", "title": "string", "body_markdown": "string"], ["anchor_id", "body_markdown"]),
            tool("anchor.list", "List anchors for a paper.", ["paper_id": "string"], ["paper_id"]),
            tool("anchor.get", "Get an anchor.", ["anchor_id": "string"], ["anchor_id"]),
            tool("anchor.search", "Search anchors by selected text/context.", ["paper_id": "string", "query": "string"], ["paper_id", "query"]),
            tool("citation.resolve", "Resolve a Paper Codex citation id to span or anchor metadata.", ["citation_id": "string"], ["citation_id"]),
            tool("app.open_paper", "Ask the running Paper Codex app to open a paper.", ["paper_id": "string"], ["paper_id"]),
            tool("app.reveal_paper", "Ask the running Paper Codex app to reveal a paper in Library.", ["paper_id": "string"], ["paper_id"]),
            tool("app.open_folder", "Ask the running Paper Codex app to show a folder.", ["folder_id": "string"], ["folder_id"]),
            tool("app.open_tag", "Ask the running Paper Codex app to show a tag.", ["tag_id": "string"], ["tag_id"]),
            tool("app.jump_to_page", "Ask the running Paper Codex app to open a paper at a page.", ["paper_id": "string", "page": "integer"], ["paper_id", "page"]),
            tool("app.jump_to_anchor", "Ask the running Paper Codex app to jump to an anchor or citation id.", ["anchor_id": "string"], ["anchor_id"]),
            tool("watched_folder.list", "List watched folders.", [:], []),
            tool("watched_folder.add", "Add a watched folder.", ["path": "string"], ["path"]),
            tool("watched_folder.remove", "Remove a watched folder.", ["folder_id": "string"], ["folder_id"]),
            tool("watched_folder.scan", "Scan watched folders now.", [:], []),
            tool("session.list_recent", "List recent reading sessions.", ["limit": "integer"], []),
            tool("session.get", "Get a session.", ["session_id": "string"], ["session_id"]),
            tool("session.get_workspace", "Get a session workspace description.", ["session_id": "string"], ["session_id"]),
            tool("prompt_template.create", "Create a typed prompt template.", ["task": "string", "name": "string", "body_markdown": "string", "variables": "array"], ["task", "name", "body_markdown"]),
            tool("prompt_template.rename", "Rename a prompt template.", ["template_id": "string", "name": "string"], ["template_id", "name"]),
            tool("prompt_template.duplicate", "Duplicate a prompt template.", ["template_id": "string", "name": "string"], ["template_id"]),
            tool("prompt_template.replace_body", "Replace a prompt template body.", ["template_id": "string", "body_markdown": "string"], ["template_id", "body_markdown"]),
            tool("prompt_template.set_variables", "Set declared prompt template variables.", ["template_id": "string", "variables": "array"], ["template_id", "variables"]),
            tool("prompt_template.set_default_for_task", "Set the default template for a task.", ["task": "string", "template_id": "string"], ["task", "template_id"]),
            tool("prompt_template.enable", "Enable a prompt template.", ["template_id": "string"], ["template_id"]),
            tool("prompt_template.disable", "Disable a prompt template.", ["template_id": "string"], ["template_id"]),
            tool("prompt_template.archive", "Archive a prompt template.", ["template_id": "string"], ["template_id"]),
            tool("prompt_template.preview_render", "Render a prompt template with sample variables.", ["template_id": "string", "variables": "object"], ["template_id"]),
            tool("prompt_template.validate", "Validate a prompt template.", ["template_id": "string"], ["template_id"]),
            tool("reader.position_get", "Get a reader position for a session/paper.", ["session_id": "string", "paper_id": "string"], ["session_id", "paper_id"]),
            tool("reader.position_set", "Set a reader position for a session/paper.", ["session_id": "string", "paper_id": "string", "page_index": "integer", "page_point_x": "number", "page_point_y": "number", "scale_factor": "number"], ["session_id", "paper_id", "page_index"])
        ]
    }

    private func callTool(name: String, arguments: [String: Any]) throws -> String {
        switch name {
        case "paper.import_pdf":
            return try toolImportPDF(arguments)
        case "paper.list":
            return try jsonText(paperSummaries())
        case "paper.get":
            return try jsonText(paperMetadata(paperID: try stringArgument("paper_id", in: arguments)))
        case "paper.search":
            return try jsonText(searchPapers(query: try stringArgument("query", in: arguments), limit: intArgument("limit", in: arguments) ?? 20))
        case "paper.update_metadata":
            return try toolUpdatePaperMetadata(arguments)
        case "paper.star":
            return try toolStarPaper(arguments)
        case "paper.delete":
            return try toolDeletePapers(arguments)
        case "paper.deduplicate":
            return try jsonText(deduplicatePapers())
        case "paper.add_to_folder", "paper.copy_to_folder":
            return try toolAddPaperToFolder(arguments)
        case "paper.remove_from_folder":
            return try toolRemovePaperFromFolder(arguments)
        case "paper.move_folder":
            return try toolMovePaperFolder(arguments)
        case "paper.add_tags":
            return try toolAddTags(arguments)
        case "paper.remove_tags":
            return try toolRemoveTags(arguments)
        case "paper.set_tags":
            return try toolSetTags(arguments)
        case "paper.digest_get":
            return try jsonText(digestDictionary(paperID: try stringArgument("paper_id", in: arguments)))
        case "paper.digest_upsert":
            return try toolUpsertDigest(arguments)
        case "folder.list":
            return try jsonText(withRepository { try repository.fetchCategories().map(categoryDictionary) })
        case "folder.create":
            return try toolCreateFolder(arguments)
        case "folder.rename":
            return try toolRenameFolder(arguments)
        case "folder.delete":
            return try toolDeleteFolder(arguments)
        case "folder.move":
            return try toolMoveFolder(arguments)
        case "tag.list":
            return try jsonText(withRepository { try repository.fetchTags().map(tagDictionary) })
        case "tag.create":
            return try toolCreateTag(arguments)
        case "tag.rename":
            return try toolRenameTag(arguments)
        case "tag.delete":
            return try toolDeleteTag(arguments)
        case "tag.suggest":
            return try toolSuggestTags(arguments)
        case "note.list":
            return try jsonText(withRepository { try repository.fetchNotes(paperID: try stringArgument("paper_id", in: arguments)).map(codableDictionary) })
        case "note.get":
            return try jsonText(codableDictionary(findNote(noteID: try stringArgument("note_id", in: arguments), paperID: arguments["paper_id"] as? String)))
        case "note.create":
            return try toolCreateNote(arguments)
        case "note.update":
            return try toolUpdateNote(arguments)
        case "note.delete":
            return try toolDeleteNote(arguments)
        case "note.create_from_anchor":
            return try toolCreateNoteFromAnchor(arguments)
        case "anchor.list":
            return try jsonText(withRepository { try repository.fetchAnchors(paperID: try stringArgument("paper_id", in: arguments)).map(codableDictionary) })
        case "anchor.get":
            return try jsonText(codableDictionary(resolveAnchor(id: try stringArgument("anchor_id", in: arguments))))
        case "anchor.search":
            return try toolSearchAnchors(arguments)
        case "citation.resolve":
            return try jsonText(resolveCitation(id: try stringArgument("citation_id", in: arguments)))
        case "app.open_paper":
            return try enqueueAppCommand(type: "app.open_paper", arguments: ["paper_id": try stringArgument("paper_id", in: arguments)])
        case "app.reveal_paper":
            return try enqueueAppCommand(type: "app.reveal_paper", arguments: ["paper_id": try stringArgument("paper_id", in: arguments)])
        case "app.open_folder":
            return try enqueueAppCommand(type: "app.open_folder", arguments: ["folder_id": try stringArgument("folder_id", in: arguments)])
        case "app.open_tag":
            return try enqueueAppCommand(type: "app.open_tag", arguments: ["tag_id": try stringArgument("tag_id", in: arguments)])
        case "app.jump_to_page":
            return try enqueueAppCommand(type: "app.jump_to_page", arguments: [
                "paper_id": try stringArgument("paper_id", in: arguments),
                "page": String(intArgument("page", in: arguments) ?? 1)
            ])
        case "app.jump_to_anchor":
            return try enqueueAppCommand(type: "app.jump_to_anchor", arguments: ["anchor_id": try stringArgument("anchor_id", in: arguments)])
        case "watched_folder.list":
            return try jsonText(withRepository { try repository.fetchWatchedFolders().map(codableDictionary) })
        case "watched_folder.add":
            return try toolAddWatchedFolder(arguments)
        case "watched_folder.remove":
            return try toolRemoveWatchedFolder(arguments)
        case "watched_folder.scan":
            return try toolScanWatchedFolders()
        case "session.list_recent":
            return try jsonText(withRepository { try repository.fetchRecentSessions(limit: intArgument("limit", in: arguments) ?? 20).map(codableDictionary) })
        case "session.get":
            return try jsonText(codableDictionary(resolveSession(id: try stringArgument("session_id", in: arguments))))
        case "session.get_workspace":
            return try readSessionResource(components: ["sessions", try stringArgument("session_id", in: arguments), "workspace"], uri: "tool://session.get_workspace")
        case "prompt_template.create":
            return try jsonText(codableDictionary(promptTemplateStore.create(
                task: try stringArgument("task", in: arguments),
                name: try stringArgument("name", in: arguments),
                bodyMarkdown: try stringArgument("body_markdown", in: arguments),
                variables: stringArrayArgument("variables", in: arguments) ?? []
            )))
        case "prompt_template.rename":
            return try jsonText(codableDictionary(promptTemplateStore.rename(templateID: try stringArgument("template_id", in: arguments), name: try stringArgument("name", in: arguments))))
        case "prompt_template.duplicate":
            return try jsonText(codableDictionary(promptTemplateStore.duplicate(templateID: try stringArgument("template_id", in: arguments), name: arguments["name"] as? String)))
        case "prompt_template.replace_body":
            _ = try promptTemplateStore.replaceBody(templateID: try stringArgument("template_id", in: arguments), bodyMarkdown: try stringArgument("body_markdown", in: arguments))
            return try jsonText(["status": "updated", "template_id": try stringArgument("template_id", in: arguments)])
        case "prompt_template.set_variables":
            return try jsonText(codableDictionary(promptTemplateStore.setVariables(templateID: try stringArgument("template_id", in: arguments), variables: stringArrayArgument("variables", in: arguments) ?? [])))
        case "prompt_template.set_default_for_task":
            return try jsonText(codableDictionary(promptTemplateStore.setDefault(task: try stringArgument("task", in: arguments), templateID: try stringArgument("template_id", in: arguments))))
        case "prompt_template.enable":
            return try jsonText(codableDictionary(promptTemplateStore.setEnabled(templateID: try stringArgument("template_id", in: arguments), enabled: true)))
        case "prompt_template.disable":
            return try jsonText(codableDictionary(promptTemplateStore.setEnabled(templateID: try stringArgument("template_id", in: arguments), enabled: false)))
        case "prompt_template.archive":
            return try jsonText(codableDictionary(promptTemplateStore.archive(templateID: try stringArgument("template_id", in: arguments))))
        case "prompt_template.preview_render":
            return try jsonText([
                "template_id": try stringArgument("template_id", in: arguments),
                "rendered": try promptTemplateStore.previewRender(
                    templateID: try stringArgument("template_id", in: arguments),
                    variables: stringDictionaryArgument("variables", in: arguments) ?? [:]
                )
            ])
        case "prompt_template.validate":
            return try jsonText(codableDictionary(promptTemplateStore.validate(templateID: try stringArgument("template_id", in: arguments))))
        case "reader.position_get":
            return try toolGetReaderPosition(arguments)
        case "reader.position_set":
            return try toolSetReaderPosition(arguments)
        default:
            throw PaperCodexMCPServiceError.toolNotFound(name)
        }
    }

    private func promptsList() -> [[String: Any]] {
        PromptTemplateStore.supportedTasks.map { task in
            [
                "name": task,
                "description": "Render the default Paper Codex prompt template for \(task).",
                "arguments": [
                    ["name": "paper_title", "description": "Paper title.", "required": false],
                    ["name": "user_goal", "description": "Current reading or organization goal.", "required": false],
                    ["name": "selected_text", "description": "Selected PDF or chat text.", "required": false]
                ]
            ]
        }
    }

    private func getPrompt(name: String, arguments: [String: String]) throws -> [String: Any] {
        let template = try promptTemplateStore.defaultTemplate(forTask: name)
        let rendered = try promptTemplateStore.previewRender(templateID: template.id, variables: arguments)
        return [
            "description": template.name,
            "messages": [[
                "role": "user",
                "content": [
                    "type": "text",
                    "text": rendered
                ]
            ]]
        ]
    }

    private func toolImportPDF(_ arguments: [String: Any]) throws -> String {
        let sourcePath = try stringArgument("source_path", in: arguments)
        let metadata = PaperImportMetadata(
            title: arguments["title"] as? String,
            authors: stringArrayArgument("authors", in: arguments) ?? [],
            year: intArgument("year", in: arguments),
            sourceURL: arguments["source_url"] as? String
        )
        let result = try withRepository {
            try PaperLibraryImporter(repository: repository, supportRoot: supportRoot).importPDF(
                from: URL(fileURLWithPath: sourcePath),
                metadata: metadata
            )
        }
        if let folderIDs = stringArrayArgument("folder_ids", in: arguments) {
            for folderID in folderIDs {
                try withRepository { try repository.assignPaper(result.paper.id, toCategory: folderID) }
            }
        }
        if let tagNames = stringArrayArgument("tag_names", in: arguments) {
            try assignTags(tagNames, toPaperID: result.paper.id, replaceExisting: false)
        }
        return try jsonText([
            "status": result.didImport ? "imported" : "already_exists",
            "paper": try codableDictionary(result.paper)
        ])
    }

    private func toolUpdatePaperMetadata(_ arguments: [String: Any]) throws -> String {
        let paperID = try stringArgument("paper_id", in: arguments)
        var paper = try resolvePaper(id: paperID)
        if let title = arguments["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paper.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let authors = stringArrayArgument("authors", in: arguments) {
            paper.authors = authors
        }
        if arguments.keys.contains("year") {
            paper.year = intArgument("year", in: arguments)
        }
        if let sourceURL = arguments["source_url"] as? String {
            paper.sourceURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        paper.updatedAt = Date()
        try withRepository { try repository.upsertPaper(paper) }
        return try jsonText(codableDictionary(paper))
    }

    private func toolStarPaper(_ arguments: [String: Any]) throws -> String {
        let paperID = try stringArgument("paper_id", in: arguments)
        guard let isStarred = boolArgument("is_starred", in: arguments) else {
            throw PaperCodexMCPServiceError.missingArgument("is_starred")
        }
        try withRepository { try repository.setPaperStarred(isStarred, paperID: paperID) }
        return try jsonText(["status": "updated", "paper_id": paperID, "is_starred": isStarred])
    }

    private func toolDeletePapers(_ arguments: [String: Any]) throws -> String {
        let paperIDs = try requiredStringArrayArgument("paper_ids", in: arguments)
        guard boolArgument("confirm", in: arguments) == true else {
            return try jsonText([
                "confirm_required": true,
                "operation": "paper.delete",
                "paper_ids": paperIDs,
                "message": "Call again with confirm=true to delete these papers and their repository rows."
            ])
        }
        try withRepository { try repository.deletePapers(ids: paperIDs) }
        return try jsonText(["status": "deleted", "paper_ids": paperIDs])
    }

    private func toolAddPaperToFolder(_ arguments: [String: Any]) throws -> String {
        let paperID = try stringArgument("paper_id", in: arguments)
        let folderID = try stringArgument("folder_id", in: arguments)
        try withRepository { try repository.assignPaper(paperID, toCategory: folderID) }
        return try jsonText(["status": "assigned", "paper_id": paperID, "folder_id": folderID])
    }

    private func toolRemovePaperFromFolder(_ arguments: [String: Any]) throws -> String {
        let paperID = try stringArgument("paper_id", in: arguments)
        let folderID = try stringArgument("folder_id", in: arguments)
        try withRepository { try repository.removePaper(paperID, fromCategory: folderID) }
        return try jsonText(["status": "removed", "paper_id": paperID, "folder_id": folderID])
    }

    private func toolMovePaperFolder(_ arguments: [String: Any]) throws -> String {
        let paperID = try stringArgument("paper_id", in: arguments)
        let toFolderID = arguments["to_folder_id"] as? String
        if let fromFolderID = arguments["from_folder_id"] as? String {
            try withRepository { try repository.removePaper(paperID, fromCategory: fromFolderID) }
        } else {
            for folderID in try withRepository({ try repository.fetchCategoryIDs(forPaperID: paperID) }) {
                try withRepository { try repository.removePaper(paperID, fromCategory: folderID) }
            }
        }
        if let toFolderID, !toFolderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try withRepository { try repository.assignPaper(paperID, toCategory: toFolderID) }
        }
        return try jsonText(["status": "moved", "paper_id": paperID, "to_folder_id": toFolderID as Any])
    }

    private func toolAddTags(_ arguments: [String: Any]) throws -> String {
        let paperID = try stringArgument("paper_id", in: arguments)
        let tags = try requiredStringArrayArgument("tags", in: arguments)
        try assignTags(tags, toPaperID: paperID, replaceExisting: false)
        return try jsonText(["status": "tagged", "paper_id": paperID, "tags": tags])
    }

    private func toolRemoveTags(_ arguments: [String: Any]) throws -> String {
        let paperID = try stringArgument("paper_id", in: arguments)
        let requested = Set(try requiredStringArrayArgument("tags", in: arguments).map(normalizedLookup))
        let tags = try withRepository { try repository.fetchTags() }
        for tag in tags where requested.contains(normalizedLookup(tag.id)) || requested.contains(normalizedLookup(tag.name)) {
            try withRepository { try repository.removePaper(paperID, fromTag: tag.id) }
        }
        return try jsonText(["status": "tags_removed", "paper_id": paperID])
    }

    private func toolSetTags(_ arguments: [String: Any]) throws -> String {
        let paperID = try stringArgument("paper_id", in: arguments)
        let tags = try requiredStringArrayArgument("tags", in: arguments)
        try assignTags(tags, toPaperID: paperID, replaceExisting: true)
        return try jsonText(["status": "tags_set", "paper_id": paperID, "tags": tags])
    }

    private func toolUpsertDigest(_ arguments: [String: Any]) throws -> String {
        let paperID = try stringArgument("paper_id", in: arguments)
        let body = try stringArgument("body_markdown", in: arguments)
        let existing = try digestNote(paperID: paperID)
        let now = Date()
        let note = PaperNote(
            id: existing?.id ?? "digest-\(paperID)",
            paperID: paperID,
            anchorID: existing?.anchorID,
            title: "Paper Digest",
            bodyMarkdown: body,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            deletedAt: nil,
            syncRevision: (existing?.syncRevision ?? 0) + 1
        )
        try withRepository { try repository.upsertNote(note) }
        return try jsonText(codableDictionary(note))
    }

    private func toolCreateFolder(_ arguments: [String: Any]) throws -> String {
        let name = try stringArgument("name", in: arguments).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw PaperCodexMCPServiceError.invalidArgument("folder name cannot be empty")
        }
        let parentID = arguments["parent_id"] as? String
        let categories = try withRepository { try repository.fetchCategories() }
        if let existing = categories.first(where: { $0.parentID == parentID && normalizedLookup($0.name) == normalizedLookup(name) }) {
            return try jsonText(["status": "already_exists", "folder": categoryDictionary(existing)])
        }
        let category = Category(id: manualID(prefix: "cat", name: name), parentID: parentID, name: name, sortOrder: (categories.map(\.sortOrder).max() ?? 0) + 10)
        try withRepository { try repository.upsertCategory(category) }
        return try jsonText(["status": "created", "folder": categoryDictionary(category)])
    }

    private func toolRenameFolder(_ arguments: [String: Any]) throws -> String {
        let folderID = try stringArgument("folder_id", in: arguments)
        var category = try resolveCategory(id: folderID)
        category.name = try stringArgument("name", in: arguments)
        try withRepository { try repository.upsertCategory(category) }
        return try jsonText(["status": "renamed", "folder": categoryDictionary(category)])
    }

    private func toolDeleteFolder(_ arguments: [String: Any]) throws -> String {
        let folderID = try stringArgument("folder_id", in: arguments)
        guard boolArgument("confirm", in: arguments) == true else {
            return try jsonText(["confirm_required": true, "operation": "folder.delete", "folder_id": folderID])
        }
        try withRepository { try repository.deleteCategory(id: folderID) }
        return try jsonText(["status": "deleted", "folder_id": folderID])
    }

    private func toolMoveFolder(_ arguments: [String: Any]) throws -> String {
        let folderID = try stringArgument("folder_id", in: arguments)
        var category = try resolveCategory(id: folderID)
        let parentID = arguments["parent_id"] as? String
        if parentID == folderID {
            throw PaperCodexMCPServiceError.invalidArgument("folder cannot be its own parent")
        }
        category.parentID = parentID
        try withRepository { try repository.upsertCategory(category) }
        return try jsonText(["status": "moved", "folder": categoryDictionary(category)])
    }

    private func toolCreateTag(_ arguments: [String: Any]) throws -> String {
        let name = try stringArgument("name", in: arguments).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw PaperCodexMCPServiceError.invalidArgument("tag name cannot be empty")
        }
        let tag = try ensureTag(nameOrID: name)
        return try jsonText(["status": "created_or_existing", "tag": tagDictionary(tag)])
    }

    private func toolRenameTag(_ arguments: [String: Any]) throws -> String {
        let tagID = try stringArgument("tag_id", in: arguments)
        let name = try stringArgument("name", in: arguments)
        let tag = PaperTag(id: tagID, name: name)
        try withRepository { try repository.upsertTag(tag) }
        return try jsonText(["status": "renamed", "tag": tagDictionary(tag)])
    }

    private func toolDeleteTag(_ arguments: [String: Any]) throws -> String {
        let tagID = try stringArgument("tag_id", in: arguments)
        guard boolArgument("confirm", in: arguments) == true else {
            return try jsonText(["confirm_required": true, "operation": "tag.delete", "tag_id": tagID])
        }
        try withRepository { try repository.deleteTag(id: tagID) }
        return try jsonText(["status": "deleted", "tag_id": tagID])
    }

    private func toolSuggestTags(_ arguments: [String: Any]) throws -> String {
        let text = [
            arguments["text"] as? String,
            (arguments["paper_id"] as? String).flatMap { try? paperMetadata(paperID: $0)["title"] as? String }
        ].compactMap { $0 }.joined(separator: " ")
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        let stop: Set<String> = ["this", "that", "with", "from", "paper", "method", "result"]
        let suggestions = Array(Set(words.filter { !stop.contains($0) })).sorted().prefix(8)
        return try jsonText(["suggestions": Array(suggestions), "applied": false])
    }

    private func toolCreateNote(_ arguments: [String: Any]) throws -> String {
        let paperID = try stringArgument("paper_id", in: arguments)
        let body = try stringArgument("body_markdown", in: arguments)
        let title = (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled note"
        let now = Date()
        let note = PaperNote(
            id: "note-\(UUID().uuidString.lowercased())",
            paperID: paperID,
            anchorID: arguments["anchor_id"] as? String,
            title: title,
            bodyMarkdown: body,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            syncRevision: 1
        )
        try withRepository { try repository.upsertNote(note) }
        return try jsonText(codableDictionary(note))
    }

    private func toolUpdateNote(_ arguments: [String: Any]) throws -> String {
        let paperID = try stringArgument("paper_id", in: arguments)
        let noteID = try stringArgument("note_id", in: arguments)
        var note = try findNote(noteID: noteID, paperID: paperID)
        if let title = arguments["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            note.title = title
        }
        if let body = arguments["body_markdown"] as? String {
            note.bodyMarkdown = body
        }
        note.updatedAt = Date()
        note.syncRevision += 1
        try withRepository { try repository.upsertNote(note) }
        return try jsonText(codableDictionary(note))
    }

    private func toolDeleteNote(_ arguments: [String: Any]) throws -> String {
        let paperID = try stringArgument("paper_id", in: arguments)
        let noteID = try stringArgument("note_id", in: arguments)
        guard boolArgument("confirm", in: arguments) == true else {
            return try jsonText(["confirm_required": true, "operation": "note.delete", "paper_id": paperID, "note_id": noteID])
        }
        try withRepository { try repository.deleteNote(id: noteID) }
        return try jsonText(["status": "deleted", "paper_id": paperID, "note_id": noteID])
    }

    private func toolCreateNoteFromAnchor(_ arguments: [String: Any]) throws -> String {
        let anchor = try resolveAnchor(id: try stringArgument("anchor_id", in: arguments))
        var enriched = arguments
        enriched["paper_id"] = anchor.paperID
        enriched["anchor_id"] = anchor.id
        if enriched["title"] == nil {
            enriched["title"] = "Note from page \(anchor.page)"
        }
        return try toolCreateNote(enriched)
    }

    private func toolSearchAnchors(_ arguments: [String: Any]) throws -> String {
        let paperID = try stringArgument("paper_id", in: arguments)
        let query = normalizedLookup(try stringArgument("query", in: arguments))
        let anchors = try withRepository { try repository.fetchAnchors(paperID: paperID) }.filter { anchor in
            [anchor.selectedText, anchor.beforeContext, anchor.afterContext].contains { normalizedLookup($0).contains(query) }
        }
        return try jsonText(anchors.map(codableDictionary))
    }

    private func toolAddWatchedFolder(_ arguments: [String: Any]) throws -> String {
        let path = try stringArgument("path", in: arguments)
        let folder = WatchedFolder(id: manualID(prefix: "watch", name: path), path: path, createdAt: Date(), lastScannedAt: nil)
        try withRepository { try repository.upsertWatchedFolder(folder) }
        return try jsonText(codableDictionary(folder))
    }

    private func toolRemoveWatchedFolder(_ arguments: [String: Any]) throws -> String {
        let folderID = try stringArgument("folder_id", in: arguments)
        try withRepository { try repository.deleteWatchedFolder(id: folderID) }
        return try jsonText(["status": "removed", "folder_id": folderID])
    }

    private func toolScanWatchedFolders() throws -> String {
        let results = try withRepository {
            try WatchedFolderScanner(repository: repository, supportRoot: supportRoot).scanAllWatchedFolders()
        }
        return try jsonText(results.map { result in
            [
                "folder": result.folder.path,
                "imported_paper_ids": result.importedPapers.map { $0.id },
                "existing_paper_ids": result.existingPapers.map { $0.id }
            ]
        })
    }

    private func enqueueAppCommand(type: String, arguments: [String: String]) throws -> String {
        let command = PaperCodexMCPAppCommand(type: type, arguments: arguments)
        let logURL = PaperCodexMCPAppCommand.commandLogURL(supportRoot: supportRoot)
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(command) + Data("\n".utf8)
        if FileManager.default.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: logURL, options: [.atomic])
        }
        return try jsonText([
            "status": "queued",
            "command": codableDictionary(command)
        ])
    }

    private func toolGetReaderPosition(_ arguments: [String: Any]) throws -> String {
        let sessionID = try stringArgument("session_id", in: arguments)
        let paperID = try stringArgument("paper_id", in: arguments)
        guard let position = try withRepository({ try repository.fetchReaderPosition(sessionID: sessionID, paperID: paperID) }) else {
            return try jsonText(["position": NSNull()])
        }
        return try jsonText(codableDictionary(position))
    }

    private func toolSetReaderPosition(_ arguments: [String: Any]) throws -> String {
        let sessionID = try stringArgument("session_id", in: arguments)
        let paperID = try stringArgument("paper_id", in: arguments)
        let position = PaperReaderPosition(
            sessionID: sessionID,
            paperID: paperID,
            pageIndex: intArgument("page_index", in: arguments) ?? 0,
            pagePointX: doubleArgument("page_point_x", in: arguments) ?? 0,
            pagePointY: doubleArgument("page_point_y", in: arguments) ?? 0,
            scaleFactor: doubleArgument("scale_factor", in: arguments) ?? 1,
            updatedAt: Date()
        )
        try withRepository { try repository.upsertReaderPosition(position) }
        return try jsonText(codableDictionary(position))
    }

    private func paperSummaries() throws -> [[String: Any]] {
        let papers = try withRepository { try repository.fetchPapers() }
        let categoryIDsByPaperID = try withRepository { try repository.fetchCategoryIDsByPaperID() }
        let tagsByPaperID = try withRepository { try repository.fetchTagsByPaperID() }
        let categories = Dictionary(uniqueKeysWithValues: try withRepository { try repository.fetchCategories() }.map { ($0.id, $0) })
        return papers.map { paper in
            let folderIDs = categoryIDsByPaperID[paper.id, default: []]
            let tags = tagsByPaperID[paper.id, default: []]
            return [
                "id": paper.id,
                "title": paper.title,
                "authors": paper.authors,
                "year": paper.year as Any,
                "source_url": paper.sourceURL as Any,
                "is_starred": paper.isStarred,
                "file_path": paper.filePath,
                "folder_ids": folderIDs,
                "folders": folderIDs.compactMap { categories[$0]?.name },
                "tag_ids": tags.map(\.id),
                "tags": tags.map(\.name)
            ]
        }
    }

    private func paperMetadata(paperID: String) throws -> [String: Any] {
        let paper = try resolvePaper(id: paperID)
        let folderIDs = try withRepository { try repository.fetchCategoryIDs(forPaperID: paperID) }
        let categories = Dictionary(uniqueKeysWithValues: try withRepository { try repository.fetchCategories() }.map { ($0.id, $0) })
        let tags = try withRepository { try repository.fetchTags(forPaperID: paperID) }
        var dictionary = try codableDictionary(paper)
        dictionary["folder_ids"] = folderIDs
        dictionary["folders"] = folderIDs.compactMap { categories[$0]?.name }
        dictionary["tag_ids"] = tags.map(\.id)
        dictionary["tags"] = tags.map(\.name)
        return dictionary
    }

    private func digestDictionary(paperID: String) throws -> [String: Any] {
        if let note = try digestNote(paperID: paperID) {
            return try [
                "paper_id": paperID,
                "note": codableDictionary(note)
            ]
        }
        return ["paper_id": paperID, "note": NSNull()]
    }

    private func digestNote(paperID: String) throws -> PaperNote? {
        try withRepository { try repository.fetchNotes(paperID: paperID) }
            .first { $0.title.localizedCaseInsensitiveCompare("Paper Digest") == .orderedSame || $0.id == "digest-\(paperID)" }
    }

    private func searchPapers(query: String, limit: Int) throws -> [[String: Any]] {
        let normalized = normalizedLookup(query)
        guard !normalized.isEmpty else {
            return []
        }
        let summaries = try paperSummaries()
        var matches = summaries.filter { summary in
            let haystack = [
                summary["title"] as? String,
                (summary["authors"] as? [String])?.joined(separator: " "),
                summary["source_url"] as? String,
                (summary["folders"] as? [String])?.joined(separator: " "),
                (summary["tags"] as? [String])?.joined(separator: " ")
            ].compactMap { $0 }.joined(separator: " ")
            return normalizedLookup(haystack).contains(normalized)
        }
        if matches.count < limit {
            let knownIDs = Set(matches.compactMap { $0["id"] as? String })
            for paper in try withRepository({ try repository.fetchPapers() }) where !knownIDs.contains(paper.id) {
                let pages = try withRepository { try repository.fetchPages(paperID: paper.id) }
                if pages.contains(where: { normalizedLookup($0.text).contains(normalized) }),
                   let summary = summaries.first(where: { $0["id"] as? String == paper.id }) {
                    matches.append(summary)
                }
                if matches.count >= limit {
                    break
                }
            }
        }
        return Array(matches.prefix(limit))
    }

    private func deduplicatePapers() throws -> [[String: Any]] {
        let papers = try withRepository { try repository.fetchPapers() }
        let bySource = Dictionary(grouping: papers) { paper in
            normalizedLookup(paper.sourceURL ?? "")
        }
        return bySource.values
            .filter { group in group.count > 1 && !(group.first?.sourceURL ?? "").isEmpty }
            .map { group in
                [
                    "reason": "same_source_url",
                    "paper_ids": group.map(\.id),
                    "titles": group.map(\.title)
                ]
            }
    }

    private func resolvePaper(id: String) throws -> Paper {
        guard let paper = try withRepository({ try repository.fetchPapers(ids: [id]).first }) else {
            throw PaperCodexMCPServiceError.resourceNotFound("paper \(id)")
        }
        return paper
    }

    private func resolveCategory(id: String) throws -> Category {
        guard let category = try withRepository({ try repository.fetchCategories().first(where: { $0.id == id }) }) else {
            throw PaperCodexMCPServiceError.resourceNotFound("folder \(id)")
        }
        return category
    }

    private func resolveAnchor(id: String) throws -> Anchor {
        guard let anchor = try withRepository({ try repository.fetchAnchor(id: id) }) else {
            throw PaperCodexMCPServiceError.resourceNotFound("anchor \(id)")
        }
        return anchor
    }

    private func resolveSession(id: String) throws -> PaperSession {
        guard let session = try withRepository({ try repository.fetchSession(id: id) }) else {
            throw PaperCodexMCPServiceError.resourceNotFound("session \(id)")
        }
        return session
    }

    private func resolveCitation(id: String) throws -> [String: Any] {
        if let span = try withRepository({ try repository.fetchSpan(id: id) }) {
            return ["kind": "span", "span": try codableDictionary(span)]
        }
        if let baseID = CitationParser.baseSpanCitationID(for: id),
           let span = try withRepository({ try repository.fetchSpan(id: baseID) }) {
            return ["kind": "span", "requested_id": id, "span": try codableDictionary(span)]
        }
        if let anchor = try withRepository({ try repository.fetchAnchor(id: id) }) {
            return ["kind": "anchor", "anchor": try codableDictionary(anchor)]
        }
        throw PaperCodexMCPServiceError.resourceNotFound("citation \(id)")
    }

    private func findNote(noteID: String, paperID: String?) throws -> PaperNote {
        if let paperID,
           let note = try withRepository({ try repository.fetchNotes(paperID: paperID).first(where: { $0.id == noteID }) }) {
            return note
        }
        for paper in try withRepository({ try repository.fetchPapers() }) {
            if let note = try withRepository({ try repository.fetchNotes(paperID: paper.id).first(where: { $0.id == noteID }) }) {
                return note
            }
        }
        throw PaperCodexMCPServiceError.resourceNotFound("note \(noteID)")
    }

    private func ensureTag(nameOrID: String) throws -> PaperTag {
        let normalized = normalizedLookup(nameOrID)
        let tags = try withRepository { try repository.fetchTags() }
        if let existing = tags.first(where: { normalizedLookup($0.id) == normalized || normalizedLookup($0.name) == normalized }) {
            return existing
        }
        let tag = PaperTag(id: manualID(prefix: "tag", name: nameOrID), name: nameOrID)
        try withRepository { try repository.upsertTag(tag) }
        return tag
    }

    private func assignTags(_ namesOrIDs: [String], toPaperID paperID: String, replaceExisting: Bool) throws {
        if replaceExisting {
            for tag in try withRepository({ try repository.fetchTags(forPaperID: paperID) }) {
                try withRepository { try repository.removePaper(paperID, fromTag: tag.id) }
            }
        }
        for nameOrID in namesOrIDs {
            let tag = try ensureTag(nameOrID: nameOrID)
            try withRepository { try repository.assignPaper(paperID, toTag: tag.id) }
        }
    }

    private func activeContextDictionary() throws -> [String: Any] {
        let snapshotURL = supportRoot.appendingPathComponent("mcp/active-context.json")
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return try codableDictionary(PaperCodexMCPActiveContext())
        }
        let data = try Data(contentsOf: snapshotURL)
        let context = try JSONDecoder.paperCodex.decode(PaperCodexMCPActiveContext.self, from: data)
        return try codableDictionary(context)
    }

    private func categoryDictionary(_ category: Category) -> [String: Any] {
        [
            "id": category.id,
            "parent_id": category.parentID as Any,
            "name": category.name,
            "sort_order": category.sortOrder,
            "is_pinned": category.isPinned
        ]
    }

    private func tagDictionary(_ tag: PaperTag) -> [String: Any] {
        [
            "id": tag.id,
            "name": tag.name
        ]
    }

    private func runtimeSessionLinkDictionary(_ link: AgentRuntimeSessionLink) -> [String: Any] {
        [
            "runtime_id": link.runtimeID,
            "session_id": link.sessionID
        ]
    }

    private func sessionWorkspaceURL(_ session: PaperSession) -> URL {
        URL(fileURLWithPath: session.workspacePath, isDirectory: true)
    }

    private func withRepository<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func jsonText(_ object: Any) throws -> String {
        let normalized = sanitizeJSONValue(object)
        let data = try JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw PaperCodexMCPServiceError.invalidRequest("could not encode JSON text")
        }
        return text
    }

    private func codableDictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PaperCodexMCPServiceError.invalidRequest("could not encode \(T.self) as JSON object")
        }
        return dictionary
    }

    private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ]
    }

    private func errorCode(for error: Error) -> Int {
        switch error {
        case PaperCodexMCPServiceError.methodNotFound:
            return -32601
        case PaperCodexMCPServiceError.toolNotFound, PaperCodexMCPServiceError.resourceNotFound:
            return -32004
        case PaperCodexMCPServiceError.missingArgument, PaperCodexMCPServiceError.invalidArgument:
            return -32602
        default:
            return -32000
        }
    }
}

private func resource(uri: String, name: String, description: String) -> [String: Any] {
    [
        "uri": uri,
        "name": name,
        "description": description,
        "mimeType": "application/json"
    ]
}

private func resourceTemplate(uri: String, name: String, description: String) -> [String: Any] {
    [
        "uriTemplate": uri,
        "name": name,
        "description": description,
        "mimeType": "application/json"
    ]
}

private func tool(_ name: String, _ description: String, _ properties: [String: String], _ required: [String]) -> [String: Any] {
    [
        "name": name,
        "description": description,
        "inputSchema": [
            "type": "object",
            "properties": properties.mapValues { type in
                ["type": type]
            },
            "required": required
        ]
    ]
}

private func pathComponents(uri: String) -> [String] {
    guard uri.hasPrefix("papercodex://") else {
        return []
    }
    return String(uri.dropFirst("papercodex://".count))
        .split(separator: "/")
        .map(String.init)
}

private func stringArgument(_ name: String, in arguments: [String: Any]) throws -> String {
    guard let value = arguments[name] as? String,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw PaperCodexMCPServiceError.missingArgument(name)
    }
    return value
}

private func intArgument(_ name: String, in arguments: [String: Any]) -> Int? {
    if let int = arguments[name] as? Int {
        return int
    }
    if let number = arguments[name] as? NSNumber {
        return number.intValue
    }
    if let string = arguments[name] as? String {
        return Int(string)
    }
    return nil
}

private func doubleArgument(_ name: String, in arguments: [String: Any]) -> Double? {
    if let double = arguments[name] as? Double {
        return double
    }
    if let number = arguments[name] as? NSNumber {
        return number.doubleValue
    }
    if let string = arguments[name] as? String {
        return Double(string)
    }
    return nil
}

private func boolArgument(_ name: String, in arguments: [String: Any]) -> Bool? {
    if let bool = arguments[name] as? Bool {
        return bool
    }
    if let number = arguments[name] as? NSNumber {
        return number.boolValue
    }
    if let string = arguments[name] as? String {
        return ["true", "yes", "1"].contains(string.lowercased())
    }
    return nil
}

private func stringArrayArgument(_ name: String, in arguments: [String: Any]) -> [String]? {
    if let values = arguments[name] as? [String] {
        return values
    }
    if let values = arguments[name] as? [Any] {
        return values.compactMap { $0 as? String }
    }
    if let value = arguments[name] as? String {
        return value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    return nil
}

private func requiredStringArrayArgument(_ name: String, in arguments: [String: Any]) throws -> [String] {
    guard let values = stringArrayArgument(name, in: arguments), !values.isEmpty else {
        throw PaperCodexMCPServiceError.missingArgument(name)
    }
    return values
}

private func stringDictionaryArgument(_ name: String, in arguments: [String: Any]) -> [String: String]? {
    if let dictionary = arguments[name] as? [String: String] {
        return dictionary
    }
    if let dictionary = arguments[name] as? [String: Any] {
        return dictionary.reduce(into: [String: String]()) { partial, pair in
            if let value = pair.value as? String {
                partial[pair.key] = value
            } else {
                partial[pair.key] = String(describing: pair.value)
            }
        }
    }
    return nil
}

private func manualID(prefix: String, name: String) -> String {
    let slug = name
        .lowercased()
        .map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        .reduce(into: "") { partial, character in
            if character == "-", partial.last == "-" {
                return
            }
            partial.append(character)
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return "\(prefix)-\(slug.isEmpty ? UUID().uuidString.lowercased() : slug)"
}

private func normalizedLookup(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func sanitizeJSONValue(_ value: Any) -> Any {
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional {
        guard let child = mirror.children.first else {
            return NSNull()
        }
        return sanitizeJSONValue(child.value)
    }
    switch value {
    case let dictionary as [String: Any]:
        return dictionary.mapValues(sanitizeJSONValue)
    case let array as [Any]:
        return array.map(sanitizeJSONValue)
    case let value as Bool:
        return value
    case let value as String:
        return value
    case let value as Int:
        return value
    case let value as Double:
        return value
    case let value as NSNull:
        return value
    case let value as NSNumber:
        return value
    default:
        return String(describing: value)
    }
}

private extension JSONDecoder {
    static var paperCodex: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
