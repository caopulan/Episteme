import AppKit
import ImageIO
import PaperCodexCore
import SwiftUI

struct LibraryPaperTableRow: Identifiable, Equatable {
    var paper: Paper
    var categories: [PaperCodexCore.Category]
    var tags: [PaperTag]
    var thumbnailURLs: [URL]
    var isImportPlaceholder: Bool
    var placeholderDetail: String
    var isSelected: Bool
    var isMultiSelected: Bool

    var id: String { paper.id }
}

struct LibraryPaperTableView: NSViewRepresentable {
    var rows: [LibraryPaperTableRow]
    var selectedPaperID: String?
    var revealRequestID: UUID?
    var focusRequestID: UUID?
    var rowHeight: CGFloat = 128
    var onMoveSelection: (Int) -> Void
    var onSelect: (LibraryPaperTableRow) -> Void
    var onToggleStar: (LibraryPaperTableRow) -> Void
    var onRead: (LibraryPaperTableRow) -> Void
    var onBeginDrag: (LibraryPaperTableRow) -> Void
    var dragPayload: (LibraryPaperTableRow) -> String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = LibraryPaperTableScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let tableView = LibraryPaperNSTableView()
        let column = NSTableColumn(identifier: Coordinator.columnIdentifier)
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
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.style = .plain
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.onMoveSelection = onMoveSelection
        tableView.onActivateRow = { [weak coordinator = context.coordinator] rowIndex in
            coordinator?.activateRow(at: rowIndex)
        }
        tableView.onPressRow = { [weak coordinator = context.coordinator] rowIndex, isPressing in
            coordinator?.setPressedRow(rowIndex, isPressing: isPressing)
        }
        tableView.setDraggingSourceOperationMask(.copy, forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.update(from: self)
        tableView.reloadData()
        context.coordinator.fitColumnToVisibleWidth()
        context.coordinator.applyFocusAndReveal(from: self)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? LibraryPaperNSTableView else {
            return
        }
        context.coordinator.tableView = tableView
        context.coordinator.update(from: self)
        tableView.onMoveSelection = onMoveSelection
        tableView.onActivateRow = { [weak coordinator = context.coordinator] rowIndex in
            coordinator?.activateRow(at: rowIndex)
        }
        tableView.onPressRow = { [weak coordinator = context.coordinator] rowIndex, isPressing in
            coordinator?.setPressedRow(rowIndex, isPressing: isPressing)
        }
        tableView.rowHeight = rowHeight
        tableView.reloadData()
        context.coordinator.fitColumnToVisibleWidth()
        context.coordinator.applyFocusAndReveal(from: self)
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static var columnIdentifier: NSUserInterfaceItemIdentifier {
            NSUserInterfaceItemIdentifier("paper")
        }

        private static var cellIdentifier: NSUserInterfaceItemIdentifier {
            NSUserInterfaceItemIdentifier("LibraryPaperHostingCell")
        }

        weak var tableView: LibraryPaperNSTableView?
        private var rows: [LibraryPaperTableRow] = []
        private var rowHeight: CGFloat = 128
        private var selectedPaperID: String?
        private var lastRevealRequestID: UUID?
        private var lastFocusRequestID: UUID?
        private var pressedRow: Int?
        private var onSelect: (LibraryPaperTableRow) -> Void = { _ in }
        private var onToggleStar: (LibraryPaperTableRow) -> Void = { _ in }
        private var onRead: (LibraryPaperTableRow) -> Void = { _ in }
        private var onBeginDrag: (LibraryPaperTableRow) -> Void = { _ in }
        private var dragPayload: (LibraryPaperTableRow) -> String = { _ in "" }

        func update(from view: LibraryPaperTableView) {
            rows = view.rows
            rowHeight = view.rowHeight
            selectedPaperID = view.selectedPaperID
            onSelect = view.onSelect
            onToggleStar = view.onToggleStar
            onRead = view.onRead
            onBeginDrag = view.onBeginDrag
            dragPayload = view.dragPayload
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            rowHeight
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            false
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = LibraryPaperTableRowView()
            rowView.isEmphasized = false
            return rowView
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row) else {
                return nil
            }
            let cell = (tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? LibraryPaperNativeCellView)
                ?? LibraryPaperNativeCellView(identifier: Self.cellIdentifier)
            let tableRow = rows[row]
            cell.configure(
                row: tableRow,
                isPressing: pressedRow == row,
                onToggleStar: onToggleStar,
                onRead: onRead
            )
            return cell
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard rows.indices.contains(row) else {
                return nil
            }
            let tableRow = rows[row]
            onBeginDrag(tableRow)
            let payload = dragPayload(tableRow).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty else {
                return nil
            }
            return payload as NSString
        }

