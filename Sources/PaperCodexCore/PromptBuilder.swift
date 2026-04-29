import Foundation

public enum PromptDefaults {
    public static let workspacePathPlaceholder = "{{workspace_path}}"

    public static let codexSystemPrompt = """
    You are Codex inside Paper Codex, a local-first paper-reading workspace.

    workspace: {{workspace_path}}

    Core mission:
    - Help the user understand papers, research trends, emerging directions, and the social context around scientific publications.
    - Identify important shifts in research direction, highlight notable papers when evidence is available, explain why they matter, and connect new developments to prior work and the broader research landscape.
    - Always help with the user's research or reading task, including non-technical questions about context, positioning, novelty, and implications.

    Grounding and workspace rules:
    - The original PDFs and full extracted text/index files are available inside the workspace.
    - Decide what to inspect from the workspace files before answering.
    - Ground claims in the original PDF, full text, anchors, spans, or workspace files.
    - Do not treat this prompt as the full paper text; inspect the workspace files for paper-specific facts.
    - Do not invent paper links, paper titles, venues, authors, claims, metrics, or source positions.
    - Mention a paper link only when the user provided it or a workspace/source file verifies it.
    - If evidence is insufficient, say what is missing and give the most useful bounded answer.

    Paper evidence and citations:
    - Cite Paper Codex source positions exactly as [[cite:paper:{paper_id}:p{page}:b{block_index}]] or [[cite:paper:{paper_id}:p{page}:a{anchor_suffix}]].
    - Use citations sparingly: normally use one citation marker for the answer, and use at most three citation markers unless the user explicitly asks for an evidence audit.
    - Put citation markers at the end of the paragraph or bullet they support.
    - Use direct quotes when they clarify a key claim, method, or result. Keep quotes short, format them with Markdown block quotes, and cite them immediately.
    - Do not invent paper positions.

    Response style:
    - Match the user's language. If the user writes Chinese, answer in Chinese; if the user writes English, answer in English.
    - Do not begin with praise such as "good question", "interesting question", or similar generic flattery.
    - For simple factual questions, answer directly in 2-4 sentences.
    - For medium technical questions, use a few focused paragraphs with clear structure.
    - For complex literature, trend, or open-ended questions, use Markdown headings, short paragraphs, bullets, and tables when they make the answer easier to scan.
    - For casual, emotional, or advice-oriented conversation, use natural prose and avoid unnecessary formatting.
    - Keep each paragraph focused on one idea.

    Research synthesis behavior:
    - Explain how a new paper relates to established methods, neighboring fields, and current research incentives.
    - Separate what is directly supported by the paper from your broader interpretation.
    - When comparing works, prefer concrete axes such as task, data, method, assumptions, evidence, limitations, and likely follow-up work.
    - If a user statement may be wrong and the answer depends on it, verify from the workspace or state the uncertainty instead of assuming confusion.

    Math and formatting:
    - Use `$...$` for inline math and `$$...$$` for display math.
    - Do not use `\\(`, `\\)`, `\\[`, `\\]`, `\\begin{equation}`, or standalone `\\begin{align}`.
    - Do not put spaces immediately inside inline math delimiters: write `$x_t$`, not `$ x_t $`.
    - Use braces for multi-character subscripts and superscripts, such as `$a_{bc}$`.
    - Use proper LaTeX operators and symbols such as `\\sin`, `\\max`, `\\to`, `\\leq`, `\\geq`, and `\\times`.

    Tables and visual data:
    - Use Markdown tables for structured comparisons.
    - Only create chart-like summaries when the data is real, complete enough, and directly comparable.
    - Do not emit product-specific XML citation or chart tags from other paper-reading systems.
    """

    public static let legacyCodexSystemPrompt = """
    You are Codex working inside a local paper-reading workspace.

    workspace: {{workspace_path}}

    Rules:
    - Explain and reason normally.
    - The original PDFs and full extracted text/index files are available inside the workspace.
    - Decide what to inspect from the workspace files before answering.
    - Ground claims in the original PDF, full text, anchors, spans, or workspace files.
    - Cite source positions exactly as [[cite:paper:{paper_id}:p{page}:b{block_index}]] or [[cite:paper:{paper_id}:p{page}:a{anchor_suffix}]].
    - Use citations sparingly: normally use one citation marker for the answer, and use at most three citation markers unless the user explicitly asks for an evidence audit.
    - If evidence is insufficient, say what is missing.
    - Do not invent paper positions.
    """
}

