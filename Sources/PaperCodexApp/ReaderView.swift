import AppKit
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
        .paperCodexNativeSheet(isPresented: $isShowingAddPaperToSessionSheet, title: "Add Paper", minimumSize: CGSize(width: 560, height: 400)) {
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
                PaperCodexNativeEmptyState(title: "No Paper Selected", systemImage: "doc.text")
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
                PaperCodexIconButton(title: "Close Split", systemImage: "xmark") {
                    closePDFSplit()
                }
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
            PaperCodexNativeSpinner()
                .frame(width: 16, height: 16)
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
                PaperCodexNativeEmptyState(title: "No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(width: 520, height: 220)
            } else {
                PaperCodexNativeScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredPapers) { paper in
                            AddPaperToSessionRowButton(
                                title: paper.title,
                                detail: paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", ")
                            ) {
                                onAdd(paper)
                            }
                            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: 520, height: 280)
            }
            HStack {
                Spacer()
                PaperCodexPanelButton(title: "Cancel", systemImage: "xmark") {
                    onCancel()
                }
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

private struct AddPaperToSessionRowButton: NSViewRepresentable {
    var title: String
    var detail: String
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NativeAddPaperToSessionRowButtonView {
        let button = NativeAddPaperToSessionRowButtonView()
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction(_:))
        button.apply(title: title, detail: detail)
        return button
    }

    func updateNSView(_ button: NativeAddPaperToSessionRowButtonView, context: Context) {
        context.coordinator.action = action
        button.apply(title: title, detail: detail)
    }

    @MainActor final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
            super.init()
        }

        @objc func performAction(_ sender: NSButton) {
            action()
        }
    }
}

private final class NativeAddPaperToSessionRowButtonView: NSButton {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var trackingAreaToken: NSTrackingArea?
    private var isHovering = false
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 54)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaToken {
            removeTrackingArea(trackingAreaToken)
        }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaToken = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressed = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
        super.mouseDown(with: event)
        isPressed = false
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func apply(title: String, detail: String) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        toolTip = "\(title)\n\(detail)"
        setAccessibilityLabel(title)
        setAccessibilityValue(detail)
        updateAppearance()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        title = ""
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        iconView.contentTintColor = .controlAccentColor
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3)
        ])

        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.cornerRadius = 7
        layer?.masksToBounds = false
        let accent = NSColor.controlAccentColor
        if isPressed {
            layer?.backgroundColor = accent.withAlphaComponent(0.16).cgColor
            layer?.borderColor = accent.withAlphaComponent(0.42).cgColor
            layer?.borderWidth = 1
        } else if isHovering {
            layer?.backgroundColor = accent.withAlphaComponent(0.10).cgColor
            layer?.borderColor = accent.withAlphaComponent(0.26).cgColor
            layer?.borderWidth = 1
        } else {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
            layer?.borderWidth = 1
        }
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = isHovering && !isPressed ? 0.08 : 0
        layer?.shadowRadius = isHovering ? 5 : 0
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        alphaValue = isPressed ? 0.78 : 1
    }
}
