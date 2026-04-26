import CryptoKit
import Foundation
import PaperCodexCore
import SwiftUI

enum AppRoute {
    case library
    case reader
}

struct PDFSelectionInfo: Equatable {
    var text: String
    var page: Int
    var bbox: BoundingBox
}

@MainActor
final class AppModel: ObservableObject {
    @Published var route: AppRoute = .library
    @Published var papers: [Paper] = []
    @Published var categories: [PaperCodexCore.Category] = []
    @Published var selectedPaper: Paper?
    @Published var selectedSession: PaperSession?
    @Published var sessions: [PaperSession] = []
    @Published var messages: [ChatMessage] = []
    @Published var currentSelection: PDFSelectionInfo?
    @Published var errorMessage: String?

    private var repository: PaperRepository?
    private let supportRoot: URL
    private let workspaceManager = SessionWorkspaceManager()

    init() {
        let root = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperCodex", isDirectory: true)
        supportRoot = root
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = try PaperRepository(databasePath: root.appendingPathComponent("store.sqlite").path)
            try store.migrate()
            repository = store
            try reloadLibrary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadLibrary() throws {
        guard let repository else {
            return
        }
        papers = try repository.fetchPapers()
        categories = try repository.fetchCategories()
    }

    func importPDF(from sourceURL: URL) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: sourceURL)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let title = sourceURL.deletingPathExtension().lastPathComponent
            let paperID = makePaperID(title: title, hash: hash)
            let paperDir = supportRoot.appendingPathComponent("papers/\(paperID)", isDirectory: true)
            try FileManager.default.createDirectory(at: paperDir, withIntermediateDirectories: true)
            let destination = paperDir.appendingPathComponent("original.pdf")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try data.write(to: destination, options: [.atomic])

            let now = Date()
            let paper = Paper(
                id: paperID,
                filePath: destination.path,
                fileHash: hash,
                title: title,
                authors: [],
                year: nil,
                sourceURL: nil,
                importedAt: now,
                updatedAt: now
            )
            try repository.upsertPaper(paper)

            let index = try PDFIndexExtractor().extract(paperID: paperID, pdfURL: destination)
            for span in index.spans {
                try repository.upsertSpan(span)
            }

            try reloadLibrary()
            openPaper(paper)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func openPaper(_ paper: Paper) {
        do {
            selectedPaper = paper
            currentSelection = nil
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            sessions = try repository.fetchSessions(paperID: paper.id)
            if let first = sessions.last {
                selectedSession = first
                messages = try repository.fetchMessages(sessionID: first.id)
            } else {
                try createSession()
            }
            route = .reader
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func createSession() throws {
        guard let paper = selectedPaper else {
            throw AppModelError.noSelectedPaper
        }
        guard let repository else {
            throw AppModelError.repositoryUnavailable
        }
        let now = Date()
        let sessionID = UUID().uuidString.lowercased()
        let workspacePath = supportRoot.appendingPathComponent("sessions/\(sessionID)", isDirectory: true).path
        let session = PaperSession(
            id: sessionID,
            title: "\(paper.title) Notes",
            paperIDs: [paper.id],
            codexSessionID: nil,
            workspacePath: workspacePath,
            createdAt: now,
            updatedAt: now
        )
        try repository.upsertSession(session)
        let spans = try repository.fetchSpans(paperID: paper.id)
        let anchors = try repository.fetchAnchors(paperID: paper.id)
        try workspaceManager.writeWorkspace(
            session: session,
            papers: [paper],
            pagesByPaperID: [paper.id: []],
            spansByPaperID: [paper.id: spans],
            anchorsByPaperID: [paper.id: anchors]
        )
        sessions = try repository.fetchSessions(paperID: paper.id)
        selectedSession = session
        messages = []
    }

    func newSessionButtonTapped() {
        do {
            try createSession()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func selectSession(_ sessionID: String) {
        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard let session = sessions.first(where: { $0.id == sessionID }) else {
                return
            }
            selectedSession = session
            messages = try repository.fetchMessages(sessionID: session.id)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func updateSelection(_ selection: PDFSelectionInfo?) {
        currentSelection = selection
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        do {
            guard let repository else {
                throw AppModelError.repositoryUnavailable
            }
            guard let paper = selectedPaper else {
                throw AppModelError.noSelectedPaper
            }
            guard var session = selectedSession else {
                throw AppModelError.noSelectedSession
            }

            var content = trimmed
            if let selection = currentSelection {
                let anchorID = Anchor.makeID(paperID: paper.id, page: selection.page, suffix: UUID().uuidString.lowercased())
                let anchor = Anchor(
                    id: anchorID,
                    paperID: paper.id,
                    page: selection.page,
                    selectedText: selection.text,
                    bboxList: [selection.bbox],
                    matchedSpanIDs: [],
                    beforeContext: "",
                    afterContext: "",
                    createdSessionID: session.id,
                    createdAt: Date(),
                    confidence: 0.75
                )
                try repository.upsertAnchor(anchor)
                content += "\n\n[selected source]\nanchor_id: \(anchor.id)\npage: \(anchor.page)\ntext: \"\(anchor.selectedText)\""
                currentSelection = nil
            }

            let message = ChatMessage(
                id: UUID().uuidString.lowercased(),
                sessionID: session.id,
                role: .user,
                content: content,
                createdAt: Date()
            )
            try repository.appendMessage(message)
            session.updatedAt = Date()
            try repository.upsertSession(session)
            selectedSession = session
            sessions = try repository.fetchSessions(paperID: paper.id)
            messages = try repository.fetchMessages(sessionID: session.id)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func goToLibrary() {
        route = .library
        selectedPaper = nil
        selectedSession = nil
        sessions = []
        messages = []
        currentSelection = nil
    }

    private func makePaperID(title: String, hash: String) -> String {
        let slug = title
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
        return "\(slug.isEmpty ? "paper" : slug)-\(hash.prefix(10))"
    }
}

enum AppModelError: Error, CustomStringConvertible {
    case repositoryUnavailable
    case noSelectedPaper
    case noSelectedSession

    var description: String {
        switch self {
        case .repositoryUnavailable:
            "Local repository is not available."
        case .noSelectedPaper:
            "No paper is selected."
        case .noSelectedSession:
            "No Codex session is selected."
        }
    }
}