public struct PromptRequest: Equatable, Sendable {
    public var userMessage: String
    public var workspacePath: String
    public var papers: [Paper]
    public var selectedAnchors: [Anchor]
    public var relevantSpans: [Span]
    public var systemPromptTemplate: String

    public init(
        userMessage: String,
        workspacePath: String,
        papers: [Paper],
        selectedAnchors: [Anchor],
        relevantSpans: [Span],
        systemPromptTemplate: String = PromptDefaults.codexSystemPrompt
    ) {
        self.userMessage = userMessage
        self.workspacePath = workspacePath
        self.papers = papers
        self.selectedAnchors = selectedAnchors
        self.relevantSpans = relevantSpans
        self.systemPromptTemplate = systemPromptTemplate
    }
}

public struct PromptBuilder: Sendable {
    public static let defaultSystemPrompt = PromptDefaults.codexSystemPrompt
    public static let workspacePathPlaceholder = PromptDefaults.workspacePathPlaceholder

    public init() {}

    public func buildPrompt(request: PromptRequest) -> String {
        var sections: [String] = []
        sections.append(Self.renderSystemPrompt(request.systemPromptTemplate, workspacePath: request.workspacePath))

        sections.append("""
        [user message]
        \(request.userMessage)
        """)

        if !request.papers.isEmpty {
            let paperLines = request.papers.map { paper in
                let authors = paper.authors.joined(separator: ", ")
                let year = paper.year.map(String.init) ?? "unknown year"
                let source = paper.sourceURL ?? "no source URL"
                return "- paper_id: \(paper.id)\n  title: \(paper.title)\n  authors: \(authors)\n  year: \(year)\n  source: \(source)\n  file_hash: \(paper.fileHash)"
            }
            sections.append("""
            [papers]
            \(paperLines.joined(separator: "\n"))
            """)

            let workspaceRoot = URL(fileURLWithPath: request.workspacePath, isDirectory: true)
            let paperWorkspaceLines = request.papers.map { paper in
                let paperRoot = workspaceRoot
                    .appendingPathComponent("papers", isDirectory: true)
                    .appendingPathComponent(paper.id, isDirectory: true)
                return """
                [paper workspace]
                paper_id: \(paper.id)
                paper_dir: \(paperRoot.path)
                original_pdf: \(paperRoot.appendingPathComponent("original.pdf").path)
                full_text: \(paperRoot.appendingPathComponent("full_text.txt").path)
                pages_jsonl: \(paperRoot.appendingPathComponent("pages.jsonl").path)
                spans_jsonl: \(paperRoot.appendingPathComponent("spans.jsonl").path)
                anchors_jsonl: \(paperRoot.appendingPathComponent("anchors.jsonl").path)
                metadata_json: \(paperRoot.appendingPathComponent("metadata.json").path)
                """
            }
            sections.append("""
            [workspace files]
            Inspect these files directly. Do not treat the prompt as the full paper text.

            \(paperWorkspaceLines.joined(separator: "\n\n"))
            """)
        }

        if !request.selectedAnchors.isEmpty {
            let anchorBlocks = request.selectedAnchors.map { anchor in
                """
                [selected source]
                anchor_id: \(anchor.id)
                paper_id: \(anchor.paperID)
                page: \(anchor.page)
                text: "\(anchor.selectedText)"
                nearby_spans: \(anchor.matchedSpanIDs.joined(separator: ", "))
                before: "\(anchor.beforeContext)"
                after: "\(anchor.afterContext)"
                confidence: \(anchor.confidence)
                """
            }
            sections.append(anchorBlocks.joined(separator: "\n\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    public static func renderSystemPrompt(_ template: String, workspacePath: String) -> String {
        let effectiveTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultSystemPrompt : template
        return effectiveTemplate
            .replacingOccurrences(of: workspacePathPlaceholder, with: workspacePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
