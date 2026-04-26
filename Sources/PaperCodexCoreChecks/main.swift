import Foundation
import PaperCodexCore

struct CheckFailure: Error, CustomStringConvertible {
    var description: String
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CheckFailure(description: message)
    }
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
    try check(decodedSession == session, "session should JSON round-trip")
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
    let category = Category(id: "cat-methods", parentID: nil, name: "Methods", sortOrder: 1)
    let childCategory = Category(id: "cat-vae", parentID: "cat-methods", name: "VAE", sortOrder: 2)
    let tag = PaperTag(id: "tag-control", name: "control")
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
    try repository.upsertCategory(category)
    try repository.upsertCategory(childCategory)
    try repository.upsertTag(tag)
    try repository.assignPaper("paper-a", toCategory: "cat-vae")
    try repository.assignPaper("paper-a", toTag: "tag-control")
    try repository.upsertSpan(span)
    try repository.upsertAnchor(anchor)
    try repository.upsertSession(session)
    try repository.appendMessage(message)

    let fetchedPapers = try repository.fetchPapers()
    let fetchedCategories = try repository.fetchCategories()
    let fetchedTags = try repository.fetchTags(forPaperID: "paper-a")
    let fetchedCategoryIDs = try repository.fetchCategoryIDs(forPaperID: "paper-a")
    let fetchedSpans = try repository.fetchSpans(paperID: "paper-a")
    let fetchedAnchors = try repository.fetchAnchors(paperID: "paper-a")
    let fetchedSessions = try repository.fetchSessions(paperID: "paper-a")
    let fetchedMessages = try repository.fetchMessages(sessionID: "session-a")

    try check(fetchedPapers == [paper], "paper should round-trip through SQLite")
    try check(fetchedCategories == [category, childCategory], "categories should preserve hierarchy and sort order")
    try check(fetchedTags == [tag], "paper tags should round-trip")
    try check(fetchedCategoryIDs == ["cat-vae"], "paper category links should round-trip")
    try check(fetchedSpans == [span], "spans should round-trip")
    try check(fetchedAnchors == [anchor], "anchors should round-trip")
    try check(fetchedSessions == [session], "sessions should round-trip")
    try check(fetchedMessages == [message], "messages should round-trip")
}

let selectedChecks = Set(CommandLine.arguments.dropFirst())

do {
    if selectedChecks.isEmpty || selectedChecks.contains("models") {
        try runModelsChecks()
        print("models: pass")
    }
    if selectedChecks.isEmpty || selectedChecks.contains("repository") {
        try runRepositoryChecks()
        print("repository: pass")
    }
} catch {
    fputs("check failed: \(error)\n", stderr)
    exit(1)
}
