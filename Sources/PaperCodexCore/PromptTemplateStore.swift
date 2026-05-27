import Foundation

public struct PromptTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var task: String
    public var name: String
    public var bodyMarkdown: String
    public var variables: [String]
    public var isEnabled: Bool
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        task: String,
        name: String,
        bodyMarkdown: String,
        variables: [String],
        isEnabled: Bool = true,
        isArchived: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.task = task
        self.name = name
        self.bodyMarkdown = bodyMarkdown
        self.variables = variables
        self.isEnabled = isEnabled
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PromptTemplateValidation: Codable, Equatable, Sendable {
    public var templateID: String
    public var isValid: Bool
    public var variables: [String]
    public var undeclaredVariables: [String]
    public var unusedDeclaredVariables: [String]
    public var errors: [String]

    public init(
        templateID: String,
        isValid: Bool,
        variables: [String],
        undeclaredVariables: [String],
        unusedDeclaredVariables: [String],
        errors: [String]
    ) {
        self.templateID = templateID
        self.isValid = isValid
        self.variables = variables
        self.undeclaredVariables = undeclaredVariables
        self.unusedDeclaredVariables = unusedDeclaredVariables
        self.errors = errors
    }
}

public enum PromptTemplateStoreError: Error, CustomStringConvertible, Equatable {
    case templateNotFound(String)
    case invalidTemplateID(String)
    case invalidTask(String)
    case emptyName
    case emptyBody
    case invalidArchiveOfDefault(String)

    public var description: String {
        switch self {
        case let .templateNotFound(id):
            "Prompt template was not found: \(id)."
        case let .invalidTemplateID(id):
            "Prompt template id is invalid: \(id)."
        case let .invalidTask(task):
            "Prompt template task is invalid: \(task)."
        case .emptyName:
            "Prompt template name cannot be empty."
        case .emptyBody:
            "Prompt template body cannot be empty."
        case let .invalidArchiveOfDefault(id):
            "Prompt template \(id) is the default for its task and cannot be archived until another default is selected."
        }
    }
}

public final class PromptTemplateStore {
    public static let supportedTasks = [
        "paper_reading",
        "paper_summary",
        "paper_digest",
        "tag_suggestion",
        "note_generation",
        "compare_papers",
        "literature_review",
        "figure_explanation",
        "method_extraction",
        "experiment_extraction",
        "limitation_analysis",
        "citation_grounding",
        "chat_system_prompt"
    ]

    private struct Catalog: Codable {
        var templates: [PromptTemplate]
        var defaultsByTask: [String: String]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(supportRoot: URL, fileManager: FileManager = .default) {
        self.fileURL = supportRoot
            .appendingPathComponent("settings", isDirectory: true)
            .appendingPathComponent("prompt_templates.json")
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }

    public func listTemplates(includeArchived: Bool = false) throws -> [PromptTemplate] {
        let catalog = try loadCatalog()
        return catalog.templates
            .filter { includeArchived || !$0.isArchived }
            .sorted { left, right in
                if left.task != right.task {
                    return left.task < right.task
                }
                if left.name.localizedCaseInsensitiveCompare(right.name) != .orderedSame {
                    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                }
                return left.id < right.id
            }
    }

    public func defaultsByTask() throws -> [String: String] {
        try loadCatalog().defaultsByTask
    }

    public func template(id: String) throws -> PromptTemplate {
        guard let template = try loadCatalog().templates.first(where: { $0.id == id && !$0.isArchived }) else {
            throw PromptTemplateStoreError.templateNotFound(id)
        }
        return template
    }

    public func defaultTemplate(forTask task: String) throws -> PromptTemplate {
        guard Self.supportedTasks.contains(task) else {
            throw PromptTemplateStoreError.invalidTask(task)
        }
        let catalog = try loadCatalog()
        guard let templateID = catalog.defaultsByTask[task],
              let template = catalog.templates.first(where: { $0.id == templateID && !$0.isArchived }) else {
            throw PromptTemplateStoreError.templateNotFound("\(task).default")
        }
        return template
    }

