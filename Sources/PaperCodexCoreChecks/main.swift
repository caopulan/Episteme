import Foundation
import AppKit
import CryptoKit
import PDFKit
import PaperCodexCore

struct CheckFailure: Error, CustomStringConvertible {
    var description: String
}

final class LockedStringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: String?

    func set(_ value: String) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }

    func get() -> String? {
        lock.lock()
        let value = storedValue
        lock.unlock()
        return value
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CheckFailure(description: message)
    }
}

func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw CheckFailure(description: message)
    }
    return value
}

func runModelsChecks() throws {
    let span = Span(
        id: Span.makeID(paperID: "paper-a", page: 5, blockIndex: 17),
        paperID: "paper-a",
        page: 5,
        bbox: BoundingBox(x: 10, y: 20, width: 120, height: 34),
        text: "Diffusion models denoise latent variables.",
        charRange: TextRange(location: 12, length: 42),
        sectionHint: "Method",
        confidence: 0.92
    )

    try check(span.id == "paper:paper-a:p5:b17", "span stable ID should include paper, page, and block")
    try check(span.page == 5, "span page should round-trip")
    try check(span.bbox.width == 120, "span bbox width should round-trip")

    let longSpan = Span(
        id: Span.makeID(paperID: "paper-a", page: 5, blockIndex: 18),
        paperID: "paper-a",
        page: 5,
        bbox: BoundingBox(x: 10, y: 60, width: 300, height: 120),
        text: String(repeating: "Long citation evidence sentence. ", count: 18),
        charRange: TextRange(location: 60, length: 540),
        sectionHint: nil,
        confidence: 0.9
    )
    let compactedLongSpan = SpanCompactor.compact([longSpan])
    try check(compactedLongSpan.count > 1, "oversized imported spans should be split into smaller citation blocks")
    try check(compactedLongSpan.allSatisfy { $0.text.count <= 420 }, "split citation blocks should stay within the target size")
    try check(compactedLongSpan.first?.id == longSpan.id, "first split should preserve the original citation id")
    try check(compactedLongSpan.dropFirst().allSatisfy { $0.id.hasPrefix("\(longSpan.id)s") }, "later splits should keep resolvable citation aliases")

    let anchor = Anchor(
        id: Anchor.makeID(paperID: "paper-a", page: 5, suffix: "01HX"),
        paperID: "paper-a",
        page: 5,
        selectedText: "selected paragraph",
        bboxList: [BoundingBox(x: 4, y: 8, width: 40, height: 16)],
        matchedSpanIDs: ["paper:paper-a:p5:b17"],
        beforeContext: "before",
        afterContext: "after",
        createdSessionID: "session-a",
        createdAt: Date(timeIntervalSince1970: 1_777_220_000),
        confidence: 0.88
    )

    try check(anchor.id == "paper:paper-a:p5:a01HX", "anchor stable ID should include paper, page, and suffix")
    try check(anchor.matchedSpanIDs == ["paper:paper-a:p5:b17"], "anchor should keep matched span IDs")

    let paper = Paper(
        id: "paper-a",
        filePath: "/tmp/paper.pdf",
        fileHash: "sha256",
        title: "Representation Autoencoders",
        authors: ["Alice", "Bob"],
        year: 2026,
        sourceURL: "https://arxiv.org/abs/0000.00000",
        isStarred: true,
        importedAt: Date(timeIntervalSince1970: 1_777_220_000),
        updatedAt: Date(timeIntervalSince1970: 1_777_220_010)
    )
    let session = PaperSession(
        id: "session-a",
        title: "Mechanism Notes",
        paperIDs: ["paper-a", "paper-b"],
        codexSessionID: "codex-session",
        workspacePath: "/tmp/session",
        createdAt: Date(timeIntervalSince1970: 1_777_220_000),
        updatedAt: Date(timeIntervalSince1970: 1_777_220_020)
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let decodedPaper = try decoder.decode(Paper.self, from: encoder.encode(paper))
    let decodedSession = try decoder.decode(PaperSession.self, from: encoder.encode(session))
    try check(decodedPaper == paper, "paper should JSON round-trip")
    try check(decodedPaper.isStarred, "paper JSON round-trip should preserve library star state")
    try check(decodedSession == session, "session should JSON round-trip")
    let legacyPaperJSON = """
    {
      "id": "legacy-paper",
      "filePath": "/tmp/legacy.pdf",
      "fileHash": "legacy-sha256",
      "title": "Legacy Paper",
      "authors": [],
      "sourceURL": null,
      "importedAt": "2026-04-27T00:00:00Z",
      "updatedAt": "2026-04-27T00:00:00Z"
    }
    """
    let legacyPaper = try decoder.decode(Paper.self, from: Data(legacyPaperJSON.utf8))
    try check(!legacyPaper.isStarred, "paper JSON decode should default missing star state to false")

    let placeholderID = Paper.makeArxivImportPlaceholderID(for: "2604.18586v2")
    let placeholder = Paper(
        id: placeholderID,
        filePath: "",
        fileHash: Paper.arxivImportPlaceholderFileHash(canonicalID: "2604.18586"),
        title: "2604.18586",
        authors: [],
        year: nil,
        sourceURL: "https://arxiv.org/abs/2604.18586",
        importedAt: Date(timeIntervalSince1970: 1_777_220_000),
        updatedAt: Date(timeIntervalSince1970: 1_777_220_000)
    )
    try check(placeholderID == "pending-arxiv-2604-18586v2", "arXiv import placeholder IDs should be stable and path-safe")
    try check(placeholder.isArxivImportPlaceholder, "pending arXiv imports should be represented as placeholder papers")
    try check(placeholder.arxivImportPlaceholderCanonicalID == "2604.18586", "placeholder papers should expose their canonical arXiv ID")
}

func runLocalStoreV2ModelChecks() throws {
    let now = Date(timeIntervalSince1970: 1_777_300_000)
    let file = PaperFileRecord(
        id: "file-a",
        paperID: "paper-a",
        storageState: .savedLocal,
        localPath: "/tmp/paper-a/original.pdf",
        contentHash: "hash-a",
        byteCount: 42,
        mimeType: "application/pdf",
        remoteFileID: nil,
        encryptionState: .none,
        createdAt: now,
        updatedAt: now
    )
    let source = PaperSourceRecord(
        id: "source-a",
        paperID: "paper-a",
        sourceType: .arxiv,
        sourceID: "2604.18586",
        url: "https://arxiv.org/abs/2604.18586",
        version: "v1",
        metadataJSON: #"{"primary_category":"cs.CV"}"#,
        createdAt: now
    )
    let note = PaperNote(
        id: "note-a",
        paperID: "paper-a",
        anchorID: nil,
        title: "Reading note",
        bodyMarkdown: "Important limitation.",
        createdAt: now,
        updatedAt: now,
        deletedAt: nil,
        syncRevision: 1
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decodedFile = try decoder.decode(PaperFileRecord.self, from: encoder.encode(file))
    let decodedSource = try decoder.decode(PaperSourceRecord.self, from: encoder.encode(source))
    let decodedNote = try decoder.decode(PaperNote.self, from: encoder.encode(note))
    try check(decodedFile == file, "paper file record should JSON round-trip")
    try check(decodedSource == source, "paper source record should JSON round-trip")
    try check(decodedNote == note, "paper note should JSON round-trip")
    try check(PaperStorageState.feedPDFCache.rawValue == "feed_pdf_cache", "feed PDF cache state should be stable")
}

func runReaderTabStateChecks() throws {
    var state = ReaderTabState()
    let paperA = ReaderPaperTab(paperID: "paper-a", title: "Paper A", detail: "/tmp/a.pdf", isSaved: true)
    let paperB = ReaderPaperTab(paperID: "paper-b", title: "Paper B", detail: "/tmp/b.pdf", isSaved: true)
    let paperC = ReaderPaperTab(paperID: "paper-c", title: "Paper C", detail: "/tmp/c.pdf", isSaved: true)

    state.open(paperA)
    state.open(paperB)
    state.open(paperA)
    try check(state.tabs.map(\.paperID) == ["paper-a", "paper-b"], "opening an existing reader tab should focus it without duplicating it")
    try check(state.activePaperID == "paper-a", "opening an existing reader tab should make it active")

    state.open(paperC)
    _ = state.select("paper-a")
    try check(state.adjacentPaperID(offset: 1) == "paper-b", "reader tab state should find the next tab from the active tab")
    try check(state.adjacentPaperID(offset: -1) == "paper-c", "reader tab state should wrap to the previous tab from the first tab")
    try check(state.adjacentPaperID(from: "paper-c", offset: 1) == "paper-a", "reader tab state should wrap next from the last tab")
    let nextAfterClosingMiddle = state.close("paper-b")
    try check(nextAfterClosingMiddle == "paper-a", "closing an inactive tab should keep the current tab active")
    try check(state.tabs.map(\.paperID) == ["paper-a", "paper-c"], "closing a reader tab should remove only that tab")

    let nextAfterClosingActive = state.close("paper-a")
    try check(nextAfterClosingActive == "paper-c", "closing the active reader tab should select the nearest remaining tab")
    try check(state.activePaperID == "paper-c", "reader tab state should update the active paper after close")

    let savedPaperC = ReaderPaperTab(paperID: "paper-c-saved", title: "Paper C", detail: "/library/c.pdf", isSaved: true)
    state.replace("paper-c", with: savedPaperC)
    try check(state.tabs.map(\.paperID) == ["paper-c-saved"], "saving a cached paper should replace the existing reader tab")
    try check(state.activePaperID == "paper-c-saved", "replacing the active reader tab should keep it active under the new paper id")

    let last = state.close("paper-c-saved")
    try check(last == nil, "closing the last reader tab should leave no active paper")
    try check(state.tabs.isEmpty, "closing the last reader tab should clear open tabs")
}

func runReaderPositionRepositoryChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-reader-positions-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let databaseURL = tempRoot.appendingPathComponent("store.sqlite")
    let repository = try PaperRepository(databasePath: databaseURL.path)
    try repository.migrate()

    let now = Date(timeIntervalSince1970: 1_777_260_000)
    let paper = Paper(
        id: "paper-a",
        filePath: "/tmp/paper-a.pdf",
        fileHash: "hash-reader-position-a",
        title: "Paper A",
        authors: ["Alice"],
        year: 2026,
        sourceURL: nil,
        importedAt: now,
        updatedAt: now
    )
    try repository.upsertPaper(paper)

    let sessionA = PaperSession(
        id: "session-a",
        title: "Session A",
        paperIDs: [paper.id],
        codexSessionID: nil,
        workspacePath: tempRoot.appendingPathComponent("session-a").path,
        createdAt: now,
        updatedAt: now
    )
    let sessionB = PaperSession(
        id: "session-b",
        title: "Session B",
        paperIDs: [paper.id],
        codexSessionID: nil,
        workspacePath: tempRoot.appendingPathComponent("session-b").path,
        createdAt: now,
        updatedAt: now
    )
    try repository.upsertSession(sessionA)
    try repository.upsertSession(sessionB)

    let positionA = PaperReaderPosition(
        sessionID: sessionA.id,
        paperID: paper.id,
        pageIndex: 4,
        pagePointX: 120.5,
        pagePointY: 730.25,
        scaleFactor: 1.35,
        updatedAt: now
    )
    let positionB = PaperReaderPosition(
        sessionID: sessionB.id,
        paperID: paper.id,
        pageIndex: 9,
        pagePointX: 82,
        pagePointY: 240,
        scaleFactor: 0.92,
        updatedAt: now.addingTimeInterval(30)
    )

    try repository.upsertReaderPosition(positionA)
    try repository.upsertReaderPosition(positionB)

    let fetchedPositionA = try repository.fetchReaderPosition(sessionID: sessionA.id, paperID: paper.id)
    let fetchedPositionB = try repository.fetchReaderPosition(sessionID: sessionB.id, paperID: paper.id)
    try check(fetchedPositionA == positionA, "reader position should be scoped by session and paper")
    try check(fetchedPositionB == positionB, "different sessions should keep independent positions for the same paper")

    let reopened = try PaperRepository(databasePath: databaseURL.path)
    try reopened.migrate()
    let reopenedPositionA = try reopened.fetchReaderPosition(sessionID: sessionA.id, paperID: paper.id)
    try check(reopenedPositionA == positionA, "reader position should survive repository reopen")
}

func runAppKitLifecycleSourceChecks() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let rootViewSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexApp.swift"))
    let mainSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexMain.swift"))
    let delegateSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexApplicationDelegate.swift"))
    let windowControllerSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexMainWindowController.swift"))
    let menuSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexMainMenu.swift"))

    try check(
        mainSource.contains("@main")
            && mainSource.contains("NSApplication.shared")
            && mainSource.contains("PaperCodexApplicationDelegate")
            && mainSource.contains("app.run()"),
        "Episteme should boot through an AppKit NSApplication main loop"
    )
    try check(
        delegateSource.contains("NSApplicationDelegate")
            && delegateSource.contains("PaperCodexMainWindowController")
            && delegateSource.contains("PaperCodexMainMenuController")
            && delegateSource.contains("applicationShouldHandleReopen"),
        "AppKit application delegate should own the model, main window controller, menu controller, and Dock reopen behavior"
    )
    try check(
        windowControllerSource.contains("final class PaperCodexMainWindowController: NSWindowController")
            && windowControllerSource.contains("NSHostingView(rootView:")
            && windowControllerSource.contains(".fullSizeContentView")
            && windowControllerSource.contains("titlebarAppearsTransparent")
            && windowControllerSource.contains("installTitlebarDoubleClickZoomMonitor"),
        "main window should be an AppKit window controller that hosts the existing root view and owns native chrome behavior"
    )
    try check(
        menuSource.contains("final class PaperCodexMainMenuController")
            && menuSource.contains("NSMenuItemValidation")
            && menuSource.contains("makeMainMenu() -> NSMenu")
            && menuSource.contains(#"#selector(goToLibrary)"#)
            && menuSource.contains(#"#selector(showDiscover)"#)
            && menuSource.contains(#"#selector(showSearch)"#)
            && menuSource.contains(#"#selector(newSession)"#)
            && menuSource.contains(#"#selector(focusChatComposer)"#)
            && menuSource.contains(#"#selector(fitPDFWidth)"#),
        "native AppKit menu should preserve the app's navigation, session, focus, and PDF commands"
    )
    try check(
        !rootViewSource.contains("@main")
            && !rootViewSource.contains("WindowGroup")
            && !rootViewSource.contains(".windowStyle(")
            && !rootViewSource.contains(".commands {")
            && !rootViewSource.contains("PaperCodexCommands")
            && !rootViewSource.contains("WindowChromeConfigurator()")
            && rootViewSource.contains("struct RootView: View")
            && rootViewSource.contains("paperCodexTypographyScale()"),
        "SwiftUI root content should remain a hosted content view rather than owning the application/window lifecycle"
    )
    try check(
        rootViewSource.contains("private let initiallyMountedRoutes: Set<AppRoute> = []")
            && !rootViewSource.contains("scheduleRouteCacheWarmup()")
            && !rootViewSource.contains("routeCacheWarmupTask"),
        "root view should not pre-mount hidden routes because offscreen SwiftUI/AppKit scroll surfaces still perform layout work"
    )
}

func runMCPChecks() throws {
    let fixture = try makeMCPFixture(withPaper: true)
    let service = PaperCodexMCPService(repository: fixture.repository, supportRoot: fixture.root)

    let toolsResponse = try service.handleJSONRPC([
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/list"
    ])
    let toolNames = try mcpResultArray(toolsResponse, key: "tools").compactMap { $0["name"] as? String }
    try check(toolNames.contains("paper.import_pdf"), "MCP should expose PDF import as a typed tool")
    try check(toolNames.contains("paper.add_tags"), "MCP should expose paper tag assignment as a typed tool")
    try check(toolNames.contains("note.create"), "MCP should expose note creation as a typed tool")
    try check(toolNames.contains("prompt_template.validate"), "MCP should expose prompt template validation")
    try check(toolNames.contains("prompt_template.preview_render"), "MCP should expose prompt template preview rendering")
    try check(toolNames.contains("app.open_paper"), "MCP should expose app paper-opening commands")
    try check(toolNames.contains("app.jump_to_anchor"), "MCP should expose app anchor jump commands")
    try check(!toolNames.contains("settings.update"), "MCP should not expose generic settings.update")

    let templatesResponse = try service.handleJSONRPC([
        "jsonrpc": "2.0",
        "id": 2,
        "method": "resources/templates/list"
    ])
    let resourceTemplates = try mcpResultArray(templatesResponse, key: "resourceTemplates").compactMap { $0["uriTemplate"] as? String }
    try check(resourceTemplates.contains("papercodex://papers/{paper_id}/notes"), "MCP should expose paper notes as a resource template")
    try check(resourceTemplates.contains("papercodex://sessions/{session_id}/workspace-manifest"), "MCP should expose session workspace manifests as resources")
    try check(resourceTemplates.contains("papercodex://sessions/{session_id}/agent-runtime"), "MCP should expose session agent runtime state as resources")
    try check(resourceTemplates.contains("papercodex://sessions/{session_id}/prompt-contract"), "MCP should expose session prompt contracts as resources")
    try check(resourceTemplates.contains("papercodex://settings/prompt-templates/{template_id}"), "MCP should expose typed prompt templates as resources")
    try check(resourceTemplates.contains("papercodex://app/active-context"), "MCP should expose active app context")

    let promptsResponse = try service.handleJSONRPC([
        "jsonrpc": "2.0",
        "id": 3,
        "method": "prompts/list"
    ])
    let promptNames = try mcpResultArray(promptsResponse, key: "prompts").compactMap { $0["name"] as? String }
    try check(promptNames.contains("paper_reading"), "MCP should expose a paper reading prompt")
    try check(promptNames.contains("paper_summary"), "MCP should expose a paper summary prompt")
    try check(promptNames.contains("tag_suggestion"), "MCP should expose a tag suggestion prompt")

    let metadata = try mcpReadResource("papercodex://papers/\(fixture.paperID)/metadata", service: service)
    try check(metadata.contains("Example Paper"), "paper metadata resource should include the title")
    try check(metadata.contains("Visual Grounding"), "paper metadata resource should include tags")
    try check(metadata.contains("reading-list"), "paper metadata resource should include folders")

    let notes = try mcpReadResource("papercodex://papers/\(fixture.paperID)/notes", service: service)
    try check(notes.contains("Main idea"), "paper notes resource should include note titles")
    try check(notes.contains("Ground claims with spans."), "paper notes resource should include note body")

    let fullText = try mcpReadResource("papercodex://papers/\(fixture.paperID)/full-text", service: service)
    try check(fullText.contains("This paper studies visual grounding."), "paper full-text resource should include page text")

    let workspaceManifest = try mcpReadResource("papercodex://sessions/\(fixture.sessionID)/workspace-manifest", service: service)
    try check(workspaceManifest.contains("workspace_manifest.json"), "session workspace manifest resource should expose the manifest path")
    try check(workspaceManifest.contains("full_text.txt"), "session workspace manifest resource should expose paper workspace files")

    let agentRuntime = try mcpReadResource("papercodex://sessions/\(fixture.sessionID)/agent-runtime", service: service)
    try check(agentRuntime.contains("claude-code"), "session agent runtime resource should expose the default runtime id")
    try check(agentRuntime.contains("openclaw-kimi"), "session agent runtime resource should expose runtime session links")

    let promptContract = try mcpReadResource("papercodex://sessions/\(fixture.sessionID)/prompt-contract", service: service)
    try check(promptContract.contains("[[cite:paper:{paper_id}:p{page}:b{block_index}]]"), "session prompt contract resource should expose citation markers")

    let sourceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let mcpSkill = try String(contentsOf: sourceRoot.appendingPathComponent("skills/papercodex-mcp/SKILL.md"))
    let workspaceSkill = try String(contentsOf: sourceRoot.appendingPathComponent("skills/papercodex-agent-workspace/SKILL.md"))
    try check(mcpSkill.contains("papercodex://sessions/{session_id}/workspace-manifest"), "Paper Codex MCP skill should document agent workspace resources")
    try check(workspaceSkill.contains("Use MCP tools for app state changes"), "Agent workspace skill should keep app mutations behind MCP tools")
    try check(workspaceSkill.contains("[[cite:paper:{paper_id}:p{page}:b{block_index}]]"), "Agent workspace skill should document citation markers")

    let validateText = try mcpCallTool(
        "prompt_template.validate",
        arguments: ["template_id": "paper_summary.default"],
        service: service
    )
    try check(validateText.contains(#""is_valid": true"#) || validateText.contains(#""is_valid" : true"#), "prompt template validation should report valid templates")
    try check(validateText.contains("paper_title"), "prompt template validation should report variables")

    let previewText = try mcpCallTool(
        "prompt_template.preview_render",
        arguments: [
            "template_id": "paper_summary.default",
            "variables": [
                "paper_title": "A Test Paper",
                "paper_abstract": "A compact abstract",
                "selected_text": "selected span",
                "user_goal": "summarize methods"
            ]
        ],
        service: service
    )
    try check(previewText.contains("A Test Paper"), "prompt template preview should render paper_title")
    try check(previewText.contains("summarize methods"), "prompt template preview should render user_goal")

    let replaceText = try mcpCallTool(
        "prompt_template.replace_body",
        arguments: [
            "template_id": "paper_summary.default",
            "body_markdown": "Summarize {{paper_title}} for {{user_goal}}."
        ],
        service: service
    )
    try check(replaceText.contains("updated"), "prompt template replacement should persist the changed body")

    let updatedPreviewText = try mcpCallTool(
        "prompt_template.preview_render",
        arguments: [
            "template_id": "paper_summary.default",
            "variables": [
                "paper_title": "Updated Paper",
                "user_goal": "method extraction"
            ]
        ],
        service: service
    )
    try check(updatedPreviewText.contains("Updated Paper"), "updated prompt template should render new title")
    try check(updatedPreviewText.contains("method extraction"), "updated prompt template should render new user goal")

    let queuedCommandText = try mcpCallTool(
        "app.open_paper",
        arguments: ["paper_id": fixture.paperID],
        service: service
    )
    try check(queuedCommandText.contains("queued"), "app command tools should queue commands for the running app")
    let commandLogURL = PaperCodexMCPAppCommand.commandLogURL(supportRoot: fixture.root)
    try check(FileManager.default.fileExists(atPath: commandLogURL.path), "app command tools should write the command queue")

    let server = PaperCodexMCPServer(service: service, supportRoot: fixture.root)
    let endpoint = try server.start(preferredPort: 41927, token: "test-token")
    defer { server.stop() }
    try check(FileManager.default.fileExists(atPath: endpoint.metadataPath), "MCP server should write connection metadata")
    let initializeResponse = try mcpHTTPPost(
        url: endpoint.url,
        token: endpoint.token,
        object: [
            "jsonrpc": "2.0",
            "id": 99,
            "method": "initialize"
        ]
    )
    let serverInfo = try mcpResult(initializeResponse)["serverInfo"] as? [String: Any]
    try check(serverInfo?["name"] as? String == "paper-codex", "MCP HTTP endpoint should respond to initialize")
}

private func mcpResult(_ response: [String: Any]) throws -> [String: Any] {
    if let error = response["error"] {
        throw CheckFailure(description: "Unexpected MCP error: \(error)")
    }
    guard let result = response["result"] as? [String: Any] else {
        throw CheckFailure(description: "MCP response missing result: \(response)")
    }
    return result
}

private func mcpResultArray(_ response: [String: Any], key: String) throws -> [[String: Any]] {
    let result = try mcpResult(response)
    guard let array = result[key] as? [[String: Any]] else {
        throw CheckFailure(description: "MCP result missing array \(key): \(result)")
    }
    return array
}

private func mcpReadResource(_ uri: String, service: PaperCodexMCPService) throws -> String {
    let response = try service.handleJSONRPC([
        "jsonrpc": "2.0",
        "id": 10,
        "method": "resources/read",
        "params": ["uri": uri]
    ])
    let contents = try mcpResultArray(response, key: "contents")
    guard let text = contents.first?["text"] as? String else {
        throw CheckFailure(description: "MCP resource response missing text for \(uri)")
    }
    return text
}

private func mcpCallTool(_ name: String, arguments: [String: Any], service: PaperCodexMCPService) throws -> String {
    let response = try service.handleJSONRPC([
        "jsonrpc": "2.0",
        "id": 20,
        "method": "tools/call",
        "params": [
            "name": name,
            "arguments": arguments
        ]
    ])
    let content = try mcpResultArray(response, key: "content")
    guard let text = content.first?["text"] as? String else {
        throw CheckFailure(description: "MCP tool response missing text for \(name)")
    }
    return text
}

private func mcpHTTPPost(url: String, token: String, object: [String: Any]) throws -> [String: Any] {
    guard let requestURL = URL(string: url) else {
        throw CheckFailure(description: "Invalid MCP test URL: \(url)")
    }
    var request = URLRequest(url: requestURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: object)

    let semaphore = DispatchSemaphore(value: 0)
    let resultBox = MCPHTTPPostResultBox()
    let task = URLSession.shared.dataTask(with: request) { data, _, error in
        defer { semaphore.signal() }
        if let error {
            resultBox.set(.failure(error))
            return
        }
        guard let data else {
            resultBox.set(.failure(CheckFailure(description: "MCP HTTP response missing body")))
            return
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CheckFailure(description: "MCP HTTP response was not an object")
            }
            resultBox.set(.success(object))
        } catch {
            resultBox.set(.failure(error))
        }
    }
    task.resume()
    guard semaphore.wait(timeout: .now() + 5) == .success else {
        task.cancel()
        throw CheckFailure(description: "MCP HTTP request timed out")
    }
    return try resultBox.get()?.get() ?? {
        throw CheckFailure(description: "MCP HTTP request returned no result")
    }()
}

private final class MCPHTTPPostResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<[String: Any], Error>?

    func set(_ result: Result<[String: Any], Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() -> Result<[String: Any], Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

private struct MCPFixture {
    var root: URL
    var repository: PaperRepository
    var paperID: String
    var sessionID: String
}

private func makeMCPFixture(withPaper: Bool) throws -> MCPFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-mcp-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try PaperRepository(databasePath: root.appendingPathComponent("store.sqlite").path)
    try repository.migrate()

    guard withPaper else {
        return MCPFixture(root: root, repository: repository, paperID: "", sessionID: "")
    }

    let paperPath = root.appendingPathComponent("papers/paper-example/original.pdf")
    try FileManager.default.createDirectory(at: paperPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try writeFixturePDF(to: paperPath, lines: ["This paper studies visual grounding."])
    let paper = Paper(
        id: "paper-example",
        filePath: paperPath.path,
        fileHash: "hash-example",
        title: "Example Paper",
        authors: ["Ada Lovelace"],
        year: 2026,
        sourceURL: "https://arxiv.org/abs/2601.00001",
        isSaved: true,
        importedAt: Date(timeIntervalSince1970: 1_800_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    try repository.upsertPaper(paper)
    try repository.upsertPage(PageIndex(
        paperID: paper.id,
        page: 1,
        text: "This paper studies visual grounding.",
        confidence: 0.99
    ))
    try repository.upsertSpan(Span(
        id: Span.makeID(paperID: paper.id, page: 1, blockIndex: 0),
        paperID: paper.id,
        page: 1,
        bbox: BoundingBox(x: 0, y: 0, width: 10, height: 10),
        text: "This paper studies visual grounding.",
        charRange: TextRange(location: 0, length: 37),
        sectionHint: "Abstract",
        confidence: 0.99
    ))
    let folder = Category(id: "cat-reading-list", parentID: nil, name: "reading-list", sortOrder: 10)
    try repository.upsertCategory(folder)
    try repository.assignPaper(paper.id, toCategory: folder.id)
    let tag = PaperTag(id: "tag-visual-grounding", name: "Visual Grounding")
    try repository.upsertTag(tag)
    try repository.assignPaper(paper.id, toTag: tag.id)
    try repository.upsertNote(PaperNote(
        id: "note-main",
        paperID: paper.id,
        anchorID: nil,
        title: "Main idea",
        bodyMarkdown: "Ground claims with spans.",
        createdAt: Date(timeIntervalSince1970: 1_800_000_001),
        updatedAt: Date(timeIntervalSince1970: 1_800_000_001),
        deletedAt: nil,
        syncRevision: 1
    ))

    let session = PaperSession(
        id: "session-example",
        title: "Example Reading Session",
        paperIDs: [paper.id],
        codexSessionID: "codex-thread-example",
        defaultRuntimeID: "claude-code",
        runtimeSessionLinks: [
            AgentRuntimeSessionLink(runtimeID: "claude-code", sessionID: "claude-thread-example"),
            AgentRuntimeSessionLink(runtimeID: "openclaw-kimi", sessionID: "kimi-thread-example")
        ],
        workspaceMaterializationMode: .copyPDF,
        workspacePath: root.appendingPathComponent("session-example", isDirectory: true).path,
        createdAt: Date(timeIntervalSince1970: 1_800_000_002),
        updatedAt: Date(timeIntervalSince1970: 1_800_000_002)
    )
    try repository.upsertSession(session)
    try SessionWorkspaceManager().writeWorkspace(
        session: session,
        papers: [paper],
        pagesByPaperID: [
            paper.id: [
                PageIndex(
                    paperID: paper.id,
                    page: 1,
                    text: "This paper studies visual grounding.",
                    confidence: 0.99
                )
            ]
        ],
        spansByPaperID: [
            paper.id: [
                Span(
                    id: Span.makeID(paperID: paper.id, page: 1, blockIndex: 0),
                    paperID: paper.id,
                    page: 1,
                    bbox: BoundingBox(x: 0, y: 0, width: 10, height: 10),
                    text: "This paper studies visual grounding.",
                    charRange: TextRange(location: 0, length: 37),
                    sectionHint: "Abstract",
                    confidence: 0.99
                )
            ]
        ],
        anchorsByPaperID: [paper.id: []],
        mcpEndpoint: nil,
        materializationMode: session.workspaceMaterializationMode
    )

    return MCPFixture(root: root, repository: repository, paperID: paper.id, sessionID: session.id)
}

func runLibraryDerivedStateChecks() throws {
    let now = Date(timeIntervalSince1970: 1_777_400_000)
    let paperA = Paper(
        id: "paper-a",
        filePath: "/tmp/a.pdf",
        fileHash: "hash-a",
        title: "Representation Autoencoders",
        authors: ["Alice", "Bob"],
        year: 2026,
        sourceURL: "https://arxiv.org/abs/2604.00001",
        importedAt: now,
        updatedAt: now
    )
    let paperB = Paper(
        id: "paper-b",
        filePath: "/tmp/b.pdf",
        fileHash: "hash-b",
        title: "Flow Matching",
        authors: ["Carol"],
        year: 2025,
        sourceURL: nil,
        importedAt: now,
        updatedAt: now
    )
    let paperC = Paper(
        id: "paper-c",
        filePath: "/tmp/c.pdf",
        fileHash: "hash-c",
        title: "Latent Diffusion",
        authors: ["Dana"],
        year: 2024,
        sourceURL: nil,
        importedAt: now,
        updatedAt: now
    )
    let categories = [
        Category(id: "cat-methods", parentID: nil, name: "Methods", sortOrder: 1),
        Category(id: "cat-vae", parentID: "cat-methods", name: "VAE", sortOrder: 2)
    ]
    let tagsByPaperID = [
        "paper-a": [
            PaperTag(id: "tag-autoencoder", name: "Autoencoder"),
            PaperTag(id: "tag-diffusion", name: "Diffusion")
        ],
        "paper-b": [
            PaperTag(id: "tag-diffusion", name: "Diffusion")
        ]
    ]
    let state = PaperLibraryDerivedState.build(
        papers: [paperA, paperB, paperC],
        categories: categories,
        categoryIDsByPaperID: [
            "paper-a": ["cat-methods", "cat-vae"],
            "paper-b": ["cat-methods"],
            "paper-c": ["cat-vae"]
        ],
        tagsByPaperID: tagsByPaperID
    )

    try check(state.categoryPaperCountsByID == ["cat-methods": 2, "cat-vae": 2], "library derived state should precompute category counts")
    try check(state.tagPaperCountsByID == ["tag-autoencoder": 1, "tag-diffusion": 2], "library derived state should precompute tag counts")
    try check(state.descendantCategoryIDsByID["cat-methods"] == ["cat-vae"], "library derived state should precompute category descendants")
    try check(state.categoryIDsForFilter("cat-methods", includeDescendants: false) == ["cat-methods"], "library current-folder filter should only include the selected category")
    try check(state.categoryIDsForFilter("cat-methods", includeDescendants: true) == ["cat-methods", "cat-vae"], "library subtree filter should include the selected category and descendants")
    try check(state.paperIDsForCategoryFilter("cat-methods", includeDescendants: false) == ["paper-a", "paper-b"], "library current-folder filtering should use precomputed category paper IDs")
    try check(state.paperIDsForCategoryFilter("cat-methods", includeDescendants: true) == ["paper-a", "paper-b", "paper-c"], "library subtree filtering should union precomputed descendant paper IDs")
    try check(state.paperIDsForTag("tag-diffusion") == ["paper-a", "paper-b"], "library tag filtering should use precomputed tag paper IDs")
    try check(state.matchesSearch(paperID: "paper-a", query: "vae autoencoder alice 2026"), "library search index should include title, authors, year, categories, tags, and URL")
    try check(!state.matchesSearch(paperID: "paper-b", query: "alice"), "library search index should stay scoped to each paper")
    try check(state.matchesSearch(paperID: "missing", query: "anything"), "missing papers should not be filtered out by an empty derived search index")
}

func runLibraryCategoryAssignmentChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-library-category-assignment-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let repository = try PaperRepository(databasePath: tempRoot.appendingPathComponent("store.sqlite").path)
    try repository.migrate()

    let now = Date(timeIntervalSince1970: 1_777_500_000)
    let paper = Paper(
        id: "paper-a",
        filePath: "/tmp/paper-a.pdf",
        fileHash: "hash-library-category-assignment-a",
        title: "Grounded Vision Agents",
        authors: ["Alice"],
        year: 2026,
        sourceURL: nil,
        importedAt: now,
        updatedAt: now
    )
    try repository.upsertPaper(paper)
    try repository.upsertCategory(Category(id: "cat-existing", parentID: nil, name: "Existing", sortOrder: 1))
    try repository.upsertCategory(Category(id: "cat-parent", parentID: nil, name: "Parent", sortOrder: 2))

    var createdCategoryIDs: [String] = []
    let assigner = LibraryCategoryAssigner(idFactory: { prefix, name in
        var slug = ""
        for character in name.lowercased() {
            if character.isLetter || character.isNumber {
                slug.append(character)
            } else {
                if slug.last == "-" {
                    continue
                }
                slug.append("-")
            }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(prefix)-\(slug)"
    })
    try assigner.assign(
        paperID: paper.id,
        existingCategoryIDs: ["cat-existing", "missing-category", "cat-existing"],
        newCategoryNames: [" Fresh ", "fresh", ""],
        newCategories: [
            LibraryCategoryRequest(id: "new-parent", parentID: "cat-parent", name: " Vision "),
            LibraryCategoryRequest(id: "new-child", parentID: "new-parent", name: "Grounding"),
            LibraryCategoryRequest(id: "ignored-empty", parentID: nil, name: " ")
        ],
        repository: repository,
        onCategoryCreated: { category in
            createdCategoryIDs.append(category.id)
        }
    )

    let categories = try repository.fetchCategories()
    let categoriesByName = Dictionary(grouping: categories, by: \.name)
    try check(categoriesByName["Fresh"]?.count == 1, "duplicate flat new category names should create one root category")
    try check(categoriesByName["Vision"]?.first?.parentID == "cat-parent", "nested category request should keep its existing parent")
    try check(categoriesByName["Grounding"]?.first?.parentID == categoriesByName["Vision"]?.first?.id, "nested category request should resolve new parent requests")
    try check(Set(createdCategoryIDs) == ["cat-fresh", "cat-vision", "cat-grounding"], "created category callback should fire once for each created folder")

    let assignedCategoryIDs = Set(try repository.fetchCategoryIDs(forPaperID: paper.id))
    try check(assignedCategoryIDs.contains("cat-existing"), "valid existing category IDs should be assigned")
    try check(!assignedCategoryIDs.contains("missing-category"), "invalid existing category IDs should be ignored")
    try check(assignedCategoryIDs.contains("cat-fresh"), "flat new categories should be assigned to the paper")
    try check(assignedCategoryIDs.contains("cat-vision"), "new parent category should be assigned to the paper")
    try check(assignedCategoryIDs.contains("cat-grounding"), "new child category should be assigned to the paper")

    do {
        try assigner.assign(
            paperID: paper.id,
            existingCategoryIDs: [],
            newCategoryNames: [],
            newCategories: [
                LibraryCategoryRequest(id: "cycle-a", parentID: "cycle-b", name: "Cycle A"),
                LibraryCategoryRequest(id: "cycle-b", parentID: "cycle-a", name: "Cycle B")
            ],
            repository: repository
        )
        throw CheckFailure(description: "cyclic new category requests should fail")
    } catch LibraryCategoryAssignmentError.invalidCategoryHierarchy {
    } catch {
        throw CheckFailure(description: "cyclic new category requests should fail with invalidCategoryHierarchy, got \(error)")
    }
}

func runCategoryMovePlannerChecks() throws {
    let diffusion = Category(id: "cat-diffusion", parentID: nil, name: "Diffusion", sortOrder: 10)
    let rl = Category(id: "cat-rl", parentID: diffusion.id, name: "RL", sortOrder: 10)
    let reward = Category(id: "cat-reward", parentID: rl.id, name: "reward model", sortOrder: 10)
    let forward = Category(id: "cat-forward", parentID: rl.id, name: "forward-rl", sortOrder: 20)
    let grpo = Category(id: "cat-grpo", parentID: rl.id, name: "GRPO改进", sortOrder: 30)
    let opd = Category(id: "cat-opd", parentID: rl.id, name: "OPD", sortOrder: 40)
    let categories = [diffusion, rl, reward, forward, grpo, opd]

    try check(
        CategoryMovePlanner.canDropCategory(
            "cat-rl",
            ontoCategory: "cat-grpo",
            placement: .before,
            in: categories
        ) == false,
        "folder dragging should reject before/after drops onto the dragged folder's descendants"
    )
    try check(
        CategoryMovePlanner.canDropCategory(
            "cat-rl",
            ontoCategory: "cat-grpo",
            placement: .inside,
            in: categories
        ) == false,
        "folder dragging should reject inside drops onto the dragged folder's descendants"
    )
    try check(
        CategoryMovePlanner.canMoveCategory("cat-grpo", toParent: "cat-rl", in: categories) == false,
        "folder dragging should reject no-op drops into the folder's existing parent"
    )
    try check(
        CategoryMovePlanner.canMoveCategory("cat-diffusion", toParent: nil, in: categories) == false,
        "folder dragging should reject no-op drops from a top-level folder back to the top level"
    )

    let reordered = try CategoryMovePlanner.reorderedCategories(
        movingCategoryID: "cat-opd",
        relativeTo: "cat-grpo",
        placement: .before,
        in: categories
    )
    let reorderedRLSiblings = reordered
        .filter { $0.parentID == rl.id }
        .sorted { $0.sortOrder < $1.sortOrder }
        .map { "\($0.id):\($0.sortOrder)" }
    try check(
        reorderedRLSiblings == [
            "cat-reward:10",
            "cat-forward:20",
            "cat-opd:30",
            "cat-grpo:40"
        ],
        "folder reordering before a sibling should normalize the sibling order"
    )

    let movedToRoot = try CategoryMovePlanner.movedCategories(
        movingCategoryID: "cat-grpo",
        toParent: nil,
        in: categories
    )
    try check(
        movedToRoot.first(where: { $0.id == "cat-grpo" })?.parentID == nil,
        "folder dragging should support moving a nested folder back to the top level"
    )
}

func runUILayoutSourceChecks() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let libraryViewURL = root.appendingPathComponent("Sources/PaperCodexApp/LibraryView.swift")
    let librarySource = try String(contentsOf: libraryViewURL)
    let libraryCategoryOutlineSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/LibraryCategoryOutlineView.swift"))
    let libraryPaperTableSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/LibraryPaperTableView.swift"))
    let libraryToolbarSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/LibraryToolbarView.swift"))
    let libraryContentSplitURL = root.appendingPathComponent("Sources/PaperCodexApp/LibraryContentSplitView.swift")
    let libraryContentSplitSource = FileManager.default.fileExists(atPath: libraryContentSplitURL.path) ? try String(contentsOf: libraryContentSplitURL) : ""
    let appModelURL = root.appendingPathComponent("Sources/PaperCodexApp/AppModel.swift")
    let appModelSource = try String(contentsOf: appModelURL)
    let libraryFeatureStoreSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/LibraryFeatureStore.swift"))

    try check(
        librarySource.contains("static let splitPaneTopInset: CGFloat"),
        "library split panes should use an explicit titlebar compensation inset"
    )
    try check(
        librarySource.components(separatedBy: "LibraryLayout.splitPaneTopInset").count - 1 >= 2,
        "library list and inspector panes should share the same top inset constant"
    )
    try check(
        librarySource.contains("LibraryCategoryOutlineView(")
            && !librarySource.contains("CategorySidebarRow(")
            && !librarySource.contains("private struct CategorySidebarRow")
            && libraryCategoryOutlineSource.contains("NSOutlineView")
            && libraryCategoryOutlineSource.contains("NSOutlineViewDataSource")
            && libraryCategoryOutlineSource.contains("NSOutlineViewDelegate")
            && libraryCategoryOutlineSource.contains("outlineViewSelectionDidChange")
            && libraryCategoryOutlineSource.contains("outlineViewItemDidExpand")
            && libraryCategoryOutlineSource.contains("outlineViewItemDidCollapse")
            && libraryCategoryOutlineSource.contains("pasteboardWriterForItem")
            && libraryCategoryOutlineSource.contains("validateDrop")
            && libraryCategoryOutlineSource.contains("acceptDrop")
            && libraryCategoryOutlineSource.contains("CategoryOutlineCellView")
            && libraryCategoryOutlineSource.contains("onCreateChild")
            && libraryCategoryOutlineSource.contains("onTogglePinned")
            && libraryCategoryOutlineSource.contains("onBeginCategoryDrag")
            && libraryCategoryOutlineSource.contains("onEndCategoryDrag")
            && libraryCategoryOutlineSource.contains("onManage"),
        "library folder tree should use a native NSOutlineView with selection, expansion, drag/drop, and row actions"
    )
    try check(
        libraryCategoryOutlineSource.contains("folderIconName")
            && libraryCategoryOutlineSource.contains("folderIconHelp")
            && libraryCategoryOutlineSource.contains("NSImage(systemSymbolName:")
            && libraryCategoryOutlineSource.contains("outlineView.isExpandable(node)")
            && !librarySource.contains("\"chevron.down\"")
            && !librarySource.contains("\"chevron.right\"")
            && !librarySource.contains("categoryTreeChevronWidth")
            && !librarySource.contains("categoryTreeChevronIconSpacing"),
        "library folder rows should keep folder-state iconography while avoiding custom SwiftUI chevron expand controls"
    )
    try check(
        librarySource.contains("SidebarSplitLayout(minContentWidth: LibraryLayout.libraryContentMinimumWidth)")
            && librarySource.contains("static let libraryContentMinimumWidth: CGFloat = 860")
            && librarySource.contains("static let libraryPrimaryPaneMinimumWidth: CGFloat = 330")
            && librarySource.contains("static let libraryInspectorMinimumWidth: CGFloat = 300")
            && librarySource.contains("static let libraryInspectorIdealWidth: CGFloat = 360")
            && librarySource.contains("static let libraryInspectorMaximumWidth: CGFloat = 460")
            && librarySource.contains(".frame(minWidth: LibraryLayout.libraryPrimaryPaneMinimumWidth)")
            && librarySource.contains("minWidth: LibraryLayout.libraryInspectorMinimumWidth"),
        "library split panes should reserve enough outer content width for the native inspector before entering compact mode"
    )
    try check(
        librarySource.contains("LibraryContentSplitView(")
            && libraryContentSplitSource.contains("NSSplitView")
            && libraryContentSplitSource.contains("LibraryContentSplitContainerView")
            && libraryContentSplitSource.contains("Library Content Split")
            && !librarySource.contains("HSplitView"),
        "library list and inspector panes should use a native AppKit split view instead of SwiftUI HSplitView"
    )
    try check(
        libraryFeatureStoreSource.contains("func paperListState(")
            && libraryFeatureStoreSource.contains("cachedPaperListRequest")
            && appModelSource.contains("func libraryPaperListState(")
            && librarySource.contains("model.libraryPaperListState(")
            && !librarySource.contains("private func makePaperListState()"),
        "library paper filtering and sorting should be cached in LibraryFeatureStore instead of recomputed in the SwiftUI view hot path"
    )
    try check(
        librarySource.contains("LibraryRootFolderRow")
            && librarySource.contains("LibraryNativeToolbarView(")
            && librarySource.contains("LibraryPaperListState")
            && !librarySource.contains("LibraryInlineControlRow(")
            && !librarySource.contains("FolderBreadcrumbBar")
            && !librarySource.contains("folderBreadcrumbPath(for:")
            && libraryToolbarSource.contains("This folder")
            && libraryToolbarSource.contains("All levels"),
        "library folders should keep search, scope, count, and reading actions in one native inline toolbar without a breadcrumb path"
    )
    if let rootFolderRange = librarySource.range(of: "private struct LibraryRootFolderRow: View"),
       let rootFolderEndRange = librarySource.range(of: "private struct LibraryCategoryTreeSnapshot", range: rootFolderRange.upperBound..<librarySource.endIndex) {
        let rootFolderSource = String(librarySource[rootFolderRange.lowerBound..<rootFolderEndRange.lowerBound])
        try check(
            rootFolderSource.contains("LibraryRootFolderSelectionButton(")
                && rootFolderSource.contains("private struct NativeLibraryRootFolderSelectionButton: NSViewRepresentable")
                && rootFolderSource.contains("private final class NativeLibraryRootFolderSelectionButtonView: NSButton")
                && rootFolderSource.contains("override func mouseDown(with event: NSEvent)")
                && rootFolderSource.contains("override func accessibilityValue() -> Any?")
                && rootFolderSource.contains("pressHandler()")
                && rootFolderSource.contains("setAccessibilityRole(.button)")
                && rootFolderSource.contains("CATransaction.setAnimationDuration")
                && rootFolderSource.contains(".id(\"library-root-folder-\\(isSelected)-\\(isDropTargeted)\")")
                && rootFolderSource.contains(".onDrop(")
                && !rootFolderSource.contains("Button(action: onSelect)")
                && !rootFolderSource.contains("super.mouseDown(with: event)")
                && !rootFolderSource.contains(".buttonStyle(.plain)"),
            "library root All Papers row should use a native AppKit selection button while preserving top-level drop behavior"
        )
    } else {
        throw CheckFailure(description: "library root folder row source should remain inspectable")
    }
    try check(
        librarySource.contains("LibraryNativeToolbarView(")
            && !librarySource.contains("LibraryInlineControlRow(")
            && !librarySource.contains("TextField(\"Search title, author, tag, category, year, or source\"")
            && !librarySource.contains("Picker(\"Sort\"")
            && libraryToolbarSource.contains("NSSearchField")
            && libraryToolbarSource.contains("NSPopUpButton")
            && libraryToolbarSource.contains("NSButton")
            && libraryToolbarSource.contains("NSViewRepresentable")
            && libraryToolbarSource.contains("searchFocusRequestID")
            && libraryToolbarSource.contains("sortDirectionButton")
            && libraryToolbarSource.contains("clearFiltersButton")
            && libraryToolbarSource.contains("localized(\"Library\")")
            && libraryToolbarSource.contains("localized(\"Clear Filters\")")
            && libraryToolbarSource.contains("NSLocalizedString")
            && libraryToolbarSource.contains("onImportPDF"),
        "library top controls should use a native AppKit toolbar with search, sort, scope, filter, read/chat, and import actions"
    )
    try check(
        librarySource.contains("LibraryPaperTableView(")
            && !librarySource.contains("LibraryPaperList(")
            && !librarySource.contains("List(papers)")
            && !librarySource.contains("ScrollViewReader")
            && !librarySource.contains("LibraryPaperKeyboardBridge")
            && libraryPaperTableSource.contains("NSTableView")
            && libraryPaperTableSource.contains("NSScrollView")
            && libraryPaperTableSource.contains("NSViewRepresentable")
            && !libraryPaperTableSource.contains("NSHostingView")
            && libraryPaperTableSource.contains("LibraryPaperTableRow")
            && libraryPaperTableSource.contains("LibraryPaperNativeCellView")
            && libraryPaperTableSource.contains("starButton")
            && libraryPaperTableSource.contains("readButton")
            && libraryPaperTableSource.contains("scrollRowToVisibleCentered")
            && libraryPaperTableSource.contains("keyDown(with event:")
            && libraryPaperTableSource.contains("pasteboardWriterForRow")
            && libraryPaperTableSource.contains("reloadData()"),
        "library paper list should use native NSTableView cells with row reuse, keyboard navigation, drag payloads, and centered reveal"
    )
    try check(
        librarySource.contains("private var sidebarLists: some View") &&
            librarySource.contains("PaperCodexNativeScrollView {") &&
            librarySource.contains("sidebarLists"),
        "library sidebar category and tag lists should live inside a native AppKit scroll view"
    )
    if let sidebarContextRange = librarySource.range(of: "private var sidebarContext: some View"),
       let sidebarContextEndRange = librarySource.range(of: "private var sidebarLists: some View", range: sidebarContextRange.upperBound..<librarySource.endIndex) {
        let sidebarContextSource = String(librarySource[sidebarContextRange.lowerBound..<sidebarContextEndRange.lowerBound])
        try check(
            librarySource.contains(".onChange(of: activePaperSurfaceFilteredPaperIDs)")
                && librarySource.contains("private var activePaperSurfaceFilteredPaperIDs: [String]")
                && librarySource.contains("selectedLibrarySurface == .papers ? filteredPaperIDs : []")
                && sidebarContextSource.contains("switch selectedLibrarySurface")
                && sidebarContextSource.contains("case .papers:")
                && sidebarContextSource.contains("PaperCodexNativeScrollView {")
                && sidebarContextSource.contains("sidebarLists")
                && sidebarContextSource.contains("case .recentConversations:")
                && sidebarContextSource.contains("NativeRecentConversationsSidebarContext(")
                && !sidebarContextSource.contains("case .recentConversations:\n            PaperCodexNativeScrollView")
                && librarySource.contains("private struct NativeRecentConversationsSidebarContext: NSViewRepresentable")
                && librarySource.contains("private final class NativeRecentConversationsSidebarContextView: NSView")
                && librarySource.contains("private final class NativeRecentConversationsSidebarActionButton: NSButton"),
            "recent conversations should not keep the heavyweight library folder/tag context or paper filter derivation mounted while browsing sessions"
        )
    } else {
        throw CheckFailure(description: "library sidebar context source should remain inspectable")
    }
    if let tagSectionRange = librarySource.range(of: "private var tagSidebarSection: some View"),
       let tagSectionEndRange = librarySource.range(of: "private var contentPane: some View", range: tagSectionRange.upperBound..<librarySource.endIndex) {
        let tagSectionSource = String(librarySource[tagSectionRange.lowerBound..<tagSectionEndRange.lowerBound])
        try check(
            tagSectionSource.contains("LibraryTagSidebarList(")
                && !tagSectionSource.contains("ForEach(model.tags)")
                && !tagSectionSource.contains("TagSidebarRow(")
                && librarySource.contains("private struct LibraryTagSidebarRowModel: Equatable, Identifiable")
                && librarySource.contains("private struct LibraryTagSidebarList: NSViewRepresentable")
                && librarySource.contains("private final class NativeLibraryTagSidebarListView: NSView")
                && librarySource.contains("private final class NativeLibraryTagSidebarRowView: NSView")
                && librarySource.contains("private final class NativeLibraryTagSidebarManageButton: NSButton")
                && librarySource.contains("tagRows: tagSidebarRows")
                && librarySource.contains("NSStackView")
                && librarySource.contains("NSTrackingArea")
                && librarySource.contains("setAccessibilityLabel(\"Manage")
                && !librarySource.contains("private struct TagSidebarRow: View"),
            "library tag sidebar should render as one native AppKit list with native hover/manage rows instead of SwiftUI ForEach rows"
        )
    } else {
        throw CheckFailure(description: "library tag sidebar source should remain inspectable")
    }
    try check(
        librarySource.contains("onCreateChild"),
        "library category rows should expose a direct child-category creation action"
    )
    try check(
        librarySource.contains("newCategoryParentID = category.id"),
        "hover category add buttons should preselect the hovered category as parent"
    )
    try check(
        librarySource.contains("nameFocusRequestID")
            && librarySource.contains("isActiveForFocus: shouldFocusName")
            && librarySource.contains("shouldFocusName = true"),
        "category creation sheet should focus the name field for fast child folder creation"
    )
    try check(
        librarySource.contains("isShowingArxivImport"),
        "library toolbar should expose a direct arXiv import sheet"
    )
    try check(
        librarySource.contains("LibrarySortOption"),
        "library list should expose explicit sort options"
    )
    try check(
        librarySource.contains("sortedPapers"),
        "library should sort papers after filtering"
    )
    try check(
        librarySource.contains("librarySortAscending"),
        "library sorting should support ascending and descending directions"
    )
    try check(
        libraryToolbarSource.contains("sortDirectionButton"),
        "library toolbar should expose a one-click sort direction toggle"
    )
    try check(
        libraryPaperTableSource.contains("onToggleStar")
            && libraryPaperTableSource.contains("configureSymbolButton(\n            starButton")
            && libraryPaperTableSource.contains("systemSymbolName: row.paper.isStarred ? \"star.fill\" : \"star\""),
        "library native paper rows should expose a direct AppKit star toggle with filled star state"
    )
    try check(
        libraryPaperTableSource.contains("onRead")
            && libraryPaperTableSource.contains("configureSymbolButton(\n            readButton")
            && libraryPaperTableSource.contains("readButton.isEnabled = !row.isImportPlaceholder"),
        "library native paper rows should expose a direct AppKit read action disabled for pending imports"
    )
    try check(
        librarySource.contains("private let starButton = NSButton()")
            && librarySource.contains("configureSymbolButton(\n                starButton")
            && librarySource.contains("systemSymbolName: paper.isStarred ? \"star.fill\" : \"star\"")
            && librarySource.contains("paper.isStarred ? .systemYellow : .secondaryLabelColor"),
        "library detail star button should use native AppKit immediate press feedback"
    )
    try check(
        librarySource.contains("if left.isStarred != right.isStarred"),
        "library sorting should pin starred papers before applying the active sort option"
    )
    try check(
        libraryToolbarSource.contains("makeIconButton(symbolName: \"number\"")
            && libraryToolbarSource.contains("localized(\"arXiv\")")
            && libraryToolbarSource.contains("NSImage(systemSymbolName:"),
        "library toolbar should show an arXiv import button next to PDF import"
    )
    try check(
        librarySource.contains("model.enqueueArxivIDsForLibrary"),
        "library arXiv import sheet should enqueue IDs and close instead of waiting in the sheet"
    )
    try check(
        librarySource.contains("isImportPlaceholder: paper.isArxivImportPlaceholder"),
        "library paper rows should render pending arXiv imports as placeholders"
    )
    try check(
        libraryPaperTableSource.contains("readButton.isEnabled = !row.isImportPlaceholder")
            && libraryPaperTableSource.contains("starButton.isEnabled = !row.isImportPlaceholder"),
        "pending arXiv placeholder rows should disable read/open actions until the PDF is ready"
    )
    try check(
        libraryPaperTableSource.contains("tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int)")
            && libraryPaperTableSource.contains("dragPayload(tableRow)")
            && libraryPaperTableSource.contains("return payload as NSString"),
        "library paper rows should expose selected paper IDs as a native NSTableView drag payload"
    )
    try check(
        libraryCategoryOutlineSource.contains("registerForDraggedTypes([.string])")
            && libraryCategoryOutlineSource.contains("case .papers")
            && libraryCategoryOutlineSource.contains("onDropPapers")
            && librarySource.contains("dropPaperIDs(paperIDs, ontoCategory: category.id)"),
        "library category rows should accept dropped paper IDs as plain text payloads"
    )
    try check(
        librarySource.contains("isDropTargeted"),
        "library category rows should visibly highlight valid drop targets"
    )
    try check(
        librarySource.contains("selectedPaperIDs.count > 1"),
        "library bulk actions should appear only for true multi-selection, not ordinary single selection"
    )
    try check(
        librarySource.contains("seedSelectionForCommandToggle"),
        "command-click should extend from the currently focused paper before toggling another row"
    )
    try check(
        librarySource.contains("clearPaperMultiSelection()"),
        "plain paper clicks should clear multi-selection like Finder"
    )
    try check(
        !librarySource.contains(".highPriorityGesture(paperDragGesture"),
        "library paper rows should not attach a competing high-priority drag gesture over native drag/drop"
    )
    try check(
        libraryPaperTableSource.contains("tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int)")
            && libraryPaperTableSource.contains("dragPayload(tableRow)")
            && libraryPaperTableSource.contains("return payload as NSString"),
        "library paper rows should use native drag payloads for folder assignment"
    )
    try check(
        librarySource.contains("categoryDropContentTypes"),
        "library category rows should accept native plain-text paper drag payloads"
    )
    try check(
        librarySource.contains("dropPaperIDs(paperIDs, ontoCategory: category.id)"),
        "dropping papers onto a folder should decide copy vs move from the current folder context"
    )
    try check(
        appModelSource.contains("func copyPapers(_ paperIDs: [String], toCategory categoryID: String)")
            && appModelSource.contains("title: \"已复制\"")
            && appModelSource.contains("title: \"已移动\""),
        "paper folder operations should expose explicit copy and move success notices"
    )
    try check(
        libraryCategoryOutlineSource.contains("pasteboardWriterForItem")
            && libraryCategoryOutlineSource.contains("categoryDragPayloadPrefix")
            && libraryCategoryOutlineSource.contains("onDropCategory")
            && librarySource.contains("dropCategory(_:to:)"),
        "library category rows should support dragging folders onto other folders"
    )
    try check(
        libraryCategoryOutlineSource.contains("LibraryCategoryDropPlacement")
            && libraryCategoryOutlineSource.contains("validateDrop")
            && libraryCategoryOutlineSource.contains("acceptDrop")
            && librarySource.contains("LibraryCategoryOutlineDropTarget")
            && appModelSource.contains("func reorderCategory("),
        "library category rows should support animated folder reordering before or after sibling rows"
    )
    try check(
        !librarySource.contains("@State private var draggedCategoryID")
            && !librarySource.contains("@State private var liveCategoryDropKey")
            && !librarySource.contains("@State private var categoryDragPreviewCategories")
            && !librarySource.contains("@State private var categoryDragCommitTarget")
            && !librarySource.contains("CategorySidebarDropDelegate")
            && !librarySource.contains("CategoryDragDropTarget")
            && librarySource.contains("@State private var outlineDraggedCategoryID")
            && librarySource.contains("onBeginCategoryDrag")
            && librarySource.contains("onEndCategoryDrag")
            && libraryCategoryOutlineSource.contains("private func dropTarget(")
            && libraryCategoryOutlineSource.contains("draggingSession session: NSDraggingSession")
            && libraryCategoryOutlineSource.contains("canDropCategory(categoryID, target)")
            && libraryCategoryOutlineSource.contains("return .move")
            && librarySource.contains("private func canDropCategory(_ categoryID: String, to target: LibraryCategoryOutlineDropTarget) -> Bool")
            && librarySource.contains("CategoryMovePlanner.canMoveCategory(")
            && librarySource.contains("CategoryMovePlanner.canDropCategory(")
            && librarySource.contains("model.moveCategory(categoryID, toParent: target.targetCategoryID)")
            && librarySource.contains("model.reorderCategory(")
            && librarySource.contains("LibraryRootFolderDropDelegate")
            && librarySource.contains("if isTargeted {\n            return true\n        }")
            && librarySource.contains("CategoryMovePlanner.canMoveCategory(")
            && librarySource.contains("droppedCategoryID")
            && librarySource.contains("toParent: nil")
            && appModelSource.contains("func reorderCategory(")
            && appModelSource.contains("postsNotice: Bool = true")
            && appModelSource.contains("if postsNotice {"),
        "library folder dragging should reject invalid outline targets through NSOutlineView, allow top-level moves, and commit sibling reordering without stale SwiftUI preview state"
    )
    try check(
        libraryFeatureStoreSource.contains("struct LibrarySelection")
            && libraryFeatureStoreSource.contains("@Published private var selection")
            && libraryFeatureStoreSource.contains("func setSelection(")
            && !libraryFeatureStoreSource.contains("@Published var selectedLibrarySurface")
            && !libraryFeatureStoreSource.contains("@Published var librarySelectedCategoryID")
            && !libraryFeatureStoreSource.contains("@Published var librarySelectedTagID")
            && appModelSource.contains("func setLibrarySelection(")
            && librarySource.contains("model.setLibrarySelection(surface: .papers, categoryID: nil, tagID: nil)")
            && librarySource.contains("model.setLibrarySelection(surface: .papers, categoryID: categoryID, tagID: nil)")
            && librarySource.contains("model.setLibrarySelection(surface: .papers, categoryID: nil, tagID: tagID)"),
        "library route/tag/folder selection should update as one snapshot instead of firing several published changes per click"
    )
    let moveCategoryRange = try require(appModelSource.range(of: "func moveCategory(_ categoryID: String, toParent parentID: String?)"), "moveCategory source should exist")
    let setCategoryPinnedRange = try require(appModelSource.range(of: "func setCategoryPinned("), "setCategoryPinned source should exist")
    let categoryMoveSource = String(appModelSource[moveCategoryRange.lowerBound..<setCategoryPinnedRange.lowerBound])
    try check(
        categoryMoveSource.contains("libraryStore.applyCategories(updatedCategories)")
            && !categoryMoveSource.contains("try reloadLibrary()"),
        "folder move/reorder commits should update the in-memory library category snapshot instead of reloading the full library on drop"
    )
    try check(
        librarySource.contains("GeometryReader { proxy in")
            && librarySource.contains("isCompactLibraryContent(width: proxy.size.width)")
            && librarySource.contains("if isCompactLibraryContent(width: proxy.size.width)")
            && librarySource.contains("static let compactContentWidthThreshold")
            && !librarySource.contains(".frame(minWidth: LibraryLayout.libraryPrimaryPaneMinimumWidth)\n            secondaryContentPane"),
        "library split content should enter a compact layout before the primary middle pane is clipped"
    )
    let selectLibraryPaperRange = try require(appModelSource.range(of: "func selectLibraryPaper(_ paper: Paper)"), "selectLibraryPaper source should exist")
    let showDiscoverRange = try require(appModelSource.range(of: "func showDiscover()"), "showDiscover source should exist")
    let selectLibraryPaperSource = String(appModelSource[selectLibraryPaperRange.lowerBound..<showDiscoverRange.lowerBound])
    try check(
        !selectLibraryPaperSource.contains("loadPaperNotes(for: paper)"),
        "plain paper selection should not synchronously fetch notes on click"
    )
    let loadPaperNotesRange = try require(appModelSource.range(of: "func loadPaperNotes(for paper: Paper"), "loadPaperNotes source should exist")
    let saveNoteRange = try require(appModelSource.range(of: "func saveNote(paperID:"), "saveNote source should exist")
    let loadPaperNotesSource = String(appModelSource[loadPaperNotesRange.lowerBound..<saveNoteRange.lowerBound])
    try check(
        appModelSource.contains("paperNotesLoadTasks")
            && loadPaperNotesSource.contains("Task.detached(priority: .userInitiated)")
            && loadPaperNotesSource.contains("PaperRepository(databasePath: databasePath)")
            && !loadPaperNotesSource.contains("paperNotesByID[paper.id] = try repository.fetchNotes"),
        "paper note reads should run off the main actor so clicking a paper stays responsive"
    )
    let libraryMetadataRange = try require(appModelSource.range(of: "func libraryArxivMetadata(for paper: Paper)"), "libraryArxivMetadata source should exist")
    let nonEmptyRange = try require(appModelSource.range(of: "private func nonEmpty"), "nonEmpty helper source should exist")
    let libraryMetadataSource = String(appModelSource[libraryMetadataRange.lowerBound..<nonEmptyRange.lowerBound])
    try check(
        !libraryMetadataSource.contains("try? arxivCache.loadPaper")
            && !libraryMetadataSource.contains("try? localDiscoverCache.loadEnrichment"),
        "library inspector metadata should not synchronously read arXiv cache files from the SwiftUI body"
    )
    try check(
        librarySource.contains("@State private var selectedPaperRevealRequestID")
            && librarySource.contains("selectedPaperRevealRequestID = UUID()")
            && librarySource.contains("@State private var paperTableFocusRequestID")
            && librarySource.contains("revealRequestID: selectedPaperRevealRequestID")
            && libraryPaperTableSource.contains("lastRevealRequestID")
            && libraryPaperTableSource.contains("scrollRowToVisibleCentered")
            && !librarySource.contains("scrollProxy.scrollTo(selectedPaperID, anchor: .center)"),
        "paper clicks should not trigger animated scroll-to-center; only native table keyboard navigation should request reveal"
    )
    try check(
        librarySource.contains("@State private var inspectorDetailsPaperID")
            && librarySource.contains("scheduleInspectorDetailsAfterSelectionSettles(for: paper)")
            && librarySource.contains("inspectorDetailsPaperID == paper.id")
            && librarySource.contains("inspectorDetailSettleDelayNanoseconds"),
        "library inspector should defer heavy per-paper details until selection settles so row selection can paint first"
    )
    try check(
        libraryCategoryOutlineSource.contains("onTogglePinned")
            && libraryCategoryOutlineSource.contains("pin.fill")
            && librarySource.contains("model.setCategoryPinned(category.id, pinned: !category.isPinned)")
            && appModelSource.contains("func setCategoryPinned("),
        "library category rows should expose folder pinning within the current parent level"
    )
    try check(
        librarySource.contains("bulkActionBarOverlayYOffset"),
        "library bulk action overlay should sit lower over the list instead of hugging the top edge"
    )
    try check(
        librarySource.contains("bulkActionBarOverlayOpacity"),
        "library bulk action overlay should render with reduced opacity"
    )
    try check(
        librarySource.contains("static let bulkActionBarOverlayYOffset: CGFloat = 148")
            && librarySource.contains("static let bulkActionBarOverlayOpacity = 0.66")
            && librarySource.contains("onCopy")
            && librarySource.contains("LibraryBulkCopySheet")
            && !librarySource.contains("LibraryBulkMoveSheet"),
        "library multi-selection should show a lower, softer bulk bar with copy instead of move"
    )
    try check(
        librarySource.contains("dragPayload: { row in")
            && librarySource.contains("paperDragPayload(for: row.paper)")
            && librarySource.contains("paperIDsForDrag(startingWith:"),
        "native paper drags should reflect the seeded multi-selection set in their payload"
    )
    try check(
        !librarySource.contains("DragGesture(minimumDistance: 8"),
        "library paper dragging should not rely on a parallel custom drag gesture"
    )
    try check(
        libraryPaperTableSource.contains("private var isPressing = false")
            && libraryPaperTableSource.contains("onPressRow")
            && libraryPaperTableSource.contains("setPressedRow")
            && libraryPaperTableSource.contains("isPressing && !row.isImportPlaceholder")
            && !librarySource.contains("DragGesture(minimumDistance: 0"),
        "library paper rows should provide immediate pressed feedback without replacing native drag/drop"
    )
    try check(
        !librarySource.contains("ActiveLibraryPaperDrag"),
        "library paper dragging should avoid stale custom drag state when native drag/drop is used"
    )

    let repositorySource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexCore/PaperRepository.swift"))
    let settingsViewURL = root.appendingPathComponent("Sources/PaperCodexApp/SettingsView.swift")
    let settingsViewSource = try String(contentsOf: settingsViewURL)
    let discoverViewURL = root.appendingPathComponent("Sources/PaperCodexApp/DiscoverView.swift")
    let discoverSource = try String(contentsOf: discoverViewURL)
    let nativeDiscoverCollectionURL = root.appendingPathComponent("Sources/PaperCodexApp/NativeDiscoverCollectionView.swift")
    let nativeDiscoverCollectionSource = FileManager.default.fileExists(atPath: nativeDiscoverCollectionURL.path) ? try String(contentsOf: nativeDiscoverCollectionURL) : ""
    let appShellURL = root.appendingPathComponent("Sources/PaperCodexApp/AppShell.swift")
    let appShellSource = FileManager.default.fileExists(atPath: appShellURL.path) ? try String(contentsOf: appShellURL) : ""
    let collectionViewURL = root.appendingPathComponent("Sources/PaperCodexApp/CollectionView.swift")
    let collectionViewExists = FileManager.default.fileExists(atPath: collectionViewURL.path)
    let appSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexApp.swift"))
    let appKitWindowControllerSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexMainWindowController.swift"))
    let appKitMenuSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexMainMenu.swift"))
    let chatViewURL = root.appendingPathComponent("Sources/PaperCodexApp/ChatView.swift")
    let chatSource = try String(contentsOf: chatViewURL)
    let agentTerminalSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/AgentTerminalView.swift"))
    let agentTerminalNativeSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/AgentTerminalNativePanelView.swift"))
    let chatAppearanceURL = root.appendingPathComponent("Sources/PaperCodexApp/ChatAppearance.swift")
    let chatAppearanceSource = FileManager.default.fileExists(atPath: chatAppearanceURL.path) ? try String(contentsOf: chatAppearanceURL) : ""
    let chatMarkdownRendererSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexCore/ChatMarkdownRenderer.swift"))
    let saveToLibrarySource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/SaveToLibrarySheet.swift"))
    let readerViewSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/ReaderView.swift"))
    let readerToolbarSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/ReaderToolbarView.swift"))
    let readerSplitSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/ReaderSplitView.swift"))
    let readerSessionToolbarSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/ReaderSessionToolbarView.swift"))
    let chatComposerNativeSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/ChatComposerNativePanelView.swift"))
    let sessionNotesNativeSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/SessionNotesNativePanelView.swift"))
    let windowTabBarSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/WindowChromeTabBar.swift"))
    let homeChromeSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/WindowChrome.swift"))
    let localThumbnailSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/LocalThumbnailImage.swift"))
    let libraryDerivedStateSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexCore/LibraryDerivedState.swift"))
    let readerFeatureStoreSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/ReaderFeatureStore.swift"))
    let discoverFeatureStoreSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/DiscoverFeatureStore.swift"))
    let designSystemSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexDesignSystem.swift"))
    let actionButtonSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexActionButton.swift"))
    let sidebarRowSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/SidebarRowButton.swift"))
    let libraryCategoryAssignmentSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexCore/LibraryCategoryAssignment.swift"))
    let agentRuntimeSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexCore/AgentRuntime.swift"))
    let codexAgentRuntimeSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexCore/CodexAgentRuntime.swift"))
    let agentRuntimeStoreSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/AgentRuntimeStore.swift"))
    let coordinatorSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/AgentRunCoordinator.swift"))
    let arxivIDExtractorSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexCore/ArxivIDExtractor.swift"))
    let interactionFeedbackSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/InteractionFeedback.swift"))
    let localArxivClientSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexCore/LocalArxivClient.swift"))
    let nativeFormControlsURL = root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexNativeFormControls.swift")
    let nativeFormControlsSource = FileManager.default.fileExists(atPath: nativeFormControlsURL.path) ? try String(contentsOf: nativeFormControlsURL) : ""
    let nativeConfirmationURL = root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexNativeConfirmation.swift")
    let nativeConfirmationSource = FileManager.default.fileExists(atPath: nativeConfirmationURL.path) ? try String(contentsOf: nativeConfirmationURL) : ""
    let nativeSheetURL = root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexNativeSheet.swift")
    let nativeSheetSource = FileManager.default.fileExists(atPath: nativeSheetURL.path) ? try String(contentsOf: nativeSheetURL) : ""
    let nativeStatusViewsURL = root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexNativeStatusViews.swift")
    let nativeStatusViewsSource = FileManager.default.fileExists(atPath: nativeStatusViewsURL.path) ? try String(contentsOf: nativeStatusViewsURL) : ""
    let nativeScrollViewURL = root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexNativeScrollView.swift")
    let nativeScrollViewSource = FileManager.default.fileExists(atPath: nativeScrollViewURL.path) ? try String(contentsOf: nativeScrollViewURL) : ""
    let appSourceDirectory = root.appendingPathComponent("Sources/PaperCodexApp")
    let appSwiftSourceFiles = try FileManager.default.contentsOfDirectory(at: appSourceDirectory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
    let appSourcesWithSwiftUISheet = try appSwiftSourceFiles.compactMap { fileURL -> String? in
        let source = try String(contentsOf: fileURL)
        return source.contains(".sheet(") ? fileURL.lastPathComponent : nil
    }
    let swiftUIListRegex = try NSRegularExpression(pattern: #"(?m)\bList\s*\{"#)
    let appSourcesWithSwiftUIStatusViews = try appSwiftSourceFiles.compactMap { fileURL -> String? in
        let source = try String(contentsOf: fileURL)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let hasSwiftUIStatusView = source.contains("ContentUnavailableView")
            || source.contains("ProgressView(")
            || swiftUIListRegex.firstMatch(in: source, range: range) != nil
        return hasSwiftUIStatusView ? fileURL.lastPathComponent : nil
    }
    let swiftUIFormControlRegex = try NSRegularExpression(pattern: #"\b(TextField|SecureField|TextEditor|Picker|Toggle|Stepper|DatePicker)\("#)
    let swiftUIScrollViewRegex = try NSRegularExpression(pattern: #"\bScrollView\s*(?:\(|\{)"#)
    let appSourcesWithSwiftUIScrollViews = try appSwiftSourceFiles.compactMap { fileURL -> String? in
        let source = try String(contentsOf: fileURL)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return swiftUIScrollViewRegex.firstMatch(in: source, range: range) != nil || source.contains("ScrollViewReader")
            ? fileURL.lastPathComponent
            : nil
    }
    func hasSwiftUIFormControlUse(_ source: String) -> Bool {
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return swiftUIFormControlRegex.firstMatch(in: source, range: range) != nil
    }
    func hasSwiftUIScrollViewUse(_ source: String) -> Bool {
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return swiftUIScrollViewRegex.firstMatch(in: source, range: range) != nil
    }
    func swiftUIScrollViewUseCount(_ source: String) -> Int {
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return swiftUIScrollViewRegex.numberOfMatches(in: source, range: range)
    }
    try check(
        appModelSource.contains("case search")
            && appSource.contains("ArxivSearchView()")
            && appShellSource.contains("title: \"探索\"")
            && appShellSource.contains("title: \"搜索\"")
            && windowTabBarSource.contains("Home: 探索")
            && windowTabBarSource.contains("Home: 搜索"),
        "navigation should rename Discover to Explore and add an arXiv search page below it"
    )
    try check(
        discoverSource.contains("struct ArxivSearchView")
            && discoverSource.contains("model.startArxivSearch()")
            && discoverSource.contains("NativeDiscoverCollectionView(")
            && discoverSource.contains("nativeSearchCardModels")
            && discoverSource.contains("model.processCurrentDiscoverResults(searchPapers"),
        "search page should call arXiv API search and reuse the native Explore collection card surface and processing"
    )
    try check(
        localArxivClientSource.contains("func search(query:")
            && localArxivClientSource.contains("sortBy: ArxivAPISort")
            && localArxivClientSource.contains("sortOrder: ArxivAPISortOrder")
            && localArxivClientSource.contains("normalizedUserSearchQuery"),
        "LocalArxivClient should expose arXiv-compatible API search with explicit sort parameters"
    )
    try check(
        librarySource.contains("LibraryPaperArxivMetadata")
            && librarySource.contains("LibraryPaperInspectorDetailsView(")
            && librarySource.contains("private struct LibraryPaperInspectorDetailsView: NSViewRepresentable")
            && librarySource.contains("private final class NativeLibraryPaperInspectorDetailsView: NSView")
            && librarySource.contains("private final class NativeInspectorDetailsTagButton: NSButton")
            && librarySource.contains("private final class NativeInspectorDetailsNoteRowView: NSView")
            && !librarySource.contains("private func paperMetadataSection(")
            && !librarySource.contains("private func categoryAssignments(for paper: Paper)")
            && !librarySource.contains("private func tagAssignments(for paper: Paper)")
            && !librarySource.contains("private func paperNotesSection(for paper: Paper)")
            && appModelSource.contains("func libraryArxivMetadata(for paper: Paper)"),
        "library inspector details should surface metadata, categories, tags, and notes through a native AppKit view instead of SwiftUI stacks and grids"
    )
    try check(
        librarySource.contains("LibraryPaperInspectorSummaryView(")
            && librarySource.contains("private struct LibraryPaperInspectorSummaryView: NSViewRepresentable")
            && librarySource.contains("private final class NativeLibraryPaperInspectorSummaryView: NSView")
            && librarySource.contains("private let starButton = NSButton()")
            && librarySource.contains("private let readButton = NativeInspectorReadButton()")
            && librarySource.contains("private let readButtonTitleLabel = NativeInspectorPassthroughLabel(\"Read\")")
            && librarySource.contains("private final class NativeInspectorPassthroughLabel: NSTextField")
            && librarySource.contains("private final class NativeInspectorReadButton: NSButton")
            && librarySource.contains("private let buttonTitleLabel = NSTextField(labelWithString: \"Read\")")
            && librarySource.contains("buttonTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12)")
            && librarySource.contains("readButton.isEnabled = !paper.isArxivImportPlaceholder")
            && librarySource.contains("starButton.isEnabled = !paper.isArxivImportPlaceholder"),
        "library inspector summary should render selected-paper title, star, path, and read action with native AppKit controls"
    )
    try check(
        interactionFeedbackSource.contains("defaultNoticeDismissDuration")
            && interactionFeedbackSource.contains("case .success:\n        5")
            && interactionFeedbackSource.contains("case .error:\n        10")
            && appModelSource.contains("autoDismissAfter ?? defaultNoticeDismissDuration(for: kind)"),
        "success and failure notices should auto-dismiss after 5s and 10s respectively"
    )
    try check(
        interactionFeedbackSource.contains("PaperCodexIconButton(")
            && interactionFeedbackSource.contains("title: isExpanded ? \"Hide details\" : \"Show details\"")
            && interactionFeedbackSource.contains("title: \"Dismiss Notification\"")
            && !interactionFeedbackSource.contains("\n                    Button")
            && !interactionFeedbackSource.contains("\n                Button(action:")
            && !interactionFeedbackSource.contains(".buttonStyle("),
        "global interaction notices should use native AppKit-backed icon buttons for details and dismiss actions"
    )
    try check(
        !collectionViewExists
            && !appSource.contains("case .collections")
            && !appSource.contains("CollectionView()")
            && !appSource.contains("showCollections")
            && !librarySource.contains("title: \"Collections\"")
            && !librarySource.contains("createCollection")
            && !discoverSource.contains("title: \"Collections\"")
            && !settingsViewSource.contains("title: \"Collections\"")
            && !appModelSource.contains("PaperCollection")
            && !appModelSource.contains("collectionStore")
            && !appModelSource.contains("showCollections"),
        "Collection feature should be fully removed from routes, sidebars, AppModel, and dedicated views"
    )
    try check(
        !appSource.contains("AppShell {")
            && appSource.contains("routedContent")
            && !appShellSource.contains("struct AppShell"),
        "Root layout should not add an extra app-shell sidebar column"
    )
    try check(
        appModelSource.contains("enum AppRoute: Hashable")
            && appModelSource.contains("final class AppNavigation: ObservableObject")
            && appModelSource.contains("let navigation = AppNavigation()")
            && appModelSource.contains("var route: AppRoute {\n        get { navigation.route }\n        set { navigation.route = newValue }\n    }")
            && appModelSource.contains("final class AppNavigation: ObservableObject {\n    @Published var route: AppRoute = .library")
            && !appModelSource.contains("final class AppModel: ObservableObject {\n    @Published var route")
            && appKitWindowControllerSource.contains(".environmentObject(model.navigation)")
            && appSource.contains("@EnvironmentObject private var navigation: AppNavigation")
            && appShellSource.contains("@EnvironmentObject private var navigation: AppNavigation")
            && appSource.contains("private let initiallyMountedRoutes: Set<AppRoute>")
            && appSource.contains("@State private var mountedRoutes: Set<AppRoute> = initiallyMountedRoutes")
            && appSource.contains("private let persistentRouteOrder: [AppRoute]")
            && appSource.contains("persistentRoutedContent")
            && appSource.contains("RouteTransitionPlaceholder")
            && appSource.contains("RouteVisibilityHost")
            && appSource.contains("mountedRoutes.contains(navigation.route)")
            && appSource.contains("mountRoute(newRoute)")
            && appSource.contains("RouteVisibilityHost(route: route, activeRoute: navigation.route) {\n                        routedContent(for: route)\n                    }\n                    .frame(maxWidth: .infinity, maxHeight: .infinity)")
            && appSource.contains("content()\n            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)\n            .opacity(route == activeRoute ? 1 : 0)")
            && appSource.contains(".allowsHitTesting(route == activeRoute)")
            && appSource.contains(".accessibilityHidden(route != activeRoute)")
            && !appModelSource.contains("scheduleReaderContextClear()"),
        "routes should be lazily mounted and preserve visited reader context across navigation without prewarming hidden surfaces"
    )
    if let routeVisibilityRange = appSource.range(of: "private struct RouteVisibilityHost"),
       let routeVisibilityEndRange = appSource.range(of: "private struct RouteTransitionPlaceholder", range: routeVisibilityRange.upperBound..<appSource.endIndex) {
        let routeVisibilitySource = String(appSource[routeVisibilityRange.lowerBound..<routeVisibilityEndRange.lowerBound])
        try check(
            routeVisibilitySource.contains(".transaction { transaction in")
                && routeVisibilitySource.contains("transaction.animation = nil")
                && !routeVisibilitySource.contains(".animation(PaperCodexMotion.route, value: activeRoute)"),
            "route content should switch immediately while navigation row press feedback acknowledges the click"
        )
    } else {
        throw CheckFailure(description: "route visibility host source should remain inspectable")
    }
    try check(
        appShellSource.contains("struct PrimaryNavigationSection")
            && appShellSource.contains("NativePrimaryNavigationView(")
            && appShellSource.contains("NativePrimaryNavigationContainerView")
            && appShellSource.contains("NativePrimaryNavigationRowButton")
            && appShellSource.contains("NSStackView")
            && appShellSource.contains("NSButton")
            && appShellSource.contains("override func mouseDown(with event: NSEvent)")
            && appShellSource.contains("setAccessibilityRole(.button)")
            && !appShellSource.contains("SidebarRowButton(")
            && appShellSource.contains("title: \"Library\"")
            && appShellSource.contains("model.goToLibrary()")
            && appShellSource.contains("title: \"探索\"")
            && appShellSource.contains("model.showDiscover()")
            && appShellSource.contains("title: \"搜索\"")
            && appShellSource.contains("model.showSearch()")
            && appShellSource.contains("title: \"Settings\"")
            && appShellSource.contains("model.showSettings()")
            && appShellSource.contains("title: \"Recent Conversations\"")
            && appShellSource.contains("model.showRecentConversations()")
            && librarySource.contains("PrimaryNavigationSection()")
            && discoverSource.contains("PrimaryNavigationSection()")
            && settingsViewSource.contains("PrimaryNavigationSection()"),
        "Library, Explore, Search, and Settings should share one in-sidebar global navigation section"
    )
    if let navigationRange = appShellSource.range(of: "struct PrimaryNavigationSection"),
       let libraryRange = appShellSource.range(of: "title: \"Library\""),
       let discoverRange = appShellSource.range(of: "title: \"探索\""),
       let searchRange = appShellSource.range(of: "title: \"搜索\""),
       let settingsRange = appShellSource.range(of: "title: \"Settings\""),
       let recentRange = appShellSource.range(of: "title: \"Recent Conversations\"") {
        try check(
            navigationRange.lowerBound < libraryRange.lowerBound
                && libraryRange.lowerBound < discoverRange.lowerBound
                && discoverRange.lowerBound < searchRange.lowerBound
                && searchRange.lowerBound < settingsRange.lowerBound
                && settingsRange.lowerBound < recentRange.lowerBound,
            "Recent Conversations should live under Settings in the shared sidebar navigation"
        )
    } else {
        throw CheckFailure(description: "shared sidebar navigation should include Library, Explore, Search, Settings, and Recent Conversations")
    }
    try check(
        !librarySource.contains("title: \"Discover\",")
            && !librarySource.contains("title: \"Settings\",")
            && !librarySource.contains("title: \"Recent Conversations\",")
            && !discoverSource.contains("navButton(title: \"Library\"")
            && !discoverSource.contains("navButton(title: \"Settings\"")
            && !settingsViewSource.contains("navButton(title: \"Library\"")
            && !settingsViewSource.contains("navButton(title: \"Discover\""),
        "page sidebars should use the shared navigation component instead of duplicating route rows"
    )
    try check(
        appShellSource.contains("PrimaryNavigationSection")
            && appShellSource.contains("NativePrimaryNavigationView(")
            && appShellSource.contains("title: \"Library\"")
            && appShellSource.contains("title: \"探索\"")
            && appShellSource.contains("title: \"搜索\"")
            && appShellSource.contains("title: \"Settings\"")
            && appShellSource.contains("title: \"Recent Conversations\""),
        "Shared sidebar navigation should centralize global route labels"
    )
    try check(
        (appModelSource.contains("@Published var selectedLibrarySurface: LibrarySurface")
            || libraryFeatureStoreSource.contains("@Published var selectedLibrarySurface: LibrarySurface")
            || libraryFeatureStoreSource.contains("@Published private var selection"))
            && appModelSource.contains("func showRecentConversations()")
            && appModelSource.contains("setLibrarySelection(surface: .recentConversations, categoryID: nil, tagID: nil)")
            && !librarySource.contains("@State private var selectedLibrarySurface"),
        "Recent Conversations selection should be app-level navigation state instead of LibraryView local state"
    )
    try check(
        appModelSource.contains("movePapers(_ paperIDs: [String], toCategory categoryID: String?)"),
        "AppModel should provide a batch paper category move path for drag and drop"
    )
    try check(
        appModelSource.contains("moveCategory(_ categoryID: String, toParent parentID: String?)"),
        "AppModel should provide a dedicated category reparenting path for folder drag and drop"
    )
    try check(
        appModelSource.contains("let categoryIDs = Set([categoryID]).union(categoryDescendantIDs(of: categoryID))")
            && appModelSource.contains("isDisjoint(with: categoryIDs)"),
        "category similarity sources should include papers assigned to descendant folders"
    )
    try check(
        appModelSource.contains("func rerankCurrentDiscoverResults() async")
            && discoverSource.contains("await model.rerankCurrentDiscoverResults()"),
        "discover similarity source changes should rerank the current results without another search"
    )
    try check(
        saveToLibrarySource.contains("libraryCategories")
            && saveToLibrarySource.contains("selectedCategoryIDs")
            && !saveToLibrarySource.contains("selectedTagNames"),
        "saving a Discover paper should assign library categories instead of tags"
    )
    try check(
        saveToLibrarySource.contains("SaveToLibraryNewCategory")
            && saveToLibrarySource.contains("NativeSaveToLibraryFolderPicker(")
            && saveToLibrarySource.contains("SaveToLibraryFolderPickerRowModel")
            && saveToLibrarySource.contains("private final class NativeSaveToLibraryFolderPickerView: NSScrollView")
            && saveToLibrarySource.contains("private final class NativeSaveToLibraryFolderPickerTableView: NSTableView")
            && saveToLibrarySource.contains("private final class NativeSaveToLibraryFolderPickerController: NSObject, NSTableViewDataSource, NSTableViewDelegate")
            && saveToLibrarySource.contains("private final class NativeSaveToLibraryFolderRowCellView: NSTableCellView")
            && saveToLibrarySource.contains("collapsedCategoryIDs")
            && saveToLibrarySource.contains("activeNewCategoryParentID")
            && saveToLibrarySource.contains("newCategories: selectedNewCategoriesInOrder")
            && !saveToLibrarySource.contains("ForEach(visibleFolderItems)")
            && !saveToLibrarySource.contains("SaveToLibraryFolderRow("),
        "save-to-library should use a reusable native AppKit folder tree with selectable folders and in-tree folder creation"
    )
    try check(
        saveToLibrarySource.contains("NativeSaveToLibraryTreeConnectorView")
            && saveToLibrarySource.contains("connectorContinuations")
            && saveToLibrarySource.contains("treeConnectorHeight: CGFloat = 34")
            && saveToLibrarySource.contains("treeIndentWidth")
            && saveToLibrarySource.contains("folderIconCenterX")
            && saveToLibrarySource.contains("treeConnectorTargetInset")
            && saveToLibrarySource.contains("NSBezierPath")
            && saveToLibrarySource.contains("setLineDash")
            && saveToLibrarySource.contains("currentTargetX")
            && !saveToLibrarySource.contains("SaveToLibraryDepthGuide"),
        "save-to-library folder picker should use the same continuous, lightweight folder-tree connectors as the library sidebar"
    )
    try check(
        appModelSource.contains("selectedCategoryIDs:")
            && appModelSource.contains("assignCategories(")
            && !appModelSource.contains("addArxivPaperToLibrary(_ arxivPaper: ArxivFeedPaper, selectedTagNames"),
        "arXiv save paths should assign selected categories instead of selected tags"
    )
    try check(
        appModelSource.contains("newCategories: [SaveToLibraryNewCategory]")
            && appModelSource.contains("LibraryCategoryAssigner().assign")
            && appModelSource.contains("onCategoryCreated")
            && libraryCategoryAssignmentSource.contains("createdCategoryIDsByRequestID")
            && libraryCategoryAssignmentSource.contains("LibraryCategoryAssignmentError.invalidCategoryHierarchy"),
        "arXiv and cached-paper save paths should create new folders under their selected parent folders"
    )
    try check(
        libraryFeatureStoreSource.contains("final class LibraryFeatureStore")
            && libraryFeatureStoreSource.contains("func applySnapshot")
            && appModelSource.contains("private let libraryStore = LibraryFeatureStore()")
            && appModelSource.contains("libraryStore.applySnapshot")
            && !appModelSource.contains("@Published var papers: [Paper]")
            && !appModelSource.contains("@Published var categories: [PaperCodexCore.Category]")
            && !appModelSource.contains("@Published var libraryDerivedState: PaperLibraryDerivedState"),
        "Library state should live in LibraryFeatureStore while AppModel remains the compatibility coordinator"
    )
    try check(
        readerFeatureStoreSource.contains("final class ReaderFeatureStore")
            && appModelSource.contains("private let readerStore = ReaderFeatureStore()")
            && appModelSource.contains("readerStore.objectWillChange")
            && !appModelSource.contains("@Published var selectedPaper: Paper?")
            && !appModelSource.contains("@Published var readerTabState")
            && !appModelSource.contains("@Published var selectedSession: PaperSession?")
            && !appModelSource.contains("@Published var messages: [ChatMessage]")
            && !appModelSource.contains("@Published var pdfJumpTarget: PDFJumpTarget?"),
        "Reader and session state should live in ReaderFeatureStore while AppModel coordinates commands"
    )
    try check(
        discoverFeatureStoreSource.contains("final class DiscoverFeatureStore")
            && appModelSource.contains("private let discoverStore: DiscoverFeatureStore")
            && appModelSource.contains("discoverStore.objectWillChange")
            && !appModelSource.contains("@Published var arxivFeed: ArxivFeedResponse?")
            && !appModelSource.contains("@Published var discoverKeyword")
            && !appModelSource.contains("@Published var discoverResultIDs")
            && !appModelSource.contains("@Published var discoverEnrichmentsByID")
            && !appModelSource.contains("@Published var isSearchingDiscover"),
        "Discover state should live in DiscoverFeatureStore while AppModel coordinates search and processing commands"
    )
    try check(
        agentRuntimeSource.contains("protocol AgentRuntime")
            && agentRuntimeSource.contains("struct AgentRunRequest")
            && agentRuntimeSource.contains("struct AgentRunResult")
            && agentRuntimeSource.contains("func runTurn(")
            && agentRuntimeSource.contains("typealias AgentRuntimeRequest = AgentRunRequest")
            && agentRuntimeSource.contains("typealias AgentRuntimeResult = AgentRunResult")
            && agentRuntimeSource.contains("public var mcpServers: [CodexMCPServerConfig]")
            && agentRuntimeSource.contains("public var mcpEnvironmentOverrides: [String: String]")
            && codexAgentRuntimeSource.contains("struct CodexAgentRuntime")
            && codexAgentRuntimeSource.contains("func runTurn(")
            && codexAgentRuntimeSource.contains("CodexCLI")
            && codexAgentRuntimeSource.contains("mcpServers: request.mcpServers")
            && codexAgentRuntimeSource.contains("environmentOverrides: request.mcpEnvironmentOverrides")
            && codexAgentRuntimeSource.contains("GeneratedImageCollector.newImages")
            && appModelSource.contains("private let agentRunCoordinator = AgentRunCoordinator()")
            && appModelSource.contains("agentRunCoordinator.runChatTurn"),
        "Codex CLI streaming should sit behind an AgentRuntime boundary and carry app-local MCP settings"
    )
    try check(
        agentRuntimeStoreSource.contains("final class AgentRuntimeStore: ObservableObject")
            && agentRuntimeStoreSource.contains("selectedChatRuntimeID")
            && agentRuntimeStoreSource.contains("selectedEnrichmentRuntimeID")
            && agentRuntimeStoreSource.contains("enabledRuntimeIDs")
            && agentRuntimeStoreSource.contains("modelOverridesByRuntimeID")
            && agentRuntimeStoreSource.contains("providerOverridesByRuntimeID")
            && agentRuntimeStoreSource.contains("mcpModesByRuntimeID")
            && agentRuntimeStoreSource.contains("diagnosticsByRuntimeID")
            && agentRuntimeStoreSource.contains("authSummariesByRuntimeID")
            && agentRuntimeStoreSource.contains("func refreshDiagnostics() async")
            && agentRuntimeStoreSource.contains("safeAuthStatusArguments")
            && appModelSource.contains("private let agentRuntimeStore = AgentRuntimeStore()")
            && appModelSource.contains("agentRuntimeStore.objectWillChange")
            && appModelSource.contains("var agentRuntimeProfiles: [AgentRuntimeProfile]")
            && appModelSource.contains("var selectedChatRuntimeDisplayName: String")
            && appModelSource.contains("func setSelectedChatRuntimeID")
            && appModelSource.contains("func setAgentRuntimeEnabled")
            && appModelSource.contains("func refreshAgentRuntimeDiagnostics() async"),
        "generic agent runtime settings should live in AgentRuntimeStore and be exposed through AppModel"
    )
    try check(
        settingsViewSource.contains("agentRuntimeSettings")
            && settingsViewSource.contains("Agent Runtimes")
            && settingsViewSource.contains("selectedChatRuntimeID")
            && settingsViewSource.contains("selectedEnrichmentRuntimeID")
            && settingsViewSource.contains("setAgentRuntimeEnabled")
            && settingsViewSource.contains("setAgentRuntimeModelOverride")
            && settingsViewSource.contains("setAgentRuntimeProviderOverride")
            && settingsViewSource.contains("setAgentRuntimeMCPMode")
            && settingsViewSource.contains("refreshAgentRuntimeDiagnostics"),
        "settings should expose runtime selection, enablement, diagnostics, auth, model/provider overrides, and MCP mode"
    )
    try check(
        chatSource.contains("ChatComposerNativePanelView(")
            && chatSource.contains("selectedChatRuntimeDisplayName")
            && chatSource.contains("selectedChatRuntimeDiagnostic")
            && chatSource.contains("setSelectedChatRuntimeID")
            && chatComposerNativeSource.contains("Stop Agent")
            && chatComposerNativeSource.contains("runtimePopup")
            && !chatSource.contains("Stop Codex")
            && !chatSource.contains("ask Codex in this session"),
        "reader chat controls should present runtime-neutral agent labels instead of Codex-only labels"
    )
    try check(
        nativeFormControlsSource.contains("struct PaperCodexNativeTextField: NSViewRepresentable")
            && nativeFormControlsSource.contains("struct PaperCodexNativeTextEditor: NSViewRepresentable")
            && nativeFormControlsSource.contains("struct PaperCodexNativePopupButton: NSViewRepresentable")
            && nativeFormControlsSource.contains("struct PaperCodexNativeCheckboxRow: NSViewRepresentable")
            && nativeFormControlsSource.contains("final class PaperCodexNativeTextFieldView: NSTextField")
            && nativeFormControlsSource.contains("final class PaperCodexNativeTextEditorContainerView: NSView")
            && nativeFormControlsSource.contains("final class PaperCodexNativePopupButtonView: NSPopUpButton")
            && nativeFormControlsSource.contains("final class PaperCodexNativeCheckboxRowView: NSView")
            && nativeFormControlsSource.contains("setButtonType(.switch)")
            && nativeFormControlsSource.contains("setAccessibilityRole(.checkBox)")
            && nativeFormControlsSource.contains("NSTextView")
            && nativeFormControlsSource.contains("NSScrollView")
            && chatSource.contains("PaperCodexNativeTextField(")
            && (saveToLibrarySource.contains("PaperCodexNativeTextField(") || saveToLibrarySource.contains("private let nameField = NSTextField()"))
            && readerViewSource.contains("PaperCodexNativeTextField(")
            && (librarySource.contains("PaperCodexNativeTextField(") || librarySource.contains("private let noteTitleField = NSTextField()"))
            && (librarySource.contains("PaperCodexNativeTextEditor(") || librarySource.contains("private let noteBodyTextView = NSTextView()"))
            && librarySource.contains("PaperCodexNativePopupButton(")
            && (librarySource.contains("PaperCodexNativeCheckboxRow(") || librarySource.contains("NSButton(checkboxWithTitle:"))
            && !hasSwiftUIFormControlUse(chatSource)
            && !hasSwiftUIFormControlUse(saveToLibrarySource)
            && !hasSwiftUIFormControlUse(readerViewSource)
            && !hasSwiftUIFormControlUse(librarySource),
        "remaining app form inputs should use shared native AppKit text, popup, editor, and checkbox controls"
    )
    try check(
        nativeConfirmationSource.contains("enum PaperCodexNativeConfirmation")
            && nativeConfirmationSource.contains("let alert = NSAlert()")
            && nativeConfirmationSource.contains("alert.beginSheetModal(for: window)")
            && nativeConfirmationSource.contains("alert.runModal()")
            && librarySource.contains("PaperCodexNativeConfirmation.present")
            && settingsViewSource.contains("PaperCodexNativeConfirmation.present")
            && !librarySource.contains(".alert(")
            && !settingsViewSource.contains(".alert(")
            && !librarySource.contains("isConfirmingBulkDelete")
            && !settingsViewSource.contains("isConfirmingClearCache")
            && !librarySource.contains("Button(\"Delete\", role: .destructive)")
            && !settingsViewSource.contains("Button(\"Clear\", role: .destructive)"),
        "destructive confirmation dialogs should be explicit native AppKit NSAlert sheets instead of SwiftUI alert buttons"
    )
    try check(
        nativeSheetSource.contains("struct PaperCodexNativeSheetPresenter")
            && nativeSheetSource.contains("window.beginSheet(sheetWindow)")
            && nativeSheetSource.contains("window.endSheet(sheetWindow)")
            && nativeSheetSource.contains("NSHostingController(rootView:")
            && nativeSheetSource.contains("extension View")
            && nativeSheetSource.contains("paperCodexNativeSheet")
            && appSourcesWithSwiftUISheet.isEmpty,
        "modal sheets should be presented through the shared AppKit sheet presenter instead of SwiftUI .sheet; remaining files: \(appSourcesWithSwiftUISheet.joined(separator: ", "))"
    )
    try check(
        nativeStatusViewsSource.contains("struct PaperCodexNativeEmptyState")
            && nativeStatusViewsSource.contains("struct PaperCodexNativeSpinner")
            && nativeStatusViewsSource.contains("struct PaperCodexNativeProgressBar")
            && nativeStatusViewsSource.contains("NSProgressIndicator")
            && nativeStatusViewsSource.contains("NSTextField(labelWithString:")
            && nativeStatusViewsSource.contains("NSImage(systemSymbolName:")
            && chatSource.contains("renderEmptyState")
            && discoverSource.contains("PaperCodexNativeProgressBar(")
            && interactionFeedbackSource.contains("PaperCodexNativeSpinner(")
            && appSourcesWithSwiftUIStatusViews.isEmpty,
        "empty states, loading indicators, and remaining lists should use shared AppKit status views instead of SwiftUI ContentUnavailableView/ProgressView/List; remaining files: \(appSourcesWithSwiftUIStatusViews.joined(separator: ", "))"
    )
    try check(
        discoverSource.contains("NativeDiscoverCollectionView(")
            && nativeDiscoverCollectionSource.contains("struct NativeDiscoverCollectionView")
            && nativeDiscoverCollectionSource.contains("NSCollectionView")
            && nativeDiscoverCollectionSource.contains("NSCollectionViewFlowLayout")
            && nativeDiscoverCollectionSource.contains("NSCollectionViewItem")
            && nativeDiscoverCollectionSource.contains("makeItem(withIdentifier:")
            && nativeDiscoverCollectionSource.contains("final class NativeDiscoverPaperCardView: NSView")
            && nativeDiscoverCollectionSource.contains("onVisiblePaperChange")
            && nativeDiscoverCollectionSource.contains("scrollToPaper")
            && !nativeDiscoverCollectionSource.contains("NSHostingView"),
        "Discover main results should use a reusable native AppKit NSCollectionView card surface instead of an AppKit scroll view hosting SwiftUI cards"
    )
    try check(
        nativeScrollViewSource.contains("struct PaperCodexNativeScrollView")
            && nativeScrollViewSource.contains("struct PaperCodexNativeScrollRequest")
            && nativeScrollViewSource.contains("struct PaperCodexNativeVisibleRange")
            && nativeScrollViewSource.contains("final class NativePaperCodexHostingScrollView: NSScrollView")
            && nativeScrollViewSource.contains("NSHostingView(rootView:")
            && nativeScrollViewSource.contains("documentView = documentContainer")
            && nativeScrollViewSource.contains("scrollRequest:")
            && nativeScrollViewSource.contains("onVisibleRangeChange:")
            && settingsViewSource.contains("PaperCodexNativeScrollView")
            && librarySource.contains("PaperCodexNativeScrollView")
            && saveToLibrarySource.contains("PaperCodexNativeScrollView")
            && interactionFeedbackSource.contains("PaperCodexNativeScrollView")
            && chatSource.contains("NativeChatTranscriptView(")
            && chatSource.contains("scrollRequestToken: chatScrollRequestToken")
            && chatSource.contains("requestChatScrollToBottom")
            && discoverSource.contains("PaperCodexNativeScrollView")
            && discoverSource.contains("NativeDiscoverCollectionView(")
            && discoverSource.contains("requestNativeDiscoverScrollRestore")
            && readerViewSource.contains("NativeAddPaperToSessionList(")
            && !hasSwiftUIScrollViewUse(settingsViewSource)
            && !hasSwiftUIScrollViewUse(librarySource)
            && !hasSwiftUIScrollViewUse(saveToLibrarySource)
            && !hasSwiftUIScrollViewUse(interactionFeedbackSource)
            && !hasSwiftUIScrollViewUse(chatSource)
            && !hasSwiftUIScrollViewUse(discoverSource)
            && !hasSwiftUIScrollViewUse(readerViewSource)
            && !chatSource.contains("ScrollViewReader")
            && !discoverSource.contains("ScrollViewReader")
            && appSourcesWithSwiftUIScrollViews.isEmpty,
        "static app scroll regions should use shared AppKit NSScrollView hosting, chat should use a single native transcript surface, and high-throughput Discover results should use native NSCollectionView; remaining SwiftUI scroll files: \(appSourcesWithSwiftUIScrollViews.joined(separator: ", "))"
    )
    if let nativeScrollApplyRange = nativeScrollViewSource.range(of: "    func apply("),
       let nativeScrollSetupRange = nativeScrollViewSource.range(of: "    private func setup()", range: nativeScrollApplyRange.upperBound..<nativeScrollViewSource.endIndex) {
        let nativeScrollApplySource = String(nativeScrollViewSource[nativeScrollApplyRange.lowerBound..<nativeScrollSetupRange.lowerBound])
        try check(
            nativeScrollViewSource.contains("private var isLayingOutHostedContent = false")
                && nativeScrollViewSource.contains("private var needsContentMeasurement = true")
                && nativeScrollViewSource.contains("private var lastMeasuredWidth: CGFloat?")
                && nativeScrollViewSource.contains("var contentID: AnyHashable?")
                && nativeScrollViewSource.contains("let contentChanged = contentID == nil || self.contentID != contentID")
                && nativeScrollViewSource.contains("if contentChanged {")
                && nativeScrollViewSource.contains("guard !isLayingOutHostedContent else")
                && discoverSource.contains("PaperCodexNativeScrollView(contentID: sidebarContentID)")
                && !nativeScrollApplySource.contains("layoutSubtreeIfNeeded()"),
            "shared native hosted scroll view should avoid synchronous update-layout recursion and cache content measurement/root updates"
        )
    } else {
        throw CheckFailure(description: "native hosted scroll apply source should remain inspectable")
    }
    try check(
        actionButtonSource.contains("struct PaperCodexToolbarButton")
            && actionButtonSource.contains("struct PaperCodexIconButton")
            && discoverSource.contains("PaperCodexToolbarButton")
            && (librarySource.contains("PaperCodexToolbarButton")
                || (libraryToolbarSource.contains("LibraryNativeToolbarView") && libraryToolbarSource.contains("NSButton")))
            && (chatSource.contains("PaperCodexToolbarButton")
                || readerSessionToolbarSource.contains("ReaderSessionToolbarView") && readerSessionToolbarSource.contains("NSButton"))
            && !discoverSource.contains("private struct ToolbarActionButton"),
        "common toolbar and icon actions should use shared controls, with reader-specific compact header actions only where layout requires them"
    )
    try check(
        actionButtonSource.contains("import AppKit")
            && actionButtonSource.contains("private struct NativePaperCodexToolbarButton: NSViewRepresentable")
            && actionButtonSource.contains("private final class NativePaperCodexToolbarButtonView: NSButton")
            && actionButtonSource.contains("private struct NativePaperCodexIconButton: NSViewRepresentable")
            && actionButtonSource.contains("private final class NativePaperCodexIconButtonView: NSButton")
            && actionButtonSource.components(separatedBy: "override func mouseDown(with event: NSEvent)").count - 1 >= 2
            && actionButtonSource.components(separatedBy: "setAccessibilityRole(.button)").count - 1 >= 2
            && actionButtonSource.components(separatedBy: "CATransaction.setAnimationDuration").count - 1 >= 2
            && !actionButtonSource.contains("struct PaperCodexToolbarButtonStyle")
            && !actionButtonSource.contains("struct PaperCodexIconButtonStyle")
            && !actionButtonSource.contains(".buttonStyle(PaperCodexToolbarButtonStyle(")
            && !actionButtonSource.contains(".buttonStyle(PaperCodexIconButtonStyle(")
            && !actionButtonSource.contains(".buttonStyle(.plain)"),
        "shared toolbar and icon actions should use native AppKit buttons with immediate pressed feedback"
    )
    if let detailsViewRange = librarySource.range(of: "private struct LibraryPaperInspectorDetailsView: NSViewRepresentable"),
       let sidebarHeaderRange = librarySource.range(of: "private func sidebarHeader(", range: detailsViewRange.upperBound..<librarySource.endIndex) {
        let libraryInspectorActionSource = String(librarySource[detailsViewRange.lowerBound..<sidebarHeaderRange.lowerBound])
        try check(
            libraryInspectorActionSource.contains("onCreateCategory")
                && libraryInspectorActionSource.contains("onCreateTag")
                && libraryInspectorActionSource.contains("onCreateNote")
                && libraryInspectorActionSource.contains("onSaveNote")
                && libraryInspectorActionSource.contains("onCancelNote")
                && libraryInspectorActionSource.contains("NativeInspectorDetailsTagButton")
                && libraryInspectorActionSource.contains("NativeInspectorDetailsNoteRowView")
                && libraryInspectorActionSource.contains("NSButton(checkboxWithTitle:")
                && libraryInspectorActionSource.contains("NSTextField()")
                && libraryInspectorActionSource.contains("NSTextView()")
                && !libraryInspectorActionSource.contains("\n                Button")
                && !libraryInspectorActionSource.contains("\n                    Button")
                && !libraryInspectorActionSource.contains(".buttonStyle("),
            "library inspector category, tag, and note actions should use native AppKit controls instead of SwiftUI buttons, grids, and text editors"
        )
    } else {
        throw CheckFailure(description: "library inspector action source should remain inspectable")
    }
    if let bulkActionBarRange = librarySource.range(of: "private struct BulkLibraryActionBar: View"),
       let bulkCopySheetRange = librarySource.range(of: "private struct LibraryBulkCopySheet: View", range: bulkActionBarRange.upperBound..<librarySource.endIndex) {
        let bulkActionBarSource = String(librarySource[bulkActionBarRange.lowerBound..<bulkCopySheetRange.lowerBound])
        try check(
            bulkActionBarSource.components(separatedBy: "PaperCodexToolbarButton(").count - 1 >= 6
                && bulkActionBarSource.contains("title: \"Read\"")
                && bulkActionBarSource.contains("title: \"Chat\"")
                && bulkActionBarSource.contains("title: \"Copy\"")
                && bulkActionBarSource.contains("title: \"Tag\"")
                && bulkActionBarSource.contains("title: \"Delete\"")
                && bulkActionBarSource.contains("title: \"Clear\"")
                && !bulkActionBarSource.contains("\n            Button")
                && !bulkActionBarSource.contains(".buttonStyle("),
            "library bulk action bar should use shared native toolbar buttons for every action"
        )
    } else {
        throw CheckFailure(description: "library bulk action bar source should remain inspectable")
    }
    if let watchedFoldersRange = librarySource.range(of: "private struct WatchedFoldersSheet: View"),
       let categoryListItemRange = librarySource.range(of: "private struct CategoryListItem", range: watchedFoldersRange.upperBound..<librarySource.endIndex) {
        let watchedFoldersSource = String(librarySource[watchedFoldersRange.lowerBound..<categoryListItemRange.lowerBound])
        try check(
            watchedFoldersSource.contains("PaperCodexPanelButton(title: \"Add Folder\"")
                && watchedFoldersSource.contains("PaperCodexPanelButton(\n                    title: model.isScanningWatchedFolders ? \"Scanning\" : \"Scan\"")
                && watchedFoldersSource.contains("PaperCodexPanelButton(title: \"Close\"")
                && watchedFoldersSource.contains("PaperCodexIconButton(title: \"Remove Folder\"")
                && !watchedFoldersSource.contains("\n                Button")
                && !watchedFoldersSource.contains("\n            Button")
                && !watchedFoldersSource.contains(".buttonStyle("),
            "library watched-folder sheet and rows should use native AppKit-backed buttons"
        )
    } else {
        throw CheckFailure(description: "library watched-folder sheet source should remain inspectable")
    }
    if let bulkCopyRange = librarySource.range(of: "private struct LibraryBulkCopySheet: View"),
       let sortOptionRange = librarySource.range(of: "enum LibrarySortOption", range: bulkCopyRange.upperBound..<librarySource.endIndex) {
        let libraryBulkSheetsSource = String(librarySource[bulkCopyRange.lowerBound..<sortOptionRange.lowerBound])
        try check(
            libraryBulkSheetsSource.contains("PaperCodexPanelButton(title: \"Cancel\", systemImage: \"xmark\")")
                && libraryBulkSheetsSource.contains("PaperCodexPanelButton(\n                    title: \"Copy\"")
                && libraryBulkSheetsSource.contains("PaperCodexPanelButton(\n                    title: \"Apply\"")
                && libraryBulkSheetsSource.contains("PaperCodexTagToggleButton(title: tag.name")
                && !libraryBulkSheetsSource.contains("\n                Button")
                && !libraryBulkSheetsSource.contains("\n                        Button")
                && !libraryBulkSheetsSource.contains(".buttonStyle("),
            "library bulk copy and tag sheets should use native AppKit-backed buttons"
        )
    } else {
        throw CheckFailure(description: "library bulk sheet source should remain inspectable")
    }
    if let arxivImportRange = librarySource.range(of: "private struct LibraryArxivImportSheet: View"),
       let flowLayoutRange = librarySource.range(of: "private struct FlowLayout", range: arxivImportRange.upperBound..<librarySource.endIndex) {
        let arxivImportSource = String(librarySource[arxivImportRange.lowerBound..<flowLayoutRange.lowerBound])
        try check(
            arxivImportSource.contains("PaperCodexPanelButton(title: \"Close\", systemImage: \"xmark\")")
                && arxivImportSource.contains("PaperCodexPanelButton(title: \"Cancel\", systemImage: \"xmark\")")
                && arxivImportSource.contains("PaperCodexPanelButton(\n                    title: \"Add\"")
                && !arxivImportSource.contains("\n                Button")
                && !arxivImportSource.contains(".buttonStyle("),
            "library arXiv import sheet should use native AppKit-backed action buttons"
        )
    } else {
        throw CheckFailure(description: "library arXiv import sheet source should remain inspectable")
    }
    if let tagSidebarRange = librarySource.range(of: "private struct LibraryTagSidebarList: NSViewRepresentable"),
       let categoryManagementRange = librarySource.range(of: "private struct CategoryManagementSheet: View", range: tagSidebarRange.upperBound..<librarySource.endIndex) {
        let tagSidebarSource = String(librarySource[tagSidebarRange.lowerBound..<categoryManagementRange.lowerBound])
        try check(
            tagSidebarSource.contains("NativeLibraryTagSidebarManageButton")
                && tagSidebarSource.contains("setAccessibilityLabel(\"Manage \\(title)\")")
                && tagSidebarSource.contains("setAccessibilityRole(.button)")
                && !tagSidebarSource.contains("PaperCodexIconButton")
                && !tagSidebarSource.contains("\n                    Button")
                && !tagSidebarSource.contains(".buttonStyle("),
            "library tag sidebar manage action should use a native AppKit icon button"
        )
    } else {
        throw CheckFailure(description: "library tag sidebar source should remain inspectable")
    }
    if let categoryManagementRange = librarySource.range(of: "private struct CategoryManagementSheet: View"),
       let categoryEditorRange = librarySource.range(of: "private struct CategoryEditorSheet: View", range: categoryManagementRange.upperBound..<librarySource.endIndex) {
        let managementSheetsSource = String(librarySource[categoryManagementRange.lowerBound..<categoryEditorRange.lowerBound])
        try check(
            managementSheetsSource.components(separatedBy: "PaperCodexPanelButton(").count - 1 >= 6
                && managementSheetsSource.contains("title: \"Delete\"")
                && managementSheetsSource.contains("title: \"Cancel\"")
                && managementSheetsSource.contains("title: \"Save\"")
                && librarySource.contains("private final class NativeInspectorDetailsNoteRowView: NSView")
                && librarySource.contains("private let deleteButton = NSButton()")
                && librarySource.contains("deleteButton.image = NSImage(systemSymbolName: \"trash\"")
                && !managementSheetsSource.contains("\n                Button")
                && !managementSheetsSource.contains("\n            Button")
                && !managementSheetsSource.contains(".buttonStyle("),
            "library category/tag management sheets and note rows should use native AppKit-backed actions"
        )
    } else {
        throw CheckFailure(description: "library management sheet source should remain inspectable")
    }
    if let categoryEditorRange = librarySource.range(of: "private struct CategoryEditorSheet: View") {
        let editorSheetsSource = String(librarySource[categoryEditorRange.lowerBound..<librarySource.endIndex])
        try check(
            editorSheetsSource.contains("PaperCodexPanelButton(title: \"Cancel\", systemImage: \"xmark\")")
                && editorSheetsSource.contains("PaperCodexPanelButton(\n                    title: \"Create\"")
                && !editorSheetsSource.contains("\n                Button")
                && !editorSheetsSource.contains(".buttonStyle("),
            "library category and tag creation sheets should use native AppKit-backed action buttons"
        )
    } else {
        throw CheckFailure(description: "library creation sheet source should remain inspectable")
    }
    try check(
        readerSessionToolbarSource.contains("ReaderSessionToolbarView")
            && readerSessionToolbarSource.contains("NSSegmentedControl")
            && readerSessionToolbarSource.contains("NSPopUpButton")
            && readerSessionToolbarSource.contains("NSButton")
            && readerSessionToolbarSource.contains("newSessionButton")
            && readerSessionToolbarSource.contains("renameButton")
            && !chatSource.contains("private struct ReaderChatHeaderActionButton: View"),
        "reader chat header actions should be native AppKit controls with direct pressed feedback before session operations"
    )
    try check(
        agentTerminalSource.contains("AgentTerminalNativePanelView(")
            && agentTerminalNativeSource.contains("NSViewRepresentable")
            && agentTerminalNativeSource.contains("AgentTerminalContainerView")
            && agentTerminalNativeSource.contains("NSPopUpButton")
            && agentTerminalNativeSource.contains("NSStepper")
            && agentTerminalNativeSource.contains("NSTextView")
            && agentTerminalNativeSource.contains("NSScrollView")
            && agentTerminalNativeSource.contains("runtimePopup")
            && agentTerminalNativeSource.contains("outputTextView")
            && agentTerminalNativeSource.contains("inputTextView")
            && agentTerminalNativeSource.contains("sendButton")
            && agentTerminalNativeSource.contains("startStopButton")
            && !agentTerminalSource.contains("private var terminalToolbar: some View")
            && !agentTerminalSource.contains("struct AgentTerminalOutputView: View")
            && !agentTerminalSource.contains("TextField(\"Terminal input\""),
        "reader terminal panel should use native AppKit controls for runtime selection, terminal output, sizing, and input"
    )
    try check(
        chatSource.contains("ChatComposerNativePanelView(")
            && chatComposerNativeSource.contains("NSViewRepresentable")
            && chatComposerNativeSource.contains("ChatComposerContainerView")
            && chatComposerNativeSource.contains("NSPopUpButton")
            && chatComposerNativeSource.contains("NSTextView")
            && chatComposerNativeSource.contains("NSScrollView")
            && chatComposerNativeSource.contains("NSButton")
            && chatComposerNativeSource.contains("quickPromptPopup")
            && chatComposerNativeSource.contains("runtimePopup")
            && chatComposerNativeSource.contains("modelPopup")
            && chatComposerNativeSource.contains("reasoningPopup")
            && chatComposerNativeSource.contains("refreshButton")
            && chatComposerNativeSource.contains("inputTextView")
            && chatComposerNativeSource.contains("sendButton")
            && chatComposerNativeSource.contains("hasMarkedText()")
            && !chatSource.contains("private struct QuickPromptLine: View")
            && !chatSource.contains("private struct AgentStatusLine: View")
            && !chatSource.contains("private struct ComposerTextView: NSViewRepresentable")
            && !chatSource.contains("private struct ChatSendButtonStyle: ButtonStyle"),
        "reader chat composer should use a native AppKit prompt/runtime/input/send panel"
    )
    try check(
        chatSource.contains("SessionNotesNativePanelView(")
            && sessionNotesNativeSource.contains("NSViewRepresentable")
            && sessionNotesNativeSource.contains("SessionNotesContainerView")
            && sessionNotesNativeSource.contains("NSSplitView")
            && sessionNotesNativeSource.contains("NSTableView")
            && sessionNotesNativeSource.contains("NSTextField")
            && sessionNotesNativeSource.contains("NSTextView")
            && sessionNotesNativeSource.contains("NSScrollView")
            && sessionNotesNativeSource.contains("newNoteButton")
            && sessionNotesNativeSource.contains("deleteNoteButton")
            && sessionNotesNativeSource.contains("saveNoteButton")
            && sessionNotesNativeSource.contains("cancelEditButton")
            && !chatSource.contains("private struct SessionNotesWorkspace: View")
            && !chatSource.contains("private struct SessionNoteListRow: View")
            && !chatSource.contains("SessionNoteListRowButtonStyle"),
        "reader notes panel should use a native AppKit split workspace with selectable notes and editor actions"
    )
    try check(
        chatSource.contains("NativeChatTranscriptView(")
            && chatSource.contains("private struct NativeChatTranscriptView: NSViewRepresentable")
            && chatSource.contains("private final class NativeChatTranscriptWebView: NSView")
            && chatSource.contains("private struct NativeChatTranscriptRenderableMessage: Equatable")
            && chatSource.contains("private enum NativeChatTranscriptHTMLBuilder")
            && chatSource.contains("WKWebView")
            && chatSource.contains("ChatMarkdownRenderer.renderFragment")
            && chatSource.contains("UserSourceAttachmentParser.parse")
            && chatSource.contains("CitationParser.parse")
            && chatSource.contains("CodexFailureNotice.parse")
            && chatSource.contains("generatedImageURLs(in:")
            && chatSource.contains("papercodex-chat://retry")
            && chatSource.contains("papercodex-chat://new-session")
            && chatSource.contains("papercodex-chat://image")
            && chatSource.contains("onCitation")
            && chatSource.contains("onRetryFailure")
            && chatSource.contains("onNewSession")
            && chatSource.contains("onGeneratedImagePreview")
            && !chatSource.contains("ForEach(model.messages)")
            && !chatSource.contains("MessageBubble(")
            && !chatSource.contains("private struct MessageBubble: View")
            && !chatSource.contains("private struct MarkdownMessageView: View")
            && !chatSource.contains("private struct MarkdownWebView: NSViewRepresentable"),
        "reader chat transcript should use one native AppKit/WebKit surface instead of SwiftUI ForEach message bubbles and per-message WKWebViews"
    )
    try check(
        chatSource.contains("message-user-bubble")
            && chatSource.contains("message-agent")
            && chatSource.contains("role-badge")
            && chatSource.contains("message.createdAt")
            && chatSource.contains("formattedTimestamp")
            && chatSource.contains("fontFamily.cssFontFamily")
            && chatSource.contains("ChatMarkdownRenderStyle(")
            && !chatSource.contains("private struct UserMessageBubbleBackground: View")
            && !chatSource.contains("private struct ChatRoleBadge: View"),
        "reader chat transcript should keep compact user bubbles, full-width agent replies, role badges, timestamps, and appearance settings inside the native surface"
    )
    try check(
        chatSource.contains("renderActiveRun")
            && chatSource.contains("visibleCodexRunEvents")
            && chatSource.contains("tokenUsageSummary")
            && chatSource.contains("case .usage")
            && chatSource.contains("event.previewDetail")
            && chatSource.contains("<details")
            && !chatSource.contains("private struct CodexRunBubble: View")
            && !chatSource.contains("private struct CodexRunEventRow: View")
            && !chatSource.contains("private struct NativeChatRunEventDisclosureRow: NSViewRepresentable"),
        "active chat runs should render inside the same native transcript surface instead of a separate SwiftUI run bubble"
    )
    try check(
        chatSource.contains("renderGeneratedImageGallery")
            && chatSource.contains("generated-image-gallery")
            && chatSource.contains("GeneratedImagePreviewOverlay")
            && chatSource.contains("ZoomableImageScrollView")
            && chatSource.contains("Preview generated image")
            && chatSource.contains("Quoted source")
            && chatSource.contains("Open quoted source"),
        "reader chat generated images and quoted sources should stay interactive inside the native transcript and use the in-app preview overlay"
    )
    try check(
        chatAppearanceSource.contains("enum ChatFontFamily: String, CaseIterable, Identifiable")
            && chatAppearanceSource.contains("static let defaultMessageFontSize: Double = 16")
            && chatAppearanceSource.contains("static let defaultComposerFontSize: Double = 15")
            && appModelSource.contains("@Published var chatMessageFontSize")
            && appModelSource.contains("@Published var chatComposerFontSize")
            && appModelSource.contains("@Published var chatFontFamily")
            && appModelSource.contains("func setChatAppearance(")
            && settingsViewSource.contains("private var chatAppearanceSettings: some View")
            && settingsViewSource.contains("SettingsChatFontSegmentedControl(")
            && (settingsViewSource.contains("SettingsFontSizeStepper(") || settingsViewSource.contains("Stepper("))
            && settingsViewSource.contains("Message text")
            && settingsViewSource.contains("Composer text")
            && chatSource.contains("ChatMarkdownRenderStyle(")
            && chatSource.contains("messageFontSize: model.chatMessageFontSize")
            && chatSource.contains("fontSize: model.chatComposerFontSize")
            && chatMarkdownRendererSource.contains("public struct ChatMarkdownRenderStyle"),
        "Reader Chat should expose persistent font family and size settings with larger defaults for messages and composer"
    )
    if let chatAppearanceRange = settingsViewSource.range(of: "private var chatAppearanceSettings: some View"),
       let chatAppearanceEndRange = settingsViewSource.range(of: "private var localRankingSettings: some View", range: chatAppearanceRange.upperBound..<settingsViewSource.endIndex) {
        let chatAppearanceSettingsSource = String(settingsViewSource[chatAppearanceRange.lowerBound..<chatAppearanceEndRange.lowerBound])
        try check(
            chatAppearanceSettingsSource.components(separatedBy: "SettingsFontSizeStepper(").count - 1 == 2
                && settingsViewSource.contains("private struct SettingsFontSizeStepper: View")
                && settingsViewSource.contains("private struct NativeSettingsFontSizeStepper: NSViewRepresentable")
                && settingsViewSource.contains("private final class NativeSettingsFontSizeStepperView: NSView")
                && settingsViewSource.contains("NSStepper()")
                && settingsViewSource.contains("stepper.setAccessibilityLabel(title)")
                && settingsViewSource.contains("stepper.setAccessibilityValue(\"\\(Int(clampedValue)) pt\")")
                && settingsViewSource.contains("labelField.stringValue = \"\\(title): \\(Int(clampedValue)) pt\"")
                && settingsViewSource.contains("stepper.minValue = range.lowerBound")
                && settingsViewSource.contains("stepper.maxValue = range.upperBound")
                && settingsViewSource.contains("stepper.increment = step")
                && settingsViewSource.contains("override func acceptsFirstMouse(for event: NSEvent?) -> Bool")
                && settingsViewSource.contains("CATransaction.setAnimationDuration")
                && !chatAppearanceSettingsSource.contains("\n            Stepper("),
            "Settings chat appearance font-size controls should use native AppKit NSStepper rows"
        )
    } else {
        throw CheckFailure(description: "settings chat appearance section source should remain inspectable")
    }
    if let arxivFeedRange = settingsViewSource.range(of: "private var arxivFeedSettings: some View"),
       let arxivFeedEndRange = settingsViewSource.range(of: "private var globalLanguageSettings: some View", range: arxivFeedRange.upperBound..<settingsViewSource.endIndex) {
        let arxivFeedSettingsSource = String(settingsViewSource[arxivFeedRange.lowerBound..<arxivFeedEndRange.lowerBound])
        try check(
            !arxivFeedSettingsSource.contains("\n            TextField(")
                && settingsViewSource.contains("SettingsTextField(")
                && !arxivFeedSettingsSource.contains(".textFieldStyle(.roundedBorder)"),
            "arXiv settings controls should use native SettingsTextField instead of SwiftUI text fields"
        )
    } else {
        throw CheckFailure(description: "settings arXiv section source should remain inspectable")
    }
    if let localRankingRange = settingsViewSource.range(of: "private var localRankingSettings: some View"),
       let localRankingEndRange = settingsViewSource.range(of: "private var codexEnrichmentSettings: some View", range: localRankingRange.upperBound..<settingsViewSource.endIndex) {
        let localRankingSettingsSource = String(settingsViewSource[localRankingRange.lowerBound..<localRankingEndRange.lowerBound])
        try check(
            !localRankingSettingsSource.contains("\n            TextField(")
                && !localRankingSettingsSource.contains(".textFieldStyle(.roundedBorder)"),
            "Local ranking settings controls should use native SettingsTextField instead of SwiftUI text fields"
        )
    } else {
        throw CheckFailure(description: "settings local ranking section source should remain inspectable")
    }
    if let codexEnrichmentRange = settingsViewSource.range(of: "private var codexEnrichmentSettings: some View"),
       let codexEnrichmentEndRange = settingsViewSource.range(of: "private var discoverCodexProcessingSettings: some View", range: codexEnrichmentRange.upperBound..<settingsViewSource.endIndex) {
        let codexEnrichmentSettingsSource = String(settingsViewSource[codexEnrichmentRange.lowerBound..<codexEnrichmentEndRange.lowerBound])
        try check(
            codexEnrichmentSettingsSource.components(separatedBy: "SettingsCheckboxToggle(").count - 1 == 2
                && settingsViewSource.contains("private struct SettingsCheckboxToggle: View")
                && settingsViewSource.contains("private struct NativeSettingsCheckboxToggle: NSViewRepresentable")
                && settingsViewSource.contains("private final class NativeSettingsCheckboxToggleButtonView: NSButton")
                && settingsViewSource.contains("setButtonType(.switch)")
                && settingsViewSource.contains("setAccessibilityRole(.checkBox)")
                && settingsViewSource.contains("override func mouseDown(with event: NSEvent)")
                && settingsViewSource.contains("override func accessibilityValue() -> Any?")
                && settingsViewSource.contains("override func accessibilityPerformPress() -> Bool")
                && settingsViewSource.contains("CATransaction.setAnimationDuration")
                && !codexEnrichmentSettingsSource.contains("\n            Toggle(")
                && !codexEnrichmentSettingsSource.contains(".toggleStyle(.checkbox)"),
            "Settings Codex enrichment toggles should use native AppKit checkbox controls"
        )
    } else {
        throw CheckFailure(description: "settings Codex enrichment section source should remain inspectable")
    }
    if let discoverProcessingRange = settingsViewSource.range(of: "private var discoverCodexProcessingSettings: some View"),
       let discoverProcessingEndRange = settingsViewSource.range(of: "private var codexSystemPromptSettings: some View", range: discoverProcessingRange.upperBound..<settingsViewSource.endIndex) {
        let discoverProcessingSource = String(settingsViewSource[discoverProcessingRange.lowerBound..<discoverProcessingEndRange.lowerBound])
        try check(
            discoverProcessingSource.components(separatedBy: "SettingsModelPopup(").count - 1 == 1
                && discoverProcessingSource.contains("SettingsReasoningEffortPopup(")
                && discoverProcessingSource.contains("SettingsIntegerStepper(")
                && !discoverProcessingSource.contains("\n            TextField(")
                && !discoverProcessingSource.contains(".textFieldStyle(.roundedBorder)")
                && settingsViewSource.contains("private struct SettingsModelPopup: View")
                && settingsViewSource.contains("private struct SettingsReasoningEffortPopup: View")
                && settingsViewSource.contains("private struct NativeSettingsPopupButton: NSViewRepresentable")
                && settingsViewSource.contains("private final class NativeSettingsPopupButtonView: NSPopUpButton")
                && settingsViewSource.contains("super.init(frame: frameRect, pullsDown: false)")
                && settingsViewSource.contains("selectItem(withRepresentedObject:")
                && settingsViewSource.contains("selectedItem?.representedObject as? String")
                && settingsViewSource.contains("private struct SettingsIntegerStepper: View")
                && settingsViewSource.contains("private struct NativeSettingsIntegerStepper: NSViewRepresentable")
                && settingsViewSource.contains("private final class NativeSettingsIntegerStepperView: NSView")
                && settingsViewSource.contains("stepper.setAccessibilityLabel(title)")
                && !discoverProcessingSource.contains("\n            Picker(")
                && !discoverProcessingSource.contains("\n            Stepper(")
                && !discoverProcessingSource.contains(".pickerStyle(.menu)"),
            "Settings Explore Processing controls should use native AppKit popup and stepper controls"
        )
    } else {
        throw CheckFailure(description: "settings Explore Processing section source should remain inspectable")
    }
    if let codexMCPRange = settingsViewSource.range(of: "private var codexMCPSettings: some View"),
       let codexMCPEndRange = settingsViewSource.range(of: "private var agentRuntimeSettings: some View", range: codexMCPRange.upperBound..<settingsViewSource.endIndex),
       let agentRuntimeRange = settingsViewSource.range(of: "private var agentRuntimeSettings: some View"),
       let agentRuntimeEndRange = settingsViewSource.range(of: "private var embeddingProviderSettings: some View", range: agentRuntimeRange.upperBound..<settingsViewSource.endIndex),
       let embeddingRange = settingsViewSource.range(of: "private var embeddingProviderSettings: some View"),
       let embeddingEndRange = settingsViewSource.range(of: "private var quickPromptSettings: some View", range: embeddingRange.upperBound..<settingsViewSource.endIndex) {
        let codexMCPSource = String(settingsViewSource[codexMCPRange.lowerBound..<codexMCPEndRange.lowerBound])
        let agentRuntimeSource = String(settingsViewSource[agentRuntimeRange.lowerBound..<agentRuntimeEndRange.lowerBound])
        let embeddingSource = String(settingsViewSource[embeddingRange.lowerBound..<embeddingEndRange.lowerBound])
        try check(
            codexMCPSource.contains("SettingsCheckboxToggle(")
                && agentRuntimeSource.components(separatedBy: "SettingsRuntimePopup(").count - 1 == 2
                && agentRuntimeSource.contains("SettingsMCPModePopup(")
                && agentRuntimeSource.contains("SettingsCheckboxToggle(")
                && embeddingSource.contains("SettingsCheckboxToggle(")
                && settingsViewSource.contains("private struct SettingsRuntimePopup: View")
                && settingsViewSource.contains("private struct SettingsMCPModePopup: View")
                && settingsViewSource.contains("NativeSettingsPopupButton(")
                && !codexMCPSource.contains("\n            Toggle(")
                && !codexMCPSource.contains(".toggleStyle(.checkbox)")
                && !agentRuntimeSource.contains("\n                Toggle(")
                && !agentRuntimeSource.contains("\n                Picker(")
                && !agentRuntimeSource.contains(".toggleStyle(.checkbox)")
                && !agentRuntimeSource.contains(".pickerStyle(.menu)")
                && !embeddingSource.contains("\n            Toggle(")
                && !embeddingSource.contains(".toggleStyle(.checkbox)")
                && !embeddingSource.contains("\n            TextField(")
                && !embeddingSource.contains("\n            SecureField(")
                && !embeddingSource.contains(".textFieldStyle(.roundedBorder)"),
            "Settings service and runtime controls should use native AppKit checkbox and popup controls"
        )
    } else {
        throw CheckFailure(description: "settings service and runtime sections source should remain inspectable")
    }
    if let quickPromptRange = settingsViewSource.range(of: "private var quickPromptSettings: some View"),
       let quickPromptEndRange = settingsViewSource.range(of: "private var storageRules: some View", range: quickPromptRange.upperBound..<settingsViewSource.endIndex) {
        let quickPromptSettingsSource = String(settingsViewSource[quickPromptRange.lowerBound..<quickPromptEndRange.lowerBound])
        try check(
            !quickPromptSettingsSource.contains("\n            TextField(")
                && !quickPromptSettingsSource.contains("\n                TextEditor(")
                && !quickPromptSettingsSource.contains(".textFieldStyle(.roundedBorder)"),
            "Quick prompt main settings controls should use native SettingsTextField"
        )
    } else {
        throw CheckFailure(description: "quick prompt section source should remain inspectable")
    }
    if let systemPromptSheetRange = settingsViewSource.range(of: "private var codexSystemPromptEditSheet: some View"),
       let systemPromptSheetEndRange = settingsViewSource.range(of: "private func quickPromptEditSheet", range: systemPromptSheetRange.upperBound..<settingsViewSource.endIndex),
       let quickPromptSheetRange = settingsViewSource.range(of: "private func quickPromptEditSheet"),
       let quickPromptSheetEndRange = settingsViewSource.range(of: "private func pathRow", range: quickPromptSheetRange.upperBound..<settingsViewSource.endIndex) {
        let systemPromptSheetSource = String(settingsViewSource[systemPromptSheetRange.lowerBound..<systemPromptSheetEndRange.lowerBound])
        let quickPromptSheetSource = String(settingsViewSource[quickPromptSheetRange.lowerBound..<quickPromptSheetEndRange.lowerBound])
        try check(
            settingsViewSource.contains("private struct SettingsMultilineTextView: View")
                && settingsViewSource.contains("private struct NativeSettingsMultilineTextView: NSViewRepresentable")
                && settingsViewSource.contains("private final class NativeSettingsMultilineTextViewContainer: NSView")
                && settingsViewSource.contains("private final class SettingsTextViewCoordinator: NSObject, NSTextViewDelegate")
                && settingsViewSource.contains("NSScrollView()")
                && settingsViewSource.contains("NSTextView")
                && settingsViewSource.contains("textDidChange")
                && settingsViewSource.contains("hasMarkedText()")
                && systemPromptSheetSource.contains("SettingsMultilineTextView(")
                && quickPromptSheetSource.contains("SettingsTextField(")
                && quickPromptSheetSource.contains("SettingsMultilineTextView(")
                && quickPromptSheetSource.contains("editingPromptTitle = prompt.title")
                && quickPromptSheetSource.contains("editingPromptContent = prompt.content")
                && !systemPromptSheetSource.contains("TextEditor(")
                && !quickPromptSheetSource.contains("\n            TextField(")
                && !quickPromptSheetSource.contains("TextEditor("),
            "Settings prompt editors should use native AppKit text fields and text views"
        )
    } else {
        throw CheckFailure(description: "settings prompt editor sheet sources should remain inspectable")
    }
    if let storageRulesRange = settingsViewSource.range(of: "private var storageRules: some View"),
       let storageRulesEndRange = settingsViewSource.range(of: "private var cacheControls: some View", range: storageRulesRange.upperBound..<settingsViewSource.endIndex) {
        let storageRulesSource = String(settingsViewSource[storageRulesRange.lowerBound..<storageRulesEndRange.lowerBound])
        try check(
            storageRulesSource.contains("SettingsSaveOrganizationRadioGroup(")
                && settingsViewSource.contains("private struct SettingsSaveOrganizationRadioGroup: View")
                && settingsViewSource.contains("private struct NativeSettingsRadioGroup: NSViewRepresentable")
                && settingsViewSource.contains("private final class NativeSettingsRadioGroupView: NSView")
                && settingsViewSource.contains("button.setButtonType(.radio)")
                && settingsViewSource.contains("button.setAccessibilityRole(.radioButton)")
                && settingsViewSource.contains("selectedItemID")
                && !storageRulesSource.contains("\n            Picker(")
                && !storageRulesSource.contains(".pickerStyle(.radioGroup)"),
            "Settings saved-paper organization should use a native AppKit radio group"
        )
    } else {
        throw CheckFailure(description: "settings storage rules section source should remain inspectable")
    }
    try check(
        chatSource.contains("Bundle.main.resourceURL")
            && chatSource.contains("loadHTMLString(html, baseURL: htmlBaseURL)"),
        "chat markdown web view should resolve bundled math assets relative to the app resources directory"
    )
    try check(
        nativeDiscoverCollectionSource.contains("private let saveButton = NSButton()")
            && nativeDiscoverCollectionSource.contains("private let openButton = NSButton()")
            && nativeDiscoverCollectionSource.contains("configureActionButton(saveButton, title: \"Add\"")
            && nativeDiscoverCollectionSource.contains("configureActionButton(openButton, title: \"Open\"")
            && nativeDiscoverCollectionSource.contains("saveButton.isEnabled = !model.isBusy")
            && nativeDiscoverCollectionSource.contains("openButton.isEnabled = !model.isBusy")
            && nativeDiscoverCollectionSource.contains("@objc private func performSave()")
            && nativeDiscoverCollectionSource.contains("@objc private func performOpen()")
            && !discoverSource.contains("private struct SaveActionButtonStyle")
            && !discoverSource.contains("private struct StableOpenButtonStyle")
            && !discoverSource.contains(".buttonStyle(SaveActionButtonStyle(")
            && !discoverSource.contains(".buttonStyle(StableOpenButtonStyle("),
        "Discover and Search native card save/open actions should be real AppKit buttons disabled before busy work starts"
    )
    try check(
        nativeDiscoverCollectionSource.contains("private func configureLinks(_ links: [NativeDiscoverCardLink])")
            && nativeDiscoverCollectionSource.contains("button.identifier = NSUserInterfaceItemIdentifier(link.urlString)")
            && nativeDiscoverCollectionSource.contains("@objc private func openResourceLink(_ sender: NSButton)")
            && nativeDiscoverCollectionSource.contains("NSWorkspace.shared.open(url)")
            && !discoverSource.contains("private struct ResourceLinkButton: View")
            && !discoverSource.contains("PaperCodexResourceLinkButton("),
        "Discover and Search resource links should be native AppKit buttons in the reusable collection card"
    )
    try check(
        nativeDiscoverCollectionSource.contains("private let mediaButton = NSButton()")
            && nativeDiscoverCollectionSource.contains("mediaButton.action = #selector(performMediaAction)")
            && nativeDiscoverCollectionSource.contains("@objc private func performMediaAction()")
            && nativeDiscoverCollectionSource.contains("mediaButton.toolTip = model.imageURL == nil ? \"Open cached PDF\" : \"Open image preview\"")
            && !discoverSource.contains("PaperCodexMediaPreviewButton(")
            && !discoverSource.contains("private struct DiscoverMediaButtonStyle: ButtonStyle"),
        "Discover and Search media preview actions should be native AppKit buttons before opening PDFs or previews"
    )
    try check(
        discoverSource.contains("private struct NativeSidebarFilterButton: NSViewRepresentable")
            && discoverSource.contains("NativeSidebarFilterButtonView")
            && discoverSource.contains("final class NativeSidebarFilterButtonView: NSButton")
            && discoverSource.contains("override func mouseDown(with event: NSEvent)")
            && discoverSource.contains("setAccessibilityRole(.button)")
            && discoverSource.contains("setAccessibilityValue(selected ?")
            && discoverSource.contains("CATransaction.setAnimationDuration")
            && !discoverSource.contains("private struct SidebarFilterButtonStyle")
            && !discoverSource.contains(".buttonStyle(SidebarFilterButtonStyle("),
        "Discover and Search sidebar filter buttons should use native AppKit buttons with immediate pressed feedback before list recalculation"
    )
    if let filterChipRange = discoverSource.range(of: "private struct DiscoverFilterChip: View"),
       let filterChipEndRange = discoverSource.range(of: "private struct ArxivSearchYearField", range: filterChipRange.upperBound..<discoverSource.endIndex) {
        let filterChipSource = String(discoverSource[filterChipRange.lowerBound..<filterChipEndRange.lowerBound])
        try check(
            filterChipSource.contains("NativeDiscoverFilterChipButton(")
                && filterChipSource.contains("private struct NativeDiscoverFilterChipButton: NSViewRepresentable")
                && filterChipSource.contains("private final class NativeDiscoverFilterChipButtonView: NSButton")
                && filterChipSource.contains("override func mouseDown(with event: NSEvent)")
                && filterChipSource.contains("isPressed = true")
                && filterChipSource.contains("isHovering = true")
                && filterChipSource.contains("CATransaction.setAnimationDuration")
                && filterChipSource.contains("contentTintColor = foreground")
                && !filterChipSource.contains("private struct DiscoverFilterChipStyle: ButtonStyle")
                && !filterChipSource.contains(".buttonStyle(.plain)"),
            "Discover and Search active filter chips should use native AppKit buttons with immediate pressed feedback before list recalculation"
        )
    } else {
        throw CheckFailure(description: "Discover active filter chip source should remain inspectable")
    }
    if let arxivSearchRange = discoverSource.range(of: "struct ArxivSearchView: View"),
       let arxivSearchEndRange = discoverSource.range(of: "private struct SidebarFilterButton: View", range: arxivSearchRange.upperBound..<discoverSource.endIndex) {
        let arxivSearchSource = String(discoverSource[arxivSearchRange.lowerBound..<arxivSearchEndRange.lowerBound])
        if let searchFeedRange = arxivSearchSource.range(of: "private var feed: some View"),
           let searchToolbarRange = arxivSearchSource.range(of: "private var toolbar: some View", range: searchFeedRange.upperBound..<arxivSearchSource.endIndex) {
            let arxivSearchFeedSource = String(arxivSearchSource[searchFeedRange.lowerBound..<searchToolbarRange.lowerBound])
            try check(
                arxivSearchFeedSource.contains("NativeDiscoverCollectionView(")
                    && arxivSearchFeedSource.contains("let cardModels = nativeSearchCardModels")
                    && arxivSearchFeedSource.contains("updateNativeSearchCardModels(for: papers, inputID:")
                    && !arxivSearchFeedSource.contains("LazyVStack")
                    && !arxivSearchFeedSource.contains("ArxivPaperCard("),
                "Search results should use the same reusable native AppKit collection surface as Discover instead of SwiftUI card rows"
            )
        } else {
            throw CheckFailure(description: "Search feed source should remain inspectable")
        }
        try check(
            arxivSearchSource.contains("PaperCodexIconButton(\n                    title: sortOrderTitle")
                && arxivSearchSource.contains("private var sortOrderTitle: String")
                && arxivSearchSource.contains("private var sortOrderSystemImage: String")
                && arxivSearchSource.contains("toggleRequiredCategory(category)")
                && !arxivSearchSource.contains("Toggle(category, isOn: requiredCategoryBinding")
                && !arxivSearchSource.contains(".buttonStyle(.bordered)"),
            "Search sort direction should use shared immediate icon press feedback instead of the generic bordered button"
        )
    } else {
        throw CheckFailure(description: "Search top control source should remain inspectable")
    }
    if let quickRangeRange = discoverSource.range(of: "private struct QuickRangeButtons: View"),
       let quickRangeEndRange = discoverSource.range(of: "private struct DiscoverProcessActionSheet", range: quickRangeRange.upperBound..<discoverSource.endIndex) {
        let quickRangeSource = String(discoverSource[quickRangeRange.lowerBound..<quickRangeEndRange.lowerBound])
        try check(
            actionButtonSource.contains("struct PaperCodexQuickRangeButton: View")
                && actionButtonSource.contains("private struct NativePaperCodexQuickRangeButton: NSViewRepresentable")
                && actionButtonSource.contains("private final class NativePaperCodexQuickRangeButtonView: NSButton")
                && actionButtonSource.components(separatedBy: "override func mouseDown(with event: NSEvent)").count - 1 >= 8
                && actionButtonSource.components(separatedBy: "setAccessibilityRole(.button)").count - 1 >= 8
                && actionButtonSource.components(separatedBy: "CATransaction.setAnimationDuration").count - 1 >= 8
                && quickRangeSource.contains("PaperCodexQuickRangeButton(title: range.title)")
                && !quickRangeSource.contains("@State private var isHovering = false")
                && !quickRangeSource.contains("private struct DiscoverQuickRangeButtonStyle: ButtonStyle")
                && !quickRangeSource.contains(".buttonStyle(DiscoverQuickRangeButtonStyle(")
                && !quickRangeSource.contains(".buttonStyle(.bordered)"),
            "Explore date quick range buttons should use shared native AppKit buttons before range recalculation"
        )
    } else {
        throw CheckFailure(description: "Discover quick range button source should remain inspectable")
    }
    if let discoverMenuRange = discoverSource.range(of: "private struct QuickRangeButtons: View"),
       let discoverMenuEndRange = discoverSource.range(of: "private struct ArxivCacheProgressStrip", range: discoverMenuRange.upperBound..<discoverSource.endIndex) {
        let discoverMenuSource = String(discoverSource[discoverMenuRange.lowerBound..<discoverMenuEndRange.lowerBound])
        try check(
            discoverMenuSource.contains("DiscoverQuickRangePopup(")
                && discoverMenuSource.contains("NativeDiscoverMenuButton(")
                && discoverMenuSource.contains("NativeDiscoverMenuButtonRepresentable(")
                && discoverMenuSource.contains("private struct NativeDiscoverMenuButtonRepresentable: NSViewRepresentable")
                && discoverMenuSource.contains("private final class NativeDiscoverMenuButtonView: NSPopUpButton")
                && discoverMenuSource.contains("super.init(frame: .zero, pullsDown:")
                && discoverMenuSource.contains("menu?.addItem(.separator())")
                && discoverMenuSource.contains("selectedItem?.representedObject as? String")
                && discoverMenuSource.contains("override func mouseDown(with event: NSEvent)")
                && !discoverMenuSource.contains("\n            Menu {")
                && !discoverMenuSource.contains("\n        Menu {")
                && !discoverMenuSource.contains(".menuStyle(.borderlessButton)")
                && !discoverMenuSource.contains("private struct DateMenuButton: View"),
            "Discover top toolbar menus should use native AppKit NSPopUpButton menus instead of SwiftUI Menu"
        )
    } else {
        throw CheckFailure(description: "Discover top toolbar menu source should remain inspectable")
    }
    if let processSheetRange = discoverSource.range(of: "private struct DiscoverProcessActionSheet: View"),
       let processSheetEndRange = discoverSource.range(of: "private struct DiscoverProcessActionRow", range: processSheetRange.upperBound..<discoverSource.endIndex) {
        let processSheetSource = String(discoverSource[processSheetRange.lowerBound..<processSheetEndRange.lowerBound])
        guard let actionRowEndRange = discoverSource.range(of: "private struct DiscoverCategoryMenu", range: processSheetEndRange.upperBound..<discoverSource.endIndex) else {
            throw CheckFailure(description: "Discover process action row source should remain inspectable")
        }
        let processActionRowSource = String(discoverSource[processSheetEndRange.lowerBound..<actionRowEndRange.lowerBound])
        try check(
            actionButtonSource.contains("struct PaperCodexPanelButton: View")
                && actionButtonSource.contains("private struct NativePaperCodexPanelButton: NSViewRepresentable")
                && actionButtonSource.contains("private final class NativePaperCodexPanelButtonView: NSButton")
                && processSheetSource.contains("PaperCodexPanelButton(title: \"Cancel\", systemImage: \"xmark\")")
                && processSheetSource.contains("PaperCodexPanelButton(\n                    title: \"Process Results\"")
                && processSheetSource.contains("kind: .primary")
                && processSheetSource.contains("disabled: !canProcessResults")
                && !processSheetSource.contains("@State private var isProcessButtonHovering = false")
                && !processSheetSource.contains("@State private var isCancelButtonHovering = false")
                && !processSheetSource.contains("private struct DiscoverProcessFooterButtonStyle: ButtonStyle")
                && !processSheetSource.contains(".buttonStyle(DiscoverProcessFooterButtonStyle(")
                && !processSheetSource.contains(".buttonStyle(.borderedProminent)"),
            "Discover and Search process confirmation should use native AppKit panel buttons before starting long processing"
        )
        try check(
            processSheetSource.contains("DiscoverProcessModelPopup(")
                && processSheetSource.contains("DiscoverProcessTextField(")
                && processSheetSource.contains("DiscoverProcessThinkingPopup(")
                && processActionRowSource.contains("DiscoverProcessActionToggleRow(")
                && discoverSource.contains("private struct DiscoverProcessModelPopup: NSViewRepresentable")
                && discoverSource.contains("private struct DiscoverProcessTextField: NSViewRepresentable")
                && discoverSource.contains("private struct DiscoverProcessThinkingPopup: NSViewRepresentable")
                && discoverSource.contains("private final class NativeDiscoverProcessPopupButton: NSPopUpButton")
                && discoverSource.contains("private struct DiscoverProcessActionToggleRow: NSViewRepresentable")
                && discoverSource.contains("private final class NativeDiscoverProcessActionToggleButton: NSButton")
                && discoverSource.contains("setButtonType(.switch)")
                && discoverSource.contains("setAccessibilityRole(.checkBox)")
                && !processSheetSource.contains("Picker(\"Model\"")
                && !processSheetSource.contains("TextField(\"Custom model override\"")
                && !processSheetSource.contains("Picker(\"Thinking\"")
                && !processActionRowSource.contains("Toggle(isOn:")
                && !processActionRowSource.contains(".toggleStyle(.checkbox)"),
            "Discover and Search process confirmation fields should use native AppKit popups, text fields, and checkbox rows"
        )
    } else {
        throw CheckFailure(description: "Discover process action sheet source should remain inspectable")
    }
    try check(
        saveToLibrarySource.contains("SaveToLibraryDestinationHeader")
            && saveToLibrarySource.contains("SaveToLibraryFolderPathChip")
            && saveToLibrarySource.contains("Choose destination")
            && saveToLibrarySource.contains("New root folder")
            && saveToLibrarySource.contains("destinationChipMaxHeight")
            && saveToLibrarySource.contains("PaperCodexNativeScrollView {")
            && saveToLibrarySource.contains(".frame(maxHeight: SaveToLibraryLayout.destinationChipMaxHeight)"),
        "save-to-library should bound selected path chips so the folder tree remains usable with many suggested destinations"
    )
    if let actionRowRange = saveToLibrarySource.range(of: "private var actionRow: some View"),
       let actionRowEndRange = saveToLibrarySource.range(of: "private var visibleFolderItems", range: actionRowRange.upperBound..<saveToLibrarySource.endIndex) {
        let actionRowSource = String(saveToLibrarySource[actionRowRange.lowerBound..<actionRowEndRange.lowerBound])
        try check(
            actionRowSource.components(separatedBy: "PaperCodexPanelButton(").count - 1 == 2
                && actionRowSource.contains("title: \"Cancel\"")
                && actionRowSource.contains("title: \"Save\"")
                && actionButtonSource.contains("struct PaperCodexPanelButton: View")
                && actionButtonSource.contains("private final class NativePaperCodexPanelButtonView: NSButton")
                && !saveToLibrarySource.contains("@State private var isSaveButtonHovering = false")
                && !saveToLibrarySource.contains("private struct SaveToLibraryFooterButtonStyle: ButtonStyle")
                && !actionRowSource.contains(".buttonStyle(SaveToLibraryFooterButtonStyle(")
                && !actionRowSource.contains(".buttonStyle(.borderedProminent)"),
            "save-to-library footer actions should use the shared native panel button before saving destinations"
        )
    } else {
        throw CheckFailure(description: "save-to-library action row source should remain inspectable")
    }
    if let pathChipRange = saveToLibrarySource.range(of: "private struct SaveToLibraryFolderPathChip: View"),
       let pathChipEndRange = saveToLibrarySource.range(of: "private struct SaveToLibraryFlowLayout", range: pathChipRange.upperBound..<saveToLibrarySource.endIndex),
       let folderTreeRange = saveToLibrarySource.range(of: "private struct NativeSaveToLibraryFolderPicker: NSViewRepresentable"),
       let folderTreeEndRange = saveToLibrarySource.range(of: "private struct SaveToLibraryDestinationHeader", range: folderTreeRange.upperBound..<saveToLibrarySource.endIndex) {
        let pathChipSource = String(saveToLibrarySource[pathChipRange.lowerBound..<pathChipEndRange.lowerBound])
        let folderTreeSource = String(saveToLibrarySource[folderTreeRange.lowerBound..<folderTreeEndRange.lowerBound])
        try check(
            actionButtonSource.contains("struct PaperCodexPathChipButton: View")
                && actionButtonSource.contains("private struct NativePaperCodexPathChipButton: NSViewRepresentable")
                && actionButtonSource.contains("private final class NativePaperCodexPathChipButtonView: NSButton")
                && actionButtonSource.components(separatedBy: "override func mouseDown(with event: NSEvent)").count - 1 >= 3
                && actionButtonSource.components(separatedBy: "setAccessibilityRole(.button)").count - 1 >= 3
                && actionButtonSource.components(separatedBy: "CATransaction.setAnimationDuration").count - 1 >= 3
                && pathChipSource.contains("PaperCodexPathChipButton(")
                && !saveToLibrarySource.contains("private struct SaveToLibraryFolderPathChipStyle: ButtonStyle")
                && saveToLibrarySource.contains("PaperCodexPanelButton(title: \"New root folder\"")
                && saveToLibrarySource.contains("title: \"Add Folder\"")
                && saveToLibrarySource.contains("systemImage: \"checkmark\"")
                && saveToLibrarySource.contains("title: \"Cancel\"")
                && saveToLibrarySource.contains("systemImage: \"xmark\"")
                && !saveToLibrarySource.contains(".buttonStyle(.borderless)")
                && saveToLibrarySource.contains("private final class NativeSaveToLibraryFolderPickerTableView: NSTableView")
                && saveToLibrarySource.contains("private final class NativeSaveToLibraryFolderRowCellView: NSTableCellView")
                && saveToLibrarySource.contains("private final class NativeSaveToLibraryFolderDraftCellView: NSTableCellView")
                && saveToLibrarySource.contains("private final class NativeSaveToLibraryFolderSelectionButtonView: NSButton")
                && saveToLibrarySource.contains("private final class NativeSaveToLibraryFolderIconButtonView: NSButton")
                && saveToLibrarySource.components(separatedBy: "override func mouseDown(with event: NSEvent)").count - 1 >= 2
                && saveToLibrarySource.components(separatedBy: "setAccessibilityRole(.button)").count - 1 >= 2
                && saveToLibrarySource.components(separatedBy: "CATransaction.setAnimationDuration").count - 1 >= 2
                && folderTreeSource.contains("NativeSaveToLibraryFolderSelectionButtonView()")
                && folderTreeSource.contains("NativeSaveToLibraryFolderIconButtonView()")
                && !saveToLibrarySource.contains("private struct SaveToLibraryFolderRowButtonStyle: ButtonStyle")
                && !saveToLibrarySource.contains("private struct SaveToLibraryFolderIconButtonStyle: ButtonStyle")
                && !folderTreeSource.contains(".buttonStyle(SaveToLibraryFolderRowButtonStyle(")
                && !folderTreeSource.contains(".buttonStyle(SaveToLibraryFolderIconButtonStyle(")
                && !pathChipSource.contains(".buttonStyle(")
                && !folderTreeSource.contains(".buttonStyle(.plain)"),
            "save-to-library selected path chips, folder rows, and small creation actions should use native AppKit buttons before saving destinations"
        )
    } else {
        throw CheckFailure(description: "save-to-library folder tree button source should remain inspectable")
    }
    try check(
        windowTabBarSource.contains("PaperCodexWindowTabBar")
            && windowTabBarSource.contains("NativeWindowChromeTabBarView(")
            && windowTabBarSource.contains("NativeWindowChromeTabBarContainerView")
            && windowTabBarSource.contains("NativeChromeHomeTabButton")
            && windowTabBarSource.contains("NativeReaderChromeTabView")
            && windowTabBarSource.contains("NativeSaveToLibraryChromeButton")
            && windowTabBarSource.contains("NSScrollView")
            && windowTabBarSource.contains("NSStackView")
            && windowTabBarSource.contains("tabBarTrafficLightLeadingInset")
            && windowTabBarSource.contains("Home: 探索")
            && windowTabBarSource.contains("Home: 搜索")
            && windowTabBarSource.contains("PaperCodexChromeTabStyle.divider")
            && !windowTabBarSource.contains("ScrollViewReader")
            && !windowTabBarSource.contains("ScrollView(.horizontal)")
            && !windowTabBarSource.contains("PaperCodexReaderChromeTabItem")
            && appSource.contains("VStack(spacing: 0)")
            && appSource.contains("PaperCodexWindowTabBar {\n                isShowingSaveToLibrarySheet = true\n            }")
            && appSource.contains("persistentRoutedContent\n                .frame(maxWidth: .infinity, maxHeight: .infinity)")
            && appSource.contains(".padding(.top, PaperCodexWindowChrome.tabBarHeight + 10)")
            && !appSource.contains(".overlay(alignment: .top) {\n            PaperCodexWindowTabBar")
            && !readerViewSource.contains(".ignoresSafeArea(.container, edges: .top)")
            && !readerViewSource.contains(".padding(.top, PaperCodexWindowChrome.tabBarHeight)")
            && !readerViewSource.contains("ReaderChromeTabBar")
            && !readerViewSource.contains("ReaderChromeTabItem")
            && !readerViewSource.contains("ReaderPaperTabStrip")
            && !readerViewSource.contains("ReaderPaperTabChip"),
        "reader top tabs should be a fixed window chrome row in the root layout, not an overlay compensated by Reader padding"
    )
    try check(
        windowTabBarSource.contains("@Environment(\\.accessibilityReduceMotion)")
            && windowTabBarSource.contains("reduceMotion:")
            && windowTabBarSource.contains("isHovering")
            && windowTabBarSource.contains("isPressed")
            && windowTabBarSource.contains("NativeSaveToLibraryChromeButton")
            && windowTabBarSource.contains("onShowSaveToLibrary()"),
        "window chrome tabs and the save-to-library control should use shared interaction affordances while respecting Reduce Motion"
    )
    try check(
        windowTabBarSource.contains("override func mouseDown(with event: NSEvent)")
            && windowTabBarSource.contains("override func mouseUp(with event: NSEvent)")
            && windowTabBarSource.contains("override func hitTest(_ point: NSPoint)")
            && windowTabBarSource.contains("setPressed(")
            && windowTabBarSource.contains("closeButton.target = self")
            && windowTabBarSource.contains("NativeReaderChromeSelectButton")
            && windowTabBarSource.contains("selectTab(tab)")
            && windowTabBarSource.contains("closeTab(tab)")
            && windowTabBarSource.contains("setAccessibilityElement(true)")
            && windowTabBarSource.contains("setAccessibilityRole(.button)")
            && windowTabBarSource.contains("selectButton.setAccessibilityLabel(tab.title)")
            && windowTabBarSource.contains("setAccessibilityLabel(\"Close tab\")")
            && !windowTabBarSource.contains(".buttonStyle(.plain)"),
        "window chrome tabs should provide immediate native pressed feedback for route and reader-tab switching"
    )
    try check(
        windowTabBarSource.contains("lastRenderedTabIDs")
            && windowTabBarSource.contains("rebuildReaderTabs")
            && windowTabBarSource.contains("scrollActiveTabToVisible")
            && windowTabBarSource.contains("reduceMotion"),
        "reader tabs should update through the native tab strip and keep the active tab centered"
    )
    try check(
        designSystemSource.contains("static let press = Animation.easeOut(duration: 0.05)")
            && !designSystemSource.contains("static let route")
            && sidebarRowSource.contains("import AppKit")
            && sidebarRowSource.contains("NativeSidebarRowButton(")
            && sidebarRowSource.contains("private struct NativeSidebarRowButton: NSViewRepresentable")
            && sidebarRowSource.contains("private final class NativeSidebarRowButtonView: NSButton")
            && sidebarRowSource.contains("override func mouseDown(with event: NSEvent)")
            && sidebarRowSource.contains("setAccessibilityRole(.button)")
            && sidebarRowSource.contains("CATransaction.setAnimationDuration")
            && !sidebarRowSource.contains("SidebarRowButtonStyle")
            && !sidebarRowSource.contains(".buttonStyle(SidebarRowButtonStyle(")
            && !sidebarRowSource.contains(".buttonStyle(.plain)"),
        "secondary sidebar rows should use native AppKit buttons with immediate pressed feedback"
    )
    if let recentRowRange = librarySource.range(of: "private struct NativeRecentConversationsContent: NSViewRepresentable"),
       let recentRowEndRange = librarySource.range(of: "private struct NativeRecentConversationDetailPanel: NSViewRepresentable", range: recentRowRange.upperBound..<librarySource.endIndex) {
        let recentRowSource = String(librarySource[recentRowRange.lowerBound..<recentRowEndRange.lowerBound])
        try check(
            recentRowSource.contains("private final class NativeRecentConversationRowView: NSView")
                && recentRowSource.contains("private final class NativeRecentConversationOpenButton: NSButton")
                && recentRowSource.contains("private final class NativeRecentConversationSelectionButtonView: NSButton")
                && recentRowSource.contains("override func mouseDown(with event: NSEvent)")
                && recentRowSource.contains("override func acceptsFirstMouse(for event: NSEvent?) -> Bool")
                && recentRowSource.contains("setAccessibilityRole(.button)")
                && recentRowSource.contains("CATransaction.setAnimationDuration")
                && recentRowSource.contains("stackView.alignment = .width")
                && recentRowSource.contains("selectionButton.apply(")
                && recentRowSource.contains("openButton.apply(")
                && !recentRowSource.contains("@State private var isHovering = false")
                && !recentRowSource.contains("private struct NativeRecentConversationSelectionButton: NSViewRepresentable")
                && !recentRowSource.contains("PaperCodexIconButton(title: \"Open Session\"")
                && !recentRowSource.contains("private struct RecentConversationRowButtonStyle: ButtonStyle")
                && !recentRowSource.contains(".buttonStyle(RecentConversationRowButtonStyle(")
                && !recentRowSource.contains(".buttonStyle(.plain)")
                && !recentRowSource.contains(".buttonStyle(.borderless)"),
            "recent conversation rows should render and respond through native AppKit row buttons before selecting or opening sessions"
        )
    } else {
        throw CheckFailure(description: "recent conversation row source should remain inspectable")
    }
    if let recentDetailRange = librarySource.range(of: "private final class NativeRecentConversationDetailView: NSView"),
       let recentDetailEndRange = librarySource.range(of: "private struct BulkLibraryActionBar", range: recentDetailRange.upperBound..<librarySource.endIndex) {
        let recentDetailSource = String(librarySource[recentDetailRange.lowerBound..<recentDetailEndRange.lowerBound])
        try check(
            recentDetailSource.contains("private final class NativeRecentConversationPrimaryActionButton: NSButton")
                && recentDetailSource.contains("NativeRecentConversationPrimaryActionButton()")
                && recentDetailSource.contains("NativeRecentConversationPaperRowView")
                && recentDetailSource.contains("makePapersSection")
                && recentDetailSource.contains("bezelStyle = .rounded")
                && recentDetailSource.contains("setAccessibilityRole(.button)")
                && recentDetailSource.contains("stackView.alignment = .width")
                && !recentDetailSource.contains("@State private var isOpenButtonHovering = false")
                && !recentDetailSource.contains("PaperCodexPanelButton(")
                && !recentDetailSource.contains("private struct RecentConversationDetailOpenButtonStyle: ButtonStyle")
                && !recentDetailSource.contains(".buttonStyle(RecentConversationDetailOpenButtonStyle(")
                && !recentDetailSource.contains(".buttonStyle(.borderedProminent)"),
            "recent conversation detail should render its papers and Open Session action inside the native AppKit detail view"
        )
    } else {
        throw CheckFailure(description: "recent conversation detail source should remain inspectable")
    }
    if let inspectorRange = librarySource.range(of: "private var inspector: some View"),
       let inspectorEndRange = librarySource.range(of: "private struct LibraryPaperInspectorDetailsView", range: inspectorRange.upperBound..<librarySource.endIndex) {
        let inspectorSource = String(librarySource[inspectorRange.lowerBound..<inspectorEndRange.lowerBound])
        try check(
            inspectorSource.contains("LibraryPaperInspectorSummaryView(")
                && !inspectorSource.contains("PaperCodexPanelButton(\n                            title: \"Read\"")
                && !librarySource.contains("@State private var isInspectorReadButtonHovering = false")
                && !librarySource.contains("private struct LibraryInspectorReadButtonStyle: ButtonStyle")
                && !inspectorSource.contains(".buttonStyle(LibraryInspectorReadButtonStyle(")
                && !inspectorSource.contains(".buttonStyle(.borderedProminent)"),
            "library inspector Read action should be owned by the native AppKit summary view before opening the reader"
        )
    } else {
        throw CheckFailure(description: "library inspector source should remain inspectable")
    }
    try check(
        settingsViewSource.contains("private struct SettingsActionButton: View")
            && actionButtonSource.contains("struct PaperCodexPanelButton: View")
            && actionButtonSource.contains("private struct NativePaperCodexPanelButton: NSViewRepresentable")
            && actionButtonSource.contains("private final class NativePaperCodexPanelButtonView: NSButton")
            && settingsViewSource.contains("private enum SettingsActionButtonKind")
            && actionButtonSource.contains("override func mouseDown(with event: NSEvent)")
            && actionButtonSource.contains("setAccessibilityRole(.button)")
            && actionButtonSource.contains("CATransaction.setAnimationDuration")
            && settingsViewSource.components(separatedBy: "SettingsActionButton(").count - 1 >= 15
            && !settingsViewSource.contains("private struct NativeSettingsActionButton: NSViewRepresentable")
            && !settingsViewSource.contains("private final class NativeSettingsActionButtonView: NSButton")
            && !settingsViewSource.contains("private struct SettingsActionButtonStyle: ButtonStyle")
            && !settingsViewSource.contains(".buttonStyle(SettingsActionButtonStyle(")
            && settingsViewSource.contains("PaperCodexIconButton(title: \"Move Up\"")
            && settingsViewSource.contains("PaperCodexIconButton(title: \"Reveal in Finder\"")
            && !settingsViewSource.contains(".buttonStyle(.borderedProminent)")
            && !settingsViewSource.contains(".buttonStyle(.bordered)")
            && !settingsViewSource.contains(".buttonStyle(.borderless)")
            && !settingsViewSource.contains(".buttonStyle(.plain)"),
        "Settings action buttons should use native AppKit buttons with immediate pressed feedback instead of system default delayed button chrome"
    )
    try check(
        settingsViewSource.contains("private struct SettingsCategoryToggleRow: View")
            && settingsViewSource.contains("NativeSettingsCategoryToggleButton(")
            && settingsViewSource.contains("private struct NativeSettingsCategoryToggleButton: NSViewRepresentable")
            && settingsViewSource.contains("private final class NativeSettingsCategoryToggleButtonView: NSButton")
            && settingsViewSource.contains("override func mouseDown(with event: NSEvent)")
            && settingsViewSource.contains("override func accessibilityValue() -> Any?")
            && settingsViewSource.contains("setAccessibilityRole(.checkBox)")
            && settingsViewSource.contains("setButtonType(.switch)")
            && !settingsViewSource.contains("setButtonType(.toggle)")
            && settingsViewSource.contains("CATransaction.setAnimationDuration")
            && !settingsViewSource.contains("private struct SettingsSelectableRowButtonStyle: ButtonStyle")
            && !settingsViewSource.contains(".buttonStyle(SettingsSelectableRowButtonStyle(")
            && !settingsViewSource.contains("@State private var isHovering = false"),
        "Settings category rows should use native AppKit checkbox buttons with immediate selection feedback"
    )
    try check(
        settingsViewSource.contains("SettingsLanguageSegmentedControl(")
            && settingsViewSource.contains("SettingsChatFontSegmentedControl(")
            && settingsViewSource.contains("private struct NativeSettingsSegmentedControl: NSViewRepresentable")
            && settingsViewSource.contains("private final class NativeSettingsSegmentedControlView: NSSegmentedControl")
            && settingsViewSource.contains("setSegmentCount")
            && settingsViewSource.contains("setLabel(")
            && settingsViewSource.contains("segmentStyle = .rounded")
            && settingsViewSource.contains("trackingMode = .selectOne")
            && settingsViewSource.contains("setAccessibilityLabel")
            && settingsViewSource.contains("override func mouseDown(with event: NSEvent)")
            && settingsViewSource.contains("override func accessibilityValue() -> Any?")
            && settingsViewSource.contains("CATransaction.setAnimationDuration")
            && !settingsViewSource.contains("Picker(\"App language\"")
            && !settingsViewSource.contains("Picker(\"Chat font\"")
            && !settingsViewSource.contains(".pickerStyle(.segmented)"),
        "Settings first-screen segmented controls should use native AppKit NSSegmentedControl pickers"
    )
    try check(
        homeChromeSource.contains("static let sidebarTopPadding: CGFloat = 28")
            && librarySource.contains("static let splitPaneTopInset: CGFloat = 0")
            && librarySource.contains(".padding(.top, 14)")
            && librarySource.contains(".padding(.bottom, 24)"),
        "home library chrome should keep the Paper Codex and library titles close to the tab row without returning to the old oversized top gap"
    )
    try check(
        readerViewSource.contains("ReaderNativeToolbarView(")
            && !readerViewSource.contains("ReaderPDFToolbar(")
            && !readerViewSource.contains("Picker(\"Paper\"")
            && readerToolbarSource.contains("NSPopUpButton")
            && readerToolbarSource.contains("paperPopup")
            && readerToolbarSource.contains("onAddPaper")
            && readerToolbarSource.contains("onRemoveActivePaper"),
        "reader paper switching should live in a native PDF toolbar as a compact dropdown with add/remove actions"
    )
    try check(
        chatSource.contains("ReaderSessionToolbarView(")
            && readerSessionToolbarSource.contains("panelSegmentedControl")
            && readerSessionToolbarSource.contains("sessionPopup")
            && readerSessionToolbarSource.contains("newSessionButton")
            && readerSessionToolbarSource.contains("renameButton")
            && !chatSource.contains("Picker(\"Session Panel\"")
            && !chatSource.contains("ReaderChatHeaderActionButton"),
        "reader chat header should use a compact native single-row control layout with smaller session actions"
    )
    try check(
        librarySource.contains("LibraryPaperTableView(")
            && libraryPaperTableSource.contains("NSTableView")
            && libraryPaperTableSource.contains("NSScrollView")
            && !libraryPaperTableSource.contains("NSHostingView")
            && libraryPaperTableSource.contains("LibraryPaperThumbnailStripView")
            && libraryPaperTableSource.contains("thumbnailLimit")
            && libraryPaperTableSource.contains("thumbnailMaxPixelSize"),
        "library paper scrolling should use a native table scroll surface with a bounded native thumbnail strip"
    )
    try check(
        localThumbnailSource.contains("LocalThumbnailDecodeGate")
            && localThumbnailSource.contains("appearanceDelayNanoseconds")
            && localThumbnailSource.contains("loadedURL")
            && localThumbnailSource.contains("TaskPriority.utility"),
        "local thumbnail decoding should be delayed, concurrency-limited, and clear reused cells so scrolling stays responsive"
    )
    try check(
        discoverSource.contains("NativeDiscoverCollectionView(")
            && discoverSource.contains("requestNativeDiscoverScrollRestore")
            && discoverSource.contains("isRestoringDiscoverScrollPosition")
            && discoverSource.contains("DiscoverScrollPolicy")
            && nativeDiscoverCollectionSource.contains("scrollToPaper")
            && nativeDiscoverCollectionSource.contains("onVisiblePaperChange")
            && !discoverSource.contains(".scrollPosition(id: $discoverScrollAnchorID")
            && !discoverSource.contains("ScrollViewReader"),
        "discover scrolling should restore through the native collection view instead of SwiftUI scrollPosition or hosted scroll callbacks"
    )
    try check(
        settingsViewSource.contains("Similarity categories")
            && settingsViewSource.contains("draftSimilarityCategoryIDs"),
        "settings should expose category-based similarity defaults"
    )
    try check(
        appModelSource.contains("similarityCategorySources")
            && appModelSource.contains("interestVectorGroups")
            && appModelSource.contains("similarityCategoryIDs"),
        "embedding ranking should score category groups separately"
    )
    try check(
        appModelSource.contains("assignPapers(_ paperIDs: [String], toTags tagIDs: [String])"),
        "AppModel should provide a batch paper-to-tags assignment path"
    )
    try check(
        appModelSource.contains("deletePapers(_ paperIDs: [String])"),
        "AppModel should provide a batch library delete path"
    )
    try check(
        appModelSource.contains("togglePaperStar("),
        "AppModel should provide a library paper star toggle path"
    )
    try check(
        appModelSource.contains("pendingArxivLibraryImportIDs"),
        "AppModel should track active arXiv library imports for placeholder status"
    )
    try check(
        appModelSource.contains("completeQueuedArxivLibraryImports"),
        "AppModel should finish queued arXiv imports in the background after the sheet closes"
    )
    try check(
        appModelSource.contains("makeArxivImportPlaceholderPaper"),
        "AppModel should create saved placeholder papers for immediate library display"
    )
    try check(
        librarySource.contains("selectedPaperIDs"),
        "library should keep explicit multi-selection state"
    )
    try check(
        librarySource.contains("BulkLibraryActionBar"),
        "library should show a contextual bulk action bar for selected papers"
    )
    try check(
        librarySource.contains("LibraryBulkCopySheet"),
        "library should provide a bulk copy sheet"
    )
    try check(
        librarySource.contains("LibraryBulkTagSheet"),
        "library should provide a bulk tag sheet"
    )
    try check(
        librarySource.contains("confirmDeleteSelectedPapers()")
            && librarySource.contains("PaperCodexNativeConfirmation.present("),
        "library should confirm destructive bulk deletes with the shared native confirmation dialog"
    )
    try check(
        appModelSource.contains("codexSystemPromptDefaultsKey"),
        "AppModel should persist the configurable Codex system prompt"
    )
    try check(
        appModelSource.contains("codexSystemPrompt: codexSystemPrompt")
            && coordinatorSource.contains("systemPromptTemplate: request.codexSystemPrompt"),
        "AppModel should pass the configured Codex system prompt into prompt building"
    )
    try check(
        settingsViewSource.contains("codexSystemPromptSettings"),
        "settings should include a dedicated Codex system prompt section"
    )
    try check(
        appModelSource.contains("inAppCodexMCPEnabledDefaultsKey")
            && appModelSource.contains("@Published var inAppCodexMCPEnabled")
            && appModelSource.contains("mcpServers: inAppCodexMCPServers()")
            && appModelSource.contains("private func inAppCodexMCPServers() -> [CodexMCPServerConfig]"),
        "AppModel should inject the Paper Codex MCP endpoint into in-app Codex sessions behind a persisted setting"
    )
    try check(
        settingsViewSource.contains("codexMCPSettings")
            && settingsViewSource.contains("model.setInAppCodexMCPEnabled"),
        "settings should expose the in-app Paper Codex MCP session switch"
    )
    try check(
        settingsViewSource.contains("isEditingCodexSystemPrompt")
            && settingsViewSource.contains("codexSystemPromptEditSheet")
            && settingsViewSource.contains("text: $draftCodexSystemPrompt")
            && settingsViewSource.contains("SettingsMultilineTextView(")
            && settingsViewSource.contains("SettingsActionButton(title: \"Edit Prompt\", systemImage: \"pencil\", kind: .primary)"),
        "settings should edit the Codex system prompt in an on-demand sheet instead of loading the editor on route entry"
    )
    try check(
        settingsViewSource.contains("model.resetCodexSystemPrompt()"),
        "settings should let users restore the default Codex system prompt"
    )
    try check(
        appModelSource.contains("globalLanguageModeDefaultsKey"),
        "AppModel should persist the global language mode"
    )
    try check(
        appModelSource.contains("languageMode: globalLanguageMode"),
        "AppModel should pass the global language mode into prompt building"
    )
    try check(
        settingsViewSource.contains("globalLanguageSettings"),
        "settings should include a dedicated global language section"
    )
    try check(
        settingsViewSource.contains("SettingsLanguageSegmentedControl("),
        "settings should expose an app-wide native language picker"
    )
    try check(
        settingsViewSource.contains("Controls the whole app interface"),
        "settings should describe language as an app-wide setting, not only answer language"
    )
    try check(
        discoverSource.contains("NativeDiscoverCardModelBuilder")
            && discoverSource.contains("model.globalLanguageMode.discoverLanguageCode"),
        "Discover cards should render with the configured global language"
    )
    try check(
        appModelSource.contains("func libraryArxivPaperIDs(includePlaceholders:")
            && discoverSource.contains("let libraryArxivPaperIDs = model.libraryArxivPaperIDs()")
            && discoverSource.contains("inLibrary: libraryArxivPaperIDs.contains(paper.id)")
            && !discoverSource.contains("inLibrary: model.libraryPaper(for: paper) != nil"),
        "Discover/Search card model building should use one library arXiv ID set instead of scanning the library for every result"
    )
    try check(
        discoverSource.contains("final class NativeDiscoverCardModelCache")
            && discoverSource.contains("@StateObject private var cardModelCache = NativeDiscoverCardModelCache()")
            && discoverSource.contains("cardModelCache.models(scope: \"discover\", for: papers, model: model)")
            && discoverSource.contains("cardModelCache.models(scope: \"search\", for: papers, model: model)")
            && discoverSource.contains("@State private var nativeDiscoverCardModels: [NativeDiscoverCardModel] = []")
            && discoverSource.contains("@State private var nativeSearchCardModels: [NativeDiscoverCardModel] = []")
            && discoverSource.contains("let cardModels = nativeDiscoverCardModels")
            && discoverSource.contains("let cardModels = nativeSearchCardModels")
            && discoverSource.contains("updateNativeDiscoverCardModels(for: visiblePapers, inputID:")
            && discoverSource.contains("updateNativeSearchCardModels(for: papers, inputID:")
            && discoverSource.contains("private static func signature(scope: String, papers: [ArxivFeedPaper], model: AppModel) -> Int"),
        "Discover/Search native card models should be cached across layout passes instead of rebuilt from SwiftUI GeometryReader every frame"
    )
    try check(
        discoverFeatureStoreSource.contains("struct DiscoverSidebarFacets")
            && discoverFeatureStoreSource.contains("@Published private(set) var discoverSidebarFacets")
            && discoverFeatureStoreSource.contains("refreshDiscoverSidebarFacets()")
            && appModelSource.contains("var discoverSidebarFacets: DiscoverSidebarFacets")
            && discoverSource.contains("model.discoverSidebarFacets.sortedTags")
            && !discoverSource.contains("private var tags: [String] {\n        let counts = tagCounts")
            && !discoverSource.contains("folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)")
            && !discoverFeatureStoreSource.contains("folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)"),
        "Discover sidebar categories and tags should be precomputed outside the SwiftUI body/layout hot path"
    )
    try check(
        discoverSource.contains("paper.displayTitle(language: model.globalLanguageMode.discoverLanguageCode)"),
        "Discover save sheet should use the configured global language"
    )
    try check(
        appModelSource.contains("func suggestedCategoryIDsForDiscoverSave() -> [String]")
            && appModelSource.contains("DiscoverSaveCategorySuggestion.categoryIDs("),
        "Discover save sheet should derive initial folders from the bounded core suggestion rule"
    )
    let rootViewSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexApp.swift"))
    let typographySource = (try? String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/Typography.swift"))) ?? ""
    let sidebarSplitSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/SidebarSplitLayout.swift"))
    let windowChromeSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/WindowChrome.swift"))
    let buildScriptSource = try String(contentsOf: root.appendingPathComponent("scripts/build-app-bundle.sh"))
    try check(
        rootViewSource.contains("paperCodexTypographyScale()"),
        "root view should apply the Paper Codex typography scale across the interface"
    )
    try check(
        typographySource.contains("scaledFixedSize") && typographySource.contains("fixedFontNoBoostThreshold") && typographySource.contains("size + 2"),
        "Paper Codex typography should raise ordinary fixed font sizes while leaving already-large fonts alone"
    )
    try check(
        !rootViewSource.contains(".windowStyle(")
            && appKitWindowControllerSource.contains(".fullSizeContentView")
            && appKitWindowControllerSource.contains("titlebarAppearsTransparent = true")
            && appKitWindowControllerSource.contains("titleVisibility = .hidden"),
        "AppKit main window should hide the standard title bar and embed app content into the full-size chrome"
    )
    try check(
        rootViewSource.contains("mountRoute(newRoute)")
            && !rootViewSource.contains("scheduleRouteMount(to: newRoute)")
            && !rootViewSource.contains("private let routeMountDelayNanoseconds")
            && !rootViewSource.contains(".offset(y: route == activeRoute")
            && !rootViewSource.contains(".scaleEffect(route == activeRoute"),
        "top-level route switching should mount the requested page synchronously and avoid geometry-changing page transitions"
    )
    try check(
        !rootViewSource.contains("WindowChromeConfigurator()")
            && appKitWindowControllerSource.contains("installTitlebarDoubleClickZoomMonitor"),
        "native window chrome behavior should live in the AppKit window controller, not a SwiftUI background probe"
    )
    try check(
        rootViewSource.contains("PaperCodexWindowTabBar")
            && rootViewSource.contains("isShowingSaveToLibrarySheet")
            && rootViewSource.contains(".ignoresSafeArea(.container, edges: .top)")
            && windowTabBarSource.contains("struct PaperCodexWindowTabBar")
            && windowTabBarSource.contains("NativeChromeHomeTabButton")
            && windowTabBarSource.contains("NativeWindowChromeTabBarView(")
            && windowTabBarSource.contains("Home (Library, 探索, 搜索, Settings, Recent Conversations)")
            && windowTabBarSource.contains("navigation.route != .reader")
            && windowTabBarSource.contains("model.returnFromReader()")
            && windowTabBarSource.contains("model.goToLibrary()")
            && windowChromeSource.contains("tabBarHeight")
            && windowChromeSource.contains("tabBarTrafficLightLeadingInset"),
        "root chrome should keep a fixed titlebar tab strip with a persistent Home tab for library, explore, search, settings, and recent conversations"
    )
    try check(
        appKitWindowControllerSource.contains(".fullSizeContentView")
            && appKitWindowControllerSource.contains("titlebarAppearsTransparent = true")
            && appKitWindowControllerSource.contains("titleVisibility = .hidden"),
        "window chrome should embed traffic-light controls into full-size app content"
    )
    try check(
        appKitWindowControllerSource.contains("window.isMovableByWindowBackground = false")
            && !appKitWindowControllerSource.contains("window.isMovableByWindowBackground = true")
            && !windowChromeSource.contains("window.isMovableByWindowBackground = true"),
        "window background dragging should stay disabled so PDFKit content drags cannot move the whole app"
    )
    try check(
        windowChromeSource.contains("paperCodexSidebarChromePadding")
            && librarySource.contains("paperCodexSidebarChromePadding()")
            && discoverSource.contains("paperCodexSidebarChromePadding()")
            && settingsViewSource.contains("paperCodexSidebarChromePadding()"),
        "single page sidebars should reserve top space for embedded traffic-light controls"
    )
    try check(
        sidebarSplitSource.contains("NSSplitView")
            && sidebarSplitSource.contains("NSHostingView(rootView:")
            && sidebarSplitSource.contains("NSSplitViewDelegate")
            && sidebarSplitSource.contains("splitViewDidResizeSubviews")
            && sidebarSplitSource.contains("setLibrarySidebarWidth")
            && !sidebarSplitSource.contains("GeometryReader")
            && !sidebarSplitSource.contains("HStack(alignment: .top")
            && !sidebarSplitSource.contains("WindowSafeSplitterHandle"),
        "primary sidebar splitter should be a native NSSplitView that hosts SwiftUI panes and persists sidebar width"
    )
    try check(
        appKitWindowControllerSource.contains("installTitlebarDoubleClickZoomMonitor")
            && appKitWindowControllerSource.contains("clickCount == 2")
            && appKitWindowControllerSource.contains("performZoom(nil)"),
        "hidden-titlebar windows should preserve double-click-to-zoom behavior in the top chrome area"
    )
    try check(
        rootViewSource.contains(".environment(\\.locale"),
        "root view should drive SwiftUI localization from the app language setting"
    )
    try check(
        sidebarRowSource.contains("NSLocalizedString(title, comment: \"\")"),
        "shared sidebar rows should localize dynamic navigation titles"
    )
    try check(
        buildScriptSource.contains("*.lproj"),
        "app bundle build should copy localization resources"
    )

    try check(
        chatSource.contains("chatComposerTextHeightDefaultsKey"),
        "chat composer height should be persisted locally"
    )
    try check(
        chatSource.contains("ComposerResizeHandle"),
        "chat composer should expose a visible resize handle"
    )
    try check(
        chatSource.contains("SessionPanelTab") && chatSource.contains("SessionNotesPanel"),
        "session conversation area should provide a tabbed paper-notes view"
    )
    try check(
        appKitMenuSource.contains("item(\"Show Reader Chat\", action: #selector(showReaderChat), key: \"1\", modifiers: [.command, .option])")
            && appKitMenuSource.contains("item(\"Show Reader Terminal\", action: #selector(showReaderTerminal), key: \"2\", modifiers: [.command, .option])")
            && appKitMenuSource.contains("item(\"Show Reader Notes\", action: #selector(showReaderNotes), key: \"3\", modifiers: [.command, .option])")
            && appKitMenuSource.contains("case #selector(focusChatComposer), #selector(showReaderChat), #selector(showReaderTerminal), #selector(showReaderNotes):")
            && appModelSource.contains("func showReaderSessionPanel(_ tab: SessionPanelTab)")
            && chatSource.contains(".id(model.selectedSessionPanelTab)")
            && chatSource.contains(".transition(.opacity.combined(with: .move(edge: .trailing)))")
            && chatSource.contains(".animation(PaperCodexMotion.selection, value: model.selectedSessionPanelTab)"),
        "Reader session panels should be keyboard-switchable and animate panel content changes"
    )
    try check(
        appKitMenuSource.contains("item(\"Select Previous Reader Tab\", action: #selector(selectPreviousReaderTab), key: \"[\", modifiers: [.command, .shift])")
            && appKitMenuSource.contains("item(\"Select Next Reader Tab\", action: #selector(selectNextReaderTab), key: \"]\", modifiers: [.command, .shift])")
            && appKitMenuSource.contains("case #selector(selectPreviousReaderTab), #selector(selectNextReaderTab):")
            && appModelSource.contains("func selectPreviousReaderTab()")
            && appModelSource.contains("func selectNextReaderTab()")
            && windowTabBarSource.contains("NSScrollView")
            && windowTabBarSource.contains("scrollActiveTabToVisible")
            && windowTabBarSource.contains("activeTabView.frame.midX")
            && windowTabBarSource.contains("reflectScrolledClipView"),
        "Reader tabs should support keyboard switching and keep the active tab visibly centered"
    )
    if let panelPickerRange = readerSessionToolbarSource.range(of: "panelSegmentedControl"),
       let sessionPickerRange = readerSessionToolbarSource.range(of: "sessionPopup") {
        try check(
            panelPickerRange.lowerBound < sessionPickerRange.lowerBound,
            "session panel tabs should sit at the far left of the same row as the session picker"
        )
    } else {
        throw CheckFailure(description: "native session bar should include both the panel tabs and session picker")
    }
    try check(
        chatSource.contains("ReaderSessionToolbarView(")
            && readerSessionToolbarSource.contains("firstSeparator")
            && readerSessionToolbarSource.contains("heightAnchor.constraint(equalToConstant: 18)")
            && !chatSource.contains("private var sessionBar: some View {\n        HStack(spacing: 8)"),
        "session picker should stay right within a compact native single-row session bar"
    )
    try check(
        chatSource.contains("model.loadPaperNotes(for: paper)")
            && chatSource.contains("model.saveNote(")
            && chatSource.contains("model.deleteNote("),
        "session paper-notes tab should load, edit, and delete persisted paper notes"
    )
    try check(
        chatSource.contains("SessionNotesNativePanelView(")
            && sessionNotesNativeSource.contains("NSSplitView")
            && sessionNotesNativeSource.contains("NSTableView")
            && sessionNotesNativeSource.contains("selectedNoteID")
            && sessionNotesNativeSource.contains("editingNoteID"),
        "session paper-notes panel should use a refined native split workspace with selectable notes and an editor"
    )
    try check(
        chatSource.contains("WindowSafeComposerResizeHandle") && chatSource.contains("mouseDownCanMoveWindow"),
        "chat composer resize handle should use an AppKit view that cannot initiate window dragging"
    )
    try check(
        !chatSource.contains("DragGesture(minimumDistance: 1, coordinateSpace: .global)"),
        "chat composer resize handle should not rely on a SwiftUI drag gesture inside the movable window background"
    )
    try check(
        chatSource.contains("private var composerTopDivider: some View")
            && chatSource.contains("WindowSafeComposerResizeHandle")
            && !chatSource.contains("private var composerTopDivider: some View {\n        Divider()\n    }"),
        "chat composer top divider should be the AppKit resize handle users actually drag"
    )
    try check(
        chatSource.contains("ChatComposerLayout.clampedTextHeight"),
        "chat composer height changes should be clamped through a shared layout helper"
    )
    try check(
        appModelSource.contains("codexDefaultModelID")
            && appModelSource.contains("CodexCLI.configuredDefaultModelID"),
        "app model should expose the configured default Codex model for chat controls"
    )
    try check(
        chatSource.contains("availableModelIDs")
            && chatComposerNativeSource.contains("availableModelIDs")
            && chatComposerNativeSource.contains("defaultModelLabel"),
        "chat model menu should use the same available Codex model list as settings and label the default model"
    )
    try check(
        !chatSource.contains("Button(\"gpt-5.4\")")
            && !chatSource.contains("Button(\"gpt-5.3-codex\")"),
        "chat model menu should not be limited to hard-coded model names"
    )

    let pdfKitViewURL = root.appendingPathComponent("Sources/PaperCodexApp/PDFKitView.swift")
    let pdfKitSource = try String(contentsOf: pdfKitViewURL)
    try check(
        pdfKitSource.contains("centerJumpTarget"),
        "PDF citation jumps should use an explicit centered viewport path"
    )
    try check(
        pdfKitSource.contains("centerPDFPagePointInViewport"),
        "PDF citation jumps should scroll the target point into the middle of the viewport"
    )
    if let pdfLinkPreviewRange = pdfKitSource.range(of: "private final class NativePDFLinkPreviewPopoverView: NSView"),
       let pdfLinkPreviewEndRange = pdfKitSource.range(of: "private final class NativeReferenceEntryPopoverView: NSView", range: pdfLinkPreviewRange.upperBound..<pdfKitSource.endIndex) {
        let pdfLinkPreviewSource = String(pdfKitSource[pdfLinkPreviewRange.lowerBound..<pdfLinkPreviewEndRange.lowerBound])
        try check(
            pdfLinkPreviewSource.contains("NativePDFPopoverActionButton")
                && pdfLinkPreviewSource.contains("actionButton.apply(title: preview.actionTitle")
                && pdfLinkPreviewSource.contains("systemImage: \"arrow.up.right\"")
                && pdfKitSource.contains("setAccessibilityRole(.button)")
                && !pdfLinkPreviewSource.contains("PaperCodexPanelButton(")
                && !pdfLinkPreviewSource.contains("\n                Button")
                && !pdfLinkPreviewSource.contains(".buttonStyle("),
            "PDF link preview cards should use a native AppKit action button for open actions"
        )
    } else {
        throw CheckFailure(description: "PDF link preview source should remain inspectable")
    }
    try check(
        pdfKitSource.contains("private final class NativePDFPopoverViewController: NSViewController")
            && pdfKitSource.contains("private final class NativeInTextCitationPreviewView: NSView")
            && pdfKitSource.contains("private final class NativePDFLinkPreviewPopoverView: NSView")
            && pdfKitSource.contains("private final class NativeReferenceEntryPopoverView: NSView")
            && pdfKitSource.contains("private final class NativePDFPopoverActionButton: NSButton")
            && pdfKitSource.contains("popover.contentViewController = NativePDFPopoverViewController")
            && pdfKitSource.contains("NativeInTextCitationPreviewView(preview: preview)")
            && pdfKitSource.contains("NativeReferenceEntryPopoverView(entry: entry)")
            && pdfKitSource.contains("NativePDFLinkPreviewPopoverView(preview: preview")
            && !pdfKitSource.contains("NSHostingController(rootView:")
            && !pdfKitSource.contains("private struct InTextCitationPreview: View")
            && !pdfKitSource.contains("private struct PDFLinkPreviewCard: View")
            && !pdfKitSource.contains("private struct ReferenceEntryCard: View"),
        "PDF citation, reference, and link popovers should render with native AppKit views instead of temporary SwiftUI hosting controllers"
    )
    try check(
        !pdfKitSource.contains("first.y + first.height"),
        "PDF citation jumps should not align the highlight top edge to the viewport top"
    )
    let interactionSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/InteractionFeedback.swift"))
    try check(
        interactionSource.contains("InteractionNoticeStack"),
        "global feedback should render non-blocking notices instead of forcing every message into an alert"
    )
    try check(
        interactionSource.contains("@State private var isExpanded")
            && interactionSource.contains("PaperCodexNativeScrollView")
            && interactionSource.contains(".textSelection(.enabled)"),
        "long error notices should expand into a native scrollable selectable detail view"
    )
    try check(
        appKitMenuSource.contains("makeMainMenu() -> NSMenu")
            && appKitMenuSource.contains("NSMenuItemValidation"),
        "the app should expose keyboard shortcuts through a native AppKit main menu"
    )
    try check(
        appKitMenuSource.contains("item(\"Focus Search\", action: #selector(focusSearch), key: \"f\")")
            && appModelSource.contains("@Published var searchFocusRequestID")
            && appModelSource.contains("func requestSearchFocus()")
            && librarySource.contains("searchFocusRequestID: model.searchFocusRequestID")
            && libraryToolbarSource.contains("applyFocusIfNeeded")
            && libraryToolbarSource.contains("makeFirstResponder(toolbarView.searchField)")
            && discoverSource.contains("searchFocusRequestID: model.searchFocusRequestID")
            && discoverSource.contains("isActiveForFocus: model.route == .discover")
            && discoverSource.contains("isActiveForFocus: model.route == .search")
            && discoverSource.contains("applyFocusIfNeeded(to searchField")
            && discoverSource.contains("searchField.window?.makeFirstResponder(searchField)"),
        "Cmd-F should focus the active page search field across Library, Explore, and Search"
    )
    try check(
        appKitMenuSource.contains("item(\"Read Selected Paper\", action: #selector(readSelectedPaper), key: Self.returnKey)")
            && appKitMenuSource.contains("item(\"Chat With Selected Paper\", action: #selector(chatWithSelectedPaper), key: Self.returnKey, modifiers: [.command, .shift])")
            && appKitMenuSource.contains("case #selector(readSelectedPaper), #selector(chatWithSelectedPaper):")
            && appModelSource.contains("func openSelectedLibraryPaperForReading()")
            && appModelSource.contains("func openSelectedLibraryPaperForChat()")
            && appModelSource.contains("selectedLibraryPaper?.isArxivImportPlaceholder == false"),
        "Library focused papers should have direct keyboard commands for reading and chat"
    )
    try check(
        librarySource.contains("@State private var paperTableFocusRequestID")
            && librarySource.contains("focusRequestID: paperTableFocusRequestID")
            && librarySource.contains("onMoveSelection: moveFocusedPaperSelection(by:)")
            && libraryPaperTableSource.contains("override func keyDown(with event:")
            && libraryPaperTableSource.contains("case 126:")
            && libraryPaperTableSource.contains("case 125:")
            && librarySource.contains("private func moveFocusedPaperSelection(by offset: Int)")
            && libraryPaperTableSource.contains("scrollRowToVisibleCentered")
            && librarySource.contains("paperTableFocusRequestID = UUID()")
            && !librarySource.contains("NSEvent.addLocalMonitorForEvents(matching: .keyDown)"),
        "Library paper lists should support focused native table arrow-key browsing and keep the selected row visible"
    )
    try check(
        rootViewSource.contains("GlobalOperationStatusView"),
        "the root view should show the current long-running operation"
    )
    try check(
        appModelSource.contains("postNotice("),
        "AppModel should publish success and failure notices for interaction feedback"
    )
    try check(
        appModelSource.contains("CacheStorageSummary"),
        "AppModel should expose a cache and storage summary for Settings"
    )
    try check(
        (appModelSource.contains("@Published var libraryDerivedState")
            || libraryFeatureStoreSource.contains("@Published var libraryDerivedState"))
            && (appModelSource.contains("PaperLibraryDerivedState.build")
                || libraryFeatureStoreSource.contains("PaperLibraryDerivedState.build"))
            && (libraryFeatureStoreSource.contains("libraryDerivedState.matchesSearch")
                || librarySource.contains("model.libraryDerivedState.matchesSearch")
                || librarySource.contains("derivedState.matchesSearch"))
            && librarySource.contains("model.libraryDerivedState.categoryPaperCountsByID")
            && librarySource.contains("model.libraryDerivedState.tagPaperCountsByID")
            && libraryDerivedStateSource.contains("paperIDsByCategoryID")
            && libraryDerivedStateSource.contains("paperIDsForCategoryFilter")
            && libraryDerivedStateSource.contains("paperIDsForTag")
            && libraryFeatureStoreSource.contains("func paperListState(")
            && !librarySource.contains("private func makePaperListState()"),
        "library filtering and sidebar counts should use precomputed derived state and cached feature-store list state instead of recomputing in the view body"
    )
    try check(
        appModelSource.contains("libraryThumbnailRefreshTask")
            && appModelSource.contains("startLibraryThumbnailRefresh(for:")
            && appModelSource.contains("LibraryThumbnailLoader.load")
            && !appModelSource.contains("refreshLibraryThumbnails()"),
        "library reload should refresh PDF thumbnail URLs in a background task instead of rendering thumbnails on the main actor"
    )
    try check(
        appModelSource.contains("startDiscoverCacheWarmupIfNeeded")
            && appModelSource.contains("DiscoverCacheLoader.loadInitialState")
            && appModelSource.contains("Task.detached")
            && appModelSource.contains("applyDiscoverCachedState")
            && !appModelSource.contains("func showDiscover() {\n        route = .discover\n        clearReaderContext()\n        refreshDiscoverEnrichmentsForCurrentFeed()\n    }"),
        "opening Discover should show cached state while background loaders warm JSON, asset, and thumbnail data off the main actor"
    )
    try check(
        appSource.contains("private let initiallyMountedRoutes: Set<AppRoute> = []")
            && appSource.contains("@State private var mountedRoutes: Set<AppRoute> = initiallyMountedRoutes")
            && !appSource.contains("@State private var mountedRoutes: Set<AppRoute> = [.library]"),
        "Library, Explore, and Search route shells should mount only when visited so hidden route trees do not consume layout time"
    )
    let discoverCacheLoaderSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/DiscoverCacheLoader.swift"))
    let pdfThumbnailCacheSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PDFThumbnailCache.swift"))
    try check(
        pdfThumbnailCacheSource.contains("func cachedThumbnailURLs")
            && discoverCacheLoaderSource.contains("thumbnailCache.cachedThumbnailURLs"),
        "Discover cache warmup should read existing PDF thumbnails without generating missing thumbnails during navigation"
    )
    try check(
        appModelSource.contains("refreshCacheStorageSummary()")
            && appModelSource.contains("CacheStorageSummaryLoader.load")
            && appModelSource.contains("cacheStorageSummaryTask"),
        "cache storage size refresh should enumerate large cache directories off the main actor"
    )

    try check(
        librarySource.contains("dropPDFs(from providers:"),
        "library should accept dropped PDF files for import"
    )
    try check(
        !librarySource.contains(".onTapGesture(count: 2)"),
        "library paper rows should not use a row-level double-tap recognizer that delays single-click selection"
    )
    try check(
        librarySource.contains("lastPaperRowClick"),
        "library paper rows should detect a second quick click from the immediate single-click handler"
    )
    try check(
        libraryPaperTableSource.contains("private var isHovering = false")
            && libraryPaperTableSource.contains("NSTrackingArea"),
        "library native paper rows should track hover state for row feedback and selection affordances"
    )
    try check(
        librarySource.contains("bulkActionBarOverlay"),
        "library bulk action controls should float over the list instead of shifting rows down"
    )
    try check(
        !librarySource.contains("onSelectionToggle"),
        "library paper rows should not show checkbox-style selection controls"
    )
    try check(
        !librarySource.contains("showSelectionToggle"),
        "library paper rows should rely on command/shift multi-select instead of hover checkboxes"
    )
    try check(
        libraryPaperTableSource.contains("arxivDisplayID(for:")
            && libraryPaperTableSource.contains("ArxivIDExtractor.firstCanonicalID(in:)"),
        "library paper rows should show the arXiv ID in the visible card area when available"
    )
    try check(
        libraryPaperTableSource.contains("chipFont = NSFont.systemFont(ofSize: 12.5"),
        "library arXiv, folder, and tag chips should be slightly larger than caption text"
    )
    try check(
        librarySource.contains("paperIDsForDrag(startingWith:"),
        "dragging a library paper should carry the selected paper set when the row is part of a multi-selection"
    )
    try check(
        libraryCategoryOutlineSource.contains("outlineView.indentationPerLevel")
            && libraryCategoryOutlineSource.contains("outlineView.rowHeight = 32")
            && librarySource.contains("categoryTreeConnectorHeight: CGFloat = 32")
            && !librarySource.contains("CategoryTreeConnector")
            && !librarySource.contains("TreeConnectorLevel")
            && !librarySource.contains("connectorContinuations")
            && !librarySource.contains("index == connectorContinuations.count - 1 ? 0.34 : 0.18")
            && !librarySource.contains("CategoryDepthGuide"),
        "library folder hierarchy should use native outline indentation instead of custom SwiftUI connector drawing"
    )
    try check(
        librarySource.contains("LibraryPaperTableView(")
            && librarySource.contains("rows: paperTableRows")
            && libraryPaperTableSource.contains("tableView.rowHeight")
            && libraryPaperTableSource.contains("heightOfRow"),
        "library paper rows should keep dense, stable native table row sizing instead of SwiftUI list row insets"
    )
    try check(
        librarySource.contains("categoryManagementSheet"),
        "library should provide category rename, move, and delete management"
    )
    try check(
        librarySource.contains("tagManagementSheet"),
        "library should provide tag rename and delete management"
    )
    try check(
        librarySource.contains("collapsedCategoryIDs"),
        "library category tree should support folding"
    )
    try check(
        librarySource.contains("countText:"),
        "library sidebar rows should show category and tag counts"
    )
    try check(
        librarySource.contains("NativeInspectorDetailsNoteRowView")
            && librarySource.contains("onEditNote")
            && librarySource.contains("onDeleteNote")
            && librarySource.contains("onSaveNote"),
        "library inspector should expose per-paper notes"
    )
    try check(
        libraryPaperTableSource.contains("LibraryPaperThumbnailDecodeGate")
            && libraryPaperTableSource.contains("decodeLibraryPaperThumbnailImage")
            && libraryPaperTableSource.contains("Task.detached(priority: LibraryPaperThumbnailDecodePolicy.decodePriority)")
            && !libraryPaperTableSource.contains("NSImage(contentsOf: url)")
            && !librarySource.contains("LocalThumbnailImage"),
        "library native thumbnail rows should decode local thumbnail images asynchronously instead of reading image files in body"
    )
    try check(
        appModelSource.contains("updateCategory(") && appModelSource.contains("deleteCategory("),
        "AppModel should manage category rename, move, and delete operations"
    )
    try check(
        appModelSource.contains("updateTag(") && appModelSource.contains("deleteTag("),
        "AppModel should manage tag rename and delete operations"
    )
    try check(
        appModelSource.contains("saveNote("),
        "AppModel should persist paper notes"
    )
    try check(
        appModelSource.contains("loadedPaperNotesPaperIDs")
            && appModelSource.contains("func loadPaperNotes(for paper: Paper, force: Bool = false)")
            && appModelSource.contains("guard force || !loadedPaperNotesPaperIDs.contains(paper.id)")
            && appModelSource.contains("loadedPaperNotesPaperIDs.insert(paperID)"),
        "paper notes should be cached after first load and explicitly refreshed after note mutations"
    )
    try check(
        appModelSource.contains("librarySelectedCategoryID"),
        "AppModel should keep library category selection outside LibraryView local state"
    )
    try check(
        librarySource.contains("libraryIncludeSubfolders")
            && librarySource.contains("showsFolderScope")
            && librarySource.contains("includeSubfolders: libraryIncludeSubfolders")
            && libraryFeatureStoreSource.contains("paperIDsForCategoryFilter(")
            && libraryFeatureStoreSource.contains("includeDescendants: request.includeSubfolders"),
        "library folder view should toggle between current-folder papers and current-plus-subfolders papers"
    )
    try check(
        appModelSource.contains("readerReturnRoute"),
        "AppModel should remember whether the reader was opened from Library or Discover"
    )
    try check(
        discoverSource.contains("requestNativeDiscoverScrollRestore")
            && nativeDiscoverCollectionSource.contains("restorePaperID"),
        "Discover should restore the last visible paper when returning from the reader"
    )

    try check(
        readerViewSource.contains("ReaderNativeToolbarView(")
            && readerToolbarSource.contains("NSSegmentedControl")
            && readerToolbarSource.contains("NSPopUpButton")
            && readerToolbarSource.contains("NSButton")
            && readerToolbarSource.contains("pageStatusLabel")
            && readerToolbarSource.contains("zoomStatusLabel")
            && readerToolbarSource.contains("onCommand(.previousPage)")
            && readerToolbarSource.contains("onCommand(.nextPage)")
            && readerToolbarSource.contains("onCommand(.zoomOut)")
            && readerToolbarSource.contains("onCommand(.zoomIn)")
            && readerToolbarSource.contains("onCommand(.fitWidth)")
            && readerToolbarSource.contains("onToggleSplit")
            && !readerViewSource.contains("private struct ReaderPDFToolbar: View")
            && !readerViewSource.contains("PaperCodexIconButton(title: \"Previous Page\""),
        "reader should provide explicit native PDF toolbar controls"
    )
    try check(
        readerViewSource.contains("PaperCodexIconButton(title: \"Close Split\", systemImage: \"xmark\")")
            && readerViewSource.contains("PaperCodexPanelButton(title: \"Cancel\", systemImage: \"xmark\")")
            && readerViewSource.contains("NativeAddPaperToSessionList(")
            && readerViewSource.contains("private struct NativeAddPaperToSessionList: NSViewRepresentable")
            && readerViewSource.contains("private final class NativeAddPaperToSessionListView: NSScrollView")
            && readerViewSource.contains("private final class NativeAddPaperToSessionTableView: NSTableView")
            && readerViewSource.contains("private final class NativeAddPaperToSessionTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate")
            && readerViewSource.contains("private final class NativeAddPaperToSessionRowCellView: NSTableCellView")
            && readerViewSource.contains("NSScrollView")
            && readerViewSource.contains("NSTableColumn")
            && readerViewSource.contains("makeView(withIdentifier:")
            && readerViewSource.contains("override func mouseDown(with event: NSEvent)")
            && readerViewSource.contains("setAccessibilityLabel(title)")
            && !readerViewSource.contains("private struct AddPaperToSessionRowButton: NSViewRepresentable")
            && !readerViewSource.contains("NativeAddPaperToSessionStackView")
            && !readerViewSource.contains("LazyVStack(spacing: 6)")
            && !readerViewSource.contains("ForEach(filteredPapers)")
            && !readerViewSource.contains("\n                Button {")
            && !readerViewSource.contains("\n                            Button {")
            && !readerViewSource.contains("Button(\"Cancel\", action: onCancel)")
            && !readerViewSource.contains(".buttonStyle("),
        "reader split preview and add-paper sheet should use AppKit-backed buttons instead of SwiftUI Button styles"
    )
    try check(
        readerViewSource.contains("ReaderSplitView(")
            && readerViewSource.contains("ReaderPDFSplitView(")
            && readerSplitSource.contains("NSSplitView")
            && readerSplitSource.contains("ReaderSplitContainerView")
            && readerSplitSource.contains("ReaderPDFSplitContainerView")
            && !readerViewSource.contains("HSplitView")
            && !readerViewSource.contains("VSplitView")
            && readerViewSource.contains("isPDFSplitVisible")
            && readerViewSource.contains("pdfSplitTarget"),
        "reader should use native AppKit split views for main reading/chat and top-bottom PDF link preview"
    )
    try check(
        readerViewSource.contains("ReaderSplitView(secondaryContentID: \"reader-chat\"")
            && readerViewSource.contains("ReaderPDFSplitView(secondaryContentID: pdfSplitSecondaryContentID")
            && readerViewSource.contains("private var pdfSplitSecondaryContentID: AnyHashable")
            && readerSplitSource.contains("private var lastPrimaryContentID: AnyHashable?")
            && readerSplitSource.contains("private var lastSecondaryContentID: AnyHashable?")
            && readerSplitSource.contains("primaryContentID: AnyHashable? = nil")
            && readerSplitSource.contains("secondaryContentID: AnyHashable? = nil")
            && readerSplitSource.contains("ReaderSplitHostUpdate.shouldReplaceHostedContent")
            && readerSplitSource.contains("guard let nextID else {\n            return true")
            && readerSplitSource.contains("lastSecondaryContentID = secondaryContentID"),
        "reader split hosts should use content IDs to avoid reassigning stable Chat and PDF-preview NSHostingView roots during high-frequency PDF status updates"
    )
    try check(
        readerToolbarSource.contains("keyEquivalent = \"\\\\\"")
            && readerToolbarSource.contains("keyEquivalentModifierMask = [.command, .shift]")
            && readerViewSource.contains("PaperCodexMotion.perform(PaperCodexMotion.pdfSplitOpen")
            && readerViewSource.contains(".animation(PaperCodexMotion.accessible(PaperCodexMotion.pdfSplitOpen")
            && readerViewSource.contains("ReaderPDFSplitView("),
        "reader PDF split should have a direct keyboard shortcut and animated toggle feedback"
    )
    try check(
        readerViewSource.contains("isPDFSplitContentReady")
            && readerViewSource.contains("pendingPDFSplitTarget")
            && readerViewSource.contains("splitContentMountDelay")
            && readerViewSource.contains("PDFSplitPreparingView")
            && readerViewSource.contains("schedulePDFSplitContentMount"),
        "reader PDF split should stage PDFKit mounting until after the split shell opens so Open Split feels smooth"
    )
    try check(
        !readerViewSource.contains(".frame(minWidth: 560)") && readerViewSource.contains(".frame(minWidth: ReaderPDFLayout.minimumPaneWidth"),
        "reader PDF pane should be allowed to resize with the split divider instead of holding a wide fixed minimum"
    )
    try check(
        appModelSource.contains("returnFromCitationJump"),
        "AppModel should keep a citation return path"
    )
    try check(
        pdfKitSource.contains("PDFKitCommand"),
        "PDFKit view should accept explicit toolbar commands"
    )
    try check(
        appKitMenuSource.contains("item(\"Previous PDF Page\", action: #selector(previousPDFPage), key: Self.upArrowKey)")
            && appKitMenuSource.contains("item(\"Next PDF Page\", action: #selector(nextPDFPage), key: Self.downArrowKey)")
            && appKitMenuSource.contains("item(\"Zoom PDF In\", action: #selector(zoomPDFIn), key: \"=\")")
            && appKitMenuSource.contains("item(\"Zoom PDF Out\", action: #selector(zoomPDFOut), key: \"-\")")
            && appKitMenuSource.contains("item(\"Fit PDF Width\", action: #selector(fitPDFWidth), key: \"0\")")
            && appKitMenuSource.contains("case #selector(previousPDFPage), #selector(nextPDFPage), #selector(zoomPDFIn), #selector(zoomPDFOut), #selector(fitPDFWidth):")
            && appModelSource.contains("func sendPDFKitCommand(_ kind: PDFKitCommandKind)"),
        "Reader PDF paging and zooming should have direct keyboard commands"
    )
    try check(
        pdfKitSource.contains("applyManualZoom(multiplier:")
            && pdfKitSource.contains("resolvedScaleFactor()")
            && pdfKitSource.contains("clampedManualScale")
            && pdfKitSource.contains("restoreViewportCenter")
            && pdfKitSource.contains("manualZoomMinimumScale")
            && pdfKitSource.contains("manualZoomMaximumScale")
            && !pdfKitSource.contains("pdfView.scaleFactor = min(pdfView.scaleFactor * 1.18")
            && !pdfKitSource.contains("pdfView.scaleFactor = max(pdfView.scaleFactor / 1.18"),
        "PDF zoom commands should leave auto-fit through a stable captured scale and preserve the visible center"
    )
    try check(
        pdfKitSource.contains("ResponsivePDFView") && pdfKitSource.contains("refitForCurrentWidth"),
        "PDFKit view should refit the document when its split-pane width changes"
    )
    try check(
        pdfKitSource.contains("PDFInternalLinkTarget") && pdfKitSource.contains("onInternalLinkSplit"),
        "PDF hyperlink previews should be able to open internal link targets in the secondary split pane"
    )
    try check(
        interactionSource.contains("case restorePosition(PaperReaderPosition)"),
        "PDFKit commands should provide an explicit restore-position command for citation return"
    )
    try check(
        !pdfKitSource.contains("lastAppliedReadingPositionDate"),
        "PDF reading-position saves should not trigger viewport restoration through updatedAt changes"
    )
    try check(
        pdfKitSource.contains("ResponsivePDFView") && pdfKitSource.contains("override func mouseDown"),
        "PDFKit view should use a click-aware PDFView subclass for in-PDF citation previews"
    )
    try check(
        pdfKitSource.contains("override var mouseDownCanMoveWindow"),
        "PDF drag interactions should not be treated as full-window background dragging"
    )
    try check(
        !pdfKitSource.contains("installWindowDragSuppressionMonitor")
            && !pdfKitSource.contains("suppressWindowBackgroundDragging"),
        "PDF drag suppression should rely on global window chrome policy instead of fragile PDFKit-local event monitors"
    )
    try check(
        pdfKitSource.contains("showCitationPreviewPopover"),
        "PDFKit view should show a popup preview for in-text citations"
    )
    try check(
        pdfKitSource.contains("NativeReferenceEntryPopoverView"),
        "PDFKit view should render clicked reference-list entries as a native card"
    )
    try check(
        pdfKitSource.contains("NativeInTextCitationPreviewView"),
        "PDFKit view should render non-reference citations as a lightweight native preview popup"
    )
    try check(
        pdfKitSource.contains("showPDFLinkPreviewPopover"),
        "PDFKit view should preview PDF hyperlinks before following them"
    )
    try check(
        pdfKitSource.contains("NativePDFLinkPreviewPopoverView"),
        "PDFKit view should render PDF hyperlink previews as a native card"
    )
    try check(
        pdfKitSource.contains("PDFActionURL") && pdfKitSource.contains("PDFActionGoTo"),
        "PDFKit view should intercept external and internal PDF link actions"
    )
    try check(
        windowTabBarSource.contains("model.returnFromReader()"),
        "window Home tab should return from Reader to the previous browsing surface instead of always resetting to Library"
    )
    try check(
        !appModelSource.contains("readerContextCleanupTask")
            && !appModelSource.contains("scheduleReaderContextClear()")
            && !appModelSource.contains("clearReaderContext()")
            && appModelSource.contains("func returnFromReader() {\n        let destination = readerReturnRoute"),
        "reader navigation should preserve PDF and chat context so route switches can keep reading position"
    )
    try check(
        readerViewSource.contains("ReaderNativeToolbarView")
            && readerToolbarSource.contains("paperPopup")
            && readerToolbarSource.contains("NSSegmentedControl")
            && readerViewSource.contains("AddPaperToSessionSheet")
            && readerViewSource.contains("model.addPaperToCurrentSession")
            && readerViewSource.contains("model.removePaperFromCurrentSession"),
        "reader should expose the current session paper set through the PDF toolbar and allow papers to be added or removed while reading"
    )

    try check(
        chatSource.contains("NativeChatTranscriptView(")
            && chatSource.contains("scrollRequestToken: chatScrollRequestToken")
            && chatSource.contains("requestChatScrollToBottom")
            && chatSource.contains("scrollToBottom")
            && !chatSource.contains("ScrollViewReader"),
        "chat should auto-scroll to the newest message and active run through the native transcript surface"
    )
    try check(
        chatSource.contains("isCurrentSessionSending"),
        "chat should distinguish the active session run from other sessions"
    )
    try check(
        chatSource.contains("model.activeCodexRun(for: model.selectedSession?.id)")
            && chatSource.contains("model.isSessionSending(model.selectedSession?.id)")
            && !chatSource.contains("isOtherSessionSending"),
        "chat should allow other sessions to send while this session is running or idle"
    )
    try check(
        !chatSource.contains("guard !model.isSending, !message.isEmpty"),
        "chat send action should not use a global sending guard"
    )
    try check(
        chatSource.contains("@State private var draftsByComposerKey")
            && chatSource.contains("composerDraftKey")
            && chatSource.contains("composerDraftBinding"),
        "chat composer drafts should be keyed by the selected paper and session"
    )
    try check(
        !chatSource.contains("@State private var draft =")
            && !chatSource.contains("text: $draft"),
        "chat composer should not keep one global draft shared across papers"
    )
    try check(
        chatSource.contains("canEditComposer"),
        "other session composers should remain editable while Codex runs elsewhere"
    )
    try check(
        chatSource.contains("composerTopDivider"),
        "chat input separator should be owned by the composer above the input area"
    )
    try check(
        chatSource.contains("renameSessionSheet"),
        "chat sessions should be renameable from the session bar"
    )
    try check(
        chatSource.contains("Label(\"Rename\", systemImage: \"pencil\")")
            || chatSource.contains("PaperCodexToolbarButton(\n                title: \"Rename\"")
            || chatSource.contains("ReaderChatHeaderActionButton(\n                title: \"Rename\"")
            || readerSessionToolbarSource.contains("renameButton"),
        "chat session rename should be exposed as a direct button after New"
    )
    try check(
        !chatSource.contains("ellipsis.circle"),
        "chat session rename should not be hidden behind an ellipsis menu"
    )
    try check(
        chatSource.contains("renderGeneratedImageGallery")
            && chatSource.contains("papercodex-chat://image")
            && chatSource.contains("GeneratedImagePreviewOverlay")
            && chatSource.contains("ZoomableImageScrollView"),
        "chat should render generated local images as an explicit in-transcript gallery"
    )
    try check(
        chatComposerNativeSource.contains("hasMarkedText()"),
        "chat composer should let IME marked text handle Return before submitting"
    )
    try check(
        chatSource.contains("CurrentSelectionReplyCard(selection: selection)")
            && chatSource.contains("private struct CurrentSelectionReplyCard: NSViewRepresentable")
            && chatSource.contains("private final class CurrentSelectionReplyCardView: NSView")
            && chatSource.contains("private final class CurrentSelectionReplyClearButton: NSButton")
            && chatSource.contains("NSTextField(labelWithString:")
            && chatSource.contains("NSImageView()")
            && chatSource.contains("NSButton")
            && chatSource.contains("setAccessibilityLabel(\"Remove Source\")")
            && chatSource.contains("override func acceptsFirstMouse(for event: NSEvent?) -> Bool")
            && !chatSource.contains("private struct CurrentSelectionReplyCard: View")
            && !chatSource.contains("PaperCodexIconButton(title: \"Remove Source\""),
        "chat selected-source reply card should use a native AppKit view above the composer instead of a SwiftUI HStack"
    )
    try check(
        appKitMenuSource.contains("item(\"Focus Chat Composer\", action: #selector(focusChatComposer), key: \"l\")")
            && appModelSource.contains("@Published var chatComposerFocusRequestID")
            && appModelSource.contains("func requestChatComposerFocus()")
            && appModelSource.contains("selectedSessionPanelTab = .chat")
            && chatSource.contains("focusRequestID: composerFocusRequestID")
            && chatSource.contains(".onChange(of: model.chatComposerFocusRequestID)")
            && chatComposerNativeSource.contains("window?.makeFirstResponder(textView)")
            && chatComposerNativeSource.contains("scrollRangeToVisible"),
        "Cmd-L should focus the Reader chat composer and switch back to the Chat tab"
    )
    try check(
        appModelSource.contains("appendCodexCancellationMessage"),
        "cancelling Codex should leave a visible trace in the session"
    )
    try check(
        appModelSource.contains("@Published var activeCodexRunsBySessionID")
            && appModelSource.contains("private var activeCodexRunHandlesBySessionID")
            && appModelSource.contains("private var cancellingCodexRunSessionIDs"),
        "AppModel should track active Codex runs independently by session"
    )
    try check(
        appModelSource.contains("func isSessionSending(_ sessionID: String?) -> Bool")
            && appModelSource.contains("func activeCodexRun(for sessionID: String?) -> ActiveCodexRun?"),
        "AppModel should expose per-session run state to chat views"
    )
    try check(
        !appModelSource.contains("@Published var isSending = false")
            && !appModelSource.contains("guard !isSending else"),
        "AppModel should not block all sessions with one global sending flag"
    )
    try check(
        appModelSource.contains("sessionsForPaperSet")
            && appModelSource.contains("Set(session.paperIDs) == Set(paperIDs)"),
        "reader should expose sessions scoped to the selected paper set"
    )
    try check(
        appModelSource.contains("try createSession(paperIDs: currentReaderPaperIDs())"),
        "new chat sessions should keep the current reader paper set"
    )
    try check(
        appModelSource.contains("openPapersForReading")
            && appModelSource.contains("openPapersForChat")
            && appModelSource.contains("openRecentSession"),
        "AppModel should open single-paper and multi-paper conversations from library and recent conversation entries"
    )
    try check(
        !appModelSource.contains("session.paperIDs + [fallbackPaper.id]"),
        "session context loading should not silently add the selected fallback paper to another paper's session"
    )
    try check(
        (appModelSource.contains("@Published var recentSessions")
            || readerFeatureStoreSource.contains("@Published var recentSessions"))
            && appModelSource.contains("refreshRecentSessions"),
        "AppModel should publish recent conversations for the library surface"
    )
    try check(
        librarySource.contains("RecentConversationsContent")
            && librarySource.contains("openSelectedPapersForReading")
            && librarySource.contains("openSelectedPapersForChat")
            && librarySource.contains("LibraryNativeToolbarView")
            && librarySource.contains("readablePaperIDs"),
        "library should expose recent conversations and open multi-paper sessions from selections or folders"
    )
    if let recentContentRange = librarySource.range(of: "private struct NativeRecentConversationsContent: NSViewRepresentable"),
       let recentDetailRange = librarySource.range(of: "private struct NativeRecentConversationDetailPanel: NSViewRepresentable", range: recentContentRange.upperBound..<librarySource.endIndex) {
        let recentContentSource = String(librarySource[recentContentRange.lowerBound..<recentDetailRange.lowerBound])
        try check(
            librarySource.contains("NativeRecentConversationsContent(")
                && librarySource.contains("NativeRecentConversationDetailPanel(")
                && recentContentSource.contains("NativeRecentConversationsContainerView")
                && recentContentSource.contains("NativeRecentConversationRowView")
                && recentContentSource.contains("NativeRecentConversationOpenButton")
                && recentContentSource.contains("NSScrollView")
                && recentContentSource.contains("NSStackView")
                && recentContentSource.contains("NativeRecentConversationSelectionButtonView")
                && !librarySource.contains("private struct RecentConversationsContent: View")
                && !librarySource.contains("private struct RecentConversationRow: View")
                && !librarySource.contains("private struct RecentConversationSelectionButton: View")
                && !librarySource.contains("PaperCodexNativeScrollView {\n                    LazyVStack(spacing: 8)")
                && !librarySource.contains("ForEach(sessions)"),
            "recent conversations list should render as a single native AppKit scroll/list surface instead of SwiftUI LazyVStack rows"
        )
    } else {
        throw CheckFailure(description: "native recent conversations list source should remain inspectable")
    }
    if let sidebarRange = appShellSource.range(of: "struct PrimaryNavigationSection"),
       let paperListRange = librarySource.range(of: "private var paperList: some View"),
       let recentNavRange = appShellSource.range(of: "title: \"Recent Conversations\""),
       let settingsButtonRange = appShellSource.range(of: "title: \"Settings\"") {
        try check(
            sidebarRange.lowerBound < recentNavRange.lowerBound
                && settingsButtonRange.lowerBound < recentNavRange.lowerBound
                && !librarySource.prefix(upTo: paperListRange.lowerBound).contains("title: \"Recent Conversations\""),
            "recent conversations should be a shared sidebar navigation item under Settings"
        )
    } else {
        throw CheckFailure(description: "shared sidebar navigation should include a Recent Conversations item under Settings")
    }
    try check(
        appModelSource.contains("enum LibrarySurface")
            && appModelSource.contains("case recentConversations")
            && librarySource.contains("LibrarySurface")
            && librarySource.contains("NativeRecentConversationsContent")
            && librarySource.contains("NativeRecentConversationDetailPanel")
            && librarySource.contains("NativeRecentConversationDetailView")
            && !librarySource.contains("private struct RecentConversationDetailPanel: View")
            && !librarySource.contains("ForEach(papers)"),
        "recent conversations should render session content in the main library panes instead of embedding session rows in the sidebar"
    )
    try check(
        repositorySource.contains("fetchRecentSessions(limit:"),
        "repository should expose recent sessions for the library conversation list"
    )

    try check(
        nativeDiscoverCollectionSource.contains("private let statusLabel = NSTextField(labelWithString: \"\")")
            && nativeDiscoverCollectionSource.contains("nativeDiscoverStatusTitle(for: model.interactionState)")
            && nativeDiscoverCollectionSource.contains("statusLabel.isHidden = model.interactionState == nil"),
        "Discover and Search native cards should show per-paper processing and cache state"
    )
    try check(
        appModelSource.contains("discoverScrollPositionPaperID")
            && appModelSource.contains("recordDiscoverScrollPosition")
            && discoverSource.contains("visibleDiscoverPaperID")
            && discoverSource.contains("markDiscoverVisibleRow")
            && discoverSource.contains("requestNativeDiscoverScrollRestore")
            && nativeDiscoverCollectionSource.contains("onVisiblePaperChange")
            && nativeDiscoverCollectionSource.contains("scrollToPaper")
            && discoverSource.contains("commitDiscoverScrollPosition")
            && !discoverSource.contains("ScrollViewReader")
            && !discoverSource.contains("discoverReturnPaperID"),
        "Discover should record the current visible paper and restore that scroll position when returning from Reader or other app sections"
    )
    if let datePickerRange = discoverSource.range(of: "private struct CompactDiscoverDatePicker: View"),
       let datePickerEndRange = discoverSource.range(of: "private enum DiscoverDateStrings", range: datePickerRange.upperBound..<discoverSource.endIndex) {
        let datePickerSource = String(discoverSource[datePickerRange.lowerBound..<datePickerEndRange.lowerBound])
        try check(
            datePickerSource.contains("NativeCompactDiscoverDatePicker(")
                && discoverSource.contains("private struct NativeCompactDiscoverDatePicker: NSViewRepresentable")
                && discoverSource.contains("private final class NativeCompactDiscoverDatePickerView: NSDatePicker")
                && discoverSource.contains("datePickerElements = [.yearMonthDay]")
                && discoverSource.contains("datePickerStyle = .textFieldAndStepper")
                && !datePickerSource.contains("\n        DatePicker(")
                && !datePickerSource.contains(".datePickerStyle(.compact)"),
            "Discover date range controls should use native AppKit NSDatePicker controls"
        )
    } else {
        throw CheckFailure(description: "Discover compact date picker source should remain inspectable")
    }
    try check(
        discoverSource.contains("[DiscoverQuickRange.today, .last7Days, .last30Days]"),
        "Discover quick ranges should be limited to Today, Last 7 Days, and Last 30 Days"
    )
    try check(
        appModelSource.contains("let initialDiscoverDate = DiscoverDateRange.isoDate()")
            && !appModelSource.contains("latestCompleteArxivSubmissionISODate"),
        "Discover initial date should use today's local date instead of the latest complete arXiv submission date"
    )
    try check(
        appModelSource.contains("let range = try preset.dateRange(containing: Date())"),
        "Discover quick ranges should anchor to today's date instead of the current end date"
    )
    try check(
        !discoverSource.contains("ArxivSourceBadge"),
        "Discover toolbar should not render the decorative arXiv source badge"
    )
    try check(
        !discoverSource.contains("Cache PDFs") && !discoverSource.contains("Cache visible"),
        "Discover toolbar should not expose a separate PDF cache action"
    )
    try check(
        discoverSource.contains("DiscoverProcessActionSheet"),
        "Discover Process Results should open an action sheet before starting processing"
    )
    try check(
        !discoverSource.contains("\n        Button(")
            && !discoverSource.contains("\n                    Button(")
            && !discoverSource.contains("\n                        Button {")
            && !discoverSource.contains("private struct DiscoverFilterChipStyle: ButtonStyle")
            && discoverSource.contains("NativeDiscoverFilterChipButton(")
            && discoverSource.contains("private struct NativeDiscoverFilterChipButton: NSViewRepresentable")
            && discoverSource.contains("private final class NativeDiscoverFilterChipButtonView: NSButton")
            && discoverSource.contains("PaperCodexPanelButton(title: \"Select All\", systemImage: \"checkmark.circle\")")
            && discoverSource.contains("PaperCodexPanelButton(title: \"Clear\", systemImage: \"xmark.circle\")")
            && discoverSource.contains("PaperCodexPanelButton(\n                            title: isRefreshingModels ? \"Refreshing\" : \"Refresh Models\""),
        "Discover should use AppKit-backed buttons for filter chips and process-sheet actions"
    )
    try check(
        appModelSource.contains("enum DiscoverProcessAction")
            && appModelSource.contains("case translate")
            && appModelSource.contains("case summarize")
            && appModelSource.contains("case cachePDFThumbnails"),
        "Discover processing should model selectable processing actions instead of paper selection"
    )
    try check(
        discoverSource.contains("Set(DiscoverProcessAction.allCases)")
            && !discoverSource.contains("initialSelectedPaperIDs")
            && !discoverSource.contains("DiscoverProcessPaperRow"),
        "Discover processing actions should default to all selected and should not render per-paper selection rows"
    )
    try check(
        appModelSource.contains("processCurrentDiscoverResults(_ papers: [ArxivFeedPaper], actions:")
            && appModelSource.contains("actions.contains(.cachePDFThumbnails)")
            && appModelSource.contains("await cacheDiscoverPDFs(visiblePapers)"),
        "Discover processing should run selected actions, including PDF download and thumbnail generation"
    )
    try check(
        appModelSource.contains("discoverCodexReasoningEffort")
            && appModelSource.contains("discoverCodexReasoningEffortDefaultsKey")
            && appModelSource.contains("processCurrentDiscoverResults(_ papers: [ArxivFeedPaper], actions: Set<DiscoverProcessAction> = Set(DiscoverProcessAction.allCases), modelOverride: String? = nil, reasoningEffort: CodexReasoningEffort? = nil)")
            && appModelSource.contains("runDiscoverAgentEnrichment(")
            && appModelSource.contains("reasoningEffort: selectedReasoningEffort"),
        "Discover processing should carry process-specific model and thinking settings instead of reusing chat reasoning"
    )
    try check(
        discoverSource.contains("modelOverride:")
            && discoverSource.contains("reasoningEffort:")
            && discoverSource.contains("draftModelOverride")
            && discoverSource.contains("draftReasoningEffort")
            && discoverSource.contains("CodexReasoningEffort.allCases"),
        "Discover Process Results sheet should allow choosing the model and thinking effort for this run"
    )
    try check(
        settingsViewSource.contains("draftDiscoverCodexReasoningEffort")
            && settingsViewSource.contains("SettingsReasoningEffortPopup(selection: draftDiscoverCodexReasoningEffort)")
            && settingsViewSource.contains("SettingsModelPopup(")
            && settingsViewSource.contains("model.setDiscoverCodexSettings(")
            && settingsViewSource.contains("reasoningEffort: draftDiscoverCodexReasoningEffort"),
        "Settings should expose native default Discover processing model and thinking controls"
    )
    try check(
        appModelSource.contains("processDiscoverPaperForEnrichment(")
            && appModelSource.contains("runtimeProfile: enrichmentRuntimeProfile")
            && appModelSource.contains("discoverEnrichment(existing, satisfies: actions)")
            && appModelSource.contains("discoverEnrichmentPrompt(for: paper, actions: actions)"),
        "Discover translation and summarization actions should use action-aware enrichment prompts and cache completeness checks"
    )
    try check(
        discoverSource.contains("@State private var visibleDiscoverPaperID: String?")
            && discoverSource.contains("@State private var discoverScrollPositionCommitTask: Task<Void, Never>?")
            && discoverSource.contains("NativeDiscoverCollectionView(")
            && nativeDiscoverCollectionSource.contains("onVisiblePaperChange")
            && discoverSource.contains("isRestoringDiscoverScrollPosition")
            && !discoverSource.contains(".scrollPosition(id:")
            && !discoverSource.contains(".scrollTargetLayout()")
            && !discoverSource.contains("DiscoverVisiblePaperReporter")
            && !discoverSource.contains("DiscoverVisiblePaperPreferenceKey"),
        "Discover scroll restoration should avoid per-pixel scroll binding, SwiftUI scroll targets, and per-card geometry tracking"
    )
    try check(
        discoverSource.contains("let visiblePapers = papers")
            && discoverSource.contains("DiscoverLayoutSignature")
            && discoverSource.contains("NativeDiscoverCollectionView(")
            && !discoverSource.contains("papers.map(\\.id).joined(separator: \",\")"),
        "Discover feed rendering should reuse one visible-paper snapshot and avoid building long string layout signatures in body"
    )
    try check(
        appModelSource.contains("cachedSearchResult = try loadCachedDiscoverSearch(query: query, allowPartialFragments: true)")
            && appModelSource.contains("if cachedSearchResult == .complete")
            && appModelSource.contains("cacheQueryResult:")
            && appModelSource.contains("guard !feed.papers.isEmpty else")
            && appModelSource.contains("try loadDiscoverEnrichments(for: feed.papers)"),
        "Discover search should hit cached non-empty query results before network fetch and immediately load cached enrichments"
    )
    try check(
        appModelSource.contains("allowPartialFragments: true")
            && appModelSource.contains("localDiscoverCache.loadQueryResults(containedIn: query)")
            && appModelSource.contains("\"Partial cached search\"")
            && appModelSource.contains("cacheQueryResult: hasCompleteCoverage"),
        "Discover search should fall back to reusable cached query fragments when live arXiv is unavailable"
    )
    try check(
        appModelSource.contains("loadLastDiscoverResultsState()")
            && appModelSource.contains("localDiscoverCache.loadLastQueryResult()")
            && appModelSource.contains("discoverKeyword = query.keyword")
            && appModelSource.contains("discoverSelectedCategories = query.categories")
            && appModelSource.contains("discoverSelectedSimilaritySourceIDs = query.similaritySourceIDs"),
        "Discover should restore the latest cached search result and its controls on launch"
    )
    try check(
        !discoverSource.contains("let expectedDate = \"\\(model.discoverStartDate)...\\(model.discoverEndDate)\"")
            && !discoverSource.contains("model.startDiscoverSearch()\n        }"),
        "Opening Discover should not automatically start a network search"
    )
    try check(
        nativeDiscoverCollectionSource.contains("mediaButton.leadingAnchor.constraint(equalTo: mediaWrap.leadingAnchor, constant: 14)")
            && nativeDiscoverCollectionSource.contains("mediaButton.trailingAnchor.constraint(equalTo: mediaWrap.trailingAnchor, constant: -14)")
            && nativeDiscoverCollectionSource.contains("mediaButton.topAnchor.constraint(equalTo: mediaWrap.topAnchor, constant: 14)")
            && nativeDiscoverCollectionSource.contains("mediaButton.bottomAnchor.constraint(equalTo: mediaWrap.bottomAnchor, constant: -8)"),
        "Discover paper images should use a small native inset aligned with card text"
    )
    try check(
        discoverSource.components(separatedBy: "NativeDiscoverCollectionView(").count - 1 >= 2
            && nativeDiscoverCollectionSource.contains("NativeDiscoverCollectionMetrics.columnCount")
            && nativeDiscoverCollectionSource.contains("flowLayout.itemSize")
            && nativeDiscoverCollectionSource.contains("currentItemSize")
            && !discoverSource.contains("discoverPaperGridColumnWidth")
            && !discoverSource.contains("LazyVStack(alignment: .leading, spacing: discoverPaperGridRowSpacing)")
            && !discoverSource.contains("Color.clear\n                                                .frame(maxWidth: .infinity)")
            && !discoverSource.contains("Color.clear\n                                            .frame(maxWidth: .infinity)"),
        "Discover and Search paper results should use stable native collection item sizes instead of SwiftUI grid row placeholders"
    )
    try check(
        nativeDiscoverCollectionSource.contains("NativeDiscoverImageCache")
            && !discoverSource.contains("private struct ArxivPaperCard: View")
            && !discoverSource.contains("private struct DiscoverPDFThumbnailHero")
            && !discoverSource.contains("private struct ArxivPreviewImage")
            && !discoverSource.contains("warmDiscoverLocalImages")
            && !discoverSource.contains("DiscoverLocalImageCache")
            && !discoverSource.contains("LocalCachedImage"),
        "Discover and Search native collection migration should remove the unused SwiftUI card and duplicate image warmup path"
    )
    try check(
        nativeDiscoverCollectionSource.contains("let shouldReloadCards = context.coordinator.update(from: self)")
            && nativeDiscoverCollectionSource.contains("if shouldReloadCards {\n            view.collectionView.reloadData()\n        }")
            && nativeDiscoverCollectionSource.contains("@discardableResult\n        func update(from view: NativeDiscoverCollectionView) -> Bool")
            && nativeDiscoverCollectionSource.contains("let shouldReload = cards != view.cards"),
        "Native Discover/Search collection should avoid full reloads when SwiftUI updates without card data changes"
    )
    try check(
        nativeDiscoverCollectionSource.contains("private var lastReportedVisiblePaperID: String?")
            && nativeDiscoverCollectionSource.contains("private func publishVisiblePaper(_ paperID: String?)")
            && nativeDiscoverCollectionSource.contains("guard !hasReportedVisiblePaper || lastReportedVisiblePaperID != paperID else")
            && discoverSource.contains("guard visibleDiscoverPaperID != paperID else"),
        "Native Discover/Search collection should avoid re-reporting the same visible item into SwiftUI state on every update pass"
    )
    try check(
        appModelSource.contains("tokenUsage: CodexTokenUsage?")
            && appModelSource.contains("aggregateTokenUsage")
            && appModelSource.contains("Process Tokens")
            && chatSource.contains("tokenUsageSummary")
            && chatSource.contains("case .usage"),
        "Process and chat Codex runs should surface token usage from real Codex usage events"
    )
    try check(
        discoverSource.contains("activeFilterChips"),
        "Discover should show removable active filter chips"
    )
    try check(
        discoverSource.contains("private let discoverRouteToolbarMinHeight: CGFloat")
            && discoverSource.contains(".frame(maxWidth: .infinity, minHeight: discoverRouteToolbarMinHeight, alignment: .topLeading)")
            && discoverSource.contains("DiscoverRouteLoadingPlaceholder")
            && discoverSource.contains("model.isLoadingArxivFeed && model.arxivFeed == nil")
            && discoverSource.contains("model.isSearchingArxivSearch && model.arxivSearchFeed == nil"),
        "Explore and Search should keep a stable toolbar and lightweight loading shell so route switches do not visually jump"
    )
    if let searchRowRange = discoverSource.range(of: "private var searchAndActionRow: some View"),
       let filterButtonRange = discoverSource.range(of: "private func filterButton", range: searchRowRange.upperBound..<discoverSource.endIndex) {
        let searchRowSource = String(discoverSource[searchRowRange.lowerBound..<filterButtonRange.lowerBound])
        try check(
            searchRowSource.contains("DiscoverSearchField(")
                && searchRowSource.contains("text: $model.discoverKeyword")
                && discoverSource.contains("private struct DiscoverSearchField: NSViewRepresentable")
                && discoverSource.contains("private final class NativeDiscoverSearchFieldView: NSSearchField")
                && discoverSource.contains("private final class DiscoverSearchFieldCoordinator: NSObject, NSSearchFieldDelegate")
                && discoverSource.contains("doCommandBy commandSelector")
                && discoverSource.contains("makeFirstResponder(searchField)")
                && searchRowSource.contains("title: model.isSearchingDiscover ? \"Searching\" : \"Search\"")
                && searchRowSource.contains("title: \"Process\"")
                && searchRowSource.contains(".fixedSize(horizontal: true, vertical: false)")
                && searchRowSource.contains(".frame(maxWidth: .infinity, minHeight: 34)")
                && !searchRowSource.contains("TextField(")
                && !searchRowSource.contains(".textFieldStyle(.roundedBorder)")
                && !searchRowSource.contains(".focused($isDiscoverSearchFocused)")
                && discoverSource.contains("VStack(alignment: .leading, spacing: 8) {\n                searchAndActionRow\n\n                FlowLayout"),
            "Discover search, Search, Stop, and Process should share one compact row above the filter controls"
        )
    } else {
        try check(false, "Discover should keep the search action row as a distinct source region for layout checks")
    }
    if let yearFieldRange = discoverSource.range(of: "private struct ArxivSearchYearField: View"),
       let yearFieldEndRange = discoverSource.range(of: "private struct DiscoverRouteLoadingPlaceholder", range: yearFieldRange.upperBound..<discoverSource.endIndex) {
        let yearFieldSource = String(discoverSource[yearFieldRange.lowerBound..<yearFieldEndRange.lowerBound])
        try check(
            yearFieldSource.contains("DiscoverSearchField(")
                && !yearFieldSource.contains("TextField(")
                && !yearFieldSource.contains(".textFieldStyle(.roundedBorder)"),
            "Search year filters should use native AppKit text fields"
        )
    } else {
        throw CheckFailure(description: "Search year filter field source should remain inspectable")
    }
    if let arxivSearchRange = discoverSource.range(of: "struct ArxivSearchView: View"),
       let toolbarRange = discoverSource.range(of: "private var toolbar: some View", range: arxivSearchRange.upperBound..<discoverSource.endIndex),
       let toolbarEndRange = discoverSource.range(of: "private func toggleSearchSortOrder", range: toolbarRange.upperBound..<discoverSource.endIndex) {
        let arxivSearchToolbarSource = String(discoverSource[toolbarRange.lowerBound..<toolbarEndRange.lowerBound])
        try check(
            arxivSearchToolbarSource.contains("DiscoverSearchField(")
                && arxivSearchToolbarSource.contains("text: $model.arxivSearchQuery")
                && arxivSearchToolbarSource.contains("DiscoverSortPopup(")
                && discoverSource.contains("private struct DiscoverSortPopup: NSViewRepresentable")
                && discoverSource.contains("private final class NativeDiscoverSortPopupButton: NSPopUpButton")
                && !arxivSearchToolbarSource.contains("TextField(")
                && !arxivSearchToolbarSource.contains("Picker(\"Sort\"")
                && !arxivSearchToolbarSource.contains(".pickerStyle(.menu)")
                && !arxivSearchToolbarSource.contains(".focused($isArxivSearchFocused)"),
            "Search toolbar query and sort controls should use native AppKit search field and popup controls"
        )
    } else {
        throw CheckFailure(description: "Search toolbar source should remain inspectable")
    }

    try check(
        !settingsViewSource.contains("SettingsSectionAnchor")
            && !settingsViewSource.contains("ScrollViewReader")
            && !settingsViewSource.contains("Settings Sections"),
        "settings should not add a second navigation rail or force scroll-anchor layout work"
    )
    try check(
        settingsViewSource.contains("LazyVStack(alignment: .leading, spacing: 22)")
            && settingsViewSource.contains("LazyVStack(alignment: .leading, spacing: 6)")
            && !settingsViewSource.contains(".onAppear {\n            syncLocalDrafts()\n            model.refreshCacheStorageSummary()\n            Task {\n                await model.refreshAvailableCodexModels()\n            }\n        }"),
        "settings should lazily build offscreen sections and should not refresh Codex models on every route entry"
    )
    try check(
        settingsViewSource.contains("title: \"System prompt template editor\"")
            && settingsViewSource.contains("textView.setAccessibilityLabel(title)")
            && settingsViewSource.contains("placeholderLabel.isHidden = !textView.string.isEmpty")
            && settingsViewSource.contains("title: \"New quick prompt editor\"")
            && !settingsViewSource.contains(".frame(height: 240)"),
        "settings should avoid exposing full long prompt editor contents as route-level accessibility text"
    )
    try check(
        appModelSource.contains("embeddingProviderAPIKeyDefaultsKey")
            && appModelSource.contains("loadEmbeddingProviderAPIKeyFromDefaults()")
            && appModelSource.contains("saveEmbeddingProviderAPIKeyToDefaults")
            && appModelSource.contains("private func embeddingProviderAPIKeyValue() -> String")
            && !appModelSource.contains("import Security")
            && !appModelSource.contains("SecItem")
            && !appModelSource.contains("Keychain")
            && !appModelSource.contains("keychainFailure"),
        "embedding API key should avoid Keychain entirely so app launch and route switching never trigger password prompts"
    )
    try check(
        appModelSource.contains("private var watchedFolderScanTask: Task<Void, Never>?")
            && appModelSource.contains("Task.detached(priority: .utility) {\n                    let repository = try PaperRepository(databasePath: databasePath)")
            && !appModelSource.contains("Task {\n                scanWatchedFolders()\n                await refreshCodexDiagnostic()"),
        "startup should not immediately scan watched folders or run folder enumeration on the main actor"
    )
    try check(
        arxivIDExtractorSource.contains("private static let versionedIDRegex")
            && arxivIDExtractorSource.contains("private static let versionSuffixRegex")
            && !arxivIDExtractorSource.contains("guard let regex = try? NSRegularExpression(pattern:"),
        "arXiv ID extraction should reuse compiled regular expressions instead of compiling during every sort comparison"
    )
    try check(
        librarySource.contains(".onChange(of: activePaperSurfaceFilteredPaperIDs)")
            && librarySource.contains("private var activePaperSurfaceFilteredPaperIDs: [String]")
            && librarySource.contains("selectedLibrarySurface == .papers ? filteredPaperIDs : []")
            && !librarySource.contains(".onChange(of: sortedPapers.map")
            && librarySource.contains("let arxivIDsByPaperID")
            && librarySource.contains("arxivIDComesBefore(left, right, ascending: ascending, arxivIDsByPaperID: arxivIDsByPaperID)"),
        "library route updates should not sort and re-parse arXiv IDs while handling navigation changes"
    )
    try check(
        settingsViewSource.contains("isArxivFeedDirty"),
        "settings should show dirty/saved state for editable sections"
    )
    try check(
        settingsViewSource.contains("testEmbeddingProvider"),
        "settings should provide an embedding-provider test action"
    )
    try check(
        settingsViewSource.contains("moveQuickPrompt"),
        "settings should allow quick prompts to be reordered"
    )
    try check(
        settingsViewSource.contains("revealPath("),
        "settings should reveal library and cache paths in Finder"
    )
}

func runUIDesignSourceChecks() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let designSystemURL = root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexDesignSystem.swift")
    let designSystemSource = try String(contentsOf: designSystemURL)
    let actionButtonSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/PaperCodexActionButton.swift"))
    let sidebarRowSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/SidebarRowButton.swift"))
    let tabBarSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/WindowChromeTabBar.swift"))
    let typographySource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/Typography.swift"))
    let chatSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/ChatView.swift"))

    try check(
        designSystemSource.contains("enum PaperCodexSurface")
            && designSystemSource.contains("enum PaperCodexSpacing")
            && designSystemSource.contains("enum PaperCodexCornerRadius")
            && designSystemSource.contains("enum PaperCodexHitTarget")
            && designSystemSource.contains("enum PaperCodexMotion"),
        "Paper Codex should centralize UI surface, spacing, radius, hit-target, and motion tokens"
    )
    try check(
        designSystemSource.contains("static func accessible(")
            && actionButtonSource.contains("@Environment(\\.accessibilityReduceMotion)")
            && sidebarRowSource.contains("@Environment(\\.accessibilityReduceMotion)")
            && tabBarSource.contains("@Environment(\\.accessibilityReduceMotion)"),
        "shared interactive components should respect Reduce Motion through PaperCodexMotion.accessible"
    )
    try check(
        actionButtonSource.contains("PaperCodexHitTarget.toolbarIconSize")
            && actionButtonSource.contains("PaperCodexHitTarget.toolbarButtonVerticalPadding")
            && sidebarRowSource.contains("PaperCodexHitTarget.sidebarRowHeight")
            && sidebarRowSource.contains("PaperCodexHitTarget.sidebarSelectionIndicatorHeight")
            && sidebarRowSource.contains("PaperCodexSpacing.sidebarRowLeading")
            && tabBarSource.contains("PaperCodexCornerRadius.control"),
        "shared controls should use Paper Codex design tokens instead of scattering local measurements"
    )
    try check(
        typographySource.contains(".dynamicTypeSize(.medium ... .accessibility2)")
            && typographySource.contains("paperCodexReadableLineLimit"),
        "Paper Codex typography should preserve readable line length and avoid forcing a single Dynamic Type size"
    )
    try check(
        chatSource.contains("private struct NativeChatTranscriptView: NSViewRepresentable")
            && chatSource.contains("private final class NativeChatTranscriptWebView: NSView")
            && chatSource.contains("NativeChatTranscriptHTMLBuilder")
            && chatSource.contains("message-user-bubble")
            && chatSource.contains("max-width: min(70%,")
            && chatSource.contains("message-agent")
            && chatSource.contains("width: 100%")
            && chatSource.contains("role-badge")
            && chatSource.contains("loadHTMLString(html, baseURL: htmlBaseURL)")
            && chatSource.contains("setContentHuggingPriority(.defaultLow, for: .horizontal)")
            && chatSource.contains("setContentCompressionResistancePriority(.defaultLow, for: .horizontal)")
            && !chatSource.contains("private struct MessageBubble: View")
            && !chatSource.contains("private struct MarkdownWebView: NSViewRepresentable"),
        "chat transcript should keep short user messages compact while Agent Markdown expands full-width inside one native WebKit surface"
    )
    try check(
        chatSource.contains("background: color-mix(in srgb, LinkText 9%, transparent)")
            && chatSource.contains("border: 1px solid color-mix(in srgb, LinkText 18%, transparent)")
            && !chatSource.contains("private struct UserMessageBubbleBackground: View")
            && !chatSource.contains("private struct ChatMessageBubbleBackground: View"),
        "only user chat bubbles should keep a quiet framed background, now rendered by the native transcript CSS"
    )
}

func runRepositoryChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-repository-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let databaseURL = tempRoot.appendingPathComponent("store.sqlite")
    let repository = try PaperRepository(databasePath: databaseURL.path)
    try repository.migrate()

    let now = Date(timeIntervalSince1970: 1_777_220_000)
    let paper = Paper(
        id: "paper-a",
        filePath: "/tmp/paper-a.pdf",
        fileHash: "hash-a",
        title: "Paper A",
        authors: ["Alice", "Bob"],
        year: 2026,
        sourceURL: nil,
        importedAt: now,
        updatedAt: now
    )
    let paperB = Paper(
        id: "paper-b",
        filePath: "/tmp/paper-b.pdf",
        fileHash: "hash-b",
        title: "Paper B",
        authors: ["Carol"],
        year: 2025,
        sourceURL: nil,
        importedAt: now,
        updatedAt: now
    )
    let category = Category(id: "cat-methods", parentID: nil, name: "Methods", sortOrder: 1)
    let childCategory = Category(id: "cat-vae", parentID: "cat-methods", name: "VAE", sortOrder: 2)
    let pinnedCategory = Category(id: "cat-pinned", parentID: nil, name: "Pinned", sortOrder: 3, isPinned: true)
    let tag = PaperTag(id: "tag-control", name: "control")
    let unassignedTag = PaperTag(id: "tag-diffusion", name: "diffusion")
    let page = PageIndex(
        paperID: "paper-a",
        page: 2,
        text: "Full text for page two.",
        confidence: 0.93
    )
    let span = Span(
        id: Span.makeID(paperID: "paper-a", page: 2, blockIndex: 3),
        paperID: "paper-a",
        page: 2,
        bbox: BoundingBox(x: 1, y: 2, width: 3, height: 4),
        text: "A stable span.",
        charRange: TextRange(location: 10, length: 14),
        sectionHint: "Method",
        confidence: 0.91
    )
    let anchor = Anchor(
        id: Anchor.makeID(paperID: "paper-a", page: 2, suffix: "sel1"),
        paperID: "paper-a",
        page: 2,
        selectedText: "A stable span.",
        bboxList: [span.bbox],
        matchedSpanIDs: [span.id],
        beforeContext: "Before",
        afterContext: "After",
        createdSessionID: "session-a",
        createdAt: now,
        confidence: 0.9
    )
    let session = PaperSession(
        id: "session-a",
        title: "Mechanism Notes",
        paperIDs: ["paper-a"],
        codexSessionID: "codex-a",
        workspacePath: tempRoot.appendingPathComponent("session-a").path,
        createdAt: now,
        updatedAt: now
    )
    let message = ChatMessage(
        id: "message-a",
        sessionID: "session-a",
        role: .user,
        content: "Use [[cite:\(anchor.id)]] here.",
        createdAt: now
    )

    try repository.upsertPaper(paper)
    try repository.upsertPaper(paperB)
    try repository.setPaperStarred(true, paperID: "paper-b", updatedAt: now.addingTimeInterval(1))
    try repository.upsertCategory(category)
    try repository.upsertCategory(childCategory)
    try repository.upsertCategory(pinnedCategory)
    try repository.upsertTag(tag)
    try repository.upsertTag(unassignedTag)
    try repository.assignPaper("paper-a", toCategory: "cat-vae")
    try repository.assignPaper("paper-a", toTag: "tag-control")
    try repository.upsertPage(page)
    try repository.upsertSpan(span)
    try repository.upsertAnchor(anchor)
    try repository.upsertSession(session)
    try repository.appendMessage(message)

    let fetchedPapers = try repository.fetchPapers()
    let fetchedPapersByID = try repository.fetchPapers(ids: ["paper-b", "missing-paper", "paper-a"])
    let fetchedPaperByHash = try repository.fetchPaper(fileHash: "hash-a")
    let missingPaperByHash = try repository.fetchPaper(fileHash: "missing-hash")
    let fetchedCategories = try repository.fetchCategories()
    let fetchedAllTags = try repository.fetchTags()
    let fetchedTags = try repository.fetchTags(forPaperID: "paper-a")
    let fetchedCategoryIDs = try repository.fetchCategoryIDs(forPaperID: "paper-a")
    let fetchedPages = try repository.fetchPages(paperID: "paper-a")
    let fetchedSpans = try repository.fetchSpans(paperID: "paper-a")
    let fetchedSpanByID = try repository.fetchSpan(id: span.id)
    let fetchedAnchors = try repository.fetchAnchors(paperID: "paper-a")
    let fetchedAnchorByID = try repository.fetchAnchor(id: anchor.id)
    let fetchedSessions = try repository.fetchSessions(paperID: "paper-a")
    let fetchedMessages = try repository.fetchMessages(sessionID: "session-a")

    var starredPaperB = paperB
    starredPaperB.isStarred = true
    starredPaperB.updatedAt = now.addingTimeInterval(1)
    try check(fetchedPapers == [starredPaperB, paper], "starred papers should round-trip through SQLite and be pinned first")
    try check(fetchedPapersByID == [starredPaperB, paper], "papers should be fetchable by ID in requested order")
    try check(fetchedPaperByHash == paper, "paper should be fetchable by file hash for duplicate detection")
    try check(missingPaperByHash == nil, "missing file hash should not return a paper")
    try check(fetchedCategories == [pinnedCategory, category, childCategory], "pinned categories should round-trip and sort before unpinned siblings")
    try check(fetchedAllTags == [tag, unassignedTag], "all tags should round-trip sorted by name")
    try check(fetchedTags == [tag], "paper tags should round-trip")
    try check(fetchedCategoryIDs == ["cat-vae"], "paper category links should round-trip")
    try check(fetchedPages == [page], "page indexes should round-trip")
    try check(fetchedSpans == [span], "spans should round-trip")
    try check(fetchedSpanByID == span, "spans should be fetchable by citation ID")
    try check(fetchedAnchors == [anchor], "anchors should round-trip")
    try check(fetchedAnchorByID == anchor, "anchors should be fetchable by citation ID")
    try check(fetchedSessions == [session], "sessions should round-trip")
    try check(fetchedMessages == [message], "messages should round-trip")

    var multiPaperSession = session
    multiPaperSession.paperIDs = ["paper-b", "paper-a"]
    multiPaperSession.updatedAt = Date(timeIntervalSince1970: 1_777_220_100)
    try repository.upsertSession(multiPaperSession)
    let fetchedSessionByID = try repository.fetchSession(id: "session-a")
    let fetchedSessionsForPaperB = try repository.fetchSessions(paperID: "paper-b")
    try check(fetchedSessionByID == multiPaperSession, "session should be fetchable by ID with ordered paper IDs")
    try check(fetchedSessionsForPaperB == [multiPaperSession], "sessions should be visible from every linked paper")

    let laterSession = PaperSession(
        id: "session-b",
        title: "Later Single Paper Notes",
        paperIDs: ["paper-a"],
        codexSessionID: nil,
        workspacePath: tempRoot.appendingPathComponent("session-b").path,
        createdAt: now,
        updatedAt: Date(timeIntervalSince1970: 1_777_220_200)
    )
    try repository.upsertSession(laterSession)
    let recentSessions = try repository.fetchRecentSessions(limit: 2)
    try check(recentSessions == [laterSession, multiPaperSession], "recent sessions should return newest sessions first with ordered paper IDs")
    let limitedRecentSessions = try repository.fetchRecentSessions(limit: 1)
    try check(limitedRecentSessions == [laterSession], "recent sessions should honor the requested limit")
    let categoryIDsByPaperID = try repository.fetchCategoryIDsByPaperID()
    let tagsByPaperID = try repository.fetchTagsByPaperID()
    let recentPapersBySessionID = try repository.fetchPapersBySessionID(for: recentSessions)
    try check(categoryIDsByPaperID == ["paper-a": ["cat-vae"]], "repository should batch-fetch category IDs grouped by paper")
    try check(tagsByPaperID == ["paper-a": [tag]], "repository should batch-fetch tags grouped by paper")
    try check(recentPapersBySessionID == [
        laterSession.id: [paper],
        multiPaperSession.id: [starredPaperB, paper]
    ], "repository should batch-fetch recent session papers without per-session paper queries")

    let legacyRoot = tempRoot.appendingPathComponent("PaperCodex", isDirectory: true)
    let repairedRoot = tempRoot.appendingPathComponent("Episteme", isDirectory: true)
    let legacyPDFPath = legacyRoot.appendingPathComponent("papers/paper-c/original.pdf").path
    let repairedPDFURL = repairedRoot.appendingPathComponent("papers/paper-c/original.pdf")
    try FileManager.default.createDirectory(
        at: repairedPDFURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("%PDF-1.4\n".utf8).write(to: repairedPDFURL)
    let legacyPathPaper = Paper(
        id: "paper-c",
        filePath: legacyPDFPath,
        fileHash: "hash-c",
        title: "Paper C",
        authors: [],
        year: nil,
        sourceURL: nil,
        importedAt: now,
        updatedAt: now
    )
    try repository.upsertPaper(legacyPathPaper)
    let repairedCount = try repository.repairPaperFilePaths(from: legacyRoot, to: repairedRoot)
    let repairedPaper = try repository.fetchPapers(ids: ["paper-c"]).first
    try check(repairedCount == 1, "repository should count repaired legacy support-root file paths")
    try check(repairedPaper?.filePath == repairedPDFURL.path, "repository should repair stale absolute PaperCodex paths after Episteme migration")

    var reorderedCategory = category
    reorderedCategory.sortOrder = 9
    try repository.upsertCategory(reorderedCategory)
    let reorderedCategories = try repository.fetchCategories()
    try check(
        reorderedCategories.first(where: { $0.id == "cat-methods" })?.sortOrder == 9,
        "category sort order updates should persist for drag reordering"
    )

    try repository.removePaper("paper-a", fromCategory: "cat-vae")
    try repository.removePaper("paper-a", fromTag: "tag-control")
    let removedCategoryIDs = try repository.fetchCategoryIDs(forPaperID: "paper-a")
    let removedTags = try repository.fetchTags(forPaperID: "paper-a")
    try check(removedCategoryIDs.isEmpty, "paper category links should be removable")
    try check(removedTags.isEmpty, "paper tag links should be removable")

    try repository.assignPaper("paper-a", toCategory: "cat-vae")
    try repository.assignPaper("paper-a", toTag: "tag-control")
    try repository.deletePapers(ids: ["paper-a", "missing-paper"])
    let papersAfterDelete = try repository.fetchPapers(ids: ["paper-a", "paper-b"])
    let deletedPaperCategoryIDs = try repository.fetchCategoryIDs(forPaperID: "paper-a")
    let deletedPaperTags = try repository.fetchTags(forPaperID: "paper-a")
    let sessionsAfterPaperDelete = try repository.fetchSessions(paperID: "paper-a")
    try check(papersAfterDelete == [starredPaperB], "repository should delete requested papers while preserving others")
    try check(deletedPaperCategoryIDs.isEmpty, "repository should remove category links for deleted papers")
    try check(deletedPaperTags.isEmpty, "repository should remove tag links for deleted papers")
    try check(sessionsAfterPaperDelete.isEmpty, "repository should remove session paper links for deleted papers")
}

func runLocalStoreV2MigrationChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-local-store-v2-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let repository = try PaperRepository(databasePath: tempRoot.appendingPathComponent("store.sqlite").path)
    try repository.migrate()

    let now = Date(timeIntervalSince1970: 1_777_300_000)
    let paper = Paper(
        id: "paper-a",
        filePath: tempRoot.appendingPathComponent("paper-a/original.pdf").path,
        fileHash: "hash-a",
        title: "Paper A",
        authors: ["Alice"],
        year: 2026,
        sourceURL: "https://arxiv.org/abs/2604.18586",
        importedAt: now,
        updatedAt: now
    )
    let versionedPaper = Paper(
        id: "paper-b",
        filePath: tempRoot.appendingPathComponent("paper-b/original.pdf").path,
        fileHash: "hash-b",
        title: "Paper B",
        authors: ["Bob"],
        year: 2026,
        sourceURL: "http://arxiv.org/pdf/2604.18587v2.pdf?download=1",
        isSaved: false,
        importedAt: now,
        updatedAt: now
    )
    try repository.upsertPaper(paper)
    try repository.upsertPaper(versionedPaper)
    try repository.upsertCategory(Category(id: "cat-methods", parentID: nil, name: "Methods", sortOrder: 1))
    try repository.upsertCategory(Category(id: "cat-vae", parentID: "cat-methods", name: "VAE", sortOrder: 2))
    try repository.upsertTag(PaperTag(id: "tag-diffusion", name: "Diffusion"))
    try repository.assignPaper("paper-a", toCategory: "cat-vae")
    try repository.assignPaper("paper-a", toTag: "tag-diffusion")

    let database = try SQLiteDatabase(path: tempRoot.appendingPathComponent("store.sqlite").path)
    let paperColumns = try database.tableColumns("papers")
    let paperMetadata = try database.query("SELECT id, canonical_key, source_kind, arxiv_id, arxiv_id_versioned FROM papers ORDER BY id;") { row in
        "\(try row.text(0))|\(try row.text(1))|\(try row.text(2))|\(row.optionalText(3) ?? "")|\(row.optionalText(4) ?? "")"
    }
    let folders = try database.query("SELECT id, parent_id, name FROM folders ORDER BY sort_order, name;") { row in
        "\(try row.text(0))|\(row.optionalText(1) ?? "")|\(try row.text(2))"
    }
    let folderCreatedAt = try database.query("SELECT created_at FROM paper_folders WHERE paper_id = ? AND folder_id = ?;", bindings: [.text("paper-a"), .text("cat-vae")]) { row in
        try row.text(0)
    }.first
    let fileRows = try database.query("SELECT paper_id, storage_state, local_path, content_hash FROM paper_files ORDER BY paper_id;") { row in
        "\(try row.text(0))|\(try row.text(1))|\(try row.text(2))|\(try row.text(3))"
    }
    let sources = try database.query("SELECT paper_id, source_type, source_id, version, url FROM paper_sources ORDER BY paper_id;") { row in
        "\(try row.text(0))|\(try row.text(1))|\(row.optionalText(2) ?? "")|\(row.optionalText(3) ?? "")|\(row.optionalText(4) ?? "")"
    }

    try check(paperColumns.contains("canonical_key"), "V2 migration should add canonical paper columns")
    try check(paperColumns.contains("is_starred"), "repository migration should add library star state to papers")
    try check(
        paperMetadata == [
            "paper-a|arxiv:2604.18586|arxiv|2604.18586|2604.18586",
            "paper-b|arxiv:2604.18587|arxiv|2604.18587|2604.18587v2"
        ],
        "V2 paper metadata should stay current after normal repository writes"
    )
    try check(folders == ["cat-methods||Methods", "cat-vae|cat-methods|VAE"], "V2 migration should backfill folders from categories")
    try check(folderCreatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } != nil, "V2 folder membership timestamps should be ISO8601 dates")
    try check(
        fileRows == [
            "paper-a|saved_local|\(paper.filePath)|hash-a",
            "paper-b|cache_preview|\(versionedPaper.filePath)|hash-b"
        ],
        "V2 migration should backfill paper file records"
    )
    try check(
        sources == [
            "paper-a|arxiv|2604.18586||https://arxiv.org/abs/2604.18586",
            "paper-b|arxiv|2604.18587|v2|http://arxiv.org/pdf/2604.18587v2.pdf?download=1"
        ],
        "V2 migration should backfill arXiv source records"
    )

    try repository.migrate()
    let fileRowsAfterRemigration = try database.query("SELECT paper_id, storage_state, local_path, content_hash FROM paper_files ORDER BY paper_id;") { row in
        "\(try row.text(0))|\(try row.text(1))|\(try row.text(2))|\(try row.text(3))"
    }
    try check(fileRowsAfterRemigration == fileRows, "V2 migration should be idempotent after live repository writes")
}

func runLibraryDataStoreChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-library-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let repository = try PaperRepository(databasePath: tempRoot.appendingPathComponent("store.sqlite").path)
    try repository.migrate()
    let database = try SQLiteDatabase(path: tempRoot.appendingPathComponent("store.sqlite").path)
    let store = LibraryDataStore(database: database)
    let now = Date(timeIntervalSince1970: 1_777_300_000)
    let deletedAt = Date(timeIntervalSince1970: 1_777_300_100)
    let reassignedAt = Date(timeIntervalSince1970: 1_777_300_200)

    let folder = LibraryFolder(id: "folder-root", parentID: nil, name: "Root", sortOrder: 0, deletedAt: nil, syncRevision: 1)
    let deletedFolder = LibraryFolder(id: "folder-deleted", parentID: nil, name: "Deleted", sortOrder: 1, deletedAt: deletedAt, syncRevision: 2)
    let tag = HierarchicalPaperTag(id: "tag-ai", parentID: nil, name: "AI", color: "#0A84FF", sortOrder: 0, deletedAt: nil, syncRevision: 1)
    let deletedTag = HierarchicalPaperTag(id: "tag-deleted", parentID: nil, name: "Deleted", color: "#FF3B30", sortOrder: 1, deletedAt: deletedAt, syncRevision: 2)
    let note = PaperNote(id: "note-a", paperID: "paper-a", anchorID: nil, title: "Idea", bodyMarkdown: "Use in intro.", createdAt: now, updatedAt: now, deletedAt: nil, syncRevision: 1)
    try store.upsertFolder(folder)
    try store.upsertFolder(deletedFolder)
    try store.upsertTag(tag)
    try store.upsertTag(deletedTag)
    try repository.upsertPaper(Paper(id: "paper-a", filePath: "/tmp/a.pdf", fileHash: "hash-a", title: "A", authors: [], year: nil, sourceURL: nil, importedAt: now, updatedAt: now))
    try store.assignPaper("paper-a", toFolder: "folder-root", at: now)
    try store.assignPaper("paper-a", toFolder: "folder-deleted", at: now)
    try store.assignPaper("paper-a", toTag: "tag-ai", at: now)
    try store.assignPaper("paper-a", toTag: "tag-deleted", at: now)
    try store.upsertNote(note)

    try database.run("""
    UPDATE paper_folders SET deleted_at = ? WHERE paper_id = ? AND folder_id = ?;
    """, bindings: [
        .text(ISO8601DateFormatter().string(from: deletedAt)),
        .text("paper-a"),
        .text("folder-root")
    ])
    let folderIDsAfterSoftDelete = try store.fetchFolderIDs(forPaperID: "paper-a")
    try check(folderIDsAfterSoftDelete.isEmpty, "LibraryDataStore should hide soft-deleted folder memberships")
    try store.assignPaper("paper-a", toFolder: "folder-root", at: reassignedAt)

    let tagMembershipCreatedAt = try database.query("""
    SELECT created_at FROM paper_tag_memberships WHERE paper_id = ? AND tag_id = ?;
    """, bindings: [.text("paper-a"), .text("tag-ai")]) { row in
        try row.text(0)
    }.first

    let fetchedFolders = try store.fetchFolders()
    let fetchedTags = try store.fetchTags()
    let fetchedFolderIDs = try store.fetchFolderIDs(forPaperID: "paper-a")
    let fetchedTagIDs = try store.fetchTagIDs(forPaperID: "paper-a")
    let fetchedNotes = try store.fetchNotes(paperID: "paper-a")
    let legacyFetchedTags = try repository.fetchTags(forPaperID: "paper-a")
    try check(fetchedFolders == [folder], "LibraryDataStore should round-trip folders")
    try check(fetchedTags == [tag], "LibraryDataStore should round-trip hierarchical tags")
    try check(fetchedFolderIDs == ["folder-root"], "LibraryDataStore should round-trip folder memberships")
    try check(fetchedTagIDs == ["tag-ai"], "LibraryDataStore should round-trip tag memberships")
    try check(fetchedNotes == [note], "LibraryDataStore should round-trip paper notes")
    try check(tagMembershipCreatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } == now, "LibraryDataStore should persist tag membership creation dates")
    try check(legacyFetchedTags.contains(PaperTag(id: "tag-ai", name: "AI")), "LibraryDataStore tag assignments should remain visible to legacy repository tag fetches")
}

func runArxivCacheDataStoreChecks() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-arxiv-cache-store-\(UUID().uuidString).sqlite")
    let repository = try PaperRepository(databasePath: databaseURL.path)
    try repository.migrate()
    let database = try SQLiteDatabase(path: databaseURL.path)
    let now = Date(timeIntervalSince1970: 1_777_300_000)
    let future = Date(timeInterval: 3_600, since: now)
    let past = Date(timeInterval: -3_600, since: now)
    let dates = ISO8601DateFormatter()
    let store = ArxivCacheDataStore(database: database, now: { now })

    let missingStatus = try store.feedCacheStatus(date: "2026-04-28")
    try check(!missingStatus.metadataCached, "arXiv cache store should report missing metadata cache")
    try check(missingStatus.cachedAssetCount == 0, "arXiv cache store should report zero assets for missing dates")
    try check(missingStatus.cachedPDFCount == 0, "arXiv cache store should report zero PDFs for missing dates")

    try store.upsertFeedDate(
        date: "2026-04-29",
        source: "codearxiv",
        feedVersion: "v1",
        filterSnapshotJSON: #"{"tags":[]}"#,
        cachedAt: now,
        expiresAt: nil
    )
    try database.run("""
    INSERT INTO arxiv_assets (
      asset_key, arxiv_id, date, kind, local_path, url, content_hash, byte_count, cached_at, last_accessed_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    """, bindings: [
        .text("asset:2604.18586:thumbnail"),
        .text("2604.18586"),
        .text("2026-04-29"),
        .text("thumbnail"),
        .text("/cache/2604.18586.png"),
        .text("https://example.test/2604.18586.png"),
        .text("hash-asset"),
        .int64(321),
        .text(dates.string(from: now)),
        .null
    ])
    try store.upsertPDFCache(
        arxivID: "2604.18586",
        date: "2026-04-29",
        localPath: "/cache/2604.18586.pdf",
        contentHash: "hash-pdf",
        byteCount: 123,
        cachedAt: now,
        lastAccessedAt: now,
        promotedPaperID: nil
    )
    let status = try store.feedCacheStatus(date: "2026-04-29")
    try check(status.metadataCached, "arXiv cache store should report metadata cache with nil expiry")
    try check(status.cachedAssetCount == 1, "arXiv cache store should count cached assets")
    try check(status.cachedPDFCount == 1, "arXiv cache store should count cached PDFs")

    try store.upsertFeedDate(
        date: "2026-04-30",
        source: "codearxiv",
        feedVersion: "v2",
        filterSnapshotJSON: #"{"tags":["ml"]}"#,
        cachedAt: now,
        expiresAt: future
    )
    try store.upsertFeedDate(
        date: "2026-05-01",
        source: "codearxiv",
        feedVersion: "v3",
        filterSnapshotJSON: nil,
        cachedAt: now,
        expiresAt: past
    )
    try store.upsertFeedDate(
        date: "2026-05-02",
        source: "codearxiv",
        feedVersion: nil,
        filterSnapshotJSON: nil,
        cachedAt: now,
        expiresAt: nil
    )
    try store.upsertFeedDate(
        date: "2026-05-03",
        source: "codearxiv",
        feedVersion: "v4",
        filterSnapshotJSON: nil,
        cachedAt: now,
        expiresAt: now
    )

    let futureStatus = try store.feedCacheStatus(date: "2026-04-30")
    let expiredStatus = try store.feedCacheStatus(date: "2026-05-01")
    let nullableFeedStatus = try store.feedCacheStatus(date: "2026-05-02")
    let equalExpiryStatus = try store.feedCacheStatus(date: "2026-05-03")
    try check(futureStatus.metadataCached, "arXiv cache store should report metadata cache with future expiry")
    try check(!expiredStatus.metadataCached, "arXiv cache store should ignore expired metadata cache")
    try check(nullableFeedStatus.metadataCached, "arXiv cache store should accept nullable feed metadata fields")
    try check(!equalExpiryStatus.metadataCached, "arXiv cache store should require expiry to be strictly later than now")

    try store.upsertPDFCache(
        arxivID: "2604.18586",
        date: "2026-04-30",
        localPath: "/cache/2604.18586-v2.pdf",
        contentHash: "hash-pdf-updated",
        byteCount: 456,
        cachedAt: now,
        lastAccessedAt: nil,
        promotedPaperID: nil
    )
    try store.upsertPDFCache(
        arxivID: "2604.18587",
        date: "2026-05-02",
        localPath: "/cache/2604.18587.pdf",
        contentHash: nil,
        byteCount: nil,
        cachedAt: now,
        lastAccessedAt: nil,
        promotedPaperID: nil
    )

    let oldDateStatus = try store.feedCacheStatus(date: "2026-04-29")
    let updatedDateStatus = try store.feedCacheStatus(date: "2026-04-30")
    let nullablePDFStatus = try store.feedCacheStatus(date: "2026-05-02")
    let updatedPDFRows = try database.query("""
    SELECT date, local_path, content_hash, byte_count, last_accessed_at, promoted_paper_id
    FROM arxiv_pdf_cache
    WHERE arxiv_id = ?;
    """, bindings: [.text("2604.18586")]) { row in
        "\(try row.text(0))|\(try row.text(1))|\(row.optionalText(2) ?? "")|\(row.optionalInt(3).map(String.init) ?? "")|\(row.optionalText(4) ?? "")|\(row.optionalText(5) ?? "")"
    }
    let nullablePDFRows = try database.query("""
    SELECT content_hash, byte_count, last_accessed_at, promoted_paper_id
    FROM arxiv_pdf_cache
    WHERE arxiv_id = ?;
    """, bindings: [.text("2604.18587")]) { row in
        "\(row.optionalText(0) ?? "")|\(row.optionalInt(1).map(String.init) ?? "")|\(row.optionalText(2) ?? "")|\(row.optionalText(3) ?? "")"
    }

    try check(oldDateStatus.cachedPDFCount == 0, "arXiv cache store should move updated PDFs away from old feed dates")
    try check(updatedDateStatus.cachedPDFCount == 1, "arXiv cache store should count updated PDFs under the latest feed date")
    try check(
        updatedPDFRows == ["2026-04-30|/cache/2604.18586-v2.pdf|hash-pdf-updated|456||"],
        "arXiv cache store should update cached PDF path, hash, and byte count"
    )
    try check(nullablePDFStatus.cachedPDFCount == 1, "arXiv cache store should count PDF caches with nullable fields")
    try check(nullablePDFRows == ["|||"], "arXiv cache store should persist nullable PDF cache fields")
}

func runSyncDataStoreChecks() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-sync-store-\(UUID().uuidString).sqlite")
    let repository = try PaperRepository(databasePath: databaseURL.path)
    try repository.migrate()
    let database = try SQLiteDatabase(path: databaseURL.path)
    let syncEntityColumns = try database.tableColumns("sync_entities")
    let store = SyncDataStore(database: database)
    let dates = ISO8601DateFormatter()
    let now = Date(timeIntervalSince1970: 1_777_300_000)
    let retryAt = Date(timeIntervalSince1970: 1_777_300_060)
    let tombstoneAt = Date(timeIntervalSince1970: 1_777_300_500)

    try check(syncEntityColumns.contains("local_updated_at"), "V2 migration should create sync entity local update timestamps")
    try store.markDirty(entityType: "paper", entityID: "paper-a", localRevision: 2, deleted: false, at: now)
    try store.markDirty(entityType: "paper", entityID: "paper-a", localRevision: 5, deleted: true, at: tombstoneAt)
    try store.markDirty(entityType: "paper", entityID: "paper-a", localRevision: 3, deleted: false, at: now)
    try store.enqueue(
        id: "change-a",
        entityType: "paper",
        entityID: "paper-a",
        operation: "upsert",
        payloadJSON: #"{"id":"paper-a"}"#,
        baseRemoteRevision: nil,
        createdAt: now
    )
    try store.enqueue(
        id: "change-a",
        entityType: "paper",
        entityID: "paper-a",
        operation: "upsert",
        payloadJSON: #"{"id":"paper-a"}"#,
        baseRemoteRevision: nil,
        createdAt: retryAt
    )
    var conflictingDuplicateError: String?
    do {
        try store.enqueue(
            id: "change-a",
            entityType: "paper",
            entityID: "paper-a",
            operation: "delete",
            payloadJSON: #"{"id":"paper-a","deleted":true}"#,
            baseRemoteRevision: 4,
            createdAt: now
        )
    } catch {
        conflictingDuplicateError = String(describing: error)
    }
    var conflictingEntityError: String?
    do {
        try store.enqueue(
            id: "change-a",
            entityType: "paper",
            entityID: "paper-b",
            operation: "upsert",
            payloadJSON: #"{"id":"paper-a"}"#,
            baseRemoteRevision: nil,
            createdAt: now
        )
    } catch {
        conflictingEntityError = String(describing: error)
    }
    try store.setCursor(scope: "library", cursor: "cursor-1", updatedAt: now)

    let dirtyEntityIDs = try store.fetchDirtyEntityIDs(entityType: "paper")
    let pendingOutboxIDs = try store.fetchPendingOutboxIDs()
    let cursor = try store.fetchCursor(scope: "library")
    let syncEntityRows = try database.query("""
    SELECT local_revision, deleted, local_updated_at
    FROM sync_entities
    WHERE entity_type = ? AND entity_id = ?;
    """, bindings: [.text("paper"), .text("paper-a")]) { row in
        "\(row.int(0))|\(row.int(1))|\(try row.text(2))"
    }
    let outboxCount = try database.query("""
    SELECT COUNT(*)
    FROM sync_outbox
    WHERE id = ?;
    """, bindings: [.text("change-a")]) { row in
        row.int(0)
    }.first
    let outboxCreatedAt = try database.query("""
    SELECT created_at
    FROM sync_outbox
    WHERE id = ?;
    """, bindings: [.text("change-a")]) { row in
        try row.text(0)
    }.first

    try check(dirtyEntityIDs == ["paper-a"], "SyncDataStore should track dirty entities")
    try check(syncEntityRows == ["5|1|\(dates.string(from: tombstoneAt))"], "SyncDataStore should preserve max dirty revision, tombstone, and update timestamp")
    try check(pendingOutboxIDs == ["change-a"], "SyncDataStore should track pending outbox changes")
    try check(outboxCount == 1, "SyncDataStore should treat exact duplicate outbox IDs as idempotent")
    try check(outboxCreatedAt == dates.string(from: now), "SyncDataStore should keep the original outbox creation date")
    try check(conflictingDuplicateError?.contains("change-a") == true, "SyncDataStore should reject conflicting duplicate outbox IDs")
    try check(conflictingEntityError?.contains("change-a") == true, "SyncDataStore should reject duplicate outbox IDs with different entities")
    try check(cursor == "cursor-1", "SyncDataStore should persist cursors")
}

func runSQLiteHelperChecks() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-sqlite-helpers-\(UUID().uuidString).sqlite")
    do {
        let database = try SQLiteDatabase(path: databaseURL.path)
        try database.transaction {
            try database.execute("CREATE TABLE sample (id TEXT PRIMARY KEY, value TEXT);")
            try database.run("INSERT INTO sample (id, value) VALUES (?, ?);", bindings: [.text("a"), .text("one")])
        }

        let columns = try database.tableColumns("sample")
        let values = try database.query("SELECT value FROM sample WHERE id = ?;", bindings: [.text("a")]) { row in
            try row.text(0)
        }

        try check(columns == Set(["id", "value"]), "SQLite tableColumns should read table schema")
        try check(values == ["one"], "SQLite transaction should commit successful work")
    }

    let reader = try SQLiteDatabase(path: databaseURL.path)
    let busyTimeouts = try reader.query("PRAGMA busy_timeout;") { row in
        row.int(0)
    }
    let journalModes = try reader.query("PRAGMA journal_mode;") { row in
        try row.text(0)
    }
    let lockAcquired = DispatchSemaphore(value: 0)
    let releaseLock = DispatchSemaphore(value: 0)
    let lockFinished = DispatchSemaphore(value: 0)
    let lockError = LockedStringBox()

    Thread.detachNewThread {
        do {
            let lockHolder = try SQLiteDatabase(path: databaseURL.path)
            try lockHolder.execute("BEGIN EXCLUSIVE TRANSACTION;")
            lockAcquired.signal()
            _ = releaseLock.wait(timeout: .now() + 2)
            try lockHolder.execute("COMMIT;")
        } catch {
            let message = String(describing: error)
            lockError.set(message)
            lockAcquired.signal()
        }
        lockFinished.signal()
    }

    try check(lockAcquired.wait(timeout: .now() + 2) == .success, "SQLite lock holder should acquire the transient exclusive lock")
    try check(lockError.get() == nil, "SQLite lock holder should acquire the transient exclusive lock without error")
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
        releaseLock.signal()
    }
    let valuesAfterTransientLock = try reader.query("SELECT value FROM sample WHERE id = ?;", bindings: [.text("a")]) { row in
        try row.text(0)
    }

    try check((busyTimeouts.first ?? 0) >= 5_000, "SQLite connections should wait for transient busy locks")
    try check(journalModes.first?.lowercased() == "wal", "SQLite file databases should use WAL so readers are not blocked by writers")
    try check(valuesAfterTransientLock == ["one"], "SQLite readers should survive a transient lock from another connection")
    try check(lockFinished.wait(timeout: .now() + 2) == .success, "SQLite lock holder should release the transient exclusive lock")
    try check(lockError.get() == nil, "SQLite lock holder should release the transient exclusive lock without error")
}

func runCitationChecks() throws {
    let parsed = CitationParser.parse("Answer [[cite:paper:paper-a:p5:b17]] and [[cite:paper:paper-a:p5:asel1]].")
    try check(parsed.citations.map(\.id) == ["paper:paper-a:p5:b17", "paper:paper-a:p5:asel1"], "citation parser should preserve citation IDs")
    try check(parsed.displayText == "Answer [1] and [2].", "citation parser should replace markers with display indices")
    try check(parsed.displayMarkdown.contains("[1](papercodex-cite://open?id=paper%3Apaper-a%3Ap5%3Ab17)"), "citation parser should produce inline clickable markdown links")
    try check(parsed.displayMarkdown.contains("[2](papercodex-cite://open?id=paper%3Apaper-a%3Ap5%3Aasel1)"), "citation parser should keep anchor citations clickable inline")

    let manyCitations = CitationParser.parse(
        "A [[cite:paper:paper-a:p1:b1]] B [[cite:paper:paper-a:p1:b2]] C [[cite:paper:paper-a:p1:b3]] D [[cite:paper:paper-a:p1:b4]]",
        maxVisibleCitations: 3
    )
    try check(manyCitations.citations.map(\.displayIndex) == [1, 2, 3], "citation parser should cap visible citations")
    try check(!manyCitations.displayMarkdown.contains("p1%3Ab4"), "citation parser should omit citation links above the visible cap")
    try check(manyCitations.displayText == "A [1] B [2] C [3] D ", "citation parser should remove extra citation markers from display text")
    try check(
        CitationParser.baseSpanCitationID(for: "paper:paper-a:p1:b17s2") == "paper:paper-a:p1:b17",
        "split citation aliases should resolve to their original span citation"
    )

    let malformed = CitationParser.parse("Broken [[cite:not-a-paper]] marker.")
    try check(malformed.citations.isEmpty, "malformed markers should not become citations")
    try check(malformed.brokenMarkers == ["[[cite:not-a-paper]]"], "malformed markers should be reported")

    let rendered = ChatMarkdownRenderer.renderDocument(
        markdown: "## Result\n\nValue $x^2$.\n\n![figure](/tmp/figure.png)\n\n\(parsed.displayMarkdown)"
    )
    try check(
        rendered.contains("renderMathInElement")
            && rendered.contains("throwOnError: false")
            && rendered.contains("strict: 'ignore'")
            && rendered.contains(".katex-display")
            && rendered.contains("html, body, .message")
            && rendered.contains("width: 100%;")
            && rendered.contains("box-sizing: border-box"),
        "markdown renderer should harden formula display so bad TeX does not break the whole message"
    )
    try check(
        rendered.contains("KaTeX/katex.min.css")
            && rendered.contains("KaTeX/katex.min.js")
            && rendered.contains("KaTeX/contrib/auto-render.min.js")
            && rendered.contains("renderMathInElement")
            && !rendered.contains("cdn.jsdelivr.net"),
        "markdown renderer should use bundled math assets instead of a remote CDN"
    )
    try check(rendered.contains("<h2>Result</h2>"), "markdown renderer should render markdown headings")
    try check(rendered.contains(#"<img alt="figure" src="file:///tmp/figure.png">"#), "markdown renderer should render absolute local images")
    try check(rendered.contains(#"href="papercodex-cite://open?id=paper%3Apaper-a%3Ap5%3Ab17""#), "markdown renderer should preserve clickable citation links")

    let styledRendered = ChatMarkdownRenderer.renderDocument(
        markdown: "Value $E=mc^2$.",
        style: ChatMarkdownRenderStyle(fontSize: 18, fontFamily: "ui-rounded, sans-serif")
    )
    try check(
        styledRendered.contains("font-size: 18px")
            && styledRendered.contains("font-family: ui-rounded, sans-serif"),
        "markdown renderer should accept Reader Chat font settings for formula-bearing messages"
    )

    let inlineMathBeforeCitation = ChatMarkdownRenderer.renderFragment(
        markdown: #"归一化到 $[0,1]$ 后的“好样本概率”。 [1](papercodex-cite://open?id=paper%3Apaper-a%3Ap5%3Ab17)"#
    )
    try check(
        inlineMathBeforeCitation.contains(#"归一化到 $[0,1]$ 后的“好样本概率”。 <a class="citation" href="papercodex-cite://open?id=paper%3Apaper-a%3Ap5%3Ab17">1</a>"#),
        "markdown renderer should not treat math brackets before a citation as the citation link label"
    )

    let listTypeSwitch = ChatMarkdownRenderer.renderFragment(markdown: "1. Keep ordered\n- Keep unordered")
    try check(
        listTypeSwitch.contains("<ol><li>Keep ordered</li></ol>")
            && listTypeSwitch.contains("<ul><li>Keep unordered</li></ul>"),
        "markdown renderer should not drop list items when ordered and unordered lists are adjacent"
    )

    let tableWithConditionalMath = ChatMarkdownRenderer.renderFragment(
        markdown: """
        | Formula | Meaning |
        | --- | --- |
        | $p(o = 1|x_0,c)$ | normalized probability |
        """
    )
    try check(
        tableWithConditionalMath.contains("<td>$p(o = 1|x_0,c)$</td><td>normalized probability</td>"),
        "markdown renderer should not split table cells on pipes inside inline math"
    )

    let parenthesizedDestinations = ChatMarkdownRenderer.renderFragment(
        markdown: "[appendix](https://example.test/a_(b)) and ![figure](/tmp/a_(b).png)"
    )
    try check(
        parenthesizedDestinations.contains(#"href="https://example.test/a_(b)""#)
            && parenthesizedDestinations.contains(#"src="file:///tmp/a_(b).png""#),
        "markdown renderer should keep balanced parentheses inside link and image destinations"
    )

    let nestedBracketLabel = ChatMarkdownRenderer.renderFragment(
        markdown: "[Appendix [A]](https://example.test/appendix)"
    )
    try check(
        nestedBracketLabel.contains(#"<a href="https://example.test/appendix">Appendix [A]</a>"#),
        "markdown renderer should keep nested brackets inside link labels"
    )

    let inlineBracketDisplayMath = ChatMarkdownRenderer.renderFragment(
        markdown: #"用 \[[1-\alpha(x_t)](v_{old}-v^-)\] 表示更新。 [1](papercodex-cite://open?id=paper%3Apaper-a%3Ap5%3Ab17)"#
    )
    try check(
        inlineBracketDisplayMath.contains(#"\[[1-\alpha(x_t)](v_{old}-v^-)\]"#)
            && !inlineBracketDisplayMath.contains(#"href="v_{old}-v^-""#),
        "markdown renderer should not parse links inside bracket-delimited math"
    )

    let inlineDoubleDollarMath = ChatMarkdownRenderer.renderFragment(
        markdown: #"Agent uses $$[1-\alpha(x_t)](v_{old}-v^-)$$ inline."#
    )
    try check(
        inlineDoubleDollarMath.contains(#"\([1-\alpha(x_t)](v_{old}-v^-)\)"#)
            && !inlineDoubleDollarMath.contains(#"href="v_{old}-v^-""#),
        "markdown renderer should normalize inline double-dollar math before parsing markdown links"
    )

    try check(
        rendered.contains("setTimeout(function() { renderMath(); reportHeight(); }, 250);"),
        "markdown renderer should report height after the local math renderer finishes typesetting"
    )

    let displayMath = """
    $$
    \\Delta
    =
    [1-\\alpha(x_t)](v_{old}-v^-)
    =
    \\alpha(x_t)(v^+-v_{old})
    $$
    """
    let renderedDisplayMath = ChatMarkdownRenderer.renderFragment(markdown: displayMath)
    try check(renderedDisplayMath.contains(#"class="math-display""#), "markdown renderer should keep display math as its own block")
    try check(!renderedDisplayMath.contains("<a"), "markdown renderer should not parse links inside display math")
    try check(renderedDisplayMath.contains(#"[1-\alpha(x_t)](v_{old}-v^-)"#), "markdown renderer should preserve TeX link-like syntax inside display math")
}

func runUserSourceAttachmentChecks() throws {
    let message = """
    Compare this with the method section.

    [selected source]
    anchor_id: paper:paper-a:p3:aselection
    paper_id: paper-a
    page: 3
    text: "The selected paragraph explains the training objective."
    nearby_spans: paper:paper-a:p3:b9
    before: "Previous paragraph."
    after: "Next paragraph."
    """

    let parsed = UserSourceAttachmentParser.parse(message)
    try check(parsed.visibleContent == "Compare this with the method section.", "user source attachment parser should hide selected-source metadata from chat display")
    try check(parsed.attachment?.anchorID == "paper:paper-a:p3:aselection", "user source attachment should keep its anchor citation ID")
    try check(parsed.attachment?.paperID == "paper-a", "user source attachment should keep the selected paper ID")
    try check(parsed.attachment?.page == 3, "user source attachment should keep the selected page")
    try check(parsed.attachment?.selectedText == "The selected paragraph explains the training objective.", "user source attachment should keep the selected text")

    let plain = UserSourceAttachmentParser.parse("No attached source.")
    try check(plain.visibleContent == "No attached source.", "plain user messages should remain unchanged")
    try check(plain.attachment == nil, "plain user messages should not create source attachments")
}

func runAnchorResolverChecks() throws {
    let before = Span(
        id: Span.makeID(paperID: "paper-a", page: 2, blockIndex: 1),
        paperID: "paper-a",
        page: 2,
        bbox: BoundingBox(x: 20, y: 720, width: 300, height: 20),
        text: "Before context explains the setup.",
        charRange: TextRange(location: 0, length: 34),
        sectionHint: nil,
        confidence: 0.95
    )
    let target = Span(
        id: Span.makeID(paperID: "paper-a", page: 2, blockIndex: 2),
        paperID: "paper-a",
        page: 2,
        bbox: BoundingBox(x: 20, y: 690, width: 360, height: 22),
        text: "The selected mechanism controls latent trajectories.",
        charRange: TextRange(location: 35, length: 52),
        sectionHint: nil,
        confidence: 0.95
    )
    let after = Span(
        id: Span.makeID(paperID: "paper-a", page: 2, blockIndex: 3),
        paperID: "paper-a",
        page: 2,
        bbox: BoundingBox(x: 20, y: 660, width: 300, height: 20),
        text: "After context describes the consequence.",
        charRange: TextRange(location: 88, length: 39),
        sectionHint: nil,
        confidence: 0.95
    )
    let otherPage = Span(
        id: Span.makeID(paperID: "paper-a", page: 3, blockIndex: 1),
        paperID: "paper-a",
        page: 3,
        bbox: BoundingBox(x: 20, y: 690, width: 360, height: 22),
        text: "A different page should not be matched.",
        charRange: TextRange(location: 0, length: 39),
        sectionHint: nil,
        confidence: 0.95
    )

    guard let anchor = AnchorResolver().resolve(
        paperID: "paper-a",
        page: 2,
        selectedText: "controls latent trajectories",
        bboxList: [BoundingBox(x: 40, y: 686, width: 220, height: 28)],
        spans: [before, target, after, otherPage],
        anchorID: Anchor.makeID(paperID: "paper-a", page: 2, suffix: "sel1"),
        sessionID: "session-a",
        createdAt: Date(timeIntervalSince1970: 1_777_220_000)
    ) else {
        throw CheckFailure(description: "anchor resolver should return an anchor for a matched selection")
    }

    try check(anchor.matchedSpanIDs == [target.id], "anchor resolver should match the selected page span")
    try check(anchor.beforeContext == before.text, "anchor resolver should include preceding span context")
    try check(anchor.afterContext == after.text, "anchor resolver should include following span context")
    try check(anchor.confidence > 0.8, "anchor resolver should assign high confidence for text and bbox matches")

    let unmatchedAnchor = AnchorResolver().resolve(
        paperID: "paper-a",
        page: 2,
        selectedText: "unrelated words from a different document",
        bboxList: [BoundingBox(x: 500, y: 120, width: 40, height: 18)],
        spans: [before, target, after, otherPage],
        anchorID: Anchor.makeID(paperID: "paper-a", page: 2, suffix: "missing"),
        sessionID: "session-a",
        createdAt: Date(timeIntervalSince1970: 1_777_220_000)
    )
    try check(unmatchedAnchor == nil, "anchor resolver should not create a fake anchor when matching fails")
}

func runPromptChecks() throws {
    let now = Date(timeIntervalSince1970: 1_777_220_000)
    let paper = Paper(
        id: "paper-a",
        filePath: "/tmp/paper.pdf",
        fileHash: "hash-a",
        title: "Paper A",
        authors: ["Alice"],
        year: 2026,
        sourceURL: "https://example.com/paper",
        importedAt: now,
        updatedAt: now
    )
    let span = Span(
        id: Span.makeID(paperID: "paper-a", page: 5, blockIndex: 17),
        paperID: "paper-a",
        page: 5,
        bbox: BoundingBox(x: 1, y: 2, width: 3, height: 4),
        text: "This curated span should stay in workspace files instead of being inlined.",
        charRange: TextRange(location: 0, length: 52),
        sectionHint: "Method",
        confidence: 0.9
    )
    let anchor = Anchor(
        id: Anchor.makeID(paperID: "paper-a", page: 5, suffix: "sel1"),
        paperID: "paper-a",
        page: 5,
        selectedText: "controls latent trajectories",
        bboxList: [span.bbox],
        matchedSpanIDs: [span.id],
        beforeContext: "The selected mechanism",
        afterContext: "with a decoder.",
        createdSessionID: "session-a",
        createdAt: now,
        confidence: 0.87
    )
    let prompt = PromptBuilder().buildPrompt(
        request: PromptRequest(
            userMessage: "Compare this selection with Paper B.",
            workspacePath: "/tmp/session-a",
            papers: [paper],
            selectedAnchors: [anchor],
            relevantSpans: [span]
        )
    )

    try check(prompt.contains("Compare this selection with Paper B."), "prompt should include the user message")
    try check(prompt.contains("Global language preference: Automatic"), "prompt should include the default automatic language preference")
    try check(PaperCodexLanguageMode.chinese.discoverLanguageCode == "zh", "Chinese language mode should prefer Chinese discover metadata")
    try check(PaperCodexLanguageMode.english.discoverLanguageCode == "en", "English language mode should prefer English discover metadata")
    try check(PaperCodexLanguageMode.automatic.metadataLanguageCode == "en", "automatic language mode should preserve English library metadata by default")
    try check(prompt.contains("anchor_id: paper:paper-a:p5:asel1"), "prompt should include selected anchor ID")
    try check(prompt.contains("workspace: /tmp/session-a"), "prompt should include workspace guidance")
    try check(prompt.contains("original_pdf: /tmp/session-a/papers/paper-a/original.pdf"), "prompt should point Codex at the workspace PDF copy")
    try check(prompt.contains("full_text: /tmp/session-a/papers/paper-a/full_text.txt"), "prompt should point Codex at the full text workspace file")
    try check(prompt.contains("spans_jsonl: /tmp/session-a/papers/paper-a/spans.jsonl"), "prompt should point Codex at the full span index")
    try check(prompt.contains("[[cite:paper:{paper_id}:p{page}:b{block_index}]]"), "prompt should include citation contract")
    try check(prompt.contains("Use citations sparingly"), "prompt should ask Codex to keep citation count low")
    try check(prompt.contains("at most three citation markers"), "prompt should hard-limit normal citation count")
    try check(prompt.contains("research trends"), "default system prompt should cover broader research trend analysis")
    try check(prompt.contains("broader research landscape"), "default system prompt should connect papers to the wider research landscape")
    try check(prompt.contains("Match the user's language"), "default system prompt should require language matching")
    try check(prompt.contains("Do not begin with praise"), "default system prompt should prevent generic praise openings")
    try check(prompt.contains("Do not invent paper links"), "default system prompt should forbid fabricated paper links")
    try check(prompt.contains("Use `$...$` for inline math"), "default system prompt should specify render-safe LaTeX conventions")
    try check(!prompt.localizedCaseInsensitiveContains("alphaxiv"), "default system prompt should not retain alphaXiv-specific product instructions")
    try check(!prompt.contains("<alphaxiv"), "default system prompt should not emit alphaXiv-specific XML tags")
    try check(!prompt.contains("[relevant span]"), "prompt should not inline a limited curated span list")
    try check(!prompt.contains("This curated span should stay in workspace files"), "prompt should make Codex inspect workspace files instead of reading a narrowed prompt excerpt")

    try check(PromptBuilder.defaultSystemPrompt.contains("{{workspace_path}}"), "default Codex system prompt should be editable as a workspace-aware template")
    let customPrompt = PromptBuilder().buildPrompt(
        request: PromptRequest(
            userMessage: "Explain Figure 2.",
            workspacePath: "/tmp/custom-session",
            papers: [paper],
            selectedAnchors: [],
            relevantSpans: [],
            systemPromptTemplate: "CUSTOM CODEX SYSTEM\nworkspace: {{workspace_path}}\nAnswer in Chinese."
        )
    )
    try check(customPrompt.hasPrefix("CUSTOM CODEX SYSTEM"), "custom Codex system prompt should replace the built-in default")
    try check(customPrompt.contains("workspace: /tmp/custom-session"), "custom Codex system prompt should render the workspace placeholder")
    try check(!customPrompt.contains("Use citations sparingly"), "custom Codex system prompt should not silently append the default instructions")
    let englishPrompt = PromptBuilder().buildPrompt(
        request: PromptRequest(
            userMessage: "Explain Figure 2.",
            workspacePath: "/tmp/custom-session",
            papers: [paper],
            selectedAnchors: [],
            relevantSpans: [],
            languageMode: .english
        )
    )
    try check(englishPrompt.contains("Global language preference: English"), "prompt should include the English global language preference")
    try check(englishPrompt.contains("Answer in English by default"), "English language mode should ask Codex to answer in English")
    try check(englishPrompt.contains("[global language]"), "English prompt should keep English section labels")
    let chinesePrompt = PromptBuilder().buildPrompt(
        request: PromptRequest(
            userMessage: "Explain Figure 2.",
            workspacePath: "/tmp/custom-session",
            papers: [paper],
            selectedAnchors: [],
            relevantSpans: [],
            languageMode: .chinese
        )
    )
    try check(chinesePrompt.contains("你是 Episteme 中的 Codex"), "Chinese language mode should switch the full system prompt to Chinese")
    try check(chinesePrompt.contains("全局语言偏好：中文"), "prompt should include the Chinese global language preference")
    try check(chinesePrompt.contains("[全局语言]"), "Chinese prompt should switch prompt section labels to Chinese")
    try check(!chinesePrompt.contains("[global language]"), "Chinese prompt should not keep English-only language section labels")
    try check(!chinesePrompt.contains("Response style:"), "Chinese language mode should not keep the English built-in system prompt")
}

func runWorkspaceChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-workspace-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let sourcePDF = tempRoot.appendingPathComponent("source.pdf")
    try writeFixturePDF(to: sourcePDF, lines: ["Page text"])
    let workspaceRoot = tempRoot.appendingPathComponent("workspace", isDirectory: true)
    let now = Date(timeIntervalSince1970: 1_777_220_000)
    let paper = Paper(
        id: "paper-a",
        filePath: sourcePDF.path,
        fileHash: "hash-a",
        title: "Paper A",
        authors: ["Alice"],
        year: 2026,
        sourceURL: nil,
        importedAt: now,
        updatedAt: now
    )
    let session = PaperSession(
        id: "session-a",
        title: "Mechanism Notes",
        paperIDs: ["paper-a"],
        codexSessionID: nil,
        workspacePath: workspaceRoot.path,
        createdAt: now,
        updatedAt: now
    )
    let page = PageIndex(paperID: "paper-a", page: 1, text: "Page text", confidence: 0.95)
    let span = Span(
        id: Span.makeID(paperID: "paper-a", page: 1, blockIndex: 1),
        paperID: "paper-a",
        page: 1,
        bbox: BoundingBox(x: 1, y: 2, width: 3, height: 4),
        text: "Page text continues",
        charRange: TextRange(location: 0, length: 9),
        sectionHint: nil,
        confidence: 0.95
    )
    let wrappedSpan = Span(
        id: Span.makeID(paperID: "paper-a", page: 1, blockIndex: 2),
        paperID: "paper-a",
        page: 1,
        bbox: BoundingBox(x: 1, y: 20, width: 5, height: 4),
        text: "onto the next visual line.",
        charRange: TextRange(location: 20, length: 26),
        sectionHint: nil,
        confidence: 0.95
    )
    let anchor = Anchor(
        id: Anchor.makeID(paperID: "paper-a", page: 1, suffix: "sel1"),
        paperID: "paper-a",
        page: 1,
        selectedText: "Page text",
        bboxList: [span.bbox],
        matchedSpanIDs: [span.id],
        beforeContext: "",
        afterContext: "",
        createdSessionID: "session-a",
        createdAt: now,
        confidence: 0.95
    )

    let mcpEndpoint = PaperCodexMCPEndpoint(
        url: "http://127.0.0.1:39427/mcp",
        healthURL: "http://127.0.0.1:39427/health",
        host: "127.0.0.1",
        port: 39427,
        token: "secret-token",
        authorizationHeader: "Bearer secret-token",
        metadataPath: "/tmp/PaperCodex/mcp/server.json"
    )
    try SessionWorkspaceManager().writeWorkspace(
        session: session,
        papers: [paper],
        pagesByPaperID: ["paper-a": [page]],
        spansByPaperID: ["paper-a": [span, wrappedSpan]],
        anchorsByPaperID: ["paper-a": [anchor]],
        mcpEndpoint: mcpEndpoint,
        materializationMode: .copyPDF
    )

    let paperDir = workspaceRoot.appendingPathComponent("papers/paper-a", isDirectory: true)
    try check(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("session.json").path), "workspace should contain session.json")
    try check(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("prompt_contract.md").path), "workspace should contain prompt contract")
    try check(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("agent_instructions.md").path), "workspace should contain runtime-neutral agent instructions")
    try check(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("AGENTS.md").path), "workspace should contain AGENTS.md for local agents")
    try check(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("CLAUDE.md").path), "workspace should contain CLAUDE.md for Claude Code")
    try check(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("skills/papercodex-agent-workspace/SKILL.md").path), "workspace should contain the Paper Codex agent workspace skill")
    try check(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("mcp.json").path), "workspace should contain an MCP config when endpoint metadata is available")
    try check(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("workspace_manifest.json").path), "workspace should contain an agent workspace manifest")
    try check(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("turns", isDirectory: true).path), "workspace should contain turns directory")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("metadata.json").path), "workspace should contain paper metadata")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("original.pdf").path), "workspace should contain a readable copy of the original PDF")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("full_text.txt").path), "workspace should contain full extracted text with citations")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("pages.jsonl").path), "workspace should contain pages jsonl")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("spans.jsonl").path), "workspace should contain spans jsonl")
    try check(FileManager.default.fileExists(atPath: paperDir.appendingPathComponent("anchors.jsonl").path), "workspace should contain anchors jsonl")

    let spans = try String(contentsOf: paperDir.appendingPathComponent("spans.jsonl"), encoding: .utf8)
    try check(spans.contains("paper:paper-a:p1:b1"), "spans jsonl should include span ID")
    try check(spans.split(separator: "\n").count == 1, "workspace spans should compact wrapped visual lines into one citation block")
    try check(spans.contains("Page text continues onto the next visual line."), "compacted workspace span should contain merged visual-line text")
    let fullText = try String(contentsOf: paperDir.appendingPathComponent("full_text.txt"), encoding: .utf8)
    try check(fullText.contains("original_pdf: \(paperDir.appendingPathComponent("original.pdf").path)"), "full text should point to the local workspace PDF copy")
    try check(fullText.contains("[[cite:paper:paper-a:p1:b1]] Page text continues onto the next visual line."), "full text should include compacted extracted spans with exact citation markers")

    let manifestData = try Data(contentsOf: workspaceRoot.appendingPathComponent("workspace_manifest.json"))
    let manifest = try JSONDecoder().decode(AgentWorkspaceManifest.self, from: manifestData)
    try check(manifest.sessionID == session.id, "workspace manifest should record the session id")
    try check(manifest.materializationMode == .copyPDF, "workspace manifest should record copy materialization by default")
    try check(manifest.mcpConfigPath == workspaceRoot.appendingPathComponent("mcp.json").path, "workspace manifest should link to the MCP config")
    try check(manifest.papers.first?.paperID == paper.id, "workspace manifest should list the paper")
    try check(manifest.papers.first?.fullTextPath == paperDir.appendingPathComponent("full_text.txt").path, "workspace manifest should link to full text")

    let instructions = try String(contentsOf: workspaceRoot.appendingPathComponent("agent_instructions.md"), encoding: .utf8)
    try check(instructions.contains("Use Episteme MCP for library, tag, folder, note, and app navigation actions."), "agent instructions should route app operations through MCP")
    try check(instructions.contains("[[cite:paper:{paper_id}:p{page}:b{block_index}]]"), "agent instructions should include the citation contract")
    let workspaceSkill = try String(contentsOf: workspaceRoot.appendingPathComponent("skills/papercodex-agent-workspace/SKILL.md"), encoding: .utf8)
    try check(workspaceSkill.contains("Use MCP tools for app state changes"), "workspace skill should route app mutations through MCP")
    try check(workspaceSkill.contains("[[cite:paper:{paper_id}:p{page}:b{block_index}]]"), "workspace skill should include exact citation markers")

    let mcpConfigData = try Data(contentsOf: workspaceRoot.appendingPathComponent("mcp.json"))
    guard let mcpConfig = try JSONSerialization.jsonObject(with: mcpConfigData) as? [String: Any],
          let mcpServers = mcpConfig["mcpServers"] as? [String: Any],
          let paperCodexServer = mcpServers["paper-codex"] as? [String: Any],
          let headers = paperCodexServer["headers"] as? [String: Any] else {
        throw CheckFailure(description: "workspace MCP config should include a Paper Codex server object")
    }
    try check(paperCodexServer["url"] as? String == mcpEndpoint.url, "workspace MCP config should include the local endpoint URL")
    try check(headers["Authorization"] as? String == mcpEndpoint.authorizationHeader, "workspace MCP config should include the authorization header")
}

func runCodexPluginInstallerChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-plugin-\(UUID().uuidString)", isDirectory: true)
    let codexHome = tempRoot.appendingPathComponent("codex-home", isDirectory: true)
    let supportRoot = tempRoot.appendingPathComponent("support", isDirectory: true)
    try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
    let configURL = codexHome.appendingPathComponent("config.toml")
    try """
    model_reasoning_effort = "low"

    [features]
    multi_agent = true

    [plugins."browser@openai-bundled"]
    enabled = true
    """.write(to: configURL, atomically: true, encoding: .utf8)

    let endpoint = PaperCodexMCPEndpoint(
        url: "http://127.0.0.1:39427/mcp",
        healthURL: "http://127.0.0.1:39427/health",
        host: "127.0.0.1",
        port: 39427,
        token: "secret-token",
        authorizationHeader: "Bearer secret-token",
        metadataPath: "/tmp/PaperCodex/mcp/server.json"
    )
    let installer = CodexPluginInstaller(codexHome: codexHome, supportRoot: supportRoot)
    let status = try installer.installOrUpdate(endpoint: endpoint, appVersion: "0.1.0")
    try check(status.installed, "Codex plugin installer should report installed status")
    try check(status.current, "Codex plugin installer should report current endpoint")

    let sourcePluginRoot = supportRoot.appendingPathComponent("codex-plugin-marketplace/plugins/paper-codex", isDirectory: true)
    let cachedPluginRoot = codexHome.appendingPathComponent("plugins/cache/paper-codex-local/paper-codex/local", isDirectory: true)
    try check(FileManager.default.fileExists(atPath: sourcePluginRoot.appendingPathComponent(".codex-plugin/plugin.json").path), "installer should write source plugin manifest")
    try check(FileManager.default.fileExists(atPath: cachedPluginRoot.appendingPathComponent(".codex-plugin/plugin.json").path), "installer should write active Codex plugin cache")
    try check(FileManager.default.fileExists(atPath: supportRoot.appendingPathComponent("codex-plugin-marketplace/.agents/plugins/marketplace.json").path), "installer should write marketplace manifest")

    let config = try String(contentsOf: configURL, encoding: .utf8)
    try check(config.contains("[features]"), "installer should preserve features table")
    try check(config.contains("multi_agent = true"), "installer should preserve unrelated feature settings")
    try check(config.contains("plugins = true"), "installer should enable Codex plugins")
    try check(config.contains("[marketplaces.paper-codex-local]"), "installer should register the Paper Codex marketplace")
    try check(config.contains("[plugins.\"paper-codex@paper-codex-local\"]"), "installer should enable the Paper Codex plugin")
    try check(config.contains("[plugins.\"browser@openai-bundled\"]"), "installer should preserve existing plugin settings")

    let mcpConfig = try String(contentsOf: cachedPluginRoot.appendingPathComponent(".mcp.json"), encoding: .utf8)
    try check(mcpConfig.contains(endpoint.url), "cached plugin MCP config should include the current endpoint")
    try check(mcpConfig.contains("http_headers"), "cached plugin MCP config should use Codex HTTP header format")
    try check(mcpConfig.contains(endpoint.authorizationHeader), "cached plugin MCP config should include the current auth header")

    let mcpSkill = try String(contentsOf: cachedPluginRoot.appendingPathComponent("skills/papercodex-mcp/SKILL.md"), encoding: .utf8)
    let workspaceSkill = try String(contentsOf: cachedPluginRoot.appendingPathComponent("skills/papercodex-agent-workspace/SKILL.md"), encoding: .utf8)
    try check(mcpSkill.contains("papercodex://sessions/{session_id}/workspace-manifest"), "cached plugin should include MCP skill resources")
    try check(workspaceSkill.contains("Use MCP tools for app state changes"), "cached plugin should include workspace skill")

    let rotatedEndpoint = PaperCodexMCPEndpoint(
        url: "http://127.0.0.1:39428/mcp",
        healthURL: "http://127.0.0.1:39428/health",
        host: "127.0.0.1",
        port: 39428,
        token: "rotated-token",
        authorizationHeader: "Bearer rotated-token",
        metadataPath: "/tmp/PaperCodex/mcp/server.json"
    )
    let refreshed = try installer.refreshIfInstalled(endpoint: rotatedEndpoint, appVersion: "0.1.1")
    try check(refreshed.current, "installed plugin refresh should update dynamic endpoint metadata")
    let refreshedMCPConfig = try String(contentsOf: cachedPluginRoot.appendingPathComponent(".mcp.json"), encoding: .utf8)
    try check(refreshedMCPConfig.contains(rotatedEndpoint.url), "refreshed plugin should include rotated endpoint")
    try check(refreshedMCPConfig.contains(rotatedEndpoint.authorizationHeader), "refreshed plugin should include rotated auth header")
}

func runPDFChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-pdf-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let pdfURL = tempRoot.appendingPathComponent("fixture.pdf")
    try writeFixturePDF(
        to: pdfURL,
        lines: [
            "Paper Codex extracts selectable text.",
            "This paragraph becomes a stable span."
        ]
    )

    let index = try PDFIndexExtractor().extract(paperID: "paper-a", pdfURL: pdfURL)
    try check(index.pages.count == 1, "fixture PDF should produce one page")
    try check(index.pages[0].text.contains("Paper Codex extracts selectable text."), "page text should contain first fixture line")
    try check(index.spans.contains { $0.text.contains("stable span") }, "spans should include selectable text")
    try check(index.spans.allSatisfy { $0.page == 1 }, "spans should use one-based page numbers")
    try check(index.spans.allSatisfy { $0.bbox.width > 0 && $0.bbox.height > 0 }, "spans should include non-empty bounding boxes")

    guard let document = PDFDocument(url: pdfURL),
          let page = document.page(at: 0),
          let text = page.string,
          let selection = page.selection(for: NSRange(location: 0, length: text.count)) else {
        throw CheckFailure(description: "could not create fixture PDF selection")
    }
    let capturedSelection = PDFSelectionGeometry.capture(selection: selection, in: document)
    try check(capturedSelection?.page == 1, "captured PDF selection should use one-based page numbers")
    try check(capturedSelection?.bboxList.count == 2, "captured multiline PDF selection should preserve per-line boxes")
    try check(capturedSelection?.text.contains("stable span") == true, "captured PDF selection should preserve selected text")

    let abstractPDFURL = tempRoot.appendingPathComponent("abstract.pdf")
    try writeFixturePDF(
        to: abstractPDFURL,
        lines: [
            "Transformer-based large language models have considerably",
            "advanced our understanding of language in the human",
            "brain; however, their validity is questioned.",
            "Autoregressive transformers are increasingly used in neuroscience.",
            "They support studies of language processing at scale",
            "while preserving source citation locality."
        ]
    )
    let abstractIndex = try PDFIndexExtractor().extract(paperID: "paper-b", pdfURL: abstractPDFURL)
    try check(abstractIndex.spans.count == 2, "wrapped paragraph lines should be merged into medium citation spans")
    try check(abstractIndex.spans[0].text.contains("considerably advanced"), "merged citation span should join wrapped lines")
    try check(abstractIndex.spans[0].text.contains("validity is questioned."), "merged citation span should keep the paragraph ending")
    try check(abstractIndex.spans.allSatisfy { $0.text.count <= 420 }, "citation spans should not become oversized blocks")

    let resolver = PDFReferenceResolver(pageTexts: [
        1: """
        Representation learning is widely used in sequence modeling [1, 2].
        Another body citation uses an author year form (Vaswani et al., 2017).

        References
        [1] Vaswani, A., Shazeer, N., Parmar, N. Attention Is All You Need. NeurIPS 2017.
        [2] Ho, J., Jain, A., Abbeel, P. Denoising Diffusion Probabilistic Models. NeurIPS 2020.
        """
    ])
    let numericPreview = resolver.preview(forLine: "Representation learning is widely used in sequence modeling [1, 2].", page: 1)
    try check(numericPreview?.citationText == "[1, 2]", "PDF resolver should extract the clicked numeric citation marker")
    try check(numericPreview?.references.map(\.marker) == ["1", "2"], "PDF resolver should map numeric in-text citations to reference entries")
    let clickedNumericPreview = resolver.preview(forLine: "Representation learning is widely used in sequence modeling [1, 2].", clickedText: "2", page: 1)
    try check(clickedNumericPreview?.references.map(\.marker) == ["1", "2"], "PDF resolver should open a numeric preview when the clicked word is inside the citation")
    let clickedBodyTextPreview = resolver.preview(forLine: "Representation learning is widely used in sequence modeling [1, 2].", clickedText: "Representation", page: 1)
    try check(clickedBodyTextPreview == nil, "PDF resolver should not steal ordinary text clicks from citation-bearing lines")
    let authorYearPreview = resolver.preview(forLine: "Another body citation uses an author year form (Vaswani et al., 2017).", page: 1)
    try check(authorYearPreview?.references.first?.text.contains("Attention Is All You Need") == true, "PDF resolver should map author-year citations to matching reference text")
    let clickedAuthorPreview = resolver.preview(forLine: "Vaswani et al. (2017) introduced a transformer architecture.", clickedText: "Vaswani", page: 1)
    try check(clickedAuthorPreview?.references.first?.text.contains("Attention Is All You Need") == true, "PDF resolver should support narrative author-year citation clicks")
    let referenceEntry = resolver.referenceEntry(containingLine: "[2] Ho, J., Jain, A., Abbeel, P. Denoising Diffusion Probabilistic Models. NeurIPS 2020.", page: 1)
    try check(referenceEntry?.title == "Denoising Diffusion Probabilistic Models", "PDF resolver should parse reference-list entries into cards")
    let referencePreview = resolver.preview(forLine: "[1] Vaswani, A., Shazeer, N., Parmar, N. Attention Is All You Need. NeurIPS 2017.", page: 1)
    try check(referencePreview == nil, "reference-list lines should not be treated as ordinary in-text citation popups")
    let unnumberedResolver = PDFReferenceResolver(pageTexts: [
        3: """
        References
        Vaswani, A., Shazeer, N., Parmar, N. (2017). Attention Is All You Need. NeurIPS.
        Ho, J., Jain, A., Abbeel, P. (2020). Denoising Diffusion Probabilistic Models. NeurIPS.
        """
    ])
    let unnumberedPreview = unnumberedResolver.preview(forLine: "Transformer baselines remain common (Vaswani et al., 2017).", clickedText: "2017", page: 3)
    try check(unnumberedPreview?.references.first?.title == "Attention Is All You Need", "PDF resolver should parse unnumbered author-year references")
    let unnumberedReferenceEntry = unnumberedResolver.referenceEntry(containingLine: "Ho, J., Jain, A., Abbeel, P. (2020). Denoising Diffusion Probabilistic Models. NeurIPS.", page: 3)
    try check(unnumberedReferenceEntry?.title == "Denoising Diffusion Probabilistic Models", "PDF resolver should render unnumbered references as cards")
    let templateResolver = PDFReferenceResolver(pageTexts: [
        8: """
        References
        [3] A. Vaswani, N. Shazeer, N. Parmar, J. Uszkoreit, L. Jones, A. N. Gomez, L. Kaiser, and I. Polosukhin, "Attention Is All You Need," in Advances in Neural Information Processing Systems, 2017.
        [4] Vaswani, A., Shazeer, N., Parmar, N., Uszkoreit, J., Jones, L., Gomez, A. N., Kaiser, L., & Polosukhin, I. (2017). Attention Is All You Need. Advances in Neural Information Processing Systems.
        [5] Vaswani, Ashish, et al. "Attention Is All You Need." Advances in Neural Information Processing Systems 30 (2017).
        [6] Ashish Vaswani, Noam Shazeer, Niki Parmar, Jakob Uszkoreit, Llion Jones, Aidan N. Gomez, Lukasz Kaiser, and Illia Polosukhin. 2017. Attention Is All You Need. In Proceedings of NeurIPS.
        [7] A. Vaswani et al., Attention Is All You Need, arXiv:1706.03762, 2017.
        """
    ])
    let templateTitles = templateResolver.references.map(\.title)
    try check(templateTitles == Array(repeating: "Attention Is All You Need", count: 5), "PDF resolver should extract titles from common reference templates")
}

func runCodexCLIChecks() throws {
    let codexPath = try CodexCLI.findCodexExecutable()
    try check(FileManager.default.isExecutableFile(atPath: codexPath), "codex executable should be runnable")

    let cli = CodexCLI(executablePath: codexPath)
    let isolatedWorkingDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-codex-cli-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: isolatedWorkingDirectory, withIntermediateDirectories: true)
    let sanitizedEnvironment = CodexCLI.sanitizedProcessEnvironment(
        workingDirectoryURL: isolatedWorkingDirectory,
        baseEnvironment: [
            "HOME": "/Users/chunqiu",
            "PWD": "/Users/chunqiu/Documents/New project 2",
            "OLDPWD": "/Users/chunqiu/Documents"
        ]
    )
    let isolatedWorkingDirectoryPath = isolatedWorkingDirectory.standardizedFileURL.path
    try check(sanitizedEnvironment["PWD"] == isolatedWorkingDirectoryPath, "Codex subprocesses should advertise the explicit working directory")
    try check(sanitizedEnvironment["OLDPWD"] == nil, "Codex subprocesses should not inherit protected-folder OLDPWD values")
    try check(sanitizedEnvironment["HOME"] == "/Users/chunqiu", "Codex subprocess environment should preserve unrelated variables")
    let pwdOutput = try CodexCLI(executablePath: "/bin/pwd")
        .run(arguments: [], currentDirectoryURL: isolatedWorkingDirectory)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    try check(pwdOutput == isolatedWorkingDirectoryPath, "Codex subprocesses should run from the explicit working directory")
    let start = cli.startArguments(prompt: "hello", workspacePath: "/tmp/session-a")
    try check(start == ["exec", "--skip-git-repo-check", "--json", "--enable", "image_generation", "-C", "/tmp/session-a", "hello"], "start args should allow non-git session workspaces with image generation enabled")
    let startWithOutput = cli.startArguments(prompt: "hello", workspacePath: "/tmp/session-a", outputLastMessagePath: "/tmp/last.txt")
    try check(startWithOutput == ["exec", "--skip-git-repo-check", "--json", "--enable", "image_generation", "-C", "/tmp/session-a", "--output-last-message", "/tmp/last.txt", "hello"], "start args should support output-last-message")
    let startWithModel = cli.startArguments(prompt: "hello", workspacePath: "/tmp/session-a", outputLastMessagePath: "/tmp/last.txt", modelOverride: "gpt-5.4")
    try check(startWithModel == ["exec", "--skip-git-repo-check", "--json", "--enable", "image_generation", "--model", "gpt-5.4", "-C", "/tmp/session-a", "--output-last-message", "/tmp/last.txt", "hello"], "start args should support an app-local model override")
    let startWithReasoning = cli.startArguments(prompt: "hello", workspacePath: "/tmp/session-a", reasoningEffort: .high)
    try check(startWithReasoning == ["exec", "--skip-git-repo-check", "--json", "--enable", "image_generation", "-c", "model_reasoning_effort=\"high\"", "-C", "/tmp/session-a", "hello"], "start args should support an app-local reasoning effort override")
    let startWithDefaultReasoning = cli.startArguments(prompt: "hello", workspacePath: "/tmp/session-a", reasoningEffort: .default)
    try check(startWithDefaultReasoning == start, "default reasoning effort should not add a Codex config override")
    let mcpServer = CodexMCPServerConfig(
        name: "paper-codex",
        url: "http://127.0.0.1:39427/mcp",
        bearerTokenEnvironmentVariable: "PAPER_CODEX_MCP_TOKEN",
        bearerToken: "secret-token"
    )
    let startWithMCP = cli.startArguments(prompt: "hello", workspacePath: "/tmp/session-a", mcpServers: [mcpServer])
    try check(
        startWithMCP == [
            "exec", "--skip-git-repo-check", "--json", "--enable", "image_generation",
            "-c", "mcp_servers.paper-codex.url=\"http://127.0.0.1:39427/mcp\"",
            "-c", "mcp_servers.paper-codex.bearer_token_env_var=\"PAPER_CODEX_MCP_TOKEN\"",
            "-C", "/tmp/session-a", "hello"
        ],
        "start args should inject the Paper Codex MCP server as an app-local config override"
    )
    let mcpEnvironment = CodexCLI.sanitizedProcessEnvironment(
        workingDirectoryURL: isolatedWorkingDirectory,
        baseEnvironment: ["PATH": "/usr/bin"],
        environmentOverrides: mcpServer.environmentOverrides
    )
    try check(mcpEnvironment["PAPER_CODEX_MCP_TOKEN"] == "secret-token", "Codex subprocess environment should include the Paper Codex MCP bearer token")

    let resume = cli.resumeArguments(sessionID: "session-a", prompt: "continue")
    try check(resume == ["exec", "resume", "--skip-git-repo-check", "--json", "--enable", "image_generation", "session-a", "continue"], "resume args should use codex exec resume with JSON output and image generation enabled")
    let resumeWithModel = cli.resumeArguments(sessionID: "session-a", prompt: "continue", modelOverride: "gpt-5.4")
    try check(resumeWithModel == ["exec", "resume", "--skip-git-repo-check", "--json", "--enable", "image_generation", "--model", "gpt-5.4", "session-a", "continue"], "resume args should support an app-local model override")
    let resumeWithReasoning = cli.resumeArguments(sessionID: "session-a", prompt: "continue", reasoningEffort: .xhigh)
    try check(resumeWithReasoning == ["exec", "resume", "--skip-git-repo-check", "--json", "--enable", "image_generation", "-c", "model_reasoning_effort=\"xhigh\"", "session-a", "continue"], "resume args should support an app-local reasoning effort override")
    let resumeWithMCP = cli.resumeArguments(sessionID: "session-a", prompt: "continue", mcpServers: [mcpServer])
    try check(
        resumeWithMCP == [
            "exec", "resume", "--skip-git-repo-check", "--json", "--enable", "image_generation",
            "-c", "mcp_servers.paper-codex.url=\"http://127.0.0.1:39427/mcp\"",
            "-c", "mcp_servers.paper-codex.bearer_token_env_var=\"PAPER_CODEX_MCP_TOKEN\"",
            "session-a", "continue"
        ],
        "resume args should inject the Paper Codex MCP server as an app-local config override"
    )
    let parsedThreadID = CodexCLI.parseThreadID(from: #"{"type":"thread.started","thread_id":"019dcaf6-01d5-7060-bc43-40401e3693c3"}"#)
    try check(parsedThreadID == "019dcaf6-01d5-7060-bc43-40401e3693c3", "Codex thread ID should be parsed from JSONL output")

    let threadEvent = try CodexJSONEventParser.parseLine(#"{"type":"thread.started","thread_id":"019dcaf6-01d5-7060-bc43-40401e3693c3"}"#)
    try check(threadEvent?.kind == .status, "thread events should become status updates")
    try check(threadEvent?.detail.contains("019dcaf6") == true, "thread status should include the session id")
    let reasoningEvent = try CodexJSONEventParser.parseLine(#"{"type":"agent_reasoning","text":"Reading paper context"}"#)
    try check(reasoningEvent?.kind == .thinking, "reasoning summaries should become thinking updates")
    try check(reasoningEvent?.detail == "Reading paper context", "reasoning event should preserve summary text")
    let commandEvent = try CodexJSONEventParser.parseLine(#"{"type":"exec_command","cmd":"rg -n diffusion paper.md"}"#)
    try check(commandEvent?.kind == .terminal, "terminal command events should be classified for terminal display")
    try check(commandEvent?.title == "rg -n diffusion paper.md", "terminal command events should use the command as the display title")
    try check(commandEvent?.detail == "Running command", "terminal command events should not duplicate the command in the detail text")
    try check(commandEvent?.displayTitle == "rg -n diffusion paper.md", "terminal display title should show the command")
    try check(commandEvent?.previewDetail == "Running command", "terminal preview should use a compact first line")
    let outputEvent = try CodexJSONEventParser.parseLine(#"{"type":"exec_command_output","stdout":"paper.md:12: diffusion\n"}"#)
    try check(outputEvent?.kind == .terminal, "terminal output events should be classified for terminal display")
    try check(outputEvent?.title == "Command output", "terminal output events should be displayed as command output")
    try check(outputEvent?.detail.contains("paper.md:12") == true, "terminal output events should include stdout text")
    let longOutputEvent = CodexRunEvent(kind: .terminal, title: "Command output", detail: String(repeating: "a", count: 180) + "\nsecond line")
    try check(longOutputEvent.previewDetail.count <= 96, "terminal preview should be truncated")
    try check(!longOutputEvent.previewDetail.contains("second line"), "terminal preview should only show the first line")
    let toolEvent = try CodexJSONEventParser.parseLine(#"{"type":"tool_call","name":"web.search","arguments":{"query":"paper"}}"#)
    try check(toolEvent?.kind == .tool, "non-terminal tool calls should be classified as tool events")
    try check(toolEvent?.title == "web.search", "tool events should show the tool name")
    let hermesStartedTool = try HermesBridgeEventParser.parseLine(#"{"type":"tool","state":"started","name":"read_file","detail":"full_text.txt"}"#)
    try check(hermesStartedTool?.kind == .tool, "Hermes bridge tool-start events should become visible tool updates")
    try check(hermesStartedTool?.title == "read_file", "Hermes bridge tool events should use the tool name as the title")
    try check(hermesStartedTool?.detail == "full_text.txt", "Hermes bridge tool events should preserve the preview detail")
    let hermesCompletedTool = try HermesBridgeEventParser.parseLine(#"{"type":"tool","state":"completed","name":"grep","duration":0.42,"is_error":false}"#)
    try check(hermesCompletedTool?.kind == .tool, "Hermes bridge tool-completion events should stay in the tool lane")
    try check(hermesCompletedTool?.detail == "Completed in 0.42s", "Hermes bridge tool completions should show compact duration")
    let hermesAnswer = try HermesBridgeEventParser.parseLine(#"{"type":"answer","text":"最终回答"}"#)
    try check(hermesAnswer?.kind == .answer, "Hermes bridge answer events should mark the final result")
    try check(hermesAnswer?.detail == "最终回答", "Hermes bridge answer events should preserve final answer text")
    let imageGenerationEvent = try CodexJSONEventParser.parseLine(#"{"type":"image_generation_call","id":"ig_test","status":"completed","result":"base64-payload"}"#)
    try check(imageGenerationEvent?.kind == .tool, "image generation events should be classified as compact tool events")
    try check(imageGenerationEvent?.title == "Image generation", "image generation events should have a readable title")
    try check(imageGenerationEvent?.detail == "completed · ig_test", "image generation events should omit raw image payloads from the UI stream")
    let usageEvent = try CodexJSONEventParser.parseLine(#"{"type":"turn.completed","usage":{"input_tokens":24111,"cached_input_tokens":2432,"output_tokens":424,"reasoning_output_tokens":247}}"#)
    try check(usageEvent?.kind == .usage, "turn completion usage should be classified as a usage event")
    try check(usageEvent?.tokenUsage?.inputTokens == 24_111, "usage events should preserve input token counts")
    try check(usageEvent?.tokenUsage?.cachedInputTokens == 2_432, "usage events should preserve cached input token counts")
    try check(usageEvent?.tokenUsage?.outputTokens == 424, "usage events should preserve output token counts")
    try check(usageEvent?.tokenUsage?.reasoningOutputTokens == 247, "usage events should preserve reasoning token counts")
    try check(usageEvent?.detail.contains("24.1k in") == true, "usage event detail should show compact token counts")
    let aggregateUsage = CodexCLI.aggregateTokenUsage(from: """
    {"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":100,"output_tokens":50,"reasoning_output_tokens":20}}
    {"type":"turn.completed","usage":{"input_tokens":2000,"cached_input_tokens":300,"output_tokens":70,"reasoning_output_tokens":30}}
    """)
    try check(aggregateUsage?.inputTokens == 3_000, "Codex usage aggregation should sum input tokens across JSONL")
    try check(aggregateUsage?.cachedInputTokens == 400, "Codex usage aggregation should sum cached input tokens across JSONL")
    try check(aggregateUsage?.outputTokens == 120, "Codex usage aggregation should sum output tokens across JSONL")
    try check(aggregateUsage?.reasoningOutputTokens == 50, "Codex usage aggregation should sum reasoning tokens across JSONL")

    let parsedVersion = CodexCLI.parseVersion(from: "codex-cli 0.114.0\n")
    try check(parsedVersion == "0.114.0", "Codex version parser should read codex-cli output")
    let executableCandidates = [
        CodexExecutableCandidate(path: "/opt/homebrew/bin/codex", version: "0.114.0"),
        CodexExecutableCandidate(path: "/Applications/Codex.app/Contents/Resources/codex", version: "0.125.0-alpha.3")
    ]
    let selectedExecutable = CodexCLI.selectBestExecutable(candidates: executableCandidates)
    try check(selectedExecutable?.path == "/Applications/Codex.app/Contents/Resources/codex", "newest Codex executable should be selected when multiple copies exist")
    let imageExecutable = CodexCLI.selectBestExecutable(candidates: executableCandidates, preferWorkspaceImageOutput: true)
    try check(imageExecutable?.path == "/opt/homebrew/bin/codex", "image-generation runs should prefer the CLI that writes generated images into the workspace")
    let firstUnknownExecutable = CodexCLI.selectBestExecutable(candidates: [
        CodexExecutableCandidate(path: "/first/codex", version: nil),
        CodexExecutableCandidate(path: "/second/codex", version: nil)
    ])
    try check(firstUnknownExecutable?.path == "/first/codex", "candidate order should be preserved when versions are unknown")
    let help = "Usage: codex exec [OPTIONS]\n      --json\n  -o, --output-last-message <FILE>\nCommands:\n  resume\n"
    let capabilities = CodexCLI.parseCapabilities(fromExecHelp: help)
    try check(capabilities.supportsJSONOutput, "Codex help parser should detect JSON output support")
    try check(capabilities.supportsOutputLastMessage, "Codex help parser should detect last-message output support")
    try check(capabilities.supportsResume, "Codex help parser should detect resume support")
    let cancelHandle = CodexRunHandle()
    let cancelSemaphore = DispatchSemaphore(value: 0)
    let cancelStarted = Date()
    DispatchQueue.global().async {
        do {
            _ = try CodexCLI(executablePath: "/bin/sleep")
                .runStreaming(arguments: ["5"], runHandle: cancelHandle) { _ in }
        } catch {
        }
        cancelSemaphore.signal()
    }
    Thread.sleep(forTimeInterval: 0.1)
    cancelHandle.cancel()
    let cancelResult = cancelSemaphore.wait(timeout: .now() + 2)
    try check(cancelResult == .success, "Codex run handle should terminate a running process")
    try check(Date().timeIntervalSince(cancelStarted) < 2, "Codex run cancellation should return promptly")
    let diagnostic = CodexDiagnostic.ready(
        executablePath: "/opt/homebrew/bin/codex",
        version: "0.114.0",
        capabilities: capabilities
    )
    try check(diagnostic.title == "Codex ready", "ready diagnostic should have a stable title")
    try check(diagnostic.detail.contains("0.114.0"), "ready diagnostic should include the CLI version")

    let config = """
    model = "gpt-5.5"

    [profiles.fast]
    model = "gpt-5.4"
    """
    try check(CodexCLI.parseConfiguredModel(from: config) == "gpt-5.5", "Codex config parser should read the top-level model")
    try check(CodexCLI.configuredDefaultModelID(configText: config) == "gpt-5.5", "Codex default model helper should expose the configured top-level model")
    let modelIssue = CodexCLI.configuredModelIssue(configText: config, cliVersion: "0.114.0")
    try check(modelIssue?.contains("gpt-5.5") == true, "model compatibility issue should name the configured model")
    let blockedDiagnostic = CodexCLI.diagnostic(
        executablePath: "/opt/homebrew/bin/codex",
        version: "0.114.0",
        capabilities: capabilities,
        configText: config
    )
    try check(blockedDiagnostic.severity == .blocked, "diagnostic should be blocked when the configured model needs a newer CLI")
    try check(blockedDiagnostic.title == "Codex model incompatible", "model compatibility failures should have a specific diagnostic title")
    let overrideDiagnostic = CodexCLI.diagnostic(
        executablePath: "/opt/homebrew/bin/codex",
        version: "0.114.0",
        capabilities: capabilities,
        configText: config,
        modelOverride: "gpt-5.4"
    )
    try check(overrideDiagnostic.severity == .ready, "app-local model override should bypass the incompatible default model")
    try check(overrideDiagnostic.detail.contains("gpt-5.4"), "override diagnostic should name the selected model")
    try check(CodexCLI.configuredModelIssue(configText: #"model = "gpt-5.4""#, cliVersion: "0.114.0") == nil, "other configured models should not be blocked by the gpt-5.5 compatibility rule")

    let detectedModels = CodexCLI.availableModelIDs(
        cliVersion: "0.120.0",
        embeddedText: "gpt-5.4 gpt-5.3-codex gpt-5.1-codex-mini gpt-5-4 gpt-account-id gptAuthTokens gpt.com",
        configText: #"model = "gpt-5.2""#
    )
    try check(detectedModels.contains("gpt-5.4"), "Codex model detector should include embedded GPT models")
    try check(detectedModels.contains("gpt-5.1-codex-mini"), "Codex model detector should include embedded Codex model variants")
    try check(detectedModels.contains("gpt-5.2"), "Codex model detector should include the configured model")
    try check(!detectedModels.contains("gpt-account-id"), "Codex model detector should filter telemetry strings")
    try check(!detectedModels.contains("gptAuthTokens"), "Codex model detector should filter auth implementation strings")
    try check(!detectedModels.contains("gpt-5-4"), "Codex model detector should filter hyphenated version noise")
    let oldVersionModels = CodexCLI.availableModelIDs(
        cliVersion: "0.114.0",
        embeddedText: "gpt-5.5 gpt-5.4",
        configText: nil
    )
    try check(!oldVersionModels.contains("gpt-5.5"), "Codex model detector should filter models blocked by the current CLI version")
}

func runAgentRuntimeProfileChecks() throws {
    let profiles = AgentRuntimeProfile.defaultProfiles
    let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    try check(Set(profilesByID.keys) == ["codex", "claude-code", "hermes", "openclaw-kimi", "pi"], "default agent runtime profiles should cover Codex, Claude Code, Hermes, OpenClaw Kimi, and pi")

    let codex = try requiredProfile("codex", in: profilesByID)
    try check(codex.backend == .codex, "Codex profile should use the codex backend")
    try check(codex.executableName == "codex", "Codex profile should launch the codex executable")
    try check(codex.supportsNonInteractiveRuns, "Codex profile should support deterministic non-interactive runs")
    try check(codex.supportsPTY, "Codex profile should support terminal launches")
    try check(codex.supportsResume, "Codex profile should preserve runtime session resume")
    try check(codex.supportsStructuredOutput, "Codex profile should expose structured JSONL output")
    try check(codex.mcpMode == .codexConfigOverrides, "Codex profile should use app-local config overrides for MCP")
    try check(codex.promptInjectionModes.contains(.argumentPrompt), "Codex profile should inject the rendered prompt as an argument")

    let claude = try requiredProfile("claude-code", in: profilesByID)
    try check(claude.backend == .claudeCode, "Claude Code profile should use the Claude Code backend")
    try check(claude.executableName == "claude", "Claude Code profile should launch claude")
    try check(claude.supportsNonInteractiveRuns, "Claude Code profile should support print-mode checks")
    try check(claude.supportsPTY, "Claude Code profile should support interactive terminal launches")
    try check(claude.supportsMCPConfig, "Claude Code profile should accept explicit MCP config")
    try check(claude.mcpMode == .mcpConfigFile, "Claude Code profile should use a workspace MCP config file")
    try check(claude.promptInjectionModes.contains(.systemPromptFlag), "Claude Code profile should support system prompt flags")

    let hermes = try requiredProfile("hermes", in: profilesByID)
    try check(hermes.backend == .hermes, "Hermes profile should use the Hermes backend")
    try check(hermes.executableName == "hermes", "Hermes profile should launch hermes")
    try check(hermes.supportsPTY, "Hermes profile should support TUI launches")
    try check(hermes.promptInjectionModes.contains(.skill), "Hermes profile should support skill-based Paper Codex instructions")

    let openClaw = try requiredProfile("openclaw-kimi", in: profilesByID)
    try check(openClaw.backend == .openClawKimi, "OpenClaw Kimi profile should use the OpenClaw Kimi backend")
    try check(openClaw.executableName == "openclaw", "OpenClaw Kimi profile should launch openclaw")
    try check(openClaw.defaultModelID == "kimi-coding/k2p5", "OpenClaw Kimi profile should default to the locally configured Kimi model")
    try check(openClaw.supportsStructuredOutput, "OpenClaw Kimi profile should support JSON smoke checks")

    let pi = try requiredProfile("pi", in: profilesByID)
    try check(pi.backend == .pi, "pi profile should use the pi backend")
    try check(pi.executableName == "pi", "pi profile should launch pi")
    try check(pi.supportsPTY, "pi profile should support interactive terminal launches")
    try check(pi.promptInjectionModes.contains(.appendSystemPromptFile), "pi profile should support prompt contract files")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let decoder = JSONDecoder()
    let decoded = try decoder.decode([AgentRuntimeProfile].self, from: encoder.encode(profiles))
    try check(decoded == profiles, "agent runtime profiles should JSON round-trip")
}

func runAgentWorkspaceManifestChecks() throws {
    let paper = AgentWorkspacePaper(
        paperID: "paper-a",
        title: "Test Paper",
        originalPDFPath: "/tmp/session/papers/paper-a/original.pdf",
        fullTextPath: "/tmp/session/papers/paper-a/full_text.txt",
        pagesJSONLPath: "/tmp/session/papers/paper-a/pages.jsonl",
        spansJSONLPath: "/tmp/session/papers/paper-a/spans.jsonl",
        anchorsJSONLPath: "/tmp/session/papers/paper-a/anchors.jsonl",
        metadataJSONPath: "/tmp/session/papers/paper-a/metadata.json"
    )
    let manifest = AgentWorkspaceManifest(
        sessionID: "session-a",
        workspacePath: "/tmp/session",
        materializationMode: .copyPDF,
        mcpConfigPath: "/tmp/session/mcp.json",
        promptContractPath: "/tmp/session/prompt_contract.md",
        agentInstructionsPath: "/tmp/session/agent_instructions.md",
        papers: [paper]
    )
    try check(manifest.sessionID == "session-a", "workspace manifest should keep the session id")
    try check(manifest.workspacePath == "/tmp/session", "workspace manifest should keep the workspace root")
    try check(manifest.materializationMode == .copyPDF, "workspace manifest should record the file materialization mode")
    try check(manifest.mcpConfigPath == "/tmp/session/mcp.json", "workspace manifest should point to the MCP config file")
    try check(manifest.promptContractPath == "/tmp/session/prompt_contract.md", "workspace manifest should point to the prompt contract")
    try check(manifest.agentInstructionsPath == "/tmp/session/agent_instructions.md", "workspace manifest should point to agent instructions")
    try check(manifest.papers.first?.paperID == "paper-a", "workspace manifest should list paper entries")
    try check(manifest.papers.first?.spansJSONLPath.hasSuffix("spans.jsonl") == true, "workspace paper entries should include span index paths")

    var symlinkManifest = manifest
    symlinkManifest.materializationMode = .symlinkPDF
    try check(symlinkManifest.materializationMode == .symlinkPDF, "workspace manifest should support symlinked paper files")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(AgentWorkspaceManifest.self, from: encoder.encode(manifest))
    try check(decoded == manifest, "workspace manifest should JSON round-trip")
}

func runAgentCommandBuilderChecks() throws {
    let mcpServer = CodexMCPServerConfig(
        name: "paper-codex",
        url: "http://127.0.0.1:39427/mcp",
        bearerTokenEnvironmentVariable: "PAPER_CODEX_MCP_TOKEN",
        bearerToken: "secret-token"
    )
    let executableRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-agent-executables-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: executableRoot, withIntermediateDirectories: true)
    func makeExecutable(_ name: String) throws -> String {
        let url = executableRoot.appendingPathComponent(name)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
    let claudeExecutable = try makeExecutable("claude")
    let hermesExecutable = try makeExecutable("hermes")
    let openClawExecutable = try makeExecutable("openclaw")
    let piExecutable = try makeExecutable("pi")
    let pathEnvironment = ["PATH": executableRoot.path, "HOME": executableRoot.path]
    let discoveredClaudeExecutable = try ClaudeCodeRuntimeAdapter.findExecutable(environment: pathEnvironment)
    let discoveredHermesExecutable = try HermesRuntimeAdapter.findExecutable(environment: pathEnvironment)
    let discoveredOpenClawExecutable = try OpenClawRuntimeAdapter.findExecutable(environment: pathEnvironment)
    let discoveredPiExecutable = try PiRuntimeAdapter.findExecutable(environment: pathEnvironment)
    try check(
        discoveredClaudeExecutable == claudeExecutable,
        "Claude Code adapter should discover claude from PATH"
    )
    try check(
        discoveredHermesExecutable == hermesExecutable,
        "Hermes adapter should discover hermes from PATH"
    )
    try check(
        discoveredOpenClawExecutable == openClawExecutable,
        "OpenClaw adapter should discover openclaw from PATH"
    )
    try check(
        discoveredPiExecutable == piExecutable,
        "pi adapter should discover pi from PATH"
    )

    let codexStart = CodexRuntimeAdapter(executablePath: "/usr/local/bin/codex").startCommand(
        prompt: "Summarize",
        workspacePath: "/tmp/session-a",
        outputLastMessagePath: "/tmp/session-a/turns/last.txt",
        modelOverride: "gpt-5.4",
        reasoningEffort: .high,
        mcpServers: [mcpServer]
    )
    try check(codexStart.executablePath == "/usr/local/bin/codex", "Codex adapter should keep the selected executable path")
    try check(
        codexStart.arguments == [
            "exec", "--skip-git-repo-check", "--json", "--enable", "image_generation",
            "--model", "gpt-5.4",
            "-c", "model_reasoning_effort=\"high\"",
            "-c", "mcp_servers.paper-codex.url=\"http://127.0.0.1:39427/mcp\"",
            "-c", "mcp_servers.paper-codex.bearer_token_env_var=\"PAPER_CODEX_MCP_TOKEN\"",
            "-C", "/tmp/session-a",
            "--output-last-message", "/tmp/session-a/turns/last.txt",
            "Summarize"
        ],
        "Codex adapter should preserve current codex exec behavior and MCP config overrides"
    )
    try check(codexStart.environmentOverrides["PAPER_CODEX_MCP_TOKEN"] == "secret-token", "Codex adapter should pass MCP bearer tokens through the environment")
    try check(codexStart.currentDirectoryPath == "/tmp/session-a", "Codex adapter should run from the session workspace")

    let codexResume = CodexRuntimeAdapter(executablePath: "/usr/local/bin/codex").resumeCommand(
        sessionID: "codex-session",
        prompt: "Continue",
        workspacePath: "/tmp/session-a",
        outputLastMessagePath: nil,
        modelOverride: nil,
        reasoningEffort: .default,
        mcpServers: [mcpServer]
    )
    try check(codexResume.arguments.prefix(5) == ["exec", "resume", "--skip-git-repo-check", "--json", "--enable"], "Codex resume adapter should use codex exec resume")
    try check(codexResume.arguments.suffix(2) == ["codex-session", "Continue"], "Codex resume adapter should append runtime session id and prompt")

    let claude = ClaudeCodeRuntimeAdapter(executablePath: "/usr/local/bin/claude").nonInteractiveCommand(
        prompt: "Summarize",
        workspacePath: "/tmp/session-a",
        systemPrompt: "Use the Paper Codex citation contract.",
        mcpConfigPath: "/tmp/session-a/mcp.json"
    )
    try check(
        claude.arguments == [
            "--print",
            "--output-format", "stream-json",
            "--verbose",
            "--system-prompt", "Use the Paper Codex citation contract.",
            "--add-dir=/tmp/session-a",
            "--mcp-config=/tmp/session-a/mcp.json",
            "Summarize"
        ],
        "Claude Code adapter should inject system prompt, workspace, and MCP config"
    )

    let hermes = HermesRuntimeAdapter(executablePath: "/usr/local/bin/hermes").nonInteractiveCommand(
        prompt: "Summarize",
        workspacePath: "/tmp/session-a",
        provider: "kimi",
        model: "kimi-k2",
        skillsPath: "/tmp/session-a/skills/papercodex-agent-workspace"
    )
    try check(
        hermes.arguments == [
            "chat",
            "--quiet",
            "--query", "Summarize",
            "--provider", "kimi",
            "--model", "kimi-k2",
            "--skills", "/tmp/session-a/skills/papercodex-agent-workspace",
            "--source", "papercodex"
        ],
        "Hermes adapter should build a quiet provider/model/skills query command so only the final answer reaches chat"
    )
    let hermesInstallRoot = executableRoot.appendingPathComponent("hermes-agent", isDirectory: true)
    let hermesBinRoot = hermesInstallRoot.appendingPathComponent("venv/bin", isDirectory: true)
    try FileManager.default.createDirectory(at: hermesBinRoot, withIntermediateDirectories: true)
    let hermesPythonURL = hermesBinRoot.appendingPathComponent("python3")
    try "#!/bin/sh\nexit 0\n".write(to: hermesPythonURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hermesPythonURL.path)
    let hermesBridgeExecutableURL = hermesBinRoot.appendingPathComponent("hermes")
    try "#!\(hermesPythonURL.path)\nexit 0\n".write(to: hermesBridgeExecutableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hermesBridgeExecutableURL.path)
    let hermesBridge = try HermesRuntimeAdapter(executablePath: hermesBridgeExecutableURL.path).structuredNonInteractiveCommand(
        prompt: "Summarize",
        workspacePath: "/tmp/session-a",
        provider: "kimi",
        model: "kimi-k2",
        skillsPath: "/tmp/session-a/skills/papercodex-agent-workspace"
    )
    try check(hermesBridge.executablePath == hermesPythonURL.path, "Hermes bridge should reuse Hermes' existing virtualenv Python")
    try check(hermesBridge.arguments.prefix(2) == ["-u", "-c"], "Hermes bridge should run an unbuffered embedded Python event bridge")
    try check(hermesBridge.arguments.contains("--query") && hermesBridge.arguments.contains("Summarize"), "Hermes bridge should pass the Paper Codex prompt through unchanged")
    try check(hermesBridge.environmentOverrides["PAPER_CODEX_HERMES_ROOT"] == hermesInstallRoot.path, "Hermes bridge should import Hermes from its existing install root")

    let openClaw = OpenClawRuntimeAdapter(executablePath: "/opt/homebrew/bin/openclaw").nonInteractiveCommand(
        prompt: "Summarize",
        workspacePath: "/tmp/session-a",
        sessionID: "paper-session",
        modelID: "kimi-coding/k2p5"
    )
    try check(
        openClaw.arguments == [
            "agent",
            "--local",
            "--json",
            "--session-id", "paper-session",
            "--message", "Summarize"
        ],
        "OpenClaw Kimi adapter should build a local JSON agent command"
    )
    try check(openClaw.environmentOverrides["OPENCLAW_MODEL"] == "kimi-coding/k2p5", "OpenClaw Kimi adapter should carry explicit model selection through the environment")

    let pi = PiRuntimeAdapter(executablePath: "/Users/chunqiu/.local/bin/pi").nonInteractiveCommand(
        prompt: "Summarize",
        workspacePath: "/tmp/session-a",
        systemPrompt: "Use Paper Codex citations.",
        agentInstructionsPath: "/tmp/session-a/agent_instructions.md"
    )
    try check(
        pi.arguments == [
            "-p",
            "--mode", "json",
            "--session-dir", "/tmp/session-a/agent-sessions/pi",
            "--system-prompt", "Use Paper Codex citations.",
            "--append-system-prompt", "/tmp/session-a/agent_instructions.md",
            "Summarize"
        ],
        "pi adapter should build a JSON print command with session storage and prompt files"
    )

    let codexTerminal = CodexRuntimeAdapter(executablePath: "/usr/local/bin/codex").terminalCommand(
        workspacePath: "/tmp/session-a",
        modelOverride: "gpt-5.4",
        reasoningEffort: .high,
        mcpServers: [mcpServer]
    )
    try check(codexTerminal.launchMode == .pty, "Codex terminal command should launch in PTY mode")
    try check(codexTerminal.arguments.contains("-C") && codexTerminal.arguments.contains("/tmp/session-a"), "Codex terminal command should start inside the paper workspace")
    try check(codexTerminal.environmentOverrides["PAPER_CODEX_MCP_TOKEN"] == "secret-token", "Codex terminal command should preserve MCP token environment")

    let claudeTerminal = ClaudeCodeRuntimeAdapter(executablePath: "/usr/local/bin/claude").terminalCommand(
        workspacePath: "/tmp/session-a",
        mcpConfigPath: "/tmp/session-a/mcp.json"
    )
    try check(claudeTerminal.launchMode == .pty, "Claude terminal command should launch in PTY mode")
    try check(claudeTerminal.arguments == ["--add-dir=/tmp/session-a", "--mcp-config=/tmp/session-a/mcp.json"], "Claude terminal command should pass workspace and MCP config")

    let hermesTerminal = HermesRuntimeAdapter(executablePath: "/usr/local/bin/hermes").terminalCommand(
        workspacePath: "/tmp/session-a",
        provider: "kimi",
        model: "kimi-k2",
        skillsPath: "/tmp/session-a/skills/papercodex-agent-workspace"
    )
    try check(hermesTerminal.launchMode == .pty, "Hermes terminal command should launch in PTY mode")
    try check(hermesTerminal.arguments.contains("--tui") && hermesTerminal.arguments.contains("--skills"), "Hermes terminal command should use TUI mode with Paper Codex skills")

    let openClawTerminal = OpenClawRuntimeAdapter(executablePath: "/opt/homebrew/bin/openclaw").terminalCommand(
        workspacePath: "/tmp/session-a",
        sessionID: "paper-session",
        modelID: "kimi-coding/k2p5"
    )
    try check(openClawTerminal.launchMode == .pty, "OpenClaw Kimi terminal command should launch in PTY mode")
    try check(openClawTerminal.arguments.first == "tui", "OpenClaw Kimi terminal command should enter the TUI")
    try check(openClawTerminal.environmentOverrides["OPENCLAW_MODEL"] == "kimi-coding/k2p5", "OpenClaw Kimi terminal command should carry model selection")

    let piTerminal = PiRuntimeAdapter(executablePath: "/Users/chunqiu/.local/bin/pi").terminalCommand(
        workspacePath: "/tmp/session-a",
        systemPrompt: "Use Paper Codex citations.",
        agentInstructionsPath: "/tmp/session-a/agent_instructions.md"
    )
    try check(piTerminal.launchMode == .pty, "pi terminal command should launch in PTY mode")
    try check(piTerminal.arguments.contains("--session-dir") && piTerminal.arguments.contains("--append-system-prompt"), "pi terminal command should keep session storage and prompt files")
}

func runAgentSessionMigrationChecks() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-agent-session-migration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let databaseURL = root.appendingPathComponent("store.sqlite")
    let legacyDatabase = try SQLiteDatabase(path: databaseURL.path)
    try legacyDatabase.execute("""
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      codex_session_id TEXT,
      workspace_path TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE session_papers (
      session_id TEXT NOT NULL,
      paper_id TEXT NOT NULL,
      sort_order INTEGER NOT NULL,
      PRIMARY KEY (session_id, paper_id)
    );
    """)
    try legacyDatabase.run("""
    INSERT INTO sessions (id, title, codex_session_id, workspace_path, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?);
    """, bindings: [
        .text("legacy-session"),
        .text("Legacy Notes"),
        .text("codex-thread-legacy"),
        .text(root.appendingPathComponent("legacy-session", isDirectory: true).path),
        .text("2026-05-27T01:02:03Z"),
        .text("2026-05-27T01:02:03Z")
    ])
    try legacyDatabase.run("""
    INSERT INTO session_papers (session_id, paper_id, sort_order) VALUES (?, ?, ?);
    """, bindings: [.text("legacy-session"), .text("paper-a"), .int(0)])

    let repository = try PaperRepository(databasePath: databaseURL.path)
    try repository.migrate()
    let legacySession = try repository.fetchSession(id: "legacy-session")
    try check(legacySession?.codexSessionID == "codex-thread-legacy", "legacy codex_session_id should remain readable")
    try check(legacySession?.runtimeSessionID(for: "codex") == "codex-thread-legacy", "legacy codex_session_id should migrate into a codex runtime link")
    try check(legacySession?.defaultRuntimeID == "codex", "legacy codex sessions should default to the codex runtime")
    try check(legacySession?.workspaceMaterializationMode == .copyPDF, "legacy sessions should default to copied PDFs")

    var genericSession = PaperSession(
        id: "generic-session",
        title: "Generic Agent Notes",
        paperIDs: ["paper-a"],
        codexSessionID: nil,
        defaultRuntimeID: "claude-code",
        runtimeSessionLinks: [
            AgentRuntimeSessionLink(runtimeID: "claude-code", sessionID: "claude-thread-a"),
            AgentRuntimeSessionLink(runtimeID: "openclaw-kimi", sessionID: "kimi-thread-a")
        ],
        workspaceMaterializationMode: .symlinkPDF,
        workspacePath: root.appendingPathComponent("generic-session", isDirectory: true).path,
        createdAt: Date(timeIntervalSince1970: 1_777_220_300),
        updatedAt: Date(timeIntervalSince1970: 1_777_220_300)
    )
    genericSession.setRuntimeSessionID("codex-thread-a", for: "codex")
    try repository.upsertSession(genericSession)
    let fetchedGenericSession = try repository.fetchSession(id: "generic-session")
    try check(fetchedGenericSession == genericSession, "generic runtime session links should round-trip through SQLite")
    try check(fetchedGenericSession?.codexSessionID == "codex-thread-a", "codex runtime link should stay mirrored to codexSessionID")
    try check(fetchedGenericSession?.runtimeSessionID(for: "openclaw-kimi") == "kimi-thread-a", "non-Codex runtime links should be queryable by runtime id")

    let sourceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let appModelSource = try String(contentsOf: sourceRoot.appendingPathComponent("Sources/PaperCodexApp/AppModel.swift"))
    let coordinatorSource = try String(contentsOf: sourceRoot.appendingPathComponent("Sources/PaperCodexApp/AgentRunCoordinator.swift"))
    try check(
        coordinatorSource.contains("final class AgentRunCoordinator")
            && coordinatorSource.contains("func runChatTurn")
            && coordinatorSource.contains("func runDiscoverEnrichment")
            && coordinatorSource.contains("runtimeProfile")
            && coordinatorSource.contains("prefersWorkspaceImageOutput")
            && appModelSource.contains("private let agentRunCoordinator")
            && appModelSource.contains("agentRunCoordinator.runChatTurn")
            && appModelSource.contains("agentRunCoordinator.runDiscoverEnrichment")
            && !appModelSource.contains("private func runCodex(")
            && !appModelSource.contains("private func runCodexTurn("),
        "AppModel chat and discover execution should move behind AgentRunCoordinator"
    )
}

private final class AgentRuntimeSourceOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func text() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

func runAgentRuntimeSourceChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-agent-terminal-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let process = LocalPTYProcess(
        configuration: LocalPTYProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: [
                "-lc",
                #"printf 'READY\n'; IFS= read line; printf 'GOT:%s\n' "$line""#
            ],
            workingDirectoryPath: tempRoot.path,
            environment: ["TERM": "xterm-256color"],
            columns: 80,
            rows: 24
        )
    )
    let output = AgentRuntimeSourceOutputBuffer()
    try process.start { data in
        output.append(data)
    }
    try process.resize(columns: 100, rows: 30)
    try process.write("paper-terminal\n")
    let status = process.waitUntilExit()
    let outputText = output.text()
    try check(status == 0, "local PTY shell process should exit cleanly")
    try check(outputText.contains("READY"), "local PTY process should stream child output")
    try check(outputText.contains("GOT:paper-terminal"), "local PTY process should forward user input")

    let sourceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let ptySource = try String(contentsOf: sourceRoot.appendingPathComponent("Sources/PaperCodexCore/LocalPTYProcess.swift"))
    let terminalViewSource = try String(contentsOf: sourceRoot.appendingPathComponent("Sources/PaperCodexApp/AgentTerminalView.swift"))
    let terminalNativeSource = try String(contentsOf: sourceRoot.appendingPathComponent("Sources/PaperCodexApp/AgentTerminalNativePanelView.swift"))
    let chatViewSource = try String(contentsOf: sourceRoot.appendingPathComponent("Sources/PaperCodexApp/ChatView.swift"))
    let readerSessionToolbarSource = try String(contentsOf: sourceRoot.appendingPathComponent("Sources/PaperCodexApp/ReaderSessionToolbarView.swift"))
    let appModelSource = try String(contentsOf: sourceRoot.appendingPathComponent("Sources/PaperCodexApp/AppModel.swift"))

    try check(
        ptySource.contains("final class LocalPTYProcess")
            && ptySource.contains("openpty")
            && ptySource.contains("write(_ text")
            && ptySource.contains("resize(columns:")
            && ptySource.contains("rows:")
            && ptySource.contains("terminate()")
            && ptySource.contains("waitUntilExit"),
        "LocalPTYProcess should expose PTY start, input, resize, terminate, and wait primitives"
    )
    try check(
        terminalViewSource.contains("struct AgentTerminalView")
            && terminalViewSource.contains("AgentTerminalNativePanelView")
            && terminalViewSource.contains("terminalInputDraft")
            && terminalViewSource.contains("model.startAgentTerminal")
            && terminalViewSource.contains("model.sendAgentTerminalInput")
            && terminalViewSource.contains("model.resizeAgentTerminal")
            && terminalViewSource.contains("model.stopAgentTerminal")
            && terminalNativeSource.contains("AgentTerminalContainerView")
            && terminalNativeSource.contains("outputTextView")
            && terminalNativeSource.contains("inputTextView")
            && terminalNativeSource.contains("startStopButton")
            && terminalNativeSource.contains("sendButton")
            && terminalNativeSource.contains("resizeButton"),
        "AgentTerminalView should expose launch, input, resize, output, and stop controls"
    )
    try check(
        chatViewSource.contains("case terminal")
            && chatViewSource.contains("AgentTerminalView()")
            && readerSessionToolbarSource.contains("(\"terminal\", \"Terminal\")")
            && chatViewSource.contains("visibleCodexRunEvents(from run: ActiveCodexRun)")
            && chatViewSource.contains("case .thinking, .tool, .terminal, .answer, .usage, .warning, .error:"),
        "ChatView should add a Terminal session panel tab and show tool events in active agent runs"
    )
    try check(
        appModelSource.contains("@Published var agentTerminalState")
            && appModelSource.contains("activeAgentTerminalProcess")
            && appModelSource.contains("func startAgentTerminal")
            && appModelSource.contains("func sendAgentTerminalInput")
            && appModelSource.contains("func resizeAgentTerminal")
            && appModelSource.contains("func stopAgentTerminal")
            && appModelSource.contains("workspacePath.appendingPathComponent(\"turns\"")
            && appModelSource.contains("CodexRuntimeAdapter")
            && appModelSource.contains("ClaudeCodeRuntimeAdapter")
            && appModelSource.contains("HermesRuntimeAdapter")
            && appModelSource.contains("OpenClawRuntimeAdapter")
            && appModelSource.contains("PiRuntimeAdapter"),
        "AppModel should own Terminal state, log output under turns, and launch every PTY-capable runtime"
    )
}

func runAgentRuntimeSmokeScriptChecks() throws {
    let sourceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let scriptURL = sourceRoot.appendingPathComponent("scripts/agent-runtime-smoke.sh")
    let script = try String(contentsOf: scriptURL)
    try check(FileManager.default.isExecutableFile(atPath: scriptURL.path), "agent runtime smoke script should be executable")
    try check(script.contains("--codex") && script.contains("codex exec"), "smoke script should support Codex exec")
    try check(script.contains("--claude") && script.contains("claude --print"), "smoke script should support Claude Code print mode")
    try check(script.contains("--kimi-openclaw") && script.contains("openclaw agent"), "smoke script should support OpenClaw Kimi route")
    try check(script.contains("--hermes-kimi") && script.contains("hermes chat"), "smoke script should support Hermes Kimi fallback route")
    try check(script.contains("workspace_manifest.json"), "smoke script should create or inspect a Paper Codex workspace manifest")
    try check(script.contains("citation_contract_seen"), "smoke script should verify the citation contract")
    try check(script.contains("mcp_endpoint_seen"), "smoke script should verify MCP endpoint visibility")
    try check(script.contains("--write-test"), "smoke script should make write tests explicit rather than mutating app state by default")

    let readme = try String(contentsOf: sourceRoot.appendingPathComponent("README.md"))
    let readmeZH = try String(contentsOf: sourceRoot.appendingPathComponent("README.zh-CN.md"))
    try check(readme.contains("scripts/agent-runtime-smoke.sh --codex --claude --kimi-openclaw"), "English README should document multi-runtime smoke checks")
    try check(readme.contains("OpenClaw Kimi"), "English README should document the Kimi runtime route")
    try check(readmeZH.contains("scripts/agent-runtime-smoke.sh --codex --claude --kimi-openclaw"), "Chinese README should document multi-runtime smoke checks")
    try check(readmeZH.contains("OpenClaw Kimi"), "Chinese README should document the Kimi runtime route")
}

private func requiredProfile(
    _ id: String,
    in profilesByID: [String: AgentRuntimeProfile]
) throws -> AgentRuntimeProfile {
    guard let profile = profilesByID[id] else {
        throw CheckFailure(description: "missing default agent runtime profile \(id)")
    }
    return profile
}

func runGeneratedImageChecks() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-generated-images-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let oldImage = root.appendingPathComponent("ig_old.png")
    let newImage = root.appendingPathComponent("ig_new.png")
    let nestedDir = root.appendingPathComponent("nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
    let nestedImage = nestedDir.appendingPathComponent("ig_nested.jpeg")
    let note = root.appendingPathComponent("note.txt")

    try Data([0x89, 0x50, 0x4e, 0x47]).write(to: oldImage)
    let before = try GeneratedImageCollector.snapshot(in: root)
    try Data([0x89, 0x50, 0x4e, 0x47]).write(to: newImage)
    try Data([0xff, 0xd8, 0xff, 0xd9]).write(to: nestedImage)
    try "not an image".write(to: note, atomically: true, encoding: .utf8)

    let generated = try GeneratedImageCollector.newImages(in: root, excluding: before)
    try check(generated.map(\.lastPathComponent).sorted() == ["ig_nested.jpeg", "ig_new.png"], "generated image collector should return only new images")
    let markdown = GeneratedImageCollector.markdown(for: generated)
    try check(markdown.contains("![Generated image](\(newImage.path))"), "generated image markdown should include absolute image paths")
    try check(!markdown.contains(oldImage.path), "generated image markdown should not include previous images")

    let codexHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-generated-images-home-\(UUID().uuidString)", isDirectory: true)
    let threadDir = codexHome
        .appendingPathComponent("generated_images", isDirectory: true)
        .appendingPathComponent("thread-a", isDirectory: true)
    try FileManager.default.createDirectory(at: threadDir, withIntermediateDirectories: true)
    let externalOldImage = threadDir.appendingPathComponent("ig_old_external.png")
    let externalNewImage = threadDir.appendingPathComponent("ig_new_external.png")
    try Data([0x89, 0x50, 0x4e, 0x47]).write(to: externalOldImage)

    let codexBefore = try GeneratedImageCollector.snapshot(
        in: root,
        codexThreadID: "thread-a",
        codexHome: codexHome
    )
    try Data([0x89, 0x50, 0x4e, 0x47]).write(to: externalNewImage)
    let generatedWithCodexDefault = try GeneratedImageCollector.newImages(
        in: root,
        excluding: codexBefore,
        codexThreadID: "thread-a",
        codexHome: codexHome
    )
    let copiedExternalNewImage = root
        .appendingPathComponent("generated-images", isDirectory: true)
        .appendingPathComponent("ig_new_external.png")
    try check(FileManager.default.fileExists(atPath: copiedExternalNewImage.path), "generated image collector should copy Codex default images into the session workspace")
    try check(generatedWithCodexDefault.map(\.standardizedFileURL.path).contains(copiedExternalNewImage.standardizedFileURL.path), "generated image collector should return the copied workspace image path")
    try check(!generatedWithCodexDefault.map(\.standardizedFileURL.path).contains(externalOldImage.standardizedFileURL.path), "generated image collector should ignore old Codex default images")
    try check(!generatedWithCodexDefault.map(\.standardizedFileURL.path).contains(externalNewImage.standardizedFileURL.path), "generated image collector should not expose hidden Codex default paths directly")
}

func runImageRequestChecks() throws {
    try check(ImageGenerationRequestDetector.isImageRequest("生成一张图，展示实验流程"), "Chinese image-generation wording should request image generation")
    try check(ImageGenerationRequestDetector.isImageRequest("make an infographic about this paper"), "English infographic wording should request image generation")
    try check(!ImageGenerationRequestDetector.isImageRequest("解释一下图 2 的结果"), "discussing an existing figure should not force image generation")
    try check(!ImageGenerationRequestDetector.isImageRequest("这个论文讲了什么"), "ordinary paper QA should not request image generation")
}

func runCodexRecoveryChecks() throws {
    let notice = CodexFailureNotice(detail: "Codex process failed with status 1: session not found")
    try check(notice.messageContent.hasPrefix("Codex failed:"), "failure notice should use a stable prefix")
    try check(notice.messageContent.contains("session not found"), "failure notice should preserve Codex stderr detail")
    try check(CodexFailureNotice.parse(notice.messageContent) == notice, "failure notice should parse from stored chat content")
    try check(CodexFailureNotice.parse("A normal answer") == nil, "normal answers should not be treated as recovery notices")
}

func runPathChecks() throws {
    let overrideRoot = PaperCodexPaths.supportRoot(environment: [
        "EPISTEME_SUPPORT_ROOT": "/tmp/Episteme-isolated-root"
    ])
    try check(overrideRoot.path == "/tmp/Episteme-isolated-root", "support root should honor explicit Episteme environment override")

    let legacyOverrideRoot = PaperCodexPaths.supportRoot(environment: [
        "PAPER_CODEX_SUPPORT_ROOT": "/tmp/paper-codex-isolated-root"
    ])
    try check(legacyOverrideRoot.path == "/tmp/paper-codex-isolated-root", "support root should keep honoring the legacy Paper Codex environment override")

    let tempApplicationSupportRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("Episteme-path-check-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: tempApplicationSupportRoot.deletingLastPathComponent())
    }

    let defaultRoot = PaperCodexPaths.supportRoot(environment: [:], applicationSupportDirectory: tempApplicationSupportRoot)
    try check(defaultRoot.lastPathComponent == "Episteme", "default support root should end in Episteme")
    try check(defaultRoot.path.contains("Application Support"), "default support root should live under Application Support")

    let legacyRoot = tempApplicationSupportRoot.appendingPathComponent("PaperCodex", isDirectory: true)
    try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
    try Data("legacy-library".utf8).write(to: legacyRoot.appendingPathComponent("store.sqlite"))
    try PaperCodexPaths.migrateLegacySupportRootIfNeeded(
        to: defaultRoot,
        applicationSupportDirectory: tempApplicationSupportRoot
    )
    try check(FileManager.default.fileExists(atPath: defaultRoot.appendingPathComponent("store.sqlite").path), "legacy PaperCodex support data should migrate to Episteme")
    try check(!FileManager.default.fileExists(atPath: legacyRoot.path), "legacy PaperCodex support directory should be moved after migration")
}

func runBundleChecks() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let scriptURL = root
        .appendingPathComponent("scripts/build-app-bundle.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)
    let oldHost = ["nas", "pucao", "cn"].joined(separator: ".")
    let insecureHTTPKey = "NSExceptionAllows" + "InsecureHTTPLoads"
    try check(!script.contains(oldHost), "app bundle should not keep the old remote feed host")
    try check(!script.contains(insecureHTTPKey), "app bundle should not allow insecure HTTP for old feed hosts")
    try check(
        script.contains("configuration=\"${EPISTEME_BUILD_CONFIGURATION:-${PAPER_CODEX_BUILD_CONFIGURATION:-release}}\"")
            && script.contains("swift build -c \"$configuration\"")
            && script.contains("swift build -c \"$configuration\" --show-bin-path"),
        "installed app bundle should default to a Release build while keeping an explicit configuration override"
    )
    try check(script.contains("app_path=\"${EPISTEME_APP_PATH:-${PAPER_CODEX_APP_PATH:-$HOME/Applications/Episteme.app}}\""), "bundle script should default to Episteme.app while keeping the legacy app-path override")
    try check(script.contains("<string>Episteme</string>"), "app bundle display name should be Episteme")
    let katexResourceRoot = root.appendingPathComponent("Sources/PaperCodexApp/Resources/KaTeX")
    try check(
        script.contains("Sources/PaperCodexApp/Resources/KaTeX")
            && FileManager.default.fileExists(atPath: katexResourceRoot.appendingPathComponent("katex.min.css").path)
            && FileManager.default.fileExists(atPath: katexResourceRoot.appendingPathComponent("katex.min.js").path)
            && FileManager.default.fileExists(atPath: katexResourceRoot.appendingPathComponent("contrib/auto-render.min.js").path),
        "installed app bundle should include local KaTeX assets for offline chat formula rendering"
    )
}

func runFixtureLibraryChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-fixture-\(UUID().uuidString)", isDirectory: true)
    try seedFixtureLibrary(at: tempRoot)

    let repository = try PaperRepository(databasePath: tempRoot.appendingPathComponent("store.sqlite").path)
    let papers = try repository.fetchPapers()
    let categories = try repository.fetchCategories()
    let tags = try repository.fetchTags()
    let sessions = try repository.fetchSessions(paperID: "fixture-paper-a")
    let spans = try repository.fetchSpans(paperID: "fixture-paper-a")

    try check(papers.count == 2, "fixture library should contain two real PDF papers")
    try check(categories.count >= 2, "fixture library should contain nested categories")
    try check(tags.count >= 2, "fixture library should contain tags")
    try check(sessions.first?.paperIDs == ["fixture-paper-a", "fixture-paper-b"], "fixture session should include both papers in order")
    try check(!spans.isEmpty, "fixture library should persist extracted text spans")
}

func runWatchedFolderChecks() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-watch-\(UUID().uuidString)", isDirectory: true)
    let supportRoot = tempRoot.appendingPathComponent("support", isDirectory: true)
    let inbox = tempRoot.appendingPathComponent("inbox", isDirectory: true)
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    let databaseURL = supportRoot.appendingPathComponent("store.sqlite")
    try FileManager.default.createDirectory(at: supportRoot, withIntermediateDirectories: true)

    try writeFixturePDF(to: inbox.appendingPathComponent("paper-a.pdf"), lines: [
        "Watched folders import real PDF files.",
        "The scanner should persist page text and spans."
    ])
    try writeFixturePDF(to: inbox.appendingPathComponent("paper-b.pdf"), lines: [
        "A second PDF exercises deterministic folder scans.",
        "Duplicate scans should not create duplicate papers."
    ])
    try "ignore me".write(to: inbox.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

    let repository = try PaperRepository(databasePath: databaseURL.path)
    try repository.migrate()
    let now = Date(timeIntervalSince1970: 1_777_220_000)
    let folder = WatchedFolder(id: "watch-inbox", path: inbox.path, createdAt: now, lastScannedAt: nil)
    try repository.upsertWatchedFolder(folder)
    let storedFolders = try repository.fetchWatchedFolders()
    try check(storedFolders == [folder], "watched folder should persist")

    let scanner = WatchedFolderScanner(repository: repository, supportRoot: supportRoot)
    let firstScanResults = try scanner.scanAllWatchedFolders(now: now.addingTimeInterval(5))
    try check(firstScanResults.count == 1, "scan-all should scan one watched folder")
    let firstScan = firstScanResults[0]
    try check(firstScan.importedPapers.count == 2, "first watched folder scan should import two PDFs")
    try check(firstScan.existingPapers.isEmpty, "first watched folder scan should not report existing papers")
    let firstPapers = try repository.fetchPapers()
    try check(firstPapers.count == 2, "watched folder scan should persist imported papers")
    let storedFolder = try repository.fetchWatchedFolders().first
    try check(storedFolder?.lastScannedAt == now.addingTimeInterval(5), "watched folder scan should update last scanned time")

    try writeFixturePDF(to: inbox.appendingPathComponent("paper-c.pdf"), lines: [
        "A third PDF appears after the folder is already being watched.",
        "The next scan should import only this new paper."
    ])
    let changeScan = try scanner.scanAllWatchedFolders(now: now.addingTimeInterval(10))[0]
    try check(changeScan.importedPapers.count == 1, "changed watched folder scan should import the new PDF")
    try check(changeScan.existingPapers.count == 2, "changed watched folder scan should report prior papers as existing")
    let changedPapers = try repository.fetchPapers()
    try check(changedPapers.count == 3, "changed watched folder scan should persist the new paper")

    let secondScan = try scanner.scanAllWatchedFolders(now: now.addingTimeInterval(15))[0]
    try check(secondScan.importedPapers.isEmpty, "second watched folder scan should not re-import duplicates")
    try check(secondScan.existingPapers.count == 3, "second watched folder scan should report all existing papers")
    let secondPapers = try repository.fetchPapers()
    try check(secondPapers.count == 3, "duplicate watched folder scan should keep paper count stable")

    try repository.deleteWatchedFolder(id: folder.id)
    let removedFolders = try repository.fetchWatchedFolders()
    try check(removedFolders.isEmpty, "watched folder should be removable")
}

func runArxivFeedChecks() throws {
    let sample = """
    {
      "date": "2026-04-22",
      "count": 1,
      "groups": [
        {"key": "white", "count": 1},
        {"key": "neutral", "count": 0},
        {"key": "black", "count": 0}
      ],
      "tag_options": ["Diffusion", "Med", "Toolkit"],
      "papers": [
        {
          "id": "2604.18586",
          "arxiv_id": "2604.18586",
          "arxiv_id_versioned": "2604.18586v1",
          "title": {"en": "Who Shapes Brazil's Vaccine Debate?", "zh": "谁塑造了巴西的疫苗辩论？"},
          "abstract": {"en": "A longitudinal vaccine discourse study.", "zh": "一项疫苗话语纵向研究。"},
          "summary": {"en": "Semi-supervised stance detection over YouTube comments.", "zh": "对 YouTube 评论进行半监督立场检测。"},
          "authors": ["Geovana S. de Oliveira", "Ana P. C. Silva"],
          "categories": ["cs.CY", "cs.AI"],
          "primary_category": "cs.CY",
          "list_categories": ["cs.AI", "cs.CL"],
          "tags": ["text-cls", "SSL"],
          "comment": "Paper accepted at WebSci'26",
          "published": "2026-03-04T19:21:01Z",
          "updated": "2026-03-04T19:21:01Z",
          "list_date": "2026-04-22",
          "thumbnail_version": 3,
          "embedding": [0.1, 0.2, 0.3],
          "similarity": 0.91,
          "filter_group": "white",
          "is_favorite": true,
          "links": {
            "abs": "https://arxiv.org/abs/2604.18586",
            "pdf": "https://arxiv.org/pdf/2604.18586.pdf",
            "github": "https://github.com/example/paper-code",
            "code": "https://github.com/example/paper-code",
            "project": "https://example.org/paper",
            "hugging_face": "https://huggingface.co/example/paper"
          },
          "assets": {
            "small": {"path": "images/2026-04-22/2604.18586_small.png", "url": "/api/v1/assets/2026-04-22/2604.18586_small.png"},
            "large": {"path": "images/2026-04-22/2604.18586.png", "url": "/api/v1/assets/2026-04-22/2604.18586.png"}
          }
        }
      ]
    }
    """
    let decoder = JSONDecoder()
    let response = try decoder.decode(ArxivFeedResponse.self, from: Data(sample.utf8))
    try check(response.date == "2026-04-22", "arXiv feed response should decode the date")
    try check(response.papers.count == 1, "arXiv feed response should decode papers")
    try check(response.groups?.map(\.key) == ["white", "neutral", "black"], "local arXiv feed should decode group summaries")
    try check(response.tagOptions == ["Diffusion", "Med", "Toolkit"], "local arXiv feed should decode tag options")
    let paper = response.papers[0]
    try check(paper.id == "2604.18586", "arXiv paper should decode stable arxiv id")
    try check(paper.displayTitle(language: "zh") == "谁塑造了巴西的疫苗辩论？", "arXiv paper should prefer Chinese title in zh mode")
    try check(paper.displaySummary(language: "en") == "Semi-supervised stance detection over YouTube comments.", "arXiv paper should prefer English summary in en mode")
    try check(paper.assets.small?.path == "images/2026-04-22/2604.18586_small.png", "arXiv paper should decode small asset path")
    try check(paper.links.github == "https://github.com/example/paper-code", "arXiv paper should decode GitHub link")
    try check(paper.links.project == "https://example.org/paper", "arXiv paper should decode project link")
    try check(paper.links.huggingFace == "https://huggingface.co/example/paper", "arXiv paper should decode Hugging Face link")
    try check(paper.similarity == 0.91, "arXiv paper should decode similarity score")
    try check(paper.filterGroup == "white", "arXiv paper should decode local filter group")

    let quickPrompt = QuickPrompt(
        id: "qp-summary",
        title: "Summarize",
        content: "Summarize the main contribution."
    )
    let quickPromptEncoder = JSONEncoder()
    let decodedQuickPrompt = try decoder.decode(QuickPrompt.self, from: quickPromptEncoder.encode(quickPrompt))
    try check(decodedQuickPrompt == quickPrompt, "quick prompt should JSON round-trip")

    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-arxiv-cache-\(UUID().uuidString)", isDirectory: true)
    let cache = ArxivFeedCache(root: tempRoot)
    try cache.saveFeed(response)
    let cached = try cache.loadFeed(date: "2026-04-22")
    try check(cached == response, "arXiv feed cache should round-trip feed JSON")
    var rangePaperA = paper
    rangePaperA.listDate = "2026-04-28"
    rangePaperA.categories = ["cs.CV"]
    rangePaperA.primaryCategory = "cs.CV"
    rangePaperA.listCategories = ["cs.CV"]
    var rangePaperB = paper
    rangePaperB.id = "2604.18587"
    rangePaperB.arxivID = "2604.18587"
    rangePaperB.listDate = "2026-04-29"
    rangePaperB.categories = ["cs.CL"]
    rangePaperB.primaryCategory = "cs.CL"
    rangePaperB.listCategories = ["cs.CL"]
    let broaderRangeFeed = ArxivFeedResponse(
        date: "2026-04-22...2026-04-29",
        count: 2,
        papers: [rangePaperA, rangePaperB]
    )
    try cache.saveFeed(broaderRangeFeed)
    let containedRange = try DiscoverDateRange(start: "2026-04-27", end: "2026-04-29")
    let containingFeed = try cache.loadFeed(containing: containedRange)
    try check(containingFeed?.date == broaderRangeFeed.date, "arXiv feed cache should reuse a cached range that contains a Discover range")
    let assetURL = try cache.saveAsset(Data("small".utf8), path: "images/2026-04-22/2604.18586_small.png")
    try check(FileManager.default.fileExists(atPath: assetURL.path), "arXiv feed cache should store asset bytes")
    try check(
        response.uniqueAssets(includeLarge: false).map(\.path) == ["images/2026-04-22/2604.18586_small.png"],
        "arXiv feed should expose unique small assets for preload progress"
    )
    try check(
        response.uniqueAssets(includeLarge: true).map(\.path) == [
            "images/2026-04-22/2604.18586_small.png",
            "images/2026-04-22/2604.18586.png"
        ],
        "arXiv feed should expose unique small and large assets for preload progress"
    )
    let smallAssetSummary = try cache.assetCacheSummary(for: response, includeLarge: false)
    let fullAssetSummary = try cache.assetCacheSummary(for: response, includeLarge: true)
    try check(smallAssetSummary == ArxivFeedAssetCacheSummary(cached: 1, total: 1), "arXiv cache should count cached small assets")
    try check(fullAssetSummary == ArxivFeedAssetCacheSummary(cached: 1, total: 2), "arXiv cache should count cached full image assets")
    let emptyPDFSummary = try cache.pdfCacheSummary(for: response)
    try check(emptyPDFSummary == ArxivFeedAssetCacheSummary(cached: 0, total: 1), "arXiv cache should count missing PDFs")
    let savedPDFURL = try cache.savePDF(Data("%PDF-1.4\n".utf8), arxivID: paper.id, date: paper.listDate ?? response.date)
    try check(FileManager.default.fileExists(atPath: savedPDFURL.path), "arXiv cache should store cached PDF bytes")
    let exactCachedPDFURL = try cache.cachedPDFURL(arxivID: paper.id, date: paper.listDate ?? response.date)
    let discoveredCachedPDFURL = try cache.cachedPDFURL(arxivID: paper.id)
    try check(exactCachedPDFURL == savedPDFURL, "arXiv cache should find a PDF by exact feed date")
    try check(
        discoveredCachedPDFURL?.resolvingSymlinksInPath().path == savedPDFURL.resolvingSymlinksInPath().path,
        "arXiv cache should find a PDF across cached dates"
    )
    let pdfSummary = try cache.pdfCacheSummary(for: response)
    try check(pdfSummary == ArxivFeedAssetCacheSummary(cached: 1, total: 1), "arXiv cache should count cached PDFs")
    let cachedPaperByCanonicalID = try cache.loadPaper(arxivID: "2604.18586")
    let cachedPaperByVersionedID = try cache.loadPaper(arxivID: "2604.18586v1")
    try check(cachedPaperByCanonicalID?.id == "2604.18586", "arXiv cache should load paper metadata by canonical id")
    try check(cachedPaperByVersionedID?.arxivIDVersioned == "2604.18586v1", "arXiv cache should load paper metadata by versioned id")

    let metadata = PaperImportMetadata(
        title: paper.displayTitle(language: "en"),
        authors: paper.authors,
        year: paper.publishedYear,
        sourceURL: paper.links.abs
    )
    try check(metadata.year == 2026, "paper import metadata should derive published year")

    let importRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-arxiv-import-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)
    let importPDFURL = importRoot.appendingPathComponent("2604.18586.pdf")
    try writeFixturePDF(
        to: importPDFURL,
        lines: [
            "A real PDF import should keep arXiv feed metadata.",
            "The downloaded paper then becomes readable in Paper Codex."
        ]
    )
    let repository = try PaperRepository(databasePath: importRoot.appendingPathComponent("store.sqlite").path)
    try repository.migrate()
    let imported = try PaperLibraryImporter(repository: repository, supportRoot: importRoot)
        .importPDF(from: importPDFURL, metadata: metadata)
    try check(imported.didImport, "arXiv PDF import should create a new library paper")
    try check(imported.paper.title == "Who Shapes Brazil's Vaccine Debate?", "arXiv import should preserve feed title")
    try check(imported.paper.authors == paper.authors, "arXiv import should preserve feed authors")
    try check(imported.paper.year == 2026, "arXiv import should preserve feed year")
    try check(imported.paper.sourceURL == "https://arxiv.org/abs/2604.18586", "arXiv import should preserve source URL")

    let duplicateRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-arxiv-duplicate-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: duplicateRoot, withIntermediateDirectories: true)
    let duplicatePDFURL = duplicateRoot.appendingPathComponent("2604.18586.pdf")
    try FileManager.default.copyItem(at: importPDFURL, to: duplicatePDFURL)
    let duplicateRepository = try PaperRepository(databasePath: duplicateRoot.appendingPathComponent("store.sqlite").path)
    try duplicateRepository.migrate()
    let duplicateImporter = PaperLibraryImporter(repository: duplicateRepository, supportRoot: duplicateRoot)
    let manualImport = try duplicateImporter.importPDF(from: duplicatePDFURL)
    try check(manualImport.paper.sourceURL == nil, "manual import fixture should start without source URL")
    let enrichedDuplicate = try duplicateImporter.importPDF(from: duplicatePDFURL, metadata: metadata)
    try check(!enrichedDuplicate.didImport, "duplicate arXiv import should reuse the existing PDF")
    try check(enrichedDuplicate.paper.title == "Who Shapes Brazil's Vaccine Debate?", "duplicate arXiv import should enrich title")
    try check(enrichedDuplicate.paper.authors == paper.authors, "duplicate arXiv import should enrich authors")
    try check(enrichedDuplicate.paper.year == 2026, "duplicate arXiv import should enrich year")
    try check(enrichedDuplicate.paper.sourceURL == "https://arxiv.org/abs/2604.18586", "duplicate arXiv import should enrich source URL")

    let cacheRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-arxiv-cache-import-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let cachePDFURL = cacheRoot.appendingPathComponent("2604.18586.pdf")
    try FileManager.default.copyItem(at: importPDFURL, to: cachePDFURL)
    let cacheRepository = try PaperRepository(databasePath: cacheRoot.appendingPathComponent("store.sqlite").path)
    try cacheRepository.migrate()
    let cacheImporter = PaperLibraryImporter(repository: cacheRepository, supportRoot: cacheRoot)
    let cachedImport = try cacheImporter.importPDF(from: cachePDFURL, metadata: metadata, isSaved: false)
    try check(!cachedImport.paper.isSaved, "opening an arXiv paper should create an unsaved cached paper")
    try check(cachedImport.paper.filePath.contains("/cache/papers/"), "unsaved arXiv paper should live under disposable cache")
    let savedPapersAfterCacheOpen = try cacheRepository.fetchPapers()
    let cachedPapersByID = try cacheRepository.fetchPapers(ids: [cachedImport.paper.id])
    try check(savedPapersAfterCacheOpen.isEmpty, "unsaved cached paper should not appear in the library list")
    try check(cachedPapersByID.first?.id == cachedImport.paper.id, "cached paper should remain addressable for reader sessions")
    try check(cachedPapersByID.first?.isSaved == false, "cached paper fetched by ID should remain unsaved")
    let oldCachedPath = cachedImport.paper.filePath
    let promotedImport = try cacheImporter.importPDF(
        from: cachePDFURL,
        metadata: metadata,
        isSaved: true,
        storageSubpath: "cs.AI"
    )
    try check(!promotedImport.didImport, "saving a cached arXiv paper should reuse the cached import")
    try check(promotedImport.paper.isSaved, "saving a cached arXiv paper should promote it into the library")
    try check(promotedImport.paper.filePath.contains("/papers/cs-ai/"), "saved arXiv paper should follow the configured organization path")
    try check(FileManager.default.fileExists(atPath: promotedImport.paper.filePath), "promoted arXiv PDF should exist at the library path")
    try check(!FileManager.default.fileExists(atPath: oldCachedPath), "promoted arXiv PDF should be moved out of disposable cache")
}

func runLocalDiscoverEngineChecks() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let localDiscoverSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexCore/LocalDiscoverEngine.swift"))
    try check(
        localDiscoverSource.contains("public var feed: ArxivFeedResponse?")
            && localDiscoverSource.contains("feed: ArxivFeedResponse? = nil")
            && localDiscoverSource.contains("self.feed = feed"),
        "discover query cache should persist the full non-empty search feed, not only paper ids"
    )
    try check(
        localDiscoverSource.contains("public func loadLastQueryResult() throws -> DiscoverQueryResult?")
            && localDiscoverSource.contains("lastQueryResultURL")
            && localDiscoverSource.contains("try writeJSON(result, to: lastQueryResultURL())"),
        "discover query cache should expose the latest saved search result for startup restoration"
    )

    let range = try DiscoverDateRange(start: "2026-04-27", end: "2026-04-29")
    try check(range.dates == ["2026-04-27", "2026-04-28", "2026-04-29"], "discover date range should expand inclusive dates")
    try check(range.cacheLabel == "2026-04-27...2026-04-29", "discover date range should expose a stable cache label")
    let parsedRange = try DiscoverDateRange(cacheLabel: range.cacheLabel)
    let containedRange = try DiscoverDateRange(start: "2026-04-28", end: "2026-04-29")
    try check(parsedRange == range, "discover date range should parse cache labels")
    try check(range.contains(containedRange), "discover date range should recognize contained ranges")
    let last7Days = try DiscoverQuickRange.last7Days.dateRange(endingAt: "2026-04-29")
    try check(last7Days.start == "2026-04-23", "last 7 days should include the ending date")
    try check(last7Days.end == "2026-04-29", "quick range should preserve the ending date")
    var shanghaiCalendar = Calendar(identifier: .gregorian)
    shanghaiCalendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current
    let justAfterLocalMidnight = ISO8601DateFormatter().date(from: "2026-05-26T16:30:00Z")!
    let today = try DiscoverQuickRange.today.dateRange(containing: justAfterLocalMidnight, calendar: shanghaiCalendar)
    try check(today.start == "2026-05-27", "Today quick range should use the user's local date")
    try check(today.end == "2026-05-27", "Today quick range should end on the user's local date")
    let localLast7Days = try DiscoverQuickRange.last7Days.dateRange(containing: justAfterLocalMidnight, calendar: shanghaiCalendar)
    try check(localLast7Days.start == "2026-05-21", "Last 7 Days quick range should be anchored to the user's local today")
    try check(localLast7Days.end == "2026-05-27", "Last 7 Days quick range should end on the user's local today")

    let queryA = DiscoverQuery(
        keyword: "diffusion policy",
        dateRange: range,
        categories: ["cs.CV", "cs.AI"],
        similaritySourceIDs: ["tag-robot", "cat-vision"],
        rankingVersion: "rank-v1"
    )
    let queryB = DiscoverQuery(
        keyword: "  diffusion   policy ",
        dateRange: range,
        categories: ["cs.AI", "cs.CV", "cs.AI"],
        similaritySourceIDs: ["cat-vision", "tag-robot", "tag-robot"],
        rankingVersion: "rank-v1"
    )
    try check(queryA.normalized == queryB.normalized, "discover query normalization should ignore whitespace and duplicate order")
    try check(queryA.cacheKey == queryB.cacheKey, "discover query cache key should be stable for equivalent queries")
    let manyLibraryCategoryIDs = Set((1...63).map { "folder-\($0)" })
    let defaultSimilaritySources = manyLibraryCategoryIDs.sorted().map { "category:\($0)" }
    try check(
        DiscoverSaveCategorySuggestion.categoryIDs(
            fromExplicitSimilaritySourceIDs: defaultSimilaritySources,
            existingCategoryIDs: manyLibraryCategoryIDs
        ).isEmpty,
        "Discover save preselection should ignore bulk/default similarity folders instead of opening with dozens selected"
    )
    try check(
        DiscoverSaveCategorySuggestion.categoryIDs(
            fromExplicitSimilaritySourceIDs: ["category:folder-7"],
            existingCategoryIDs: manyLibraryCategoryIDs
        ) == ["folder-7"],
        "Discover save preselection should keep one explicit folder similarity source"
    )
    try check(
        DiscoverSaveCategorySuggestion.categoryIDs(
            fromExplicitSimilaritySourceIDs: ["tag:diffusion"],
            existingCategoryIDs: manyLibraryCategoryIDs
        ).isEmpty,
        "Discover save preselection should not treat tag similarity sources as library destinations"
    )

    func cachedDiscoverPaper(id: String, listDate: String, categories: [String], title: String) -> ArxivFeedPaper {
        ArxivFeedPaper(
            id: id,
            arxivID: id,
            arxivIDVersioned: nil,
            title: ArxivLocalizedText(en: title, zh: ""),
            abstract: ArxivLocalizedText(en: title, zh: ""),
            summary: ArxivLocalizedText(en: "", zh: ""),
            authors: ["Alice Example"],
            categories: categories,
            primaryCategory: categories.first,
            listCategories: categories,
            tags: [],
            comment: "",
            published: "\(listDate)T00:00:00Z",
            updated: nil,
            listDate: listDate,
            thumbnailVersion: nil,
            embedding: nil,
            links: ArxivFeedLinks(abs: "https://arxiv.org/abs/\(id)", pdf: nil),
            assets: ArxivFeedAssets(small: nil, large: nil)
        )
    }
    let broadCachedFeed = ArxivFeedResponse(
        date: "2026-04-23...2026-04-30",
        count: 3,
        papers: [
            cachedDiscoverPaper(id: "2604.18803", listDate: "2026-04-27", categories: ["cs.CV"], title: "Vision cache hit"),
            cachedDiscoverPaper(id: "2604.18804", listDate: "2026-04-26", categories: ["cs.CV"], title: "Outside date"),
            cachedDiscoverPaper(id: "2604.18805", listDate: "2026-04-28", categories: ["math.OC"], title: "Outside category")
        ]
    )
    let scopedFeed = broadCachedFeed.scoped(to: queryA.normalized)
    try check(scopedFeed.date == range.cacheLabel, "scoped cached Discover feeds should use the requested range label")
    try check(scopedFeed.papers.map(\.id) == ["2604.18803"], "scoped cached Discover feeds should filter by requested date range and categories")

    let enrichment = DiscoverPaperEnrichment(
        arxivID: "2604.18803",
        processorVersion: DiscoverPaperEnrichment.currentProcessorVersion,
        promptVersion: DiscoverPaperEnrichment.currentPromptVersion,
        modelIdentity: "codex",
        titleZH: "本地论文阅读器",
        summaryZH: "提出一个本地优先的论文发现和阅读流程。",
        contribution: "把 arXiv 检索、缓存和阅读工作流连接起来。",
        tags: ["paper-reader", "local-first"],
        links: ["github": "https://github.com/example/paper-reader"],
        generatedAt: Date(timeIntervalSince1970: 1_777_300_000),
        error: nil
    )
    try check(enrichment.isCurrent, "fresh enrichment should be current")

    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("paper-codex-discover-engine-\(UUID().uuidString)", isDirectory: true)
    let cache = LocalDiscoverCache(root: tempRoot)
    try cache.saveQueryResult(
        DiscoverQueryResult(
            query: queryA.normalized,
            arxivIDs: ["2604.18803"],
            generatedAt: enrichment.generatedAt,
            feed: ArxivFeedResponse(
                date: "2026-04-27...2026-04-29",
                count: 1,
                papers: [
                    ArxivFeedPaper(
                        id: "2604.18803",
                        arxivID: "2604.18803",
                        arxivIDVersioned: nil,
                        title: ArxivLocalizedText(en: "Local Paper Reader", zh: ""),
                        abstract: ArxivLocalizedText(en: "A local-first paper reader.", zh: ""),
                        summary: ArxivLocalizedText(en: "", zh: ""),
                        authors: ["Alice Example"],
                        categories: ["cs.CV"],
                        primaryCategory: "cs.CV",
                        listCategories: ["cs.CV"],
                        tags: ["paper-reader"],
                        comment: "",
                        published: "2026-04-27T00:00:00Z",
                        updated: nil,
                        listDate: "2026-04-27",
                        thumbnailVersion: nil,
                        embedding: nil,
                        links: ArxivFeedLinks(abs: "https://arxiv.org/abs/2604.18803", pdf: nil),
                        assets: ArxivFeedAssets(small: nil, large: nil)
                    )
                ]
            )
        )
    )
    let fragmentQuery = DiscoverQuery(
        keyword: queryA.keyword,
        dateRange: try DiscoverDateRange(start: "2026-04-30", end: "2026-04-30"),
        categories: queryA.categories,
        similaritySourceIDs: queryA.similaritySourceIDs,
        rankingVersion: queryA.rankingVersion
    ).normalized
    try cache.saveQueryResult(
        DiscoverQueryResult(
            query: fragmentQuery,
            arxivIDs: ["2604.18804"],
            generatedAt: Date(timeIntervalSince1970: 1_777_300_100),
            feed: ArxivFeedResponse(
                date: fragmentQuery.dateRange.cacheLabel,
                count: 1,
                papers: [
                    cachedDiscoverPaper(
                        id: "2604.18804",
                        listDate: "2026-04-30",
                        categories: ["cs.CV"],
                        title: "Fragment cache hit"
                    )
                ]
            )
        )
    )
    let outsideQuery = DiscoverQuery(
        keyword: queryA.keyword,
        dateRange: try DiscoverDateRange(start: "2026-05-01", end: "2026-05-01"),
        categories: queryA.categories,
        similaritySourceIDs: queryA.similaritySourceIDs,
        rankingVersion: queryA.rankingVersion
    ).normalized
    try cache.saveQueryResult(
        DiscoverQueryResult(
            query: outsideQuery,
            arxivIDs: ["2605.18805"],
            generatedAt: Date(timeIntervalSince1970: 1_777_300_200),
            feed: ArxivFeedResponse(
                date: outsideQuery.dateRange.cacheLabel,
                count: 1,
                papers: [
                    cachedDiscoverPaper(
                        id: "2605.18805",
                        listDate: "2026-05-01",
                        categories: ["cs.CV"],
                        title: "Outside requested range"
                    )
                ]
            )
        )
    )
    try cache.saveEnrichment(enrichment)
    let cachedQuery = try cache.loadQueryResult(cacheKey: queryA.cacheKey)
    let cachedEnrichment = try cache.loadEnrichment(arxivID: "2604.18803")
    try check(cachedQuery?.arxivIDs == ["2604.18803"], "discover query cache should round-trip ordered ids")
    try check(cachedQuery?.feed?.papers.map(\.id) == ["2604.18803"], "discover query cache should round-trip the full search feed")
    try check(cachedEnrichment?.titleZH == "本地论文阅读器", "discover enrichment cache should round-trip processed metadata")
    let combinedQuery = DiscoverQuery(
        keyword: queryA.keyword,
        dateRange: try DiscoverDateRange(start: "2026-04-27", end: "2026-04-30"),
        categories: queryA.categories,
        similaritySourceIDs: queryA.similaritySourceIDs,
        rankingVersion: queryA.rankingVersion
    ).normalized
    let cachedFragments = try cache.loadQueryResults(containedIn: combinedQuery)
    try check(
        cachedFragments.map { $0.query.dateRange.cacheLabel } == [
            "2026-04-30...2026-04-30",
            "2026-04-27...2026-04-29"
        ],
        "discover query cache should find reusable cached fragments contained by a broader search"
    )

    let embeddingText = "Recursive multi-agent systems coordinate latent-state reasoning."
    let embeddingRecord = DiscoverEmbeddingRecord(
        sourceID: "arxiv:2604.18803",
        model: "text-embedding-v4",
        textHash: DiscoverEmbeddingText.hash(embeddingText),
        vector: [0.1, 0.2, 0.3],
        generatedAt: enrichment.generatedAt
    )
    try cache.saveEmbedding(embeddingRecord)
    let cachedEmbedding = try cache.loadEmbedding(
        sourceID: "arxiv:2604.18803",
        model: "text-embedding-v4",
        text: embeddingText
    )
    let staleEmbedding = try cache.loadEmbedding(
        sourceID: "arxiv:2604.18803",
        model: "text-embedding-v4",
        text: "\(embeddingText) changed"
    )
    try check(cachedEmbedding?.vector == [0.1, 0.2, 0.3], "discover embedding cache should round-trip vectors keyed by text hash")
    try check(staleEmbedding == nil, "discover embedding cache should ignore stale text hashes")

    let embeddingEndpointA = try OpenAICompatibleEmbeddingClient.endpointURL(for: "https://api.openai.com")
    let embeddingEndpointB = try OpenAICompatibleEmbeddingClient.endpointURL(for: "https://dashscope.aliyuncs.com/compatible-mode/v1")
    let embeddingEndpointC = try OpenAICompatibleEmbeddingClient.endpointURL(for: "https://example.com/custom/embeddings")
    try check(embeddingEndpointA.absoluteString == "https://api.openai.com/v1/embeddings", "embedding endpoint should append /v1/embeddings to provider roots")
    try check(embeddingEndpointB.absoluteString == "https://dashscope.aliyuncs.com/compatible-mode/v1/embeddings", "embedding endpoint should append /embeddings to /v1 base URLs")
    try check(embeddingEndpointC.absoluteString == "https://example.com/custom/embeddings", "embedding endpoint should preserve explicit embeddings URLs")
    let embeddingBatches = OpenAICompatibleEmbeddingClient.embeddingBatches(
        (1...23).map { "paper-\($0)" }
    )
    try check(
        embeddingBatches.map(\.count) == [10, 10, 3],
        "embedding client should split large requests into provider-safe batches"
    )

    let codexJSON = """
    {
      "title_zh": "本地优先的发现引擎",
      "summary_zh": "这个工作把 arXiv 检索、本地缓存和快速浏览结合起来。",
      "contribution": "提出一个本地优先的新论文发现流程。",
      "tags": ["local-first", "arxiv", "local-first"],
      "links": {"github": "https://github.com/example/discover"}
    }
    """
    let parsed = try DiscoverEnrichmentParser.parse(
        codexJSON,
        arxivID: "2604.18804",
        modelIdentity: "codex-test",
        generatedAt: Date(timeIntervalSince1970: 1_777_300_010)
    )
    try check(parsed.titleZH == "本地优先的发现引擎", "discover parser should read Chinese title")
    try check(parsed.tags == ["local-first", "arxiv"], "discover parser should dedupe tags while preserving order")
    try check(parsed.links["github"] == "https://github.com/example/discover", "discover parser should preserve extracted links")

    let partialCodexJSON = """
    {
      "title_zh": "只翻译标题"
    }
    """
    let partialParsed = try DiscoverEnrichmentParser.parse(
        partialCodexJSON,
        arxivID: "2604.18805",
        modelIdentity: "codex-test",
        generatedAt: Date(timeIntervalSince1970: 1_777_300_011)
    )
    try check(partialParsed.titleZH == "只翻译标题", "discover parser should read action-specific partial enrichment JSON")
    try check(partialParsed.summaryZH.isEmpty && partialParsed.tags.isEmpty, "discover parser should default omitted enrichment fields to empty values")
}

func runLocalArxivClientChecks() throws {
    let extractedIDs = ArxivIDExtractor.extractVersionedIDs(
        from: """
        read arXiv:2604.18803v2 and https://arxiv.org/abs/2501.01234.
        Also fetch random text 2604.18803 and old id hep-th/9901001v3 plus https://arxiv.org/pdf/2408.99999.pdf
        """
    )
    try check(
        extractedIDs == ["2604.18803v2", "2501.01234", "hep-th/9901001v3", "2408.99999"],
        "arXiv ID extractor should parse multiple canonical and versioned ids from arbitrary text"
    )
    try check(
        ArxivIDExtractor.extractCanonicalIDs(from: extractedIDs.joined(separator: " ")) == ["2604.18803", "2501.01234", "hep-th/9901001", "2408.99999"],
        "arXiv ID extractor should expose canonical ids without version suffixes"
    )

    let apiRange = try DiscoverDateRange(start: "2026-04-27", end: "2026-04-29")
    let apiQuery = try LocalArxivClient.submittedDateSearchQuery(range: apiRange, categories: ["cs.AI", "cs.CL"])
    let apiURL = try LocalArxivClient.apiSearchURL(
        query: apiQuery,
        start: 2_000,
        maxResults: 1_000,
        sortBy: .submittedDate,
        sortOrder: .descending
    )
    let defaultConfiguration = LocalArxivClientConfiguration(categories: ["cs.AI"])
    let defaultAPIURL = try LocalArxivClient.apiSearchURL(
        query: apiQuery,
        start: 0,
        maxResults: defaultConfiguration.apiPageSize,
        sortBy: .submittedDate,
        sortOrder: .descending
    )
    let relevanceURL = try LocalArxivClient.apiSearchURL(query: "all:diffusion", start: 0, maxResults: 25)
    try check(apiQuery == "(cat:cs.AI OR cat:cs.CL) AND submittedDate:[202604270000 TO 202604292359]", "local arXiv client should build submittedDate category range queries")
    try check(apiURL.absoluteString.contains("sortBy=submittedDate"), "local arXiv API URL should sort by submitted date")
    try check(apiURL.absoluteString.contains("sortOrder=descending"), "local arXiv API URL should sort newest papers first")
    try check(apiURL.absoluteString.contains("start=2000"), "local arXiv API URL should support paging start")
    try check(apiURL.absoluteString.contains("max_results=1000"), "local arXiv API URL should support paging size")
    try check(relevanceURL.absoluteString.contains("sortBy=relevance"), "generic arXiv search URLs should default to arXiv relevance sorting")
    try check(defaultConfiguration.apiPageSize == 500, "local arXiv client should default to moderate API pages to reduce rate-limit pressure without using 1000-result requests")
    try check(defaultAPIURL.absoluteString.contains("max_results=500"), "local arXiv default API URL should avoid 1000-result search requests")

    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let clientSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexCore/LocalArxivClient.swift"))
    let appModelSource = try String(contentsOf: root.appendingPathComponent("Sources/PaperCodexApp/AppModel.swift"))
    try check(clientSource.contains("isRetriableNetworkError"), "local arXiv client should retry transient network failures")
    try check(
        LocalArxivClient.isRetriableNetworkError(URLError(.secureConnectionFailed)),
        "local arXiv client should retry transient TLS connection failures"
    )
    try check(
        !LocalArxivClient.isRetriableNetworkError(URLError(.serverCertificateUntrusted)),
        "local arXiv client should not retry permanent certificate trust failures"
    )
    let tlsFailureDescription = LocalArxivClientError.networkFailure(
        url: "https://export.arxiv.org/api/query",
        reason: "TLS connection failed."
    ).description
    try check(
        tlsFailureDescription == "arXiv network request failed for https://export.arxiv.org/api/query. TLS connection failed.",
        "local arXiv network failures should produce concise UI-facing descriptions"
    )
    try check(clientSource.contains("http.statusCode == 429"), "local arXiv client should handle export API rate limiting")
    try check(clientSource.contains("arXivAPIRequestDelayNanoseconds"), "local arXiv metadata batches should be throttled")
    try check(
        clientSource.contains("LocalArxivRequestGate")
            && clientSource.contains("await Self.requestGate.acquire()")
            && clientSource.contains("await Self.requestGate.release()")
            && clientSource.contains("await Self.requestGate.postpone"),
        "local arXiv requests should share a process-wide single-connection rate-limit gate"
    )
    try check(
        appModelSource.contains("configuration.httpMaximumConnectionsPerHost = 1"),
        "app arXiv URL sessions should avoid opening parallel connections to arXiv"
    )
    try check(
        appModelSource.contains("configuration.timeoutIntervalForRequest = 45")
            && appModelSource.contains("configuration.timeoutIntervalForResource = 180"),
        "app arXiv metadata requests should allow slow export API responses before treating them as timeouts"
    )
    try check(
        appModelSource.contains("cachedArxivPaperForLibraryImport")
            && appModelSource.contains("arxivLibraryImportRetryDelaysNanoseconds")
            && appModelSource.contains("isArxivRateLimitError")
            && appModelSource.contains("Retrying arXiv Import"),
        "library arXiv imports should reuse cached metadata and keep 429-limited placeholders queued for delayed retry"
    )

    let multiDateHTML = """
    <html><body>
    <h3>Wed, 29 Apr 2026 (showing first 2 of 2 entries)</h3>
    <dl>
      <dt><a href="/abs/2604.20002">arXiv:2604.20002</a></dt>
      <dt><a href="/abs/2604.20001v2">arXiv:2604.20001v2</a></dt>
    </dl>
    <h3>Tue, 28 Apr 2026 (showing first 1 of 1 entries)</h3>
    <dl>
      <dt><a href="/abs/2604.19999">arXiv:2604.19999</a></dt>
    </dl>
    </body></html>
    """
    let listPages = try LocalArxivClient.parseListPages(multiDateHTML)
    try check(listPages.map(\.date) == ["2026-04-29", "2026-04-28"], "local arXiv parser should parse every date section")
    try check(listPages[0].ids == ["2604.20002", "2604.20001"], "local arXiv parser should dedupe versioned ids per section")
    try check(listPages[1].ids == ["2604.19999"], "local arXiv parser should parse ids in later sections")

    let listHTML = """
    <html><body>
    <h3>Wed, 29 Apr 2026 (showing first 3 of 3 entries)</h3>
    <dl>
      <dt><a name="item1">[1]</a><a href="/abs/2604.18803">arXiv:2604.18803</a></dt>
      <dt><a name="item2">[2]</a><a href="/abs/2604.18804v2">arXiv:2604.18804v2</a></dt>
      <dt><a name="item3">[3]</a><a href="/abs/2604.18803v2">arXiv:2604.18803v2</a></dt>
    </dl>
    <h3>Tue, 28 Apr 2026 (showing first 1 of 1 entries)</h3>
    </body></html>
    """
    let parsedList = try LocalArxivClient.parseListPage(listHTML)
    try check(parsedList.date == "2026-04-29", "local arXiv list parser should parse newest date heading")
    try check(parsedList.ids == ["2604.18803", "2604.18804"], "local arXiv list parser should dedupe versioned IDs")

    let atomXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom">
      <entry>
        <id>http://arxiv.org/abs/2604.18803v1</id>
        <updated>2026-04-29T12:00:00Z</updated>
        <published>2026-04-29T08:00:00Z</published>
        <title>  A Local Paper Reader  </title>
        <summary>  We present a local-first paper reader.  </summary>
        <author><name>Alice Example</name></author>
        <author><name>Bob Example</name></author>
        <arxiv:comment>Code: https://github.com/example/paper-reader</arxiv:comment>
        <arxiv:primary_category term="cs.CL" />
        <category term="cs.CL" />
        <category term="cs.AI" />
      </entry>
    </feed>
    """
    let parsedPapers = try LocalArxivClient.parseAtomFeed(
        atomXML,
        listDate: "2026-04-29",
        listCategoriesByID: ["2604.18803": ["cs.CL"]]
    )
    try check(parsedPapers.count == 1, "local arXiv Atom parser should parse one entry")
    let paper = parsedPapers[0]
    try check(paper.id == "2604.18803", "local arXiv Atom parser should normalize arXiv ID")
    try check(paper.arxivIDVersioned == "2604.18803v1", "local arXiv Atom parser should keep versioned ID")
    try check(paper.title.en == "A Local Paper Reader", "local arXiv Atom parser should normalize title whitespace")
    try check(paper.abstract.en == "We present a local-first paper reader.", "local arXiv Atom parser should normalize abstract whitespace")
    try check(paper.links.abs == "https://arxiv.org/abs/2604.18803", "local arXiv mapper should provide canonical abs link")
    try check(paper.links.pdf == "https://arxiv.org/pdf/2604.18803.pdf", "local arXiv mapper should provide canonical PDF link")
    try check(paper.links.github == "https://github.com/example/paper-reader", "local arXiv mapper should extract GitHub links from comments")
    try check(paper.listCategories == ["cs.CL"], "local arXiv mapper should preserve list categories")
}

func runLocalDiscoverPreferenceChecks() throws {
    let preferences = LocalDiscoverPreferences(
        categories: ["cs.CV", "cs.CL", "cs.CV"],
        whitelistTags: ["agent", "code", "agent"],
        blacklistTags: ["survey"],
        similaritySourceTagIDs: ["tag-agent", "tag-agent"],
        similarityCategoryIDs: ["cat-vision", "cat-rl", "cat-vision"],
        enrichment: LocalEnrichmentPreferences(autoEnrichOnOpen: true, autoEnrichOnSave: true),
        embedding: EmbeddingProviderSettings(enabled: true, baseURL: "https://dashscope.aliyuncs.com", model: "text-embedding-v4")
    )
    let normalized = preferences.normalized
    try check(normalized.categories == ["cs.CV", "cs.CL"], "local discover preferences should dedupe categories")
    try check(normalized.whitelistTags == ["agent", "code"], "local discover preferences should dedupe whitelist tags")
    try check(normalized.similaritySourceTagIDs == ["tag-agent"], "local discover preferences should dedupe similarity sources")
    try check(normalized.similarityCategoryIDs == ["cat-vision", "cat-rl"], "local discover preferences should dedupe similarity category defaults")
    try check(normalized.embedding.model == "text-embedding-v4", "embedding settings should preserve model")

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(LocalDiscoverPreferences.self, from: encoder.encode(normalized))
    try check(decoded == normalized, "local discover preferences should JSON round-trip")
}

func runSimilarityRankerChecks() throws {
    let papers = [
        ArxivFeedPaper(
            id: "a",
            arxivID: "a",
            arxivIDVersioned: nil,
            title: ArxivLocalizedText(en: "A", zh: ""),
            abstract: ArxivLocalizedText(en: "A", zh: ""),
            summary: ArxivLocalizedText(en: "", zh: ""),
            authors: [],
            categories: ["cs.CL"],
            primaryCategory: "cs.CL",
            listCategories: ["cs.CL"],
            tags: ["agent"],
            comment: "",
            published: "2026-04-29T00:00:00Z",
            updated: nil,
            listDate: "2026-04-29",
            thumbnailVersion: nil,
            embedding: [1, 0],
            links: ArxivFeedLinks(abs: nil, pdf: nil),
            assets: ArxivFeedAssets(small: nil, large: nil)
        ),
        ArxivFeedPaper(
            id: "b",
            arxivID: "b",
            arxivIDVersioned: nil,
            title: ArxivLocalizedText(en: "B", zh: ""),
            abstract: ArxivLocalizedText(en: "B", zh: ""),
            summary: ArxivLocalizedText(en: "", zh: ""),
            authors: [],
            categories: ["cs.CL"],
            primaryCategory: "cs.CL",
            listCategories: ["cs.CL"],
            tags: ["survey"],
            comment: "",
            published: "2026-04-29T00:00:00Z",
            updated: nil,
            listDate: "2026-04-29",
            thumbnailVersion: nil,
            embedding: [0, 1],
            links: ArxivFeedLinks(abs: nil, pdf: nil),
            assets: ArxivFeedAssets(small: nil, large: nil)
        ),
        ArxivFeedPaper(
            id: "c",
            arxivID: "c",
            arxivIDVersioned: nil,
            title: ArxivLocalizedText(en: "C", zh: ""),
            abstract: ArxivLocalizedText(en: "C", zh: ""),
            summary: ArxivLocalizedText(en: "", zh: ""),
            authors: [],
            categories: ["cs.CL"],
            primaryCategory: "cs.CL",
            listCategories: ["cs.CL"],
            tags: [],
            comment: "",
            published: "2026-04-29T00:00:00Z",
            updated: nil,
            listDate: "2026-04-29",
            thumbnailVersion: nil,
            embedding: [0.9, 0.1],
            links: ArxivFeedLinks(abs: nil, pdf: nil),
            assets: ArxivFeedAssets(small: nil, large: nil)
        )
    ]
    let ranked = SimilarityRanker.rank(
        papers: papers,
        whitelistTags: ["agent"],
        blacklistTags: ["survey"],
        interestVectors: [[1, 0]]
    )
    try check(ranked.map(\.id) == ["a", "c", "b"], "similarity ranker should order white, neutral, black groups")
    try check(ranked[0].filterGroup == "white", "similarity ranker should mark whitelist group")
    try check(ranked[2].filterGroup == "black", "similarity ranker should mark blacklist group")
    try check((ranked[0].similarity ?? 0) > (ranked[1].similarity ?? 0), "similarity ranker should attach cosine scores")
    try check(SimilarityRanker.meanVector([[1, 0], [0, 1]]) == [0.5, 0.5], "similarity ranker should compute collection mean vectors")
    try check(SimilarityRanker.cosine([1, 0], [0, 1]) == 0, "similarity ranker should return zero for orthogonal vectors")
    let groupedRanked = SimilarityRanker.rank(
        papers: papers,
        whitelistTags: [],
        blacklistTags: [],
        interestVectorGroups: [
            [[1, 0], [0, 1]],
            [[0, 1]]
        ]
    )
    try check(
        groupedRanked.map(\.id) == ["b", "c", "a"],
        "similarity ranker should use max category score after averaging each category"
    )
    try check(
        abs((groupedRanked[0].similarity ?? 0) - 1.0) < 0.0001,
        "category similarity should average scores within a category before taking the max"
    )
}

func seedFixtureLibrary(at root: URL) throws {
    let fileManager = FileManager.default
    let storeURL = root.appendingPathComponent("store.sqlite")
    if fileManager.fileExists(atPath: storeURL.path) {
        throw CheckFailure(description: "refusing to overwrite existing fixture store at \(storeURL.path)")
    }

    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try PaperRepository(databasePath: storeURL.path)
    try repository.migrate()

    let now = Date(timeIntervalSince1970: 1_777_220_000)
    let paperA = try seedFixturePaper(
        id: "fixture-paper-a",
        title: "Representation Autoencoders for Controllable Diffusion",
        authors: ["Alice Chen", "Bo Liu"],
        year: 2026,
        lines: [
            "Representation autoencoders preserve semantic coordinates.",
            "The decoder controls latent trajectories during diffusion.",
            "This selected mechanism is useful for source-grounded answers."
        ],
        root: root,
        repository: repository,
        importedAt: now
    )
    let paperB = try seedFixturePaper(
        id: "fixture-paper-b",
        title: "Latent Control Benchmarks for Generative Models",
        authors: ["Carla Park"],
        year: 2025,
        lines: [
            "Latent control benchmarks compare paired edit trajectories.",
            "Evaluation should inspect source-aligned changes.",
            "Cross-paper sessions keep comparison context explicit."
        ],
        root: root,
        repository: repository,
        importedAt: now
    )

    let parentCategory = Category(id: "cat-methods", parentID: nil, name: "Methods", sortOrder: 1)
    let childCategory = Category(id: "cat-methods-latent", parentID: parentCategory.id, name: "Latent Control", sortOrder: 2)
    let tagReading = PaperTag(id: "tag-reading", name: "reading")
    let tagSourceGrounded = PaperTag(id: "tag-source-grounded", name: "source-grounded")
    try repository.upsertCategory(parentCategory)
    try repository.upsertCategory(childCategory)
    try repository.upsertTag(tagReading)
    try repository.upsertTag(tagSourceGrounded)
    for paper in [paperA, paperB] {
        try repository.assignPaper(paper.id, toCategory: childCategory.id)
        try repository.assignPaper(paper.id, toTag: tagReading.id)
        try repository.assignPaper(paper.id, toTag: tagSourceGrounded.id)
    }

    let session = PaperSession(
        id: "fixture-session-compare",
        title: "Compare mechanisms",
        paperIDs: [paperA.id, paperB.id],
        codexSessionID: nil,
        workspacePath: root.appendingPathComponent("sessions/fixture-session-compare", isDirectory: true).path,
        createdAt: now,
        updatedAt: now
    )
    try repository.upsertSession(session)
    let paperASpans = try repository.fetchSpans(paperID: paperA.id)
    let paperBSpans = try repository.fetchSpans(paperID: paperB.id)
    guard let paperASpan = paperASpans.first, let paperBSpan = paperBSpans.first else {
        throw CheckFailure(description: "fixture PDFs did not produce spans")
    }
    try repository.appendMessage(ChatMessage(
        id: "fixture-message-user",
        sessionID: session.id,
        role: .user,
        content: "Compare the mechanism claims in these two papers.",
        createdAt: now
    ))
    try repository.appendMessage(ChatMessage(
        id: "fixture-message-codex",
        sessionID: session.id,
        role: .codex,
        content: "Paper A frames control through representation coordinates [[cite:\(paperASpan.id)]], while Paper B frames it as paired trajectory evaluation [[cite:\(paperBSpan.id)]].",
        createdAt: now.addingTimeInterval(1)
    ))

    let pagesByPaperID = [
        paperA.id: try repository.fetchPages(paperID: paperA.id),
        paperB.id: try repository.fetchPages(paperID: paperB.id)
    ]
    let spansByPaperID = [
        paperA.id: paperASpans,
        paperB.id: paperBSpans
    ]
    try SessionWorkspaceManager().writeWorkspace(
        session: session,
        papers: [paperA, paperB],
        pagesByPaperID: pagesByPaperID,
        spansByPaperID: spansByPaperID,
        anchorsByPaperID: [paperA.id: [], paperB.id: []]
    )
}

func seedFixturePaper(
    id: String,
    title: String,
    authors: [String],
    year: Int,
    lines: [String],
    root: URL,
    repository: PaperRepository,
    importedAt: Date
) throws -> Paper {
    let paperDir = root.appendingPathComponent("papers/\(id)", isDirectory: true)
    try FileManager.default.createDirectory(at: paperDir, withIntermediateDirectories: true)
    let pdfURL = paperDir.appendingPathComponent("original.pdf")
    try writeFixturePDF(to: pdfURL, lines: lines)
    let pdfData = try Data(contentsOf: pdfURL)
    let fileHash = SHA256.hash(data: pdfData).map { String(format: "%02x", $0) }.joined()

    let paper = Paper(
        id: id,
        filePath: pdfURL.path,
        fileHash: fileHash,
        title: title,
        authors: authors,
        year: year,
        sourceURL: nil,
        importedAt: importedAt,
        updatedAt: importedAt
    )
    try repository.upsertPaper(paper)

    let index = try PDFIndexExtractor().extract(paperID: id, pdfURL: pdfURL)
    for page in index.pages {
        try repository.upsertPage(page)
    }
    for span in index.spans {
        try repository.upsertSpan(span)
    }

    return paper
}

func writeFixturePDF(to url: URL, lines: [String]) throws {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw CheckFailure(description: "could not create PDF context")
    }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 18),
        .foregroundColor: NSColor.black
    ]
    for (index, line) in lines.enumerated() {
        let attributed = NSAttributedString(string: line, attributes: attributes)
        attributed.draw(in: CGRect(x: 72, y: 690 - (index * 34), width: 460, height: 28))
    }
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    try data.write(to: url, options: [.atomic])
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "seed-fixture" {
    do {
        guard arguments.count == 2 else {
            throw CheckFailure(description: "usage: PaperCodexCoreChecks seed-fixture <support-root>")
        }
        let root = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
        try seedFixtureLibrary(at: root)
        print(root.path)
        exit(0)
    } catch {
        fputs("check failed: \(error)\n", stderr)
        exit(1)
    }
}

let selectedChecks = Set(arguments)

do {
    if selectedChecks.isEmpty || selectedChecks.contains("models") {
        try runModelsChecks()
        print("models: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("local-store-v2-models") {
        try runLocalStoreV2ModelChecks()
        print("local-store-v2-models: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("reader-tabs") {
        try runReaderTabStateChecks()
        print("reader-tabs: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("reader-positions") {
        try runReaderPositionRepositoryChecks()
        print("reader-positions: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("appkit-lifecycle-source") {
        try runAppKitLifecycleSourceChecks()
        print("appkit-lifecycle-source: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("library-derived-state") {
        try runLibraryDerivedStateChecks()
        print("library-derived-state: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("library-category-assignment") {
        try runLibraryCategoryAssignmentChecks()
        print("library-category-assignment: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("category-move-planner") {
        try runCategoryMovePlannerChecks()
        print("category-move-planner: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("ui-layout-source") {
        try runUILayoutSourceChecks()
        print("ui-layout-source: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("ui-design-source") {
        try runUIDesignSourceChecks()
        print("ui-design-source: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("repository") {
        try runRepositoryChecks()
        print("repository: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("local-store-v2-migration") {
        try runLocalStoreV2MigrationChecks()
        print("local-store-v2-migration: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("library-data-store") {
        try runLibraryDataStoreChecks()
        print("library-data-store: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("mcp") {
        try runMCPChecks()
        print("mcp: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("arxiv-cache-data-store") {
        try runArxivCacheDataStoreChecks()
        print("arxiv-cache-data-store: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("sync-data-store") {
        try runSyncDataStoreChecks()
        print("sync-data-store: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("sqlite-helpers") {
        try runSQLiteHelperChecks()
        print("sqlite-helpers: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("citations") {
        try runCitationChecks()
        print("citations: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("user-source") {
        try runUserSourceAttachmentChecks()
        print("user-source: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("anchors") {
        try runAnchorResolverChecks()
        print("anchors: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("prompt") {
        try runPromptChecks()
        print("prompt: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("workspace") {
        try runWorkspaceChecks()
        print("workspace: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("codex-plugin-installer") {
        try runCodexPluginInstallerChecks()
        print("codex-plugin-installer: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("agent-runtime-profiles") {
        try runAgentRuntimeProfileChecks()
        print("agent-runtime-profiles: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("agent-workspace-manifest") {
        try runAgentWorkspaceManifestChecks()
        print("agent-workspace-manifest: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("agent-command-builders") {
        try runAgentCommandBuilderChecks()
        print("agent-command-builders: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("agent-session-migration") {
        try runAgentSessionMigrationChecks()
        print("agent-session-migration: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("agent-runtime-source") {
        try runAgentRuntimeSourceChecks()
        print("agent-runtime-source: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("agent-runtime-smoke-script") {
        try runAgentRuntimeSmokeScriptChecks()
        print("agent-runtime-smoke-script: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("pdf") {
        try runPDFChecks()
        print("pdf: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("codex") {
        try runCodexCLIChecks()
        print("codex: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("generated-images") {
        try runGeneratedImageChecks()
        print("generated-images: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("image-requests") {
        try runImageRequestChecks()
        print("image-requests: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("codex-recovery") {
        try runCodexRecoveryChecks()
        print("codex-recovery: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("paths") {
        try runPathChecks()
        print("paths: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("bundle") {
        try runBundleChecks()
        print("bundle: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("fixture") {
        try runFixtureLibraryChecks()
        print("fixture: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("watch") {
        try runWatchedFolderChecks()
        print("watch: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("arxiv-feed") {
        try runArxivFeedChecks()
        print("arxiv-feed: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("local-arxiv-client") {
        try runLocalArxivClientChecks()
        print("local-arxiv-client: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("local-discover-engine") {
        try runLocalDiscoverEngineChecks()
        print("local-discover-engine: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("local-discover-preferences") {
        try runLocalDiscoverPreferenceChecks()
        print("local-discover-preferences: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("similarity-ranker") {
        try runSimilarityRankerChecks()
        print("similarity-ranker: pass")
    }
} catch {
    fputs("check failed: \(error)\n", stderr)
    exit(1)
}
