import Foundation

public struct BoundingBox: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct TextRange: Codable, Equatable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

public struct Paper: Codable, Equatable, Identifiable, Sendable {
    public static let arxivImportPlaceholderFileHashPrefix = "pending-arxiv:"

    public var id: String
    public var filePath: String
    public var fileHash: String
    public var title: String
    public var authors: [String]
    public var year: Int?
    public var sourceURL: String?
    public var isSaved: Bool
    public var isStarred: Bool
    public var importedAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        filePath: String,
        fileHash: String,
        title: String,
        authors: [String],
        year: Int?,
        sourceURL: String?,
        isSaved: Bool = true,
        isStarred: Bool = false,
        importedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.filePath = filePath
        self.fileHash = fileHash
        self.title = title
        self.authors = authors
        self.year = year
        self.sourceURL = sourceURL
        self.isSaved = isSaved
        self.isStarred = isStarred
        self.importedAt = importedAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case filePath
        case fileHash
        case title
        case authors
        case year
        case sourceURL
        case isSaved
        case isStarred
        case importedAt
        case updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        filePath = try container.decode(String.self, forKey: .filePath)
        fileHash = try container.decode(String.self, forKey: .fileHash)
        title = try container.decode(String.self, forKey: .title)
        authors = try container.decode([String].self, forKey: .authors)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        isSaved = try container.decodeIfPresent(Bool.self, forKey: .isSaved) ?? true
        isStarred = try container.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(fileHash, forKey: .fileHash)
        try container.encode(title, forKey: .title)
        try container.encode(authors, forKey: .authors)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encode(isSaved, forKey: .isSaved)
        try container.encode(isStarred, forKey: .isStarred)
        try container.encode(importedAt, forKey: .importedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    public var isArxivImportPlaceholder: Bool {
        fileHash.hasPrefix(Self.arxivImportPlaceholderFileHashPrefix)
    }

    public var arxivImportPlaceholderCanonicalID: String? {
        guard isArxivImportPlaceholder else {
            return nil
        }
        return String(fileHash.dropFirst(Self.arxivImportPlaceholderFileHashPrefix.count))
    }

    public static func arxivImportPlaceholderFileHash(canonicalID: String) -> String {
        "\(arxivImportPlaceholderFileHashPrefix)\(canonicalID)"
    }

    public static func makeArxivImportPlaceholderID(for canonicalID: String) -> String {
        let safeID = canonicalID
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
        return "pending-arxiv-\(safeID.isEmpty ? "paper" : safeID)"
    }
}

public struct Category: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var parentID: String?
    public var name: String
    public var sortOrder: Int
    public var isPinned: Bool

    public init(id: String, parentID: String?, name: String, sortOrder: Int, isPinned: Bool = false) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.sortOrder = sortOrder
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case parentID
        case name
        case sortOrder
        case isPinned
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
        name = try container.decode(String.self, forKey: .name)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

public struct PaperTag: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct QuickPrompt: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var content: String

    public init(id: String, title: String, content: String) {
        self.id = id
        self.title = title
        self.content = content
    }
}

public struct WatchedFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var path: String
    public var createdAt: Date
    public var lastScannedAt: Date?

    public init(id: String, path: String, createdAt: Date, lastScannedAt: Date?) {
        self.id = id
        self.path = path
        self.createdAt = createdAt
        self.lastScannedAt = lastScannedAt
    }
}

public struct Span: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var paperID: String
    public var page: Int
    public var bbox: BoundingBox
    public var text: String
    public var charRange: TextRange
    public var sectionHint: String?
    public var confidence: Double

    public init(
        id: String,
        paperID: String,
        page: Int,
        bbox: BoundingBox,
        text: String,
        charRange: TextRange,
        sectionHint: String?,
        confidence: Double
    ) {
        self.id = id
        self.paperID = paperID
        self.page = page
        self.bbox = bbox
        self.text = text
        self.charRange = charRange
        self.sectionHint = sectionHint
        self.confidence = confidence
    }

    public static func makeID(paperID: String, page: Int, blockIndex: Int) -> String {
        "paper:\(paperID):p\(page):b\(blockIndex)"
    }
}

public struct Anchor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var paperID: String
    public var page: Int
    public var selectedText: String
    public var bboxList: [BoundingBox]
    public var matchedSpanIDs: [String]
    public var beforeContext: String
    public var afterContext: String
    public var createdSessionID: String
    public var createdAt: Date
    public var confidence: Double

    public init(
        id: String,
        paperID: String,
        page: Int,
        selectedText: String,
        bboxList: [BoundingBox],
        matchedSpanIDs: [String],
        beforeContext: String,
        afterContext: String,
        createdSessionID: String,
        createdAt: Date,
        confidence: Double
    ) {
        self.id = id
        self.paperID = paperID
        self.page = page
        self.selectedText = selectedText
        self.bboxList = bboxList
        self.matchedSpanIDs = matchedSpanIDs
        self.beforeContext = beforeContext
        self.afterContext = afterContext
        self.createdSessionID = createdSessionID
        self.createdAt = createdAt
        self.confidence = confidence
    }

    public static func makeID(paperID: String, page: Int, suffix: String) -> String {
        "paper:\(paperID):p\(page):a\(suffix)"
    }
}

public struct AgentRuntimeSessionLink: Codable, Equatable, Sendable {
    public var runtimeID: String
    public var sessionID: String

    public init(runtimeID: String, sessionID: String) {
        self.runtimeID = runtimeID
        self.sessionID = sessionID
    }
}