    public func create(task: String, name: String, bodyMarkdown: String, variables: [String], now: Date = Date()) throws -> PromptTemplate {
        guard Self.supportedTasks.contains(task) else {
            throw PromptTemplateStoreError.invalidTask(task)
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw PromptTemplateStoreError.emptyName
        }
        let trimmedBody = bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            throw PromptTemplateStoreError.emptyBody
        }
        var catalog = try loadCatalog()
        let template = PromptTemplate(
            id: uniqueTemplateID(task: task, name: trimmedName, existingIDs: Set(catalog.templates.map(\.id))),
            task: task,
            name: trimmedName,
            bodyMarkdown: trimmedBody,
            variables: normalizeVariables(variables.isEmpty ? Self.extractVariables(from: trimmedBody) : variables),
            createdAt: now,
            updatedAt: now
        )
        catalog.templates.append(template)
        if catalog.defaultsByTask[task] == nil {
            catalog.defaultsByTask[task] = template.id
        }
        try saveCatalog(catalog)
        return template
    }

    public func rename(templateID: String, name: String, now: Date = Date()) throws -> PromptTemplate {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PromptTemplateStoreError.emptyName
        }
        return try update(templateID: templateID, now: now) { template in
            template.name = trimmed
        }
    }

    public func duplicate(templateID: String, name: String?, now: Date = Date()) throws -> PromptTemplate {
        var catalog = try loadCatalog()
        guard let source = catalog.templates.first(where: { $0.id == templateID && !$0.isArchived }) else {
            throw PromptTemplateStoreError.templateNotFound(templateID)
        }
        let duplicateName = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "\(source.name) Copy"
        let duplicate = PromptTemplate(
            id: uniqueTemplateID(task: source.task, name: duplicateName, existingIDs: Set(catalog.templates.map(\.id))),
            task: source.task,
            name: duplicateName,
            bodyMarkdown: source.bodyMarkdown,
            variables: source.variables,
            isEnabled: source.isEnabled,
            isArchived: false,
            createdAt: now,
            updatedAt: now
        )
        catalog.templates.append(duplicate)
        try saveCatalog(catalog)
        return duplicate
    }

    public func replaceBody(templateID: String, bodyMarkdown: String, now: Date = Date()) throws -> PromptTemplate {
        let trimmed = bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PromptTemplateStoreError.emptyBody
        }
        return try update(templateID: templateID, now: now) { template in
            template.bodyMarkdown = trimmed
            let extracted = Self.extractVariables(from: trimmed)
            if !extracted.isEmpty {
                template.variables = normalizeVariables(Array(Set(template.variables).union(extracted)))
            }
        }
    }

    public func setVariables(templateID: String, variables: [String], now: Date = Date()) throws -> PromptTemplate {
        try update(templateID: templateID, now: now) { template in
            template.variables = normalizeVariables(variables)
        }
    }

    public func setDefault(task: String, templateID: String) throws -> PromptTemplate {
        guard Self.supportedTasks.contains(task) else {
            throw PromptTemplateStoreError.invalidTask(task)
        }
        var catalog = try loadCatalog()
        guard let template = catalog.templates.first(where: { $0.id == templateID && $0.task == task && !$0.isArchived }) else {
            throw PromptTemplateStoreError.templateNotFound(templateID)
        }
        catalog.defaultsByTask[task] = template.id
        try saveCatalog(catalog)
        return template
    }

    public func setEnabled(templateID: String, enabled: Bool, now: Date = Date()) throws -> PromptTemplate {
        try update(templateID: templateID, now: now) { template in
            template.isEnabled = enabled
        }
    }

    public func archive(templateID: String, now: Date = Date()) throws -> PromptTemplate {
        var catalog = try loadCatalog()
        guard let index = catalog.templates.firstIndex(where: { $0.id == templateID && !$0.isArchived }) else {
            throw PromptTemplateStoreError.templateNotFound(templateID)
        }
        if catalog.defaultsByTask[catalog.templates[index].task] == templateID {
            throw PromptTemplateStoreError.invalidArchiveOfDefault(templateID)
        }
        catalog.templates[index].isArchived = true
        catalog.templates[index].updatedAt = now
        let template = catalog.templates[index]
        try saveCatalog(catalog)
        return template
    }

    public func validate(templateID: String) throws -> PromptTemplateValidation {
        let template = try template(id: templateID)
        let declared = normalizeVariables(template.variables)
        let used = normalizeVariables(Self.extractVariables(from: template.bodyMarkdown))
        let declaredSet = Set(declared)
        let usedSet = Set(used)
        var errors: [String] = []
        if template.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("body_markdown is empty")
        }
        if !template.isEnabled {
            errors.append("template is disabled")
        }
        let undeclared = Array(usedSet.subtracting(declaredSet)).sorted()
        let unused = Array(declaredSet.subtracting(usedSet)).sorted()
        return PromptTemplateValidation(
            templateID: template.id,
            isValid: errors.isEmpty && undeclared.isEmpty,
            variables: used,
            undeclaredVariables: undeclared,
            unusedDeclaredVariables: unused,
            errors: errors
        )
    }

    public func previewRender(templateID: String, variables: [String: String]) throws -> String {
        let template = try template(id: templateID)
        return Self.render(template.bodyMarkdown, variables: variables)
    }

    public static func extractVariables(from body: String) -> [String] {
        let pattern = #"\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return normalizeVariables(regex.matches(in: body, range: range).compactMap { match in
            guard let variableRange = Range(match.range(at: 1), in: body) else {
                return nil
            }
            return String(body[variableRange])
        })
    }

    public static func render(_ body: String, variables: [String: String]) -> String {
        variables.reduce(body) { rendered, pair in
            rendered
                .replacingOccurrences(of: "{{\(pair.key)}}", with: pair.value)
                .replacingOccurrences(of: "{{ \(pair.key) }}", with: pair.value)
        }
    }

    private func loadCatalog() throws -> Catalog {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            let catalog = Self.defaultCatalog(now: Date())
            try saveCatalog(catalog)
            return catalog
        }
        let data = try Data(contentsOf: fileURL)
        var catalog = try decoder.decode(Catalog.self, from: data)
        let defaults = Self.defaultCatalog(now: Date())
        var existingIDs = Set(catalog.templates.map(\.id))
        for template in defaults.templates where !existingIDs.contains(template.id) {
            catalog.templates.append(template)
            existingIDs.insert(template.id)
        }
        for (task, templateID) in defaults.defaultsByTask where catalog.defaultsByTask[task] == nil {
            catalog.defaultsByTask[task] = templateID
        }
        return catalog
    }

    private func saveCatalog(_ catalog: Catalog) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(catalog)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func update(templateID: String, now: Date, mutate: (inout PromptTemplate) -> Void) throws -> PromptTemplate {
        var catalog = try loadCatalog()
        guard let index = catalog.templates.firstIndex(where: { $0.id == templateID && !$0.isArchived }) else {
            throw PromptTemplateStoreError.templateNotFound(templateID)
        }
        mutate(&catalog.templates[index])
        catalog.templates[index].updatedAt = now
        let template = catalog.templates[index]
        try saveCatalog(catalog)
        return template
    }

    private func uniqueTemplateID(task: String, name: String, existingIDs: Set<String>) -> String {
        let base = "\(task).\(Self.slug(name))"
        guard existingIDs.contains(base) else {
            return base
        }
        var suffix = 2
        while existingIDs.contains("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }

    private static func defaultCatalog(now: Date) -> Catalog {
        let templates = [
            defaultTemplate(
                task: "paper_reading",
                name: "Grounded Reading",
                body: """
                Read {{paper_title}} for {{user_goal}}. Use the original PDF, full text, spans, and anchors before making paper-specific claims. Cite precise Paper Codex source IDs when quoting or judging details.
                """,
                now: now
            ),
            defaultTemplate(
                task: "paper_summary",
                name: "Method And Evidence Summary",
                body: """
                Summarize {{paper_title}} for {{user_goal}}.

                Abstract:
                {{paper_abstract}}

                Focus on the core problem, method, experimental setup, main evidence, limitations, and what should be checked in the PDF next.
                """,
                now: now
            ),
            defaultTemplate(
                task: "paper_digest",
                name: "Structured Digest",
                body: """
                Create a durable digest for {{paper_title}} with: one-sentence summary, key claims, method, experiments, limits, important pages/spans, and follow-up questions.
                """,
                now: now
            ),
            defaultTemplate(
                task: "tag_suggestion",
                name: "Tag Suggestions",
                body: """
                Suggest concise tags for {{paper_title}}. Prefer reusable research facets over one-off labels. Explain each suggested tag briefly before applying anything.
                """,
                now: now
            ),
            defaultTemplate(
                task: "note_generation",
                name: "Reading Note",
                body: """
                Turn the current reading context for {{paper_title}} into a Markdown note. Preserve source anchors when available and separate facts from interpretation.
                """,
                now: now
            ),
            defaultTemplate(
                task: "compare_papers",
                name: "Compare Papers",
                body: """
                Compare {{paper_title}} with {{comparison_papers}} around problem setting, method, evidence, limitations, and what each paper makes easier to build next.
                """,
                now: now
            ),
            defaultTemplate(
                task: "literature_review",
                name: "Literature Review",
                body: """
                Build a literature review from {{paper_set}} for {{user_goal}}. Cluster papers by technical idea, evidence type, and unresolved gap.
                """,
                now: now
            ),
            defaultTemplate(
                task: "figure_explanation",
                name: "Figure Explanation",
                body: """
                Explain the selected figure or visual evidence in {{paper_title}}. Ground the explanation in nearby text, caption, and cited spans.
                """,
                now: now
            ),
            defaultTemplate(
                task: "method_extraction",
                name: "Method Extraction",
                body: """
                Extract the method in {{paper_title}} as implementable steps, including assumptions, inputs, outputs, training/inference details, and missing details to verify.
                """,
                now: now
            ),
            defaultTemplate(
                task: "experiment_extraction",
                name: "Experiment Extraction",
                body: """
                Extract the experimental setup in {{paper_title}}: datasets, baselines, metrics, ablations, implementation details, and what evidence supports the claims.
                """,
                now: now
            ),
            defaultTemplate(
                task: "limitation_analysis",
                name: "Limitation Analysis",
                body: """
                Analyze limitations in {{paper_title}}. Separate stated limitations, inferred risks, missing experiments, and likely failure modes.
                """,
                now: now
            ),
            defaultTemplate(
                task: "citation_grounding",
                name: "Citation Grounding",
                body: """
                Resolve {{selected_text}} in {{paper_title}} to Paper Codex page/span/anchor IDs. Do not invent source positions.
                """,
                now: now
            ),
            defaultTemplate(
                task: "chat_system_prompt",
                name: "Reader Chat System Prompt",
                body: PromptDefaults.codexSystemPrompt,
                now: now
            )
        ]
        return Catalog(
            templates: templates,
            defaultsByTask: Dictionary(uniqueKeysWithValues: templates.map { ($0.task, $0.id) })
        )
    }

    private static func defaultTemplate(task: String, name: String, body: String, now: Date) -> PromptTemplate {
        let id = "\(task).default"
        return PromptTemplate(
            id: id,
            task: task,
            name: name,
            bodyMarkdown: body.trimmingCharacters(in: .whitespacesAndNewlines),
            variables: extractVariables(from: body),
            createdAt: now,
            updatedAt: now
        )
    }

    private static func slug(_ value: String) -> String {
        value
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
    }
}

private func normalizeVariables(_ variables: [String]) -> [String] {
    Array(Set(variables.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
