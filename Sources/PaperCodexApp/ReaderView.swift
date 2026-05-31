import PaperCodexCore
import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingAddPaperToSessionSheet = false
    @State private var isPDFSplitVisible = false
    @State private var pdfSplitTarget: PDFInternalLinkTarget?
    @State private var pendingPDFSplitTarget: PDFInternalLinkTarget?
    @State private var isPDFSplitContentReady = false
    @State private var pdfSplitOpenGeneration = 0

    var body: some View {
        ReaderSplitView(
            {
                pdfPane
                    .frame(minWidth: ReaderPDFLayout.minimumPaneWidth, maxWidth: .infinity)
            },
            secondary: {
                ChatView()
                    .frame(minWidth: ReaderPDFLayout.minimumChatPaneWidth, idealWidth: 420, maxWidth: .infinity)
            }
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.selectedPaper?.id) { _, _ in
            resetPDFSplit()
        }
        .sheet(isPresented: $isShowingAddPaperToSessionSheet) {
            AddPaperToSessionSheet(
                papers: model.papers.filter { paper in
                    !paper.isArxivImportPlaceholder && !model.currentSessionPapers.contains(where: { $0.id == paper.id })
                },
                onAdd: { paper in
                    model.addPaperToCurrentSession(paper)
                    isShowingAddPaperToSessionSheet = false
                },
                onCancel: {
                    isShowingAddPaperToSessionSheet = false
                }
            )
        }
    }

    private var pdfPane: some View {
        ZStack {
            if let paper = model.selectedPaper {
                VStack(spacing: 0) {
                    ReaderNativeToolbarView(
                        status: model.pdfDocumentStatus,
                        papers: model.currentSessionPapers,
                        activePaperID: model.selectedPaper?.id,
                        returnPoint: model.citationReturnPoint,
                        isSplitVisible: isPDFSplitVisible,
                        onSelectPaper: { paper in
                            model.selectReaderPaper(paper)
                        },
                        onAddPaper: {
                            isShowingAddPaperToSessionSheet = true
                        },
                        onRemoveActivePaper: {
                            if let paperID = model.selectedPaper?.id {
                                model.removePaperFromCurrentSession(paperID)
                            }
                        },
                        onCommand: { model.sendPDFKitCommand($0) },
                        onReturn: { model.returnFromCitationJump() },
                        onToggleSplit: { togglePDFSplit() }
                    )
                    .frame(maxWidth: .infinity, minHeight: 36, idealHeight: 36, maxHeight: 36)
                    Divider()
                    pdfContent(for: paper)
                }
            } else {
                ContentUnavailableView("No Paper Selected", systemImage: "doc.text")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func pdfContent(for paper: Paper) -> some View {
        Group {
            if isPDFSplitVisible {
                ReaderPDFSplitView(
                    {
                        primaryPDFView(for: paper)
                            .frame(minHeight: ReaderPDFLayout.minimumSplitPaneHeight, maxHeight: .infinity)
                    },
                    secondary: {
                        secondaryPDFView(for: paper)
                            .frame(minHeight: ReaderPDFLayout.minimumSplitPaneHeight, maxHeight: .infinity)
                    }
                )
                .transition(.opacity)
            } else {
                primaryPDFView(for: paper)
                    .transition(.opacity)
            }
        }
        .animation(PaperCodexMotion.accessible(PaperCodexMotion.pdfSplitOpen, reduceMotion: reduceMotion), value: isPDFSplitVisible)
        .animation(PaperCodexMotion.accessible(PaperCodexMotion.pdfSplitContent, reduceMotion: reduceMotion), value: isPDFSplitContentReady)
    }

    private func primaryPDFView(for paper: Paper) -> some View {
        PDFKitView(
            filePath: paper.filePath,
            jumpTarget: model.pdfJumpTarget,
            readingContextID: model.readerPositionContextID,
            readingPosition: model.readerPosition,
            command: model.pdfKitCommand,
            internalLinkTarget: nil,
            onSelection: { selection in
                model.updateSelection(selection)
            },
            onReadingPositionChange: { position in
                model.updateReaderPosition(position)
            },
            onDocumentStatusChange: { status in
                model.updatePDFDocumentStatus(status)
            },
            onInternalLinkSplit: { target in
                openPDFSplit(target)
            }
        )
    }

    private func secondaryPDFView(for paper: Paper) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Link Preview", systemImage: "rectangle.split.2x1")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    closePDFSplit()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Close Split")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            ZStack {
                if isPDFSplitContentReady {
                    PDFKitView(
                        filePath: paper.filePath,
                        jumpTarget: nil,
                        readingContextID: "split-\(paper.id)",
                        readingPosition: nil,
                        command: nil,
                        internalLinkTarget: pdfSplitTarget,
                        onSelection: { selection in
                            model.updateSelection(selection)
                        },
                        onReadingPositionChange: { _ in },
                        onDocumentStatusChange: { _ in },
                        onInternalLinkSplit: { target in
                            openPDFSplit(target)
                        }
                    )
                    .transition(.opacity)
                } else {
                    PDFSplitPreparingView(target: pendingPDFSplitTarget ?? pdfSplitTarget)
                        .transition(.opacity)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func openPDFSplit(_ target: PDFInternalLinkTarget) {
        guard !isPDFSplitVisible else {
            if isPDFSplitContentReady {
                PaperCodexMotion.perform(PaperCodexMotion.pdfSplitContent, reduceMotion: reduceMotion) {
                    pdfSplitTarget = target
                }
            } else {
                pendingPDFSplitTarget = target
            }
            return
        }
        beginPDFSplitOpen(target: target)
    }

    private func closePDFSplit() {
        pdfSplitOpenGeneration += 1
        PaperCodexMotion.perform(PaperCodexMotion.pdfSplitOpen, reduceMotion: reduceMotion) {
            isPDFSplitVisible = false
            isPDFSplitContentReady = false
        }
        pendingPDFSplitTarget = nil
        pdfSplitTarget = nil
    }

    private func resetPDFSplit() {
        pdfSplitOpenGeneration += 1
        isPDFSplitVisible = false
        isPDFSplitContentReady = false
        pendingPDFSplitTarget = nil
        pdfSplitTarget = nil
    }

    private func togglePDFSplit() {
        if isPDFSplitVisible {
            closePDFSplit()
        } else {
            beginPDFSplitOpen(target: nil)
        }
    }

    private func beginPDFSplitOpen(target: PDFInternalLinkTarget?) {
        pdfSplitOpenGeneration += 1
        let generation = pdfSplitOpenGeneration
        pendingPDFSplitTarget = target
        isPDFSplitContentReady = false
        pdfSplitTarget = nil

        PaperCodexMotion.perform(PaperCodexMotion.pdfSplitOpen, reduceMotion: reduceMotion) {
            isPDFSplitVisible = true
        }
        schedulePDFSplitContentMount(generation: generation)
    }

    private func schedulePDFSplitContentMount(generation: Int) {
        let delay = reduceMotion ? 0 : ReaderPDFLayout.splitContentMountDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard generation == pdfSplitOpenGeneration, isPDFSplitVisible else {
                return
            }
            let target = pendingPDFSplitTarget
            PaperCodexMotion.perform(PaperCodexMotion.pdfSplitContent, reduceMotion: reduceMotion) {
                pdfSplitTarget = target
                pendingPDFSplitTarget = nil
                isPDFSplitContentReady = true
            }
        }
    }
}

private enum ReaderPDFLayout {
    static let minimumPaneWidth: CGFloat = 360
    static let minimumChatPaneWidth: CGFloat = 330
    static let minimumSplitPaneHeight: CGFloat = 220
    static let splitContentMountDelay: TimeInterval = 0.20
}

private struct PDFSplitPreparingView: View {
    var target: PDFInternalLinkTarget?

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(LocalizedStringKey(target == nil ? "Preparing split view" : "Preparing link preview"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct AddPaperToSessionSheet: View {
    var papers: [Paper]
    var onAdd: (Paper) -> Void
    var onCancel: () -> Void

    @State private var query = ""

    private var filteredPapers: [Paper] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return papers
        }
        return papers.filter { paper in
            paper.title.localizedCaseInsensitiveContains(trimmed)
                || paper.authors.joined(separator: " ").localizedCaseInsensitiveContains(trimmed)
                || (paper.year.map(String.init) ?? "").contains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Add Paper", systemImage: "plus")
                .font(.title3.weight(.semibold))
            PaperCodexNativeTextField(text: $query, placeholder: "Search library")
                .frame(height: 30)
            if filteredPapers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(width: 520, height: 220)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredPapers) { paper in
                            Button {
                                onAdd(paper)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(paper.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text(paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 520, height: 280)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}
