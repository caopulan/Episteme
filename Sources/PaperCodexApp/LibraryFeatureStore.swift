import Foundation
import PaperCodexCore

struct LibrarySelection: Equatable {
    var surface: LibrarySurface
    var categoryID: String?
    var tagID: String?
}

struct LibraryPaperListRequest: Equatable {
    var selectedCategoryID: String?
    var selectedTagID: String?
    var searchText: String
    var sortRawValue: String
    var sortAscending: Bool
    var includeSubfolders: Bool
}

struct LibraryPaperListState {
    static let empty = LibraryPaperListState(
        papers: [],
        papersByID: [:],
        paperIDs: [],
        readablePaperIDs: [],
        hasActiveFilters: false
    )

    var papers: [Paper]
    var papersByID: [String: Paper]
    var paperIDs: [String]
    var readablePaperIDs: [String]
    var hasActiveFilters: Bool
}

struct LibraryPaperSelectionRequest: Equatable {
    var paperIDs: [String]
    var readablePaperIDs: [String]
    var selectedPaperIDs: Set<String>
}

struct LibraryPaperSelectionState {
    static let empty = LibraryPaperSelectionState(
        visiblePaperIDs: [],
        visiblePaperIDSet: [],
        selectedPaperIDsInOrder: [],
        selectedReadablePaperIDsInOrder: []
    )

    var visiblePaperIDs: [String]
    var visiblePaperIDSet: Set<String>
    var selectedPaperIDsInOrder: [String]
    var selectedReadablePaperIDsInOrder: [String]
}

struct LibraryPaperTableRowsRequest: Equatable {
    var paperIDs: [String]
    var selectedPaperID: String?
    var selectedPaperIDs: Set<String>
    var paperCollectionVersion: Int
    var rowMetadataVersion: Int
    var placeholderDetailsByPaperID: [String: String]
}

struct LibraryPaperTableRowsState {
    static let empty = LibraryPaperTableRowsState(rows: [])

    var rows: [LibraryPaperTableRow]
}

@MainActor
final class LibraryFeatureStore: ObservableObject {
    @Published var papers: [Paper] = [] {
        didSet {
            paperCollectionVersion += 1
            invalidatePaperListStateCache()
            invalidatePaperTableRowsCache()
        }
    }
    @Published var categories: [PaperCodexCore.Category] = [] {
        didSet {
            rowMetadataVersion += 1
            invalidatePaperListStateCache()
            invalidatePaperTableRowsCache()
        }
    }
    @Published var tags: [PaperTag] = [] {
        didSet {
            rowMetadataVersion += 1
            invalidatePaperListStateCache()
            invalidatePaperTableRowsCache()
        }
    }
    @Published var watchedFolders: [WatchedFolder] = []
    @Published var paperCategoryIDsByID: [String: [String]] = [:] {
        didSet {
            rowMetadataVersion += 1
            invalidatePaperListStateCache()
            invalidatePaperTableRowsCache()
        }
    }
    @Published var paperTagsByID: [String: [PaperTag]] = [:] {
        didSet {
            rowMetadataVersion += 1
            invalidatePaperListStateCache()
            invalidatePaperTableRowsCache()
        }
    }
    @Published var libraryDerivedState: PaperLibraryDerivedState = .empty {
        didSet { invalidatePaperListStateCache() }
    }
    @Published var selectedLibraryPaper: Paper?
    @Published private var selection = LibrarySelection(surface: .papers, categoryID: nil, tagID: nil)
    @Published var librarySearchText = ""
    @Published var paperThumbnailURLsByID: [String: [URL]] = [:] {
        didSet {
            rowMetadataVersion += 1
            invalidatePaperTableRowsCache()
        }
    }
    @Published var paperNotesByID: [String: [PaperNote]] = [:]
    private(set) var paperCollectionVersion = 0
    private(set) var rowMetadataVersion = 0
    private var cachedPaperListRequest: LibraryPaperListRequest?
    private var cachedPaperListState: LibraryPaperListState?
    private var cachedPaperSelectionRequest: LibraryPaperSelectionRequest?
    private var cachedPaperSelectionState: LibraryPaperSelectionState?
    private var cachedPaperTableRowsRequest: LibraryPaperTableRowsRequest?
    private var cachedPaperTableRowsState: LibraryPaperTableRowsState?

    var selectedLibrarySurface: LibrarySurface {
        get { selection.surface }
        set {
            setSelection(surface: newValue, categoryID: selection.categoryID, tagID: selection.tagID)
        }
    }

    var librarySelectedCategoryID: String? {
        get { selection.categoryID }
        set {
            setSelection(surface: selection.surface, categoryID: newValue, tagID: selection.tagID)
        }
    }

    var librarySelectedTagID: String? {
        get { selection.tagID }
        set {
            setSelection(surface: selection.surface, categoryID: selection.categoryID, tagID: newValue)
        }
    }

    func setSelection(surface: LibrarySurface, categoryID: String?, tagID: String?) {
        let nextSelection = LibrarySelection(surface: surface, categoryID: categoryID, tagID: tagID)
        guard selection != nextSelection else {
            return
        }
        selection = nextSelection
    }

