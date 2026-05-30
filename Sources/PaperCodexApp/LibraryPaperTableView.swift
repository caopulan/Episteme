import AppKit
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

struct LibraryPaperTableView<RowContent: View>: NSViewRepresentable {
    var rows: [LibraryPaperTableRow]
    var selectedPaperID: String?
    var revealRequestID: UUID?
    var focusRequestID: UUID?
    var rowHeight: CGFloat = 128
    var onMoveSelection: (Int) -> Void
    @ViewBuilder var rowContent: (LibraryPaperTableRow) -> RowContent

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
        private var rowContent: (LibraryPaperTableRow) -> AnyView = { _ in AnyView(EmptyView()) }

        func update(from view: LibraryPaperTableView) {
            rows = view.rows
            rowHeight = view.rowHeight
            selectedPaperID = view.selectedPaperID
            rowContent = { row in AnyView(view.rowContent(row)) }
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
            let cell = (tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? LibraryPaperHostingCellView)
                ?? LibraryPaperHostingCellView(identifier: Self.cellIdentifier)
            let tableRow = rows[row]
            cell.configure(content: rowContent(tableRow))
            return cell
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

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
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

private final class LibraryPaperHostingCellView: NSTableCellView {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(content: AnyView) {
        hostingView.rootView = content
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
