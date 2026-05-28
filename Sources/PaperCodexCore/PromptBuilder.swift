import Foundation

public enum PromptDefaults {
    public static let workspacePathPlaceholder = "{{workspace_path}}"

    public static let codexSystemPrompt = """
    You are Codex inside Episteme, a local-first paper-reading workspace.

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
    - Cite Episteme source positions exactly as [[cite:paper:{paper_id}:p{page}:b{block_index}]] or [[cite:paper:{paper_id}:p{page}:a{anchor_suffix}]].
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

    public static let chineseCodexSystemPrompt = """
    你是 Episteme 中的 Codex，一个本地优先的论文阅读工作区助手。

    workspace: {{workspace_path}}

    核心任务：
    - 帮助用户理解论文、研究趋势、新方向，以及科学出版背后的研究语境。
    - 在证据充分时识别重要的研究方向变化，指出值得关注的论文，解释它们为什么重要，并把新进展连接到已有工作和更大的研究图景中。
    - 始终围绕用户的科研或阅读任务提供帮助，也包括研究背景、定位、创新性和影响等非纯技术问题。

    依据和工作区规则：
    - 原始 PDF、全文提取结果和索引文件都在工作区中。
    - 回答前先判断需要检查哪些工作区文件。
    - 论文相关事实必须依据原始 PDF、全文、anchors、spans 或工作区文件。
    - 不要把这段 prompt 当成论文全文；涉及具体论文事实时要检查工作区文件。
    - 不要编造论文链接、标题、会议/期刊、作者、主张、指标或来源位置。
    - 只有在用户提供过链接，或工作区/来源文件能验证链接时，才提到论文链接。
    - 如果证据不足，要说明缺少什么，并给出最有用的有边界回答。

    论文证据和引用：
    - Episteme 来源位置必须严格写成 [[cite:paper:{paper_id}:p{page}:b{block_index}]] 或 [[cite:paper:{paper_id}:p{page}:a{anchor_suffix}]]。
    - 引用要稀疏：通常一个回答只放一个引用标记；除非用户明确要求证据审计，否则最多使用三个引用标记。
    - 引用标记放在它支持的段落或 bullet 末尾。
    - 直接引用只在澄清关键主张、方法或结果时使用。引用要短，用 Markdown block quote，并立即标注引用。
    - 不要编造论文位置。

    回答风格：
    - 默认使用中文回答；只有当用户明确要求其他语言时才切换。
    - 不要用“好问题”“这个问题很有意思”等泛泛夸赞开头。
    - 简单事实问题直接用 2-4 句回答。
    - 中等技术问题用几个聚焦段落，并保持清晰结构。
    - 复杂文献、趋势或开放问题可以使用 Markdown 标题、短段落、列表和表格，让答案更容易扫读。
    - 闲聊、情绪支持或建议类对话使用自然 prose，避免不必要的格式。
    - 每个段落只集中表达一个想法。

    研究综合行为：
    - 解释新论文如何关联已有方法、相邻领域和当前研究激励。
    - 区分论文直接支持的内容和你的延伸解释。
    - 比较工作时优先使用具体维度，例如任务、数据、方法、假设、证据、局限和可能的后续工作。
    - 如果用户表述可能有误且答案依赖该表述，要先从工作区验证，或明确不确定性，而不是直接假设用户混淆。

    数学和格式：
    - 行内数学使用 `$...$`，展示数学使用 `$$...$$`。
    - 不要使用 `\\(`、`\\)`、`\\[`、`\\]`、`\\begin{equation}` 或单独的 `\\begin{align}`。
    - 行内数学分隔符内部不要紧贴空格：写 `$x_t$`，不要写 `$ x_t $`。
    - 多字符上下标使用花括号，例如 `$a_{bc}$`。
    - 使用规范 LaTeX 运算符和符号，例如 `\\sin`、`\\max`、`\\to`、`\\leq`、`\\geq` 和 `\\times`。

    表格和可视化数据：
    - 结构化比较使用 Markdown 表格。
    - 只有当数据真实、足够完整且可直接比较时，才生成图表式总结。
    - 不要输出其他论文阅读系统的产品专用 XML 引用或图表标签。
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

public enum PaperCodexLanguageMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic = "auto"
    case chinese = "zh"
    case english = "en"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic:
            "Auto"
        case .chinese:
            "中文"
        case .english:
            "English"
        }
    }

    public func title(appLanguage: PaperCodexLanguageMode) -> String {
        guard appLanguage == .chinese else {
            return title
        }
        switch self {
        case .automatic:
            return "自动"
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }

    public var appLocaleIdentifier: String {
        switch self {
        case .automatic:
            Locale.autoupdatingCurrent.identifier
        case .chinese:
            "zh-Hans"
        case .english:
            "en"
        }
    }

    public var discoverLanguageCode: String {
        switch self {
        case .automatic, .chinese:
            "zh"
        case .english:
            "en"
        }
    }

    public var metadataLanguageCode: String {
        switch self {
        case .automatic, .english:
            "en"
        case .chinese:
            "zh"
        }
    }

    public var promptInstruction: String {
        switch self {
        case .automatic:
            "Global language preference: Automatic. Match the user's language for each answer unless the user explicitly asks for a different language. The app interface follows the system language when possible."
        case .chinese:
            "全局语言偏好：中文。Episteme 的界面语言、Discover 元数据、快捷提示和默认系统提示都应以中文为主；除非用户明确要求其他语言，否则默认用中文回答。"
        case .english:
            "Global language preference: English. Episteme interface language, Discover metadata, quick prompts, and the default system prompt should use English. Answer in English by default unless the user explicitly asks for a different language."
        }
    }
}

