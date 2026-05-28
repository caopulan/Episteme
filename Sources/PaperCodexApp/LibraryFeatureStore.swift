import Foundation
import PaperCodexCore

struct LibrarySelection: Equatable {
    var surface: LibrarySurface
    var categoryID: String?
    var tagID: String?
}

@MainActor
final class LibraryFeatureStore: ObservableObject {
    @Published var papers: [Paper] = []
    @Published var categories: [PaperCodexCore.Category] = []
    @Published var tags: [PaperTag] = []
    @Published var watchedFolders: [WatchedFolder] = []
    @Published var paperCategoryIDsByID: [String: [String]] = [:]
    @Published var paperTagsByID: [String: [PaperTag]] = [:]
    @Published var libraryDerivedState: PaperLibraryDerivedState = .empty
    @Published var selectedLibraryPaper: Paper?
    @Published private var selection = LibrarySelection(surface: .papers, categoryID: nil, tagID: nil)
    @Published var librarySearchText = ""
    @Published var paperThumbnailURLsByID: [String: [URL]] = [:]
    @Published var paperNotesByID: [String: [PaperNote]] = [:]

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
}