        func activateRow(at row: Int) {
            guard rows.indices.contains(row) else {
                return
            }
            onSelect(rows[row])
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
            guard let tableView else {
                return
            }
            let validIndexes = IndexSet(rowIndexes.filter { $0 >= 0 && $0 < tableView.numberOfRows })
            guard !validIndexes.isEmpty else {
                return
            }
            tableView.reloadData(forRowIndexes: validIndexes, columnIndexes: IndexSet(integer: 0))
        }

        func applyFocusAndReveal(from view: LibraryPaperTableView) {
            guard let tableView else {
                return
            }
            if let focusRequestID = view.focusRequestID, focusRequestID != lastFocusRequestID {
                lastFocusRequestID = focusRequestID
                tableView.window?.makeFirstResponder(tableView)
            }
            guard let revealRequestID = view.revealRequestID,
                  revealRequestID != lastRevealRequestID else {
                return
            }
            lastRevealRequestID = revealRequestID
            guard let selectedPaperID,
                  let row = rows.firstIndex(where: { $0.id == selectedPaperID }) else {
                return
            }
            scrollRowToVisibleCentered(row, in: tableView)
        }

        func fitColumnToVisibleWidth() {
            guard let tableView,
                  let column = tableView.tableColumns.first else {
                return
            }
            let visibleWidth = tableView.enclosingScrollView?.contentView.bounds.width ?? tableView.bounds.width
            guard visibleWidth > 0,
                  abs(column.width - visibleWidth) > 0.5 else {
                return
            }
            column.width = visibleWidth
        }

        private func scrollRowToVisibleCentered(_ row: Int, in tableView: NSTableView) {
            guard row >= 0, row < tableView.numberOfRows else {
                return
            }
            guard let scrollView = tableView.enclosingScrollView else {
                tableView.scrollRowToVisible(row)
                return
            }
            let rowRect = tableView.rect(ofRow: row)
            let visibleHeight = scrollView.contentView.bounds.height
            guard visibleHeight > 0 else {
                tableView.scrollRowToVisible(row)
                return
            }
            let contentHeight = tableView.rect(ofRow: tableView.numberOfRows - 1).maxY
            let maximumY = max(0, contentHeight - visibleHeight)
            let centeredY = rowRect.midY - visibleHeight / 2
            let targetY = min(max(centeredY, 0), maximumY)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

private final class LibraryPaperTableScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let tableView = documentView as? NSTableView,
              let column = tableView.tableColumns.first else {
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

final class LibraryPaperNSTableView: NSTableView {
    var onMoveSelection: (Int) -> Void = { _ in }
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
            onActivateRow(rowIndex)
        }
        super.mouseDown(with: event)
        if rowIndex >= 0 {
            onPressRow(rowIndex, false)
        }
    }

    override func keyDown(with event: NSEvent) {
        let disallowedModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard disallowedModifiers.isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 126:
            onMoveSelection(-1)
        case 125:
            onMoveSelection(1)
        default:
            super.keyDown(with: event)
        }
    }
}

private final class LibraryPaperTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {}

    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}

private enum LibraryPaperNativeRowMetrics {
    static let thumbnailLimit = 3
    static let thumbnailMaxPixelSize = 128
    static let thumbnailSize = NSSize(width: 42, height: 54)
    static let thumbnailOverlap: CGFloat = 18
    static let cornerRadius: CGFloat = 8
}

private final class LibraryPaperNativeCellView: NSTableCellView {
    private let cardView = NSView()
    private let leadingIndicator = NSView()
    private let thumbnailStrip = LibraryPaperThumbnailStripView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let chipRow = LibraryPaperChipRowView()
    private let starButton = NSButton()
    private let readButton = NSButton()

    private var trackingArea: NSTrackingArea?
    private var row: LibraryPaperTableRow?
    private var onToggleStar: (LibraryPaperTableRow) -> Void = { _ in }
    private var onRead: (LibraryPaperTableRow) -> Void = { _ in }
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