public struct PaperSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var paperIDs: [String]
    public var codexSessionID: String?
    public var defaultRuntimeID: String?
    public var runtimeSessionLinks: [AgentRuntimeSessionLink]
    public var workspaceMaterializationMode: WorkspaceMaterializationMode
    public var workspacePath: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        paperIDs: [String],
        codexSessionID: String?,
        defaultRuntimeID: String? = nil,
        runtimeSessionLinks: [AgentRuntimeSessionLink] = [],
        workspaceMaterializationMode: WorkspaceMaterializationMode = .copyPDF,
        workspacePath: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.paperIDs = paperIDs
        self.codexSessionID = codexSessionID
        self.defaultRuntimeID = defaultRuntimeID ?? (codexSessionID == nil ? nil : "codex")
        self.runtimeSessionLinks = Self.normalizedRuntimeSessionLinks(
            runtimeSessionLinks,
            codexSessionID: codexSessionID
        )
        self.workspaceMaterializationMode = workspaceMaterializationMode
        self.workspacePath = workspacePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func runtimeSessionID(for runtimeID: String) -> String? {
        runtimeSessionLinks.first { $0.runtimeID == runtimeID }?.sessionID
            ?? (runtimeID == "codex" ? codexSessionID : nil)
    }

    public mutating func setRuntimeSessionID(_ sessionID: String?, for runtimeID: String) {
        runtimeSessionLinks.removeAll { $0.runtimeID == runtimeID }
        let trimmed = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            runtimeSessionLinks.append(AgentRuntimeSessionLink(runtimeID: runtimeID, sessionID: trimmed))
        }
        if runtimeID == "codex" {
            codexSessionID = trimmed.isEmpty ? nil : trimmed
        }
        runtimeSessionLinks = Self.normalizedRuntimeSessionLinks(
            runtimeSessionLinks,
            codexSessionID: codexSessionID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case paperIDs
        case codexSessionID
        case defaultRuntimeID
        case runtimeSessionLinks
        case workspaceMaterializationMode
        case workspacePath
        case createdAt
        case updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        paperIDs = try container.decode([String].self, forKey: .paperIDs)
        codexSessionID = try container.decodeIfPresent(String.self, forKey: .codexSessionID)
        defaultRuntimeID = try container.decodeIfPresent(String.self, forKey: .defaultRuntimeID)
            ?? (codexSessionID == nil ? nil : "codex")
        runtimeSessionLinks = Self.normalizedRuntimeSessionLinks(
            try container.decodeIfPresent([AgentRuntimeSessionLink].self, forKey: .runtimeSessionLinks) ?? [],
            codexSessionID: codexSessionID
        )
        workspaceMaterializationMode = try container.decodeIfPresent(
            WorkspaceMaterializationMode.self,
            forKey: .workspaceMaterializationMode
        ) ?? .copyPDF
        workspacePath = try container.decode(String.self, forKey: .workspacePath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(paperIDs, forKey: .paperIDs)
        try container.encodeIfPresent(codexSessionID, forKey: .codexSessionID)
        try container.encodeIfPresent(defaultRuntimeID, forKey: .defaultRuntimeID)
        try container.encode(runtimeSessionLinks, forKey: .runtimeSessionLinks)
        try container.encode(workspaceMaterializationMode, forKey: .workspaceMaterializationMode)
        try container.encode(workspacePath, forKey: .workspacePath)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static func normalizedRuntimeSessionLinks(
        _ links: [AgentRuntimeSessionLink],
        codexSessionID: String?
    ) -> [AgentRuntimeSessionLink] {
        var linksByRuntimeID: [String: AgentRuntimeSessionLink] = [:]
        for link in links {
            let runtimeID = link.runtimeID.trimmingCharacters(in: .whitespacesAndNewlines)
            let sessionID = link.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !runtimeID.isEmpty, !sessionID.isEmpty else {
                continue
            }
            linksByRuntimeID[runtimeID] = AgentRuntimeSessionLink(runtimeID: runtimeID, sessionID: sessionID)
        }
        if let codexSessionID = codexSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexSessionID.isEmpty {
            linksByRuntimeID["codex"] = AgentRuntimeSessionLink(runtimeID: "codex", sessionID: codexSessionID)
        }
        return linksByRuntimeID.keys.sorted().compactMap { linksByRuntimeID[$0] }
    }
}

public struct PaperReaderPosition: Codable, Equatable, Sendable {
    public var sessionID: String
    public var paperID: String
    public var pageIndex: Int
    public var pagePointX: Double
    public var pagePointY: Double
    public var scaleFactor: Double
    public var updatedAt: Date

    public init(
        sessionID: String,
        paperID: String,
        pageIndex: Int,
        pagePointX: Double,
        pagePointY: Double,
        scaleFactor: Double,
        updatedAt: Date
    ) {
        self.sessionID = sessionID
        self.paperID = paperID
        self.pageIndex = pageIndex
        self.pagePointX = pagePointX
        self.pagePointY = pagePointY
        self.scaleFactor = scaleFactor
        self.updatedAt = updatedAt
    }
}

public enum ChatRole: String, Codable, Equatable, Sendable {
    case user
    case codex
    case system
}

public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var sessionID: String
    public var role: ChatRole
    public var content: String
    public var createdAt: Date

    public init(id: String, sessionID: String, role: ChatRole, content: String, createdAt: Date) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct PageIndex: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(paperID):p\(page)" }
    public var paperID: String
    public var page: Int
    public var text: String
    public var confidence: Double

    public init(paperID: String, page: Int, text: String, confidence: Double) {
        self.paperID = paperID
        self.page = page
        self.text = text
        self.confidence = confidence
    }
}
