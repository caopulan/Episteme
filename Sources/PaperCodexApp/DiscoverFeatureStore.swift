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

@MainActor
final class DiscoverFeatureStore: ObservableObject {
    @Published var arxivDates: [String] = []
    @Published var selectedArxivDate: String?
    @Published var arxivFeed: ArxivFeedResponse? {
        didSet {
            refreshDiscoverSidebarFacets()
        }
    }
    @Published var selectedArxivPaper: ArxivFeedPaper?
    @Published var discoverKeyword = ""
    @Published var arxivSearchQuery = ""
    @Published var arxivSearchFeed: ArxivFeedResponse?
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
}