    func configure(
        row: LibraryPaperTableRow,
        isPressing: Bool,
        onToggleStar: @escaping (LibraryPaperTableRow) -> Void,
        onRead: @escaping (LibraryPaperTableRow) -> Void
    ) {
        self.row = row
        self.isPressing = isPressing
        self.onToggleStar = onToggleStar
        self.onRead = onRead

        titleLabel.stringValue = row.paper.title
        detailLabel.stringValue = row.isImportPlaceholder
            ? row.placeholderDetail
            : (row.paper.authors.isEmpty ? "Authors not set" : row.paper.authors.joined(separator: ", "))
        thumbnailStrip.configure(
            urls: Array(row.thumbnailURLs.prefix(LibraryPaperNativeRowMetrics.thumbnailLimit)),
            isDimmed: row.isImportPlaceholder
        )
        configureChips(for: row)
        configureSymbolButton(
            starButton,
            systemSymbolName: row.paper.isStarred ? "star.fill" : "star",
            accessibilityTitle: row.paper.isStarred ? "Remove Star" : "Star Paper",
            tint: row.paper.isStarred ? .systemYellow : .secondaryLabelColor,
            isEnabled: !row.isImportPlaceholder
        )
        configureSymbolButton(
            readButton,
            systemSymbolName: "book",
            accessibilityTitle: "Read",
            tint: .secondaryLabelColor,
            isEnabled: !row.isImportPlaceholder
        )
        starButton.isEnabled = !row.isImportPlaceholder
        readButton.isEnabled = !row.isImportPlaceholder
        alphaValue = row.isImportPlaceholder ? 0.66 : 1
        updateStyle()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = LibraryPaperNativeRowMetrics.cornerRadius
        cardView.layer?.masksToBounds = false
        addSubview(cardView)

        leadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        leadingIndicator.wantsLayer = true
        leadingIndicator.layer?.cornerRadius = 2
        cardView.addSubview(leadingIndicator)

        thumbnailStrip.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(thumbnailStrip)

        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 1
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        chipRow.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, detailLabel, chipRow])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 7
        textStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(textStack)

        starButton.target = self
        starButton.action = #selector(toggleStar)
        starButton.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(starButton)

        readButton.target = self
        readButton.action = #selector(readPaper)
        readButton.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(readButton)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            cardView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            leadingIndicator.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 4),
            leadingIndicator.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            leadingIndicator.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
            leadingIndicator.widthAnchor.constraint(equalToConstant: 4),

            thumbnailStrip.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            thumbnailStrip.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            thumbnailStrip.widthAnchor.constraint(equalToConstant: 132),
            thumbnailStrip.heightAnchor.constraint(equalToConstant: 54),

            textStack.leadingAnchor.constraint(equalTo: thumbnailStrip.trailingAnchor, constant: 14),
            textStack.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: starButton.leadingAnchor, constant: -14),

            starButton.trailingAnchor.constraint(equalTo: readButton.leadingAnchor, constant: -8),
            starButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            starButton.widthAnchor.constraint(equalToConstant: 30),
            starButton.heightAnchor.constraint(equalToConstant: 30),

            readButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            readButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            readButton.widthAnchor.constraint(equalToConstant: 30),
            readButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let nextTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(nextTrackingArea)
        trackingArea = nextTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateStyle()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStyle()
    }

    private func configureChips(for row: LibraryPaperTableRow) {
        var chips: [(title: String, symbolName: String)] = []
        if let arxivID = arxivDisplayID(for: row.paper) {
            chips.append((arxivID, "number"))
        }
        for category in row.categories.prefix(2) {
            chips.append((category.name, "folder"))
        }
        for tag in row.tags.prefix(3) {
            chips.append((tag.name, "tag"))
        }
        chipRow.configure(chips: chips)
    }

    private func configureSymbolButton(
        _ button: NSButton,
        systemSymbolName: String,
        accessibilityTitle: String,
        tint: NSColor,
        isEnabled: Bool
    ) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: accessibilityTitle)
        button.contentTintColor = tint
        button.toolTip = accessibilityTitle
        button.setAccessibilityLabel(accessibilityTitle)
        button.isEnabled = isEnabled
    }

    private func updateStyle() {
        guard let row else {
            return
        }
        let backgroundColor: NSColor
        let borderColor: NSColor
        let shadowColor: NSColor

        if row.isMultiSelected {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16)
            borderColor = NSColor.controlAccentColor.withAlphaComponent(0.62)
            shadowColor = NSColor.clear
        } else if isPressing && !row.isImportPlaceholder {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
            borderColor = NSColor.controlAccentColor.withAlphaComponent(0.48)
            shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
        } else if row.isSelected {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10)
            borderColor = NSColor.controlAccentColor.withAlphaComponent(0.38)
            shadowColor = NSColor.clear
        } else if isHovering {
            backgroundColor = .textBackgroundColor
            borderColor = NSColor.labelColor.withAlphaComponent(0.10)
            shadowColor = NSColor.black.withAlphaComponent(0.10)
        } else {
            backgroundColor = .controlBackgroundColor
            borderColor = .clear
            shadowColor = .clear
        }

        cardView.layer?.backgroundColor = backgroundColor.cgColor
        cardView.layer?.borderColor = borderColor.cgColor
        cardView.layer?.borderWidth = row.isMultiSelected ? 1.5 : (borderColor == .clear ? 0 : 1)
        cardView.layer?.shadowColor = shadowColor.cgColor
        cardView.layer?.shadowOpacity = shadowColor == .clear ? 0 : 1
        cardView.layer?.shadowRadius = isPressing ? 4 : 6
        cardView.layer?.shadowOffset = CGSize(width: 0, height: isPressing ? -1 : -2)

        titleLabel.textColor = row.isImportPlaceholder ? .secondaryLabelColor : .labelColor
        leadingIndicator.isHidden = !(row.isSelected || row.isMultiSelected || isPressing)
        leadingIndicator.layer?.backgroundColor = NSColor.controlAccentColor
            .withAlphaComponent(row.isMultiSelected ? 0.82 : (isPressing ? 0.70 : 0.62))
            .cgColor
    }

    @objc private func toggleStar() {
        guard let row else {
            return
        }
        onToggleStar(row)
    }

    @objc private func readPaper() {
        guard let row else {
            return
        }
        onRead(row)
    }

    private func arxivDisplayID(for paper: Paper) -> String? {
        paper.arxivImportPlaceholderCanonicalID
            ?? paper.sourceURL.flatMap(ArxivIDExtractor.firstCanonicalID(in:))
    }
}

