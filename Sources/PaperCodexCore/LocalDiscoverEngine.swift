import CryptoKit
import Foundation

public enum LocalDiscoverEngineError: Error, CustomStringConvertible, Equatable {
    case invalidDate(String)
    case invertedDateRange(start: String, end: String)
    case unsafeCacheKey(String)

    public var description: String {
        switch self {
        case let .invalidDate(value):
            "Invalid discover date: \(value). Expected yyyy-MM-dd."
        case let .invertedDateRange(start, end):
            "Discover date range start \(start) is after end \(end)."
        case let .unsafeCacheKey(value):
            "Unsafe discover cache key: \(value)"
        }
    }
}

public struct DiscoverDateRange: Codable, Equatable, Sendable {
    public var start: String
    public var end: String

    public init(start: String, end: String) throws {
        guard let startDate = Self.dateFormatter.date(from: start) else {
            throw LocalDiscoverEngineError.invalidDate(start)
        }
        guard let endDate = Self.dateFormatter.date(from: end) else {
            throw LocalDiscoverEngineError.invalidDate(end)
        }
        guard startDate <= endDate else {
            throw LocalDiscoverEngineError.invertedDateRange(start: start, end: end)
        }
        self.start = start
        self.end = end
    }

    public var dates: [String] {
        guard let startDate = Self.dateFormatter.date(from: start),
              let endDate = Self.dateFormatter.date(from: end) else {
            return []
        }
        var result: [String] = []
        var cursor = startDate
        while cursor <= endDate {
            result.append(Self.dateFormatter.string(from: cursor))
            guard let next = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return result
    }

    public func contains(_ date: String) -> Bool {
        dates.contains(date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

public struct DiscoverQuery: Codable, Equatable, Sendable {
    public var keyword: String
    public var dateRange: DiscoverDateRange
    public var categories: [String]
    public var similaritySourceIDs: [String]
    public var rankingVersion: String

    public init(
        keyword: String,
        dateRange: DiscoverDateRange,
        categories: [String],
        similaritySourceIDs: [String],
        rankingVersion: String
    ) {
        self.keyword = keyword
        self.dateRange = dateRange
        self.categories = categories
        self.similaritySourceIDs = similaritySourceIDs
        self.rankingVersion = rankingVersion
    }

    public var normalized: DiscoverQuery {
        DiscoverQuery(
            keyword: normalizeKeyword(keyword),
            dateRange: dateRange,
            categories: normalizedSorted(categories),
            similaritySourceIDs: normalizedSorted(similaritySourceIDs),
            rankingVersion: rankingVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public var cacheKey: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(normalized)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct DiscoverQueryResult: Codable, Equatable, Sendable {
    public var query: DiscoverQuery
    public var arxivIDs: [String]
    public var generatedAt: Date

    public init(query: DiscoverQuery, arxivIDs: [String], generatedAt: Date) {
        self.query = query
        self.arxivIDs = arxivIDs
        self.generatedAt = generatedAt
    }
}

public enum DiscoverQuickRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case thisWeek
    case thisMonth
    case last7Days
    case last30Days

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today:
            "Today"
        case .thisWeek:
            "This Week"
        case .thisMonth:
            "This Month"
        case .last7Days:
            "Last 7 Days"
        case .last30Days:
            "Last 30 Days"
        }
    }

    public func dateRange(endingAt value: String) throws -> DiscoverDateRange {
        guard let endDate = discoverDateFormatter.date(from: value) else {
            throw LocalDiscoverEngineError.invalidDate(value)
        }
        let calendar = Calendar(identifier: .gregorian)
        let startDate: Date
        switch self {
        case .today:
            startDate = endDate
        case .thisWeek:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: endDate)
            startDate = calendar.date(from: components) ?? endDate
        case .thisMonth:
            let components = calendar.dateComponents([.year, .month], from: endDate)
            startDate = calendar.date(from: components) ?? endDate
        case .last7Days:
            startDate = calendar.date(byAdding: .day, value: -6, to: endDate) ?? endDate
        case .last30Days:
            startDate = calendar.date(byAdding: .day, value: -29, to: endDate) ?? endDate
        }
        return try DiscoverDateRange(
            start: discoverDateFormatter.string(from: startDate),
            end: discoverDateFormatter.string(from: endDate)
        )
    }
}

public struct DiscoverPaperEnrichment: Codable, Equatable, Sendable {
    public static let currentProcessorVersion = "local-discover-enrichment-v1"
    public static let currentPromptVersion = "discover-metadata-zh-v1"

    public var arxivID: String
    public var processorVersion: String
    public var promptVersion: String
    public var modelIdentity: String
    public var titleZH: String
    public var summaryZH: String
    public var contribution: String
    public var tags: [String]
    public var links: [String: String]
    public var generatedAt: Date
    public var error: String?

    public init(
        arxivID: String,
        processorVersion: String,
        promptVersion: String,
        modelIdentity: String,
        titleZH: String,
        summaryZH: String,
        contribution: String,
        tags: [String],
        links: [String: String],
        generatedAt: Date,
        error: String?
    ) {
        self.arxivID = arxivID
        self.processorVersion = processorVersion
        self.promptVersion = promptVersion
        self.modelIdentity = modelIdentity
        self.titleZH = titleZH
        self.summaryZH = summaryZH
        self.contribution = contribution
        self.tags = tags
        self.links = links
        self.generatedAt = generatedAt
        self.error = error
    }

    public var isCurrent: Bool {
        processorVersion == Self.currentProcessorVersion && promptVersion == Self.currentPromptVersion
    }
}

public enum DiscoverEnrichmentParser {
    public static func parse(
        _ text: String,
        arxivID: String,
        modelIdentity: String,
        generatedAt: Date
    ) throws -> DiscoverPaperEnrichment {
        let jsonText = extractJSONObject(from: text)
        let data = Data(jsonText.utf8)
        let decoded = try JSONDecoder().decode(DecodedDiscoverEnrichment.self, from: data)
        return DiscoverPaperEnrichment(
            arxivID: arxivID,
            processorVersion: DiscoverPaperEnrichment.currentProcessorVersion,
            promptVersion: DiscoverPaperEnrichment.currentPromptVersion,
            modelIdentity: modelIdentity,
            titleZH: decoded.titleZH.trimmingCharacters(in: .whitespacesAndNewlines),
            summaryZH: decoded.summaryZH.trimmingCharacters(in: .whitespacesAndNewlines),
            contribution: decoded.contribution.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: normalizedOrdered(decoded.tags),
            links: decoded.links.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            generatedAt: generatedAt,
            error: nil
        )
    }

    private static func extractJSONObject(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else {
            return trimmed
        }
        return String(trimmed[start...end])
    }
}

private struct DecodedDiscoverEnrichment: Decodable {
    var titleZH: String
    var summaryZH: String
    var contribution: String
    var tags: [String]
    var links: [String: String]

    private enum CodingKeys: String, CodingKey {
        case titleZH = "title_zh"
        case summaryZH = "summary_zh"
        case contribution
        case tags
        case links
    }
}

public final class LocalDiscoverCache {
    private let root: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func saveQueryResult(_ result: DiscoverQueryResult) throws {
        try writeJSON(result, to: queryResultURL(cacheKey: result.query.cacheKey))
    }

    public func loadQueryResult(cacheKey: String) throws -> DiscoverQueryResult? {
        let url = try queryResultURL(cacheKey: cacheKey)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try decoder.decode(DiscoverQueryResult.self, from: Data(contentsOf: url))
    }

    public func saveEnrichment(_ enrichment: DiscoverPaperEnrichment) throws {
        try writeJSON(enrichment, to: enrichmentURL(arxivID: enrichment.arxivID))
    }

    public func loadEnrichment(arxivID: String) throws -> DiscoverPaperEnrichment? {
        let url = enrichmentURL(arxivID: arxivID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try decoder.decode(DiscoverPaperEnrichment.self, from: Data(contentsOf: url))
    }

    private func queryResultURL(cacheKey: String) throws -> URL {
        guard cacheKey.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw LocalDiscoverEngineError.unsafeCacheKey(cacheKey)
        }
        return root
            .appendingPathComponent("queries", isDirectory: true)
            .appendingPathComponent("\(cacheKey).json")
    }

    private func enrichmentURL(arxivID: String) -> URL {
        root
            .appendingPathComponent("enrichments", isDirectory: true)
            .appendingPathComponent("\(safeFilename(arxivID)).json")
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}

private func normalizeKeyword(_ value: String) -> String {
    value
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .lowercased()
}

private func normalizedSorted(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            continue
        }
        let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !seen.contains(key) else {
            continue
        }
        seen.insert(key)
        result.append(trimmed)
    }
    return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

private func safeFilename(_ value: String) -> String {
    let mapped = value.map { character in
        character.isLetter || character.isNumber || character == "." || character == "-" ? character : "-"
    }
    let filename = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return filename.isEmpty ? "item" : filename
}

private func normalizedOrdered(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            continue
        }
        let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !seen.contains(key) else {
            continue
        }
        seen.insert(key)
        result.append(trimmed)
    }
    return result
}

private let discoverDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()
