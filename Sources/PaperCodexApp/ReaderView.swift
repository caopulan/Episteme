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
        ReaderSplitView(secondaryContentID: "reader-chat") {
            pdfPane
                .frame(minWidth: ReaderPDFLayout.minimumPaneWidth, maxWidth: .infinity)
        } secondary: {
            ChatView()
                .frame(minWidth: ReaderPDFLayout.minimumChatPaneWidth, idealWidth: 420, maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.selectedPaper?.id) { _, _ in
            resetPDFSplit()
        }
        .paperCodexNativeSheet(isPresented: $isShowingAddPaperToSessionSheet, title: "Add Paper", minimumSize: CGSize(width: 560, height: 400)) {
            AddPaperToSessionSheet(
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

    private var pdfSplitSecondaryContentID: AnyHashable {
        let target = pendingPDFSplitTarget ?? pdfSplitTarget
        let targetToken: String
        if let target {
            targetToken = "\(target.pageIndex):\(target.pagePointX):\(target.pagePointY)"
        } else {
            targetToken = "none"
        }
        return "\(model.selectedPaper?.id ?? "no-paper")|\(isPDFSplitContentReady)|\(targetToken)"
    }

    @ViewBuilder
    private func pdfContent(for paper: Paper) -> some View {
        Group {
            if isPDFSplitVisible {
                ReaderPDFSplitView(secondaryContentID: pdfSplitSecondaryContentID) {
                    primaryPDFView(for: paper)
                        .frame(minHeight: ReaderPDFLayout.minimumSplitPaneHeight, maxHeight: .infinity)
                } secondary: {
                    secondaryPDFView(for: paper)
                        .frame(minHeight: ReaderPDFLayout.minimumSplitPaneHeight, maxHeight: .infinity)
                }
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
    @EnvironmentObject private var model: AppModel

    var onAdd: (Paper) -> Void
    var onCancel: () -> Void

    @State private var query = ""

    private var listState: ReaderAddPaperListState {
        model.readerAddPaperListState(query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Add Paper", systemImage: "plus")
                .font(.title3.weight(.semibold))
            PaperCodexNativeTextField(text: $query, placeholder: "Search library")
                .frame(height: 30)
            if listState.papers.isEmpty {
                PaperCodexNativeEmptyState(title: "No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(width: 520, height: 220)
            } else {
                NativeAddPaperToSessionList(papers: listState.papers, onAdd: onAdd)
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

private struct NativeAddPaperToSessionList: NSViewRepresentable {
    var papers: [Paper]
    var onAdd: (Paper) -> Void

    func makeNSView(context: Context) -> NativeAddPaperToSessionListView {
        let view = NativeAddPaperToSessionListView()
        view.apply(papers: papers, onAdd: onAdd)
        return view
    }

    func updateNSView(_ view: NativeAddPaperToSessionListView, context: Context) {
        view.apply(papers: papers, onAdd: onAdd)
    }
}

private final class NativeAddPaperToSessionListView: NSScrollView {
    private let tableView = NativeAddPaperToSessionTableView()
    private let controller = NativeAddPaperToSessionTableController()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func apply(papers: [Paper], onAdd: @escaping (Paper) -> Void) {
        controller.apply(papers: papers, onAdd: onAdd)
        tableView.reloadData()
        fitColumnToVisibleWidth()
        if !papers.isEmpty {
            tableView.scrollRowToVisible(0)
        }
    }

    override func layout() {
        super.layout()
        fitColumnToVisibleWidth()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        scrollerStyle = .overlay

        let column = NSTableColumn(identifier: NativeAddPaperToSessionTableController.columnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.autoresizingMask = [.width]
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.rowHeight = NativeAddPaperToSessionTableController.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 6)
        tableView.style = .plain
        tableView.dataSource = controller
        tableView.delegate = controller
        controller.attach(tableView: tableView)
        tableView.onActivateRow = { [weak controller] rowIndex in
            controller?.activateRow(at: rowIndex)
        }
        tableView.onPressRow = { [weak controller] rowIndex, isPressing in
            controller?.setPressedRow(rowIndex, isPressing: isPressing)
        }

        documentView = tableView
    }

    private func fitColumnToVisibleWidth() {
        guard let column = tableView.tableColumns.first else {
            return
        }
        let visibleWidth = contentView.bounds.width
        guard visibleWidth > 0 else {
            return
        }
        if abs(tableView.frame.width - visibleWidth) > 0.5 {
            tableView.frame.size.width = visibleWidth
        }
        if abs(column.width - visibleWidth) > 0.5 {
            column.width = visibleWidth
        }
    }
}

private final class NativeAddPaperToSessionTableView: NSTableView {
    var onActivateRow: (Int) -> Void = { _ in }
    var onPressRow: (Int?, Bool) -> Void = { _, _ in }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let localPoint = convert(event.locationInWindow, from: nil)
        let rowIndex = row(at: localPoint)
        if rowIndex >= 0 {
            onPressRow(rowIndex, true)
        }
        super.mouseDown(with: event)
        if rowIndex >= 0 {
            onPressRow(rowIndex, false)
            onActivateRow(rowIndex)
        }
    }
}

@MainActor private final class NativeAddPaperToSessionTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let columnIdentifier = NSUserInterfaceItemIdentifier("add-paper")
    static let rowHeight: CGFloat = 58

    private static let cellIdentifier = NSUserInterfaceItemIdentifier("AddPaperToSessionCell")

    private var papers: [Paper] = []
    private var pressedRow: Int?
    private var onAdd: (Paper) -> Void = { _ in }
    private weak var tableView: NSTableView?

    func attach(tableView: NSTableView) {
        self.tableView = tableView
    }

    func apply(papers: [Paper], onAdd: @escaping (Paper) -> Void) {
        self.papers = papers
        self.onAdd = onAdd
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        papers.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Self.rowHeight
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NativeAddPaperToSessionTableRowView()
        rowView.isEmphasized = false
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard papers.indices.contains(row) else {
            return nil
        }
        let cell = (tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? NativeAddPaperToSessionRowCellView)
            ?? NativeAddPaperToSessionRowCellView(identifier: Self.cellIdentifier)
        let paper = papers[row]
        cell.configure(
            title: paper.title,
            detail: paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "),
            isPressing: pressedRow == row
        )
        return cell
    }

    func activateRow(at row: Int) {
        guard papers.indices.contains(row) else {
            return
        }
        onAdd(papers[row])
    }

    func setPressedRow(_ row: Int?, isPressing: Bool) {
        let nextPressedRow = isPressing ? row : nil
        guard pressedRow != nextPressedRow else {
            return
        }
        let previousPressedRow = pressedRow
        pressedRow = nextPressedRow
        reloadRows([previousPressedRow, pressedRow].compactMap { $0 })
    }

    private func reloadRows(_ rowIndexes: [Int]) {
        guard let tableView = tableView else {
            return
        }
        let validIndexes = IndexSet(rowIndexes.filter { $0 >= 0 && $0 < tableView.numberOfRows })
        guard !validIndexes.isEmpty else {
            return
        }
        tableView.reloadData(forRowIndexes: validIndexes, columnIndexes: IndexSet(integer: 0))
    }

    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        self.tableView = tableView
    }
}

private final class NativeAddPaperToSessionTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {}

    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}

private final class NativeAddPaperToSessionRowCellView: NSTableCellView {
    private let cardView = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var trackingAreaToken: NSTrackingArea?
    private var isHovering = false
    private var isPressing = false

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    required init?(coder: NSCoder) {
        nil
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
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func configure(title: String, detail: String, isPressing: Bool) {
        self.isPressing = isPressing
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        toolTip = "\(title)\n\(detail)"
        setAccessibilityLabel(title)
        setAccessibilityValue(detail)
        updateAppearance()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityRole(.button)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 7
        cardView.layer?.masksToBounds = false
        addSubview(cardView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        iconView.contentTintColor = .controlAccentColor
        iconView.imageScaling = .scaleProportionallyDown
        cardView.addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        cardView.addSubview(titleLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        cardView.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3)
        ])

        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateAppearance()
    }

    private func updateAppearance() {
        cardView.layer?.cornerRadius = 7
        cardView.layer?.masksToBounds = false
        let accent = NSColor.controlAccentColor
        if isPressing {
            cardView.layer?.backgroundColor = accent.withAlphaComponent(0.16).cgColor
            cardView.layer?.borderColor = accent.withAlphaComponent(0.42).cgColor
            cardView.layer?.borderWidth = 1
        } else if isHovering {
            cardView.layer?.backgroundColor = accent.withAlphaComponent(0.10).cgColor
            cardView.layer?.borderColor = accent.withAlphaComponent(0.26).cgColor
            cardView.layer?.borderWidth = 1
        } else {
            cardView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            cardView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
            cardView.layer?.borderWidth = 1
        }
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.layer?.shadowOpacity = isHovering && !isPressing ? 0.08 : 0
        cardView.layer?.shadowRadius = isHovering ? 5 : 0
        cardView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        alphaValue = isPressing ? 0.78 : 1
    }
}