private final class LibraryPaperThumbnailStripView: NSView {
    private let imageViews: [NSImageView] = (0..<LibraryPaperNativeRowMetrics.thumbnailLimit).map { _ in
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 5
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
        imageView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        imageView.layer?.masksToBounds = true
        return imageView
    }

    private var representedURLs: [URL] = []
    private var decodeTasks: [Task<Void, Never>?] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for imageView in imageViews {
            addSubview(imageView)
        }
        decodeTasks = Array(repeating: nil, count: imageViews.count)
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        decodeTasks.forEach { $0?.cancel() }
    }

    func configure(urls: [URL], isDimmed: Bool) {
        let visibleURLs = Array(urls.prefix(LibraryPaperNativeRowMetrics.thumbnailLimit))
        if representedURLs != visibleURLs {
            decodeTasks.forEach { $0?.cancel() }
            decodeTasks = Array(repeating: nil, count: imageViews.count)
            representedURLs = visibleURLs
        }

        if urls.isEmpty {
            for (index, imageView) in imageViews.enumerated() {
                imageView.isHidden = index != 0
                imageView.image = index == 0
                    ? NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "Paper")
                    : nil
                imageView.contentTintColor = .systemBlue
            }
        } else {
            for (index, imageView) in imageViews.enumerated() {
                if visibleURLs.indices.contains(index) {
                    imageView.isHidden = false
                    imageView.image = LibraryPaperThumbnailImageCache.shared.image(for: visibleURLs[index])
                        ?? NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "Paper")
                    imageView.contentTintColor = nil
                    loadImageIfNeeded(at: index, url: visibleURLs[index])
                } else {
                    imageView.isHidden = true
                    imageView.image = nil
                }
            }
        }
        alphaValue = isDimmed ? 0.45 : 1
        needsLayout = true
    }

    private func loadImageIfNeeded(at index: Int, url: URL) {
        guard LibraryPaperThumbnailImageCache.shared.image(for: url) == nil else {
            return
        }
        decodeTasks[index]?.cancel()
        decodeTasks[index] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: LibraryPaperThumbnailDecodePolicy.appearanceDelayNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            if let cached = LibraryPaperThumbnailImageCache.shared.image(for: url) {
                self?.setImage(cached, at: index, for: url)
                return
            }
            guard let decoded = await decodeLibraryPaperThumbnailImage(
                at: url,
                maxPixelSize: LibraryPaperNativeRowMetrics.thumbnailMaxPixelSize
            ) else {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            let image = NSImage(cgImage: decoded.image, size: LibraryPaperNativeRowMetrics.thumbnailSize)
            LibraryPaperThumbnailImageCache.shared.insert(image, for: url)
            self?.setImage(image, at: index, for: url)
        }
    }

    private func setImage(_ image: NSImage, at index: Int, for url: URL) {
        guard representedURLs.indices.contains(index),
              representedURLs[index] == url,
              imageViews.indices.contains(index) else {
            return
        }
        imageViews[index].image = image
    }

    override func layout() {
        super.layout()
        let size = LibraryPaperNativeRowMetrics.thumbnailSize
        let step = size.width - LibraryPaperNativeRowMetrics.thumbnailOverlap
        for (index, imageView) in imageViews.enumerated() {
            imageView.frame = NSRect(
                x: CGFloat(index) * step,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        }
    }
}