    func applySnapshot(
        papers: [Paper],
        categories: [PaperCodexCore.Category],
        tags: [PaperTag],
        watchedFolders: [WatchedFolder],
        categoryIDsByPaperID: [String: [String]],
        tagsByPaperID: [String: [PaperTag]]
    ) {
        let selectedPaperID = selectedLibraryPaper?.id
        self.papers = papers
        self.categories = categories
        self.tags = tags
        self.watchedFolders = watchedFolders
        self.paperCategoryIDsByID = categoryIDsByPaperID
        self.paperTagsByID = tagsByPaperID
        libraryDerivedState = PaperLibraryDerivedState.build(
            papers: papers,
            categories: categories,
            categoryIDsByPaperID: categoryIDsByPaperID,
            tagsByPaperID: tagsByPaperID
        )
        if let selectedPaperID {
            selectedLibraryPaper = papers.first { $0.id == selectedPaperID }
        }
    }

    func applyCategories(_ categories: [PaperCodexCore.Category]) {
        self.categories = categories
        libraryDerivedState = PaperLibraryDerivedState.build(
            papers: papers,
            categories: categories,
            categoryIDsByPaperID: paperCategoryIDsByID,
            tagsByPaperID: paperTagsByID
        )
    }

    func paperListState(request: LibraryPaperListRequest) -> LibraryPaperListState {
        if cachedPaperListRequest == request, let cachedPaperListState {
            return cachedPaperListState
        }

        let query = request.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var paperIDFilter: Set<String>?

        if let selectedCategoryID = request.selectedCategoryID {
            paperIDFilter = libraryDerivedState.paperIDsForCategoryFilter(
                selectedCategoryID,
                includeDescendants: request.includeSubfolders
            )
        }

        if let selectedTagID = request.selectedTagID {
            let tagPaperIDs = libraryDerivedState.paperIDsForTag(selectedTagID)
            if let existingFilter = paperIDFilter {
                paperIDFilter = existingFilter.intersection(tagPaperIDs)
            } else {
                paperIDFilter = tagPaperIDs
            }
        }

        var visiblePapers = papers
        if let paperIDFilter {
            visiblePapers = visiblePapers.filter { paperIDFilter.contains($0.id) }
        }
        if !query.isEmpty {
            visiblePapers = visiblePapers.filter { paper in
                libraryDerivedState.matchesSearch(paperID: paper.id, query: query)
            }
        }

        let option = LibrarySortOption(rawValue: request.sortRawValue) ?? .addedNewest
        let sortedPapers = option.sorted(visiblePapers, ascending: request.sortAscending)
        let state = LibraryPaperListState(
            papers: sortedPapers,
            papersByID: Dictionary(uniqueKeysWithValues: sortedPapers.map { ($0.id, $0) }),
            paperIDs: sortedPapers.map(\.id),
            readablePaperIDs: sortedPapers.filter { !$0.isArxivImportPlaceholder }.map(\.id),
            hasActiveFilters: request.selectedCategoryID != nil || request.selectedTagID != nil || !query.isEmpty
        )
        cachedPaperListRequest = request
        cachedPaperListState = state
        return state
    }

    func paperSelectionState(request: LibraryPaperSelectionRequest) -> LibraryPaperSelectionState {
        if cachedPaperSelectionRequest == request, let cachedPaperSelectionState {
            return cachedPaperSelectionState
        }

        let selectedPaperIDs = request.selectedPaperIDs
        let readablePaperIDs = Set(request.readablePaperIDs)
        let selectedPaperIDsInOrder = request.paperIDs.filter { selectedPaperIDs.contains($0) }
        let state = LibraryPaperSelectionState(
            visiblePaperIDs: request.paperIDs,
            visiblePaperIDSet: Set(request.paperIDs),
            selectedPaperIDsInOrder: selectedPaperIDsInOrder,
            selectedReadablePaperIDsInOrder: selectedPaperIDsInOrder.filter { readablePaperIDs.contains($0) }
        )
        cachedPaperSelectionRequest = request
        cachedPaperSelectionState = state
        return state
    }

    func paperTableRowsState(
        request: LibraryPaperTableRowsRequest,
        papers: [Paper]
    ) -> LibraryPaperTableRowsState {
        if cachedPaperTableRowsRequest == request, let cachedPaperTableRowsState {
            return cachedPaperTableRowsState
        }

        let categoryRankByID = Dictionary(
            uniqueKeysWithValues: categories.enumerated().map { offset, category in
                (category.id, offset)
            }
        )
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let selectedPaperIDs = request.selectedPaperIDs
        let rows = papers.map { paper in
            let categoryIDs = paperCategoryIDsByID[paper.id, default: []]
            let paperCategories = categoryIDs
                .compactMap { categoriesByID[$0] }
                .sorted { left, right in
                    categoryRankByID[left.id, default: Int.max] < categoryRankByID[right.id, default: Int.max]
                }
            return LibraryPaperTableRow(
                paper: paper,
                categories: paperCategories,
                tags: paperTagsByID[paper.id, default: []],
                thumbnailURLs: paperThumbnailURLsByID[paper.id, default: []],
                isImportPlaceholder: paper.isArxivImportPlaceholder,
                placeholderDetail: request.placeholderDetailsByPaperID[paper.id]
                    ?? Self.defaultPaperTableRowPlaceholderDetail(for: paper),
                isSelected: request.selectedPaperID == paper.id,
                isMultiSelected: selectedPaperIDs.contains(paper.id)
            )
        }

        let state = LibraryPaperTableRowsState(rows: rows)
        cachedPaperTableRowsRequest = request
        cachedPaperTableRowsState = state
        return state
    }

    private func invalidatePaperListStateCache() {
        cachedPaperListRequest = nil
        cachedPaperListState = nil
    }

    private func invalidatePaperTableRowsCache() {
        cachedPaperTableRowsRequest = nil
        cachedPaperTableRowsState = nil
    }

    private static func defaultPaperTableRowPlaceholderDetail(for paper: Paper) -> String {
        paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", ")
    }
}
