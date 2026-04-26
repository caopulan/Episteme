import Foundation

public final class SessionWorkspaceManager {
    private let encoder: JSONEncoder

    public init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    public func writeWorkspace(
        session: PaperSession,
        papers: [Paper],
        pagesByPaperID: [String: [PageIndex]],
        spansByPaperID: [String: [Span]],
        anchorsByPaperID: [String: [Anchor]]
    ) throws {
        let root = URL(fileURLWithPath: session.workspacePath, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("turns", isDirectory: true), withIntermediateDirectories: true)
        try writeJSON(session, to: root.appendingPathComponent("session.json"))
        try Self.promptContract.write(
            to: root.appendingPathComponent("prompt_contract.md"),
            atomically: true,
            encoding: .utf8
        )

        let papersRoot = root.appendingPathComponent("papers", isDirectory: true)
        try FileManager.default.createDirectory(at: papersRoot, withIntermediateDirectories: true)

        for paper in papers {
            let paperRoot = papersRoot.appendingPathComponent(paper.id, isDirectory: true)
            try FileManager.default.createDirectory(at: paperRoot, withIntermediateDirectories: true)
            try writeJSON(paper, to: paperRoot.appendingPathComponent("metadata.json"))
            try writeJSONLines(pagesByPaperID[paper.id] ?? [], to: paperRoot.appendingPathComponent("pages.jsonl"))
            try writeJSONLines(spansByPaperID[paper.id] ?? [], to: paperRoot.appendingPathComponent("spans.jsonl"))
            try writeJSONLines(anchorsByPaperID[paper.id] ?? [], to: paperRoot.appendingPathComponent("anchors.jsonl"))
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private func writeJSONLines<T: Encodable>(_ values: [T], to url: URL) throws {
        let lines = try values.map { value in
            String(decoding: try encoder.encode(value), as: UTF8.self)
        }.joined(separator: "\n")
        let body = lines.isEmpty ? "" : lines + "\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    public static let promptContract = """
    # Paper Codex Prompt Contract

    The original PDF is the primary source. Use the local index files as navigation aids.

    Use citation IDs exactly:

    - [[cite:paper:{paper_id}:p{page}:b{block_index}]]
    - [[cite:paper:{paper_id}:p{page}:a{anchor_suffix}]]

    If evidence is insufficient, say so clearly. Do not invent source positions.
    """
}
