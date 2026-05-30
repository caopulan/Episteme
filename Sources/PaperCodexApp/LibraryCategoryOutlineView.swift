import AppKit
import PaperCodexCore
import SwiftUI

struct LibraryCategoryOutlineDropTarget: Equatable {
    var targetCategoryID: String?
    var placement: LibraryCategoryDropPlacement
}

struct LibraryCategoryOutlineView: NSViewRepresentable {
    var categories: [PaperCodexCore.Category]
    var selectedCategoryID: String?
    @Binding var collapsedCategoryIDs: Set<String>
    var paperCountsByCategoryID: [String: Int]
    var categoryDragPayloadPrefix: String
    var onSelect: (String) -> Void
    var onCreateChild: (PaperCodexCore.Category) -> Void
    var onManage: (PaperCodexCore.Category) -> Void
    var onTogglePinned: (PaperCodexCore.Category) -> Void
    var onBeginCategoryDrag: (String) -> Void
    var onEndCategoryDrag: () -> Void
    var canDropCategory: (String, LibraryCategoryOutlineDropTarget) -> Bool
    var onDropCategory: (String, LibraryCategoryOutlineDropTarget) -> Void
    var onDropPapers: ([String], PaperCodexCore.Category) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(collapsedCategoryIDs: $collapsedCategoryIDs)
    }

    func makeNSView(context: Context) -> NSOutlineView {
        let outlineView = NSOutlineView()
        let column = NSTableColumn(identifier: Coordinator.columnIdentifier)
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.backgroundColor = .clear
        outlineView.rowSizeStyle = .custom
        outlineView.rowHeight = 32
        outlineView.intercellSpacing = .zero
        outlineView.indentationPerLevel = 18
        outlineView.selectionHighlightStyle = .regular
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = false
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.registerForDraggedTypes([.string])
        context.coordinator.outlineView = outlineView
        context.coordinator.update(from: self)
        context.coordinator.reloadOutline()
        return outlineView
    }

    func updateNSView(_ outlineView: NSOutlineView, context: Context) {
        context.coordinator.outlineView = outlineView
        context.coordinator.update(from: self)
        context.coordinator.reloadOutline()
    }

    @MainActor final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        static let columnIdentifier = NSUserInterfaceItemIdentifier("category")

        weak var outlineView: NSOutlineView?
        private var roots: [CategoryOutlineNode] = []
        private var nodesByID: [String: CategoryOutlineNode] = [:]
        private var selectedCategoryID: String?
        private var paperCountsByCategoryID: [String: Int] = [:]
        private var categoryDragPayloadPrefix = ""
        private var onSelect: (String) -> Void = { _ in }
        private var onCreateChild: (PaperCodexCore.Category) -> Void = { _ in }
        private var onManage: (PaperCodexCore.Category) -> Void = { _ in }
        private var onTogglePinned: (PaperCodexCore.Category) -> Void = { _ in }
        private var onBeginCategoryDrag: (String) -> Void = { _ in }
        private var onEndCategoryDrag: () -> Void = {}
        private var canDropCategory: (String, LibraryCategoryOutlineDropTarget) -> Bool = { _, _ in false }
        private var onDropCategory: (String, LibraryCategoryOutlineDropTarget) -> Void = { _, _ in }
        private var onDropPapers: ([String], PaperCodexCore.Category) -> Void = { _, _ in }
        private var collapsedCategoryIDs: Binding<Set<String>>
        private var isApplyingExpansion = false
        private var isApplyingSelection = false

        init(collapsedCategoryIDs: Binding<Set<String>>) {
            self.collapsedCategoryIDs = collapsedCategoryIDs
        }

        func update(from view: LibraryCategoryOutlineView) {
            selectedCategoryID = view.selectedCategoryID
            paperCountsByCategoryID = view.paperCountsByCategoryID
            categoryDragPayloadPrefix = view.categoryDragPayloadPrefix
            onSelect = view.onSelect
            onCreateChild = view.onCreateChild
            onManage = view.onManage
            onTogglePinned = view.onTogglePinned
            onBeginCategoryDrag = view.onBeginCategoryDrag
            onEndCategoryDrag = view.onEndCategoryDrag
            canDropCategory = view.canDropCategory
            onDropCategory = view.onDropCategory
            onDropPapers = view.onDropPapers
            roots = Self.makeNodes(from: view.categories)
            nodesByID = Dictionary(uniqueKeysWithValues: allNodes(in: roots).map { ($0.category.id, $0) })
        }

        func reloadOutline() {
            guard let outlineView else {
                return
            }
            outlineView.reloadData()
            applyExpansionState(in: outlineView)
            applySelection(in: outlineView)
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            node(for: item)?.children.count ?? roots.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            (node(for: item)?.children ?? roots)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            node(for: item)?.children.isEmpty == false
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            32
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = node(for: item) else {
                return nil
            }
            let identifier = NSUserInterfaceItemIdentifier("CategoryOutlineCell")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? CategoryOutlineCellView)
                ?? CategoryOutlineCellView(identifier: identifier)
            let row = outlineView.row(forItem: node)
            let isSelected = row >= 0 && outlineView.selectedRowIndexes.contains(row)
            let isExpandable = outlineView.isExpandable(node)
            cell.configure(
                category: node.category,
                count: paperCountsByCategoryID[node.category.id, default: 0],
                isSelected: isSelected,
                isExpandable: isExpandable,
                isExpanded: isExpandable && outlineView.isItemExpanded(node),
                onSelect: { [weak self] in
                    self?.onSelect(node.category.id)
                },
                onToggleExpansion: { [weak self, weak outlineView] in
                    guard let outlineView else {
                        return
                    }
                    if outlineView.isExpandable(node) {
                        if outlineView.isItemExpanded(node) {
                            outlineView.collapseItem(node)
                        } else {
                            outlineView.expandItem(node)
                        }
                    } else {
                        self?.onSelect(node.category.id)
                    }
                },
                onCreateChild: { [weak self] in
                    self?.onCreateChild(node.category)
                },
                onManage: { [weak self] in
                    self?.onManage(node.category)
                },
                onTogglePinned: { [weak self] in
                    self?.onTogglePinned(node.category)
                }
            )
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection,
                  let outlineView,
                  outlineView.selectedRow >= 0,
                  let node = outlineView.item(atRow: outlineView.selectedRow) as? CategoryOutlineNode else {
                return
            }
            onSelect(node.category.id)
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !isApplyingExpansion, let node = notificationNode(notification) else {
                return
            }
            collapsedCategoryIDs.wrappedValue.remove(node.category.id)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !isApplyingExpansion, let node = notificationNode(notification) else {
                return
            }
            collapsedCategoryIDs.wrappedValue.insert(node.category.id)
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let node = node(for: item) else {
                return nil
            }
            onBeginCategoryDrag(node.category.id)
            return "\(categoryDragPayloadPrefix)\(node.category.id)" as NSString
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forItems draggedItems: [Any]
        ) {
            guard let node = draggedItems.compactMap({ self.node(for: $0) }).first else {
                return
            }
            onBeginCategoryDrag(node.category.id)
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            onEndCategoryDrag()
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex childIndex: Int
        ) -> NSDragOperation {
            guard let payload = dragPayload(from: info) else {
                return []
            }
            switch payload {
            case let .category(categoryID):
                guard let target = dropTarget(proposedItem: item, proposedChildIndex: childIndex),
                      canDropCategory(categoryID, target) else {
                    return []
                }
                return .move
            case .papers:
                guard childIndex == NSOutlineViewDropOnItemIndex, node(for: item) != nil else {
                    return []
                }
                return .copy
            }
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: NSDraggingInfo,
            item: Any?,
            childIndex: Int
        ) -> Bool {
            guard let payload = dragPayload(from: info) else {
                return false
            }
            switch payload {
            case let .category(categoryID):
                guard let target = dropTarget(proposedItem: item, proposedChildIndex: childIndex),
                      canDropCategory(categoryID, target) else {
                    return false
                }
                onDropCategory(categoryID, target)
                return true
            case let .papers(paperIDs):
                guard childIndex == NSOutlineViewDropOnItemIndex,
                      let targetNode = node(for: item) else {
                    return false
                }
                onDropPapers(paperIDs, targetNode.category)
                return true
            }
        }

        private func applyExpansionState(in outlineView: NSOutlineView) {
            isApplyingExpansion = true
            for node in allNodes(in: roots) {
                if collapsedCategoryIDs.wrappedValue.contains(node.category.id) {
                    outlineView.collapseItem(node)
                } else if !node.children.isEmpty {
                    outlineView.expandItem(node)
                }
            }
            isApplyingExpansion = false
        }

        private func applySelection(in outlineView: NSOutlineView) {
            guard let selectedCategoryID,
                  let node = nodesByID[selectedCategoryID],
                  outlineView.row(forItem: node) >= 0 else {
                isApplyingSelection = true
                outlineView.deselectAll(nil)
                isApplyingSelection = false
                return
            }
            let row = outlineView.row(forItem: node)
            guard outlineView.selectedRow != row else {
                return
            }
            isApplyingSelection = true
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            isApplyingSelection = false
        }

        private func notificationNode(_ notification: Notification) -> CategoryOutlineNode? {
            notification.userInfo?["NSObject"] as? CategoryOutlineNode
        }

        private func node(for item: Any?) -> CategoryOutlineNode? {
            item as? CategoryOutlineNode
        }

        private func allNodes(in nodes: [CategoryOutlineNode]) -> [CategoryOutlineNode] {
            nodes.flatMap { [$0] + allNodes(in: $0.children) }
        }

        private func dragPayload(from info: NSDraggingInfo) -> DragPayload? {
            guard let text = info.draggingPasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty else {
                return nil
            }
            if text.hasPrefix(categoryDragPayloadPrefix) {
                let categoryID = String(text.dropFirst(categoryDragPayloadPrefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return categoryID.isEmpty ? nil : .category(categoryID)
            }
            let paperIDs = text
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return paperIDs.isEmpty ? nil : .papers(paperIDs)
        }

        private func dropTarget(proposedItem item: Any?, proposedChildIndex childIndex: Int) -> LibraryCategoryOutlineDropTarget? {
            if childIndex == NSOutlineViewDropOnItemIndex {
                guard let targetNode = node(for: item) else {
                    return nil
                }
                return LibraryCategoryOutlineDropTarget(targetCategoryID: targetNode.category.id, placement: .inside)
            }

            let parentNode = node(for: item)
            let siblings = parentNode?.children ?? roots
            if siblings.isEmpty {
                return LibraryCategoryOutlineDropTarget(targetCategoryID: parentNode?.category.id, placement: .inside)
            }
            if childIndex >= 0, childIndex < siblings.count {
                return LibraryCategoryOutlineDropTarget(targetCategoryID: siblings[childIndex].category.id, placement: .before)
            }
            guard let lastSibling = siblings.last else {
                return nil
            }
            return LibraryCategoryOutlineDropTarget(targetCategoryID: lastSibling.category.id, placement: .after)
        }

        private static func makeNodes(from categories: [PaperCodexCore.Category]) -> [CategoryOutlineNode] {
            var nodesByID: [String: CategoryOutlineNode] = [:]
            for category in categories {
                nodesByID[category.id] = CategoryOutlineNode(category: category)
            }

            var roots: [CategoryOutlineNode] = []
            for category in categories {
                guard let node = nodesByID[category.id] else {
                    continue
                }
                if let parentID = category.parentID, let parent = nodesByID[parentID] {
                    parent.children.append(node)
                } else {
                    roots.append(node)
                }
            }

            func sort(_ nodes: inout [CategoryOutlineNode]) {
                nodes.sort { left, right in
                    if left.category.isPinned != right.category.isPinned {
                        return left.category.isPinned
                    }
                    if left.category.sortOrder == right.category.sortOrder {
                        return left.category.name.localizedCaseInsensitiveCompare(right.category.name) == .orderedAscending
                    }
                    return left.category.sortOrder < right.category.sortOrder
                }
                for node in nodes {
                    sort(&node.children)
                }
            }

            sort(&roots)
            return roots
        }
    }
}

