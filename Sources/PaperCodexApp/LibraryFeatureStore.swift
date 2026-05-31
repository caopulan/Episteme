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
        paperIDs: [],
        readablePaperIDs: [],
        hasActiveFilters: false
    )

    var papers: [Paper]
    var paperIDs: [String]
    var readablePaperIDs: [String]
    var hasActiveFilters: Bool
}

@MainActor
final class LibraryFeatureStore: ObservableObject {
    @Published var papers: [Paper] = [] {
        didSet { invalidatePaperListStateCache() }
    }
    @Published var categories: [PaperCodexCore.Category] = [] {
        didSet { invalidatePaperListStateCache() }
    }
    @Published var tags: [PaperTag] = [] {
        didSet { invalidatePaperListStateCache() }
    }
    @Published var watchedFolders: [WatchedFolder] = []
    @Published var paperCategoryIDsByID: [String: [String]] = [:] {
        didSet { invalidatePaperListStateCache() }
    }
    @Published var paperTagsByID: [String: [PaperTag]] = [:] {
        didSet { invalidatePaperListStateCache() }
    }
    @Published var libraryDerivedState: PaperLibraryDerivedState = .empty {
        didSet { invalidatePaperListStateCache() }
    }
    @Published var selectedLibraryPaper: Paper?
    @Published private var selection = LibrarySelection(surface: .papers, categoryID: nil, tagID: nil)
    @Published var librarySearchText = ""
    @Published var paperThumbnailURLsByID: [String: [URL]] = [:]
    @Published var paperNotesByID: [String: [PaperNote]] = [:]
    private var cachedPaperListRequest: LibraryPaperListRequest?
    private var cachedPaperListState: LibraryPaperListState?

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
            paperIDs: sortedPapers.map(\.id),
            readablePaperIDs: sortedPapers.filter { !$0.isArxivImportPlaceholder }.map(\.id),
            hasActiveFilters: request.selectedCategoryID != nil || request.selectedTagID != nil || !query.isEmpty
        )
        cachedPaperListRequest = request
        cachedPaperListState = state
        return state
    }

    private func invalidatePaperListStateCache() {
        cachedPaperListRequest = nil
        cachedPaperListState = nil
    }
}