@MainActor
private final class LibraryPaperThumbnailImageCache {
    static let shared = LibraryPaperThumbnailImageCache()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 700
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func image(for url: URL) -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }
        return nil
    }

    func insert(_ image: NSImage, for url: URL) {
        let key = url as NSURL
        cache.setObject(image, forKey: key)
    }
}

private enum LibraryPaperThumbnailDecodePolicy {
    static let appearanceDelayNanoseconds: UInt64 = 90_000_000
    static let decodePriority = TaskPriority.utility
}

private struct DecodedLibraryPaperThumbnailImage: @unchecked Sendable {
    var image: CGImage
}

private actor LibraryPaperThumbnailDecodeGate {
    static let shared = LibraryPaperThumbnailDecodeGate(maxConcurrent: 2)

    private let maxConcurrent: Int
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    func wait() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            activeCount = max(0, activeCount - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private func decodeLibraryPaperThumbnailImage(
    at url: URL,
    maxPixelSize: Int
) async -> DecodedLibraryPaperThumbnailImage? {
    await LibraryPaperThumbnailDecodeGate.shared.wait()
    if Task.isCancelled {
        await LibraryPaperThumbnailDecodeGate.shared.signal()
        return nil
    }

    let result = await Task.detached(priority: LibraryPaperThumbnailDecodePolicy.decodePriority) { () -> DecodedLibraryPaperThumbnailImage? in
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return DecodedLibraryPaperThumbnailImage(image: image)
    }.value
    await LibraryPaperThumbnailDecodeGate.shared.signal()
    return result
}

private final class LibraryPaperChipRowView: NSView {
    private var chipViews: [LibraryPaperChipView] = []
    private let spacing: CGFloat = 6

    func configure(chips: [(title: String, symbolName: String)]) {
        chipViews.forEach { $0.removeFromSuperview() }
        chipViews = chips.map { chip in
            LibraryPaperChipView(title: chip.title, symbolName: chip.symbolName)
        }
        for chipView in chipViews {
            addSubview(chipView)
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        let sizes = chipViews.map(\.intrinsicContentSize)
        let width = sizes.reduce(CGFloat(0)) { $0 + $1.width }
            + spacing * CGFloat(max(0, sizes.count - 1))
        let height = sizes.map(\.height).max() ?? 0
        return NSSize(width: width, height: height)
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        let rowHeight = bounds.height
        for chipView in chipViews {
            let size = chipView.intrinsicContentSize
            chipView.frame = NSRect(
                x: x,
                y: max(0, (rowHeight - size.height) / 2),
                width: size.width,
                height: size.height
            )
            x += size.width + spacing
        }
    }
}

private final class LibraryPaperChipView: NSView {
    private let chipFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    init(title: String, symbolName: String) {
        super.init(frame: .zero)
        setup()
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        iconView.contentTintColor = .secondaryLabelColor
        titleLabel.stringValue = title
        titleLabel.font = chipFont
        titleLabel.textColor = .secondaryLabelColor
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.82).cgColor
        layer?.cornerRadius = 4

        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 13),
            iconView.heightAnchor.constraint(equalToConstant: 13),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }

    override var intrinsicContentSize: NSSize {
        let titleSize = titleLabel.intrinsicContentSize
        return NSSize(width: 6 + 13 + 4 + titleSize.width + 7, height: max(20, titleSize.height + 6))
    }
}