private enum DragPayload {
    case category(String)
    case papers([String])
}

private final class CategoryOutlineNode: NSObject {
    let category: PaperCodexCore.Category
    var children: [CategoryOutlineNode] = []

    init(category: PaperCodexCore.Category) {
        self.category = category
    }
}

private final class CategoryOutlineCellView: NSTableCellView {
    private let stackView = NSStackView()
    private let iconButton = NSButton()
    private let titleField = NSTextField(labelWithString: "")
    private let countField = NSTextField(labelWithString: "")
    private let createButton = NSButton()
    private let pinButton = NSButton()
    private let manageButton = NSButton()

    private var onSelect: (() -> Void)?
    private var onToggleExpansion: (() -> Void)?
    private var onCreateChild: (() -> Void)?
    private var onManage: (() -> Void)?
    private var onTogglePinned: (() -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1 {
            onSelect?()
        }
        super.mouseDown(with: event)
    }

    func configure(
        category: PaperCodexCore.Category,
        count: Int,
        isSelected: Bool,
        isExpandable: Bool,
        isExpanded: Bool,
        onSelect: @escaping () -> Void,
        onToggleExpansion: @escaping () -> Void,
        onCreateChild: @escaping () -> Void,
        onManage: @escaping () -> Void,
        onTogglePinned: @escaping () -> Void
    ) {
        self.onSelect = onSelect
        self.onToggleExpansion = onToggleExpansion
        self.onCreateChild = onCreateChild
        self.onManage = onManage
        self.onTogglePinned = onTogglePinned

        titleField.stringValue = category.name
        titleField.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium)
        countField.stringValue = "\(count)"
        pinButton.image = NSImage(systemSymbolName: category.isPinned ? "pin.fill" : "pin", accessibilityDescription: nil)
        pinButton.toolTip = category.isPinned ? "Unpin \(category.name)" : "Pin \(category.name)"
        iconButton.image = NSImage(systemSymbolName: folderIconName(isSelected: isSelected, isExpandable: isExpandable, isExpanded: isExpanded), accessibilityDescription: nil)
        iconButton.toolTip = folderIconHelp(title: category.name, isExpandable: isExpandable, isExpanded: isExpanded)
        createButton.toolTip = "New subcategory under \(category.name)"
        manageButton.toolTip = "Manage \(category.name)"
    }

    private func setup() {
        wantsLayer = true

        iconButton.isBordered = false
        iconButton.imagePosition = .imageOnly
        iconButton.setButtonType(.momentaryChange)
        iconButton.target = self
        iconButton.action = #selector(toggleExpansion)
        iconButton.translatesAutoresizingMaskIntoConstraints = false

        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        countField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countField.textColor = .secondaryLabelColor
        countField.alignment = .right

        configureActionButton(createButton, symbolName: "plus", action: #selector(createChild))
        configureActionButton(pinButton, symbolName: "pin", action: #selector(togglePinned))
        configureActionButton(manageButton, symbolName: "ellipsis", action: #selector(manage))

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 6
        stackView.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 6)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(iconButton)
        stackView.addArrangedSubview(titleField)
        stackView.addArrangedSubview(countField)
        stackView.addArrangedSubview(createButton)
        stackView.addArrangedSubview(pinButton)
        stackView.addArrangedSubview(manageButton)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            iconButton.widthAnchor.constraint(equalToConstant: 20),
            iconButton.heightAnchor.constraint(equalToConstant: 22),
            createButton.widthAnchor.constraint(equalToConstant: 22),
            createButton.heightAnchor.constraint(equalToConstant: 22),
            pinButton.widthAnchor.constraint(equalToConstant: 22),
            pinButton.heightAnchor.constraint(equalToConstant: 22),
            manageButton.widthAnchor.constraint(equalToConstant: 22),
            manageButton.heightAnchor.constraint(equalToConstant: 22),
            countField.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func configureActionButton(_ button: NSButton, symbolName: String, action: Selector) {
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.target = self
        button.action = action
    }

    private func folderIconName(isSelected: Bool, isExpandable: Bool, isExpanded: Bool) -> String {
        isExpandable ? (isExpanded || isSelected ? "folder.fill" : "folder") : (isSelected ? "folder.fill" : "folder")
    }

    private func folderIconHelp(title: String, isExpandable: Bool, isExpanded: Bool) -> String {
        guard isExpandable else {
            return title
        }
        return isExpanded ? "Collapse \(title)" : "Expand \(title)"
    }

    @objc private func toggleExpansion() {
        onToggleExpansion?()
    }

    @objc private func createChild() {
        onCreateChild?()
    }

    @objc private func manage() {
        onManage?()
    }

    @objc private func togglePinned() {
        onTogglePinned?()
    }
}