public struct PromptRequest: Equatable, Sendable {
    public var userMessage: String
    public var workspacePath: String
    public var papers: [Paper]
    public var selectedAnchors: [Anchor]
    public var relevantSpans: [Span]
    public var systemPromptTemplate: String
    public var languageMode: PaperCodexLanguageMode

    public init(
        userMessage: String,
        workspacePath: String,
        papers: [Paper],
        selectedAnchors: [Anchor],
        relevantSpans: [Span],
        systemPromptTemplate: String = PromptDefaults.codexSystemPrompt,
        languageMode: PaperCodexLanguageMode = .automatic
    ) {
        self.userMessage = userMessage
        self.workspacePath = workspacePath
        self.papers = papers
        self.selectedAnchors = selectedAnchors
        self.relevantSpans = relevantSpans
        self.systemPromptTemplate = systemPromptTemplate
        self.languageMode = languageMode
    }
}

public struct PromptBuilder: Sendable {
    public static let defaultSystemPrompt = PromptDefaults.codexSystemPrompt
    public static let workspacePathPlaceholder = PromptDefaults.workspacePathPlaceholder

    public init() {}

    public func buildPrompt(request: PromptRequest) -> String {
        let labels = PromptSectionLabels(languageMode: request.languageMode)
        let systemPromptTemplate = Self.effectiveSystemPromptTemplate(
            request.systemPromptTemplate,
            languageMode: request.languageMode
        )
        var sections: [String] = []
        sections.append(Self.renderSystemPrompt(systemPromptTemplate, workspacePath: request.workspacePath))
        sections.append("""
        [\(labels.globalLanguage)]
        \(request.languageMode.promptInstruction)
        """)

        sections.append("""
        [\(labels.userMessage)]
        \(request.userMessage)
        """)

        if !request.papers.isEmpty {
            let paperLines = request.papers.map { paper in
                let authors = paper.authors.joined(separator: ", ")
                let year = paper.year.map(String.init) ?? labels.unknownYear
                let source = paper.sourceURL ?? labels.noSourceURL
                return "- paper_id: \(paper.id)\n  title: \(paper.title)\n  authors: \(authors)\n  year: \(year)\n  source: \(source)\n  file_hash: \(paper.fileHash)"
            }
            sections.append("""
            [\(labels.papers)]
            \(paperLines.joined(separator: "\n"))
            """)

            let workspaceRoot = URL(fileURLWithPath: request.workspacePath, isDirectory: true)
            let paperWorkspaceLines = request.papers.map { paper in
                let paperRoot = workspaceRoot
                    .appendingPathComponent("papers", isDirectory: true)
                    .appendingPathComponent(paper.id, isDirectory: true)
                return """
                [\(labels.paperWorkspace)]
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
            [\(labels.workspaceFiles)]
            \(labels.workspaceInstruction)

            \(paperWorkspaceLines.joined(separator: "\n\n"))
            """)
        }

        if !request.selectedAnchors.isEmpty {
            let anchorBlocks = request.selectedAnchors.map { anchor in
                """
                [\(labels.selectedSource)]
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

    public static func defaultSystemPrompt(for languageMode: PaperCodexLanguageMode) -> String {
        switch languageMode {
        case .automatic, .english:
            PromptDefaults.codexSystemPrompt
        case .chinese:
            PromptDefaults.chineseCodexSystemPrompt
        }
    }

    public static func isBuiltInSystemPrompt(_ prompt: String) -> Bool {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            PromptDefaults.codexSystemPrompt,
            PromptDefaults.chineseCodexSystemPrompt,
            PromptDefaults.legacyCodexSystemPrompt
        ].contains { builtInPrompt in
            builtInPrompt.trimmingCharacters(in: .whitespacesAndNewlines) == normalized
        }
    }

    public static func effectiveSystemPromptTemplate(
        _ template: String,
        languageMode: PaperCodexLanguageMode
    ) -> String {
        let normalized = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || isBuiltInSystemPrompt(normalized) {
            return defaultSystemPrompt(for: languageMode)
        }
        return template
    }

    public static func renderSystemPrompt(_ template: String, workspacePath: String) -> String {
        let effectiveTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultSystemPrompt : template
        return effectiveTemplate
            .replacingOccurrences(of: workspacePathPlaceholder, with: workspacePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct PromptSectionLabels {
    var globalLanguage: String
    var userMessage: String
    var papers: String
    var paperWorkspace: String
    var workspaceFiles: String
    var selectedSource: String
    var workspaceInstruction: String
    var unknownYear: String
    var noSourceURL: String

    init(languageMode: PaperCodexLanguageMode) {
        switch languageMode {
        case .chinese:
            globalLanguage = "全局语言"
            userMessage = "用户消息"
            papers = "论文"
            paperWorkspace = "论文工作区"
            workspaceFiles = "工作区文件"
            selectedSource = "选中的原文"
            workspaceInstruction = "直接检查这些文件。不要把 prompt 当成论文全文。"
            unknownYear = "未知年份"
            noSourceURL = "无来源 URL"
        case .automatic, .english:
            globalLanguage = "global language"
            userMessage = "user message"
            papers = "papers"
            paperWorkspace = "paper workspace"
            workspaceFiles = "workspace files"
            selectedSource = "selected source"
            workspaceInstruction = "Inspect these files directly. Do not treat the prompt as the full paper text."
            unknownYear = "unknown year"
            noSourceURL = "no source URL"
        }
    }
}
