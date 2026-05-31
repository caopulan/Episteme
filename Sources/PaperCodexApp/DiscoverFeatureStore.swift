import Foundation
import PaperCodexCore

struct DiscoverSidebarFacets: Equatable {
    static let empty = DiscoverSidebarFacets(categories: [], tagCounts: [:], sortedTags: [], totalTagCount: 0)

    var categories: [String]
    var tagCounts: [String: Int]
    var sortedTags: [String]
    var totalTagCount: Int

    static func make(
        papers: [ArxivFeedPaper],
        enrichmentsByID: [String: DiscoverPaperEnrichment]
    ) -> DiscoverSidebarFacets {
        let categories = Array(Set(papers.flatMap { $0.listCategories.isEmpty ? $0.categories : $0.listCategories })).sorted()
        let tagValues = papers.flatMap { tags(for: $0, enrichment: enrichmentsByID[$0.id]) }
        let tagCounts = Dictionary(tagValues.map { ($0, 1) }, uniquingKeysWith: +)
        let sortedTags = tagCounts.keys.sorted { left, right in
            let leftCount = tagCounts[left, default: 0]
            let rightCount = tagCounts[right, default: 0]
            if leftCount == rightCount {
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
            return leftCount > rightCount
        }
        return DiscoverSidebarFacets(
            categories: categories,
            tagCounts: tagCounts,
            sortedTags: sortedTags,
            totalTagCount: tagValues.count
        )
    }

    static func tags(for paper: ArxivFeedPaper, enrichment: DiscoverPaperEnrichment?) -> [String] {
        let generated = enrichment?.tags ?? []
        let combined = generated + paper.tags + Array(paper.categories.prefix(2))
        var seen: Set<String> = []
        var result: [String] = []
        for tag in combined {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }
}

enum DiscoverPaperListSource {
    case discover
    case search
}

enum DiscoverProcessingFilter: String, CaseIterable, Identifiable {
    case all
    case processed
    case unprocessed
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .processed:
            "Processed"
        case .unprocessed:
            "Unprocessed"
        case .failed:
            "Failed"
        }
    }
}

enum DiscoverLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case newOnly
    case inLibrary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All Papers"
        case .newOnly:
            "New Only"
        case .inLibrary:
            "In Library"
        }
    }
}

enum DiscoverSimilarityBucket: String, CaseIterable, Identifiable {
    case all
    case high
    case medium
    case low
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All Scores"
        case .high:
            "High"
        case .medium:
            "Medium"
        case .low:
            "Low"
        case .none:
            "No Similarity"
        }
    }

    func contains(_ value: Double?) -> Bool {
        switch self {
        case .all:
            true
        case .high:
            (value ?? 0) >= 0.78
        case .medium:
            (value ?? 0) >= 0.62 && (value ?? 0) < 0.78
        case .low:
            value != nil && (value ?? 0) < 0.62
        case .none:
            value == nil
        }
    }
}

struct DiscoverPaperListRequest: Equatable {
    var source: DiscoverPaperListSource
    var selectedCategory: String?
    var selectedTag: String?
    var processingFilter: DiscoverProcessingFilter
    var libraryFilter: DiscoverLibraryFilter
    var requiresProjectLink: Bool
    var similarityBucket: DiscoverSimilarityBucket
    var libraryArxivPaperIDs: Set<String>
}

struct DiscoverPaperListState {
    static let empty = DiscoverPaperListState(papers: [], paperIDs: [], hasActiveFilters: false)

    var papers: [ArxivFeedPaper]
    var paperIDs: [String]
    var hasActiveFilters: Bool
}

@MainActor
final class DiscoverFeatureStore: ObservableObject {
    @Published var arxivDates: [String] = []
    @Published var selectedArxivDate: String?
    @Published var arxivFeed: ArxivFeedResponse? {
        didSet {
            invalidatePaperListStateCache()
            refreshDiscoverSidebarFacets()
        }
    }
    @Published var selectedArxivPaper: ArxivFeedPaper?
    @Published var discoverKeyword = ""
    @Published var arxivSearchQuery = ""
    @Published var arxivSearchFeed: ArxivFeedResponse? {
        didSet { invalidatePaperListStateCache() }
    }
    @Published var arxivSearchSortRawValue = ArxivAPISort.relevance.rawValue
    @Published var arxivSearchSortOrderRawValue = ArxivAPISortOrder.descending.rawValue
    @Published var arxivSearchRequiredCategories: [String]
    @Published var arxivSearchFromYear: String
    @Published var arxivSearchThroughYear: String
    @Published var discoverStartDate: String
    @Published var discoverEndDate: String
    @Published var discoverSelectedCategories: [String] = ["cs.CV"]
    @Published var discoverSelectedSimilaritySourceIDs: [String] = []
    @Published var discoverResultIDs: [String] = []
    @Published var discoverEnrichmentsByID: [String: DiscoverPaperEnrichment] = [:] {
        didSet {
            invalidatePaperListStateCache()
            refreshDiscoverSidebarFacets()
        }
    }
    @Published private(set) var discoverSidebarFacets = DiscoverSidebarFacets.empty
    @Published var isSearchingDiscover = false
    @Published var isCancellingDiscoverSearch = false
    @Published var isSearchingArxivSearch = false
    @Published var isCancellingArxivSearch = false
    @Published var isProcessingDiscoverResults = false
    @Published var discoverProcessingProgress: ArxivCacheProgress?
    @Published var isCachingDiscoverPDFs = false
    @Published var discoverPDFCacheProgress: ArxivCacheProgress?
    @Published var arxivAssetURLs: [String: URL] = [:]
    @Published var arxivPDFThumbnailURLsByID: [String: [URL]] = [:]
    @Published var discoverPaperInteractionStateByID: [String: DiscoverPaperInteractionState] = [:]
    @Published var discoverScrollPositionPaperID: String?
    @Published var isLoadingArxivFeed = false
    @Published var isRefreshingArxivDates = false
    @Published var isPreloadingArxivAssets = false
    @Published var isAddingArxivPaper = false
    @Published var arxivDownloadingPaperIDs: Set<String> = []
    @Published var arxivDownloadProgressByID: [String: Double] = [:]
    @Published var arxivCacheProgress: ArxivCacheProgress?
    @Published var pendingArxivLibraryImportIDs: Set<String> = []
    @Published var failedArxivLibraryImportMessagesByID: [String: String] = [:]
    private var cachedPaperListRequest: DiscoverPaperListRequest?
    private var cachedPaperListState: DiscoverPaperListState?

