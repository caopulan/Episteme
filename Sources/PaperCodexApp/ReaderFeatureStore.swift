import Foundation
import PaperCodexCore

struct ReaderAddPaperListRequest: Equatable {
    var paperCollectionVersion: Int
    var currentSessionPaperIDs: Set<String>
    var query: String
}

struct ReaderAddPaperListState {
    static let empty = ReaderAddPaperListState(papers: [], paperIDs: [], hasQuery: false)

    var papers: [Paper]
    var paperIDs: [String]
    var hasQuery: Bool
}

@MainActor
final class ReaderFeatureStore: ObservableObject {
    @Published var readerReturnRoute: AppRoute = .library
    @Published var selectedPaper: Paper?
    @Published var readerTabState = ReaderTabState()
    @Published var selectedSession: PaperSession?
    @Published var sessions: [PaperSession] = []
    @Published var recentSessions: [PaperSession] = []
    @Published var recentSessionPapersByID: [String: [Paper]] = [:]
    @Published var selectedSessionPanelTab: SessionPanelTab = .chat
    @Published var messages: [ChatMessage] = []
    @Published var currentSelection: PDFSelectionInfo?
    @Published var pdfJumpTarget: PDFJumpTarget?
    @Published var readerPosition: PaperReaderPosition?
    @Published var citationReturnPoint: CitationReturnPoint?
    @Published var pdfKitCommand: PDFKitCommand?
    @Published var pdfDocumentStatus: PDFDocumentStatus?
    private var cachedAddPaperListRequest: ReaderAddPaperListRequest?
    private var cachedAddPaperListState: ReaderAddPaperListState?

    func addPaperListState(request: ReaderAddPaperListRequest, papers: [Paper]) -> ReaderAddPaperListState {
        if cachedAddPaperListRequest == request, let cachedAddPaperListState {
            return cachedAddPaperListState
        }

        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = papers.filter { paper in
            !paper.isArxivImportPlaceholder && !request.currentSessionPaperIDs.contains(paper.id)
        }
        if !query.isEmpty {
            result = result.filter { paper in
                paper.title.localizedCaseInsensitiveContains(query)
                    || paper.authors.joined(separator: " ").localizedCaseInsensitiveContains(query)
                    || (paper.year.map(String.init) ?? "").contains(query)
            }
        }

        let state = ReaderAddPaperListState(
            papers: result,
            paperIDs: result.map(\.id),
            hasQuery: !query.isEmpty
        )
        cachedAddPaperListRequest = request
        cachedAddPaperListState = state
        return state
    }
}