    init(
        startDate: String,
        endDate: String,
        scrollPositionPaperID: String?,
        searchRequiredCategories: [String],
        searchFromYear: String,
        searchThroughYear: String
    ) {
        discoverStartDate = startDate
        discoverEndDate = endDate
        discoverScrollPositionPaperID = scrollPositionPaperID
        arxivSearchRequiredCategories = searchRequiredCategories
        arxivSearchFromYear = searchFromYear
        arxivSearchThroughYear = searchThroughYear
    }

    private func refreshDiscoverSidebarFacets() {
        discoverSidebarFacets = DiscoverSidebarFacets.make(
            papers: arxivFeed?.papers ?? [],
            enrichmentsByID: discoverEnrichmentsByID
        )
    }

    func paperListState(request: DiscoverPaperListRequest) -> DiscoverPaperListState {
        if cachedPaperListRequest == request, let cachedPaperListState {
            return cachedPaperListState
        }

        var result = request.source == .search
            ? arxivSearchFeed?.papers ?? []
            : arxivFeed?.papers ?? []

        if let selectedCategory = request.selectedCategory {
            result = result.filter { paper in
                paper.categories.contains(selectedCategory) || paper.listCategories.contains(selectedCategory)
            }
        }
        if let selectedTag = request.selectedTag {
            result = result.filter { paper in
                DiscoverSidebarFacets.tags(for: paper, enrichment: discoverEnrichmentsByID[paper.id]).contains(selectedTag)
            }
        }

        result = filterByProcessingState(result, filter: request.processingFilter)
        result = filterByLibraryState(
            result,
            filter: request.libraryFilter,
            libraryArxivPaperIDs: request.libraryArxivPaperIDs
        )

        if request.requiresProjectLink {
            result = result.filter { paper in
                let enrichment = discoverEnrichmentsByID[paper.id]
                return paper.links.github != nil
                    || paper.links.project != nil
                    || paper.links.huggingFace != nil
                    || !(enrichment?.links.isEmpty ?? true)
            }
        }
        if request.similarityBucket != .all {
            result = result.filter { request.similarityBucket.contains($0.similarity) }
        }

        let state = DiscoverPaperListState(
            papers: result,
            paperIDs: result.map(\.id),
            hasActiveFilters: request.selectedCategory != nil
                || request.selectedTag != nil
                || request.processingFilter != .all
                || request.libraryFilter != .all
                || request.requiresProjectLink
                || request.similarityBucket != .all
        )
        cachedPaperListRequest = request
        cachedPaperListState = state
        return state
    }

    private func filterByProcessingState(
        _ papers: [ArxivFeedPaper],
        filter: DiscoverProcessingFilter
    ) -> [ArxivFeedPaper] {
        switch filter {
        case .processed:
            papers.filter { paper in
                let enrichment = discoverEnrichmentsByID[paper.id]
                return enrichment?.error == nil && enrichment?.isCurrent == true
            }
        case .unprocessed:
            papers.filter { discoverEnrichmentsByID[$0.id] == nil }
        case .failed:
            papers.filter { discoverEnrichmentsByID[$0.id]?.error != nil }
        case .all:
            papers
        }
    }

    private func filterByLibraryState(
        _ papers: [ArxivFeedPaper],
        filter: DiscoverLibraryFilter,
        libraryArxivPaperIDs: Set<String>
    ) -> [ArxivFeedPaper] {
        switch filter {
        case .newOnly:
            papers.filter { !libraryArxivPaperIDs.contains($0.id) }
        case .inLibrary:
            papers.filter { libraryArxivPaperIDs.contains($0.id) }
        case .all:
            papers
        }
    }

    private func invalidatePaperListStateCache() {
        cachedPaperListRequest = nil
        cachedPaperListState = nil
    }
}
