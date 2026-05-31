import Foundation
import AppKit
import PaperCodexCore
import SwiftUI

typealias SaveToLibraryNewCategory = LibraryCategoryRequest

struct SaveToLibraryCategorySelection: Equatable {
    var categoryIDs: [String]
    var newCategoryNames: [String]
    var newCategories: [SaveToLibraryNewCategory]

    static let empty = SaveToLibraryCategorySelection(categoryIDs: [], newCategoryNames: [], newCategories: [])
}

private let saveToLibraryRootDraftParentID = "__papercodex-save-root__"

private enum SaveToLibraryLayout {
    static let destinationChipMaxHeight: CGFloat = 150
    static let treeConnectorHeight: CGFloat = 34
    static let treeIndentWidth: CGFloat = 22
    static let chevronWidth: CGFloat = 16
    static let chevronFolderSpacing: CGFloat = 4
    static let folderButtonLeadingPadding: CGFloat = 10
    static let folderIconWidth: CGFloat = 17
    static let treeConnectorTargetInset: CGFloat = 7
    static let treeConnectorLineWidth: CGFloat = 1
    static let treeConnectorOpacity = 0.16

    static var folderIconCenterX: CGFloat {
        chevronWidth + chevronFolderSpacing + folderButtonLeadingPadding + folderIconWidth / 2
    }

    static func folderIconCenterX(depth: Int) -> CGFloat {
        folderIconCenterX + CGFloat(depth) * treeIndentWidth
    }
}

struct SaveToLibrarySheet: View {
    var paperTitle: String
    var detail: String?
    var libraryCategories: [PaperCodexCore.Category]
    var initialCategoryIDs: [String]
    var onSave: (SaveToLibraryCategorySelection) -> Void
    var onCancel: () -> Void

    @State private var selectedCategoryIDs: Set<String>
    @State private var selectedNewCategoryIDs: Set<String> = []
    @State private var pendingNewCategories: [SaveToLibraryNewCategory] = []
    @State private var collapsedCategoryIDs: Set<String> = []
    @State private var activeNewCategoryParentID: String?
    @State private var newCategoryName = ""

    init(
        paperTitle: String,
        detail: String? = nil,
        libraryCategories: [PaperCodexCore.Category],
        initialCategoryIDs: [String] = [],
        onSave: @escaping (SaveToLibraryCategorySelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.paperTitle = paperTitle
        self.detail = detail
        self.libraryCategories = libraryCategories
        self.initialCategoryIDs = initialCategoryIDs
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedCategoryIDs = State(initialValue: Set(initialCategoryIDs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            destinationHeader
            folderPicker
            Divider()
            actionRow
        }
        .padding(22)
        .frame(width: 560)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.paperCodexSystem(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("Save to Library")
                    .font(.title3.weight(.semibold))
                Text(paperTitle)
                    .font(.paperCodexSystem(size: 13, weight: .medium))
                    .lineLimit(2)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var destinationHeader: some View {
        SaveToLibraryDestinationHeader(
            folders: selectedFolderSummaries,
            onRemove: { folderID in
                toggleSelection(folderID)
            }
        )
    }

    private var folderPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Choose destination", systemImage: "folder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                PaperCodexPanelButton(title: "New root folder", systemImage: "folder.badge.plus") {
                    beginNewCategory(parentID: nil)
                }
            }

            Group {
                if visibleFolderItems.isEmpty && activeNewCategoryParentID == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text("No folders yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                } else {
                    NativeSaveToLibraryFolderPicker(
                        rows: folderPickerRows,
                        draftName: $newCategoryName,
                        onToggleExpanded: toggleCollapsed,
                        onToggleSelected: toggleSelection,
                        onCreateChild: beginNewCategory,
                        onRemoveNewCategory: removeNewCategory,
                        onCommitDraft: commitNewCategory,
                        onCancelDraft: cancelNewCategory
                    )
                }
            }
            .frame(maxHeight: 260)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Spacer()
            PaperCodexPanelButton(title: "Cancel", systemImage: "xmark") {
                onCancel()
            }

            PaperCodexPanelButton(
                title: "Save",
                systemImage: "checkmark",
                kind: .primary,
                disabled: !canSave
            ) {
                onSave(
                    SaveToLibraryCategorySelection(
                        categoryIDs: selectedCategoryIDsInOrder,
                        newCategoryNames: [],
                        newCategories: selectedNewCategoriesInOrder
                    )
                )
            }
        }
    }

    private var canSave: Bool {
        !selectedCategoryIDs.isEmpty || !selectedNewCategoryIDs.isEmpty
    }

    private var visibleFolderItems: [SaveToLibraryFolderItem] {
        folderItems(parentID: nil, respectingCollapse: true)
    }

    private var folderPickerRows: [SaveToLibraryFolderPickerRowModel] {
        var rows: [SaveToLibraryFolderPickerRowModel] = []
        if activeNewCategoryParentID == saveToLibraryRootDraftParentID {
            rows.append(.draft(parentID: nil, depth: 0, connectorContinuations: []))
        }
        for item in visibleFolderItems {
            rows.append(
                .folder(
                    item: item,
                    isSelected: isSelected(item.node.id),
                    isExpanded: !collapsedCategoryIDs.contains(item.node.id),
                    hasChildren: hasChildren(item.node.id),
                    canRemoveNewCategory: item.node.isNew
                )
            )
            if activeNewCategoryParentID == item.node.id {
                rows.append(
                    .draft(
                        parentID: item.node.id,
                        depth: item.depth + 1,
                        connectorContinuations: item.connectorContinuations + [hasChildren(item.node.id)]
                    )
                )
            }
        }
        return rows
    }

    private var allFolderItems: [SaveToLibraryFolderItem] {
        folderItems(parentID: nil, respectingCollapse: false)
    }

    private var allFolderNodes: [SaveToLibraryFolderNode] {
        let existing = libraryCategories.map { category in
            SaveToLibraryFolderNode(
                id: category.id,
                parentID: category.parentID,
                name: category.name,
                sortOrder: category.sortOrder,
                isPinned: category.isPinned,
                isNew: false
            )
        }
        let pending = pendingNewCategories.enumerated().map { index, category in
            SaveToLibraryFolderNode(
                id: category.id,
                parentID: category.parentID,
                name: category.name,
                sortOrder: Int.max / 2 + index,
                isPinned: false,
                isNew: true
            )
        }
        return existing + pending
    }

    private var selectedFolderSummaries: [SaveToLibrarySelectedFolderSummary] {
        allFolderItems.compactMap { item in
            guard isSelected(item.node.id) else {
                return nil
            }
            return SaveToLibrarySelectedFolderSummary(id: item.node.id, path: folderDisplayPath(for: item.node))
        }
    }

    private var selectedCategoryIDsInOrder: [String] {
        allFolderItems.compactMap { item in
            guard !item.node.isNew, selectedCategoryIDs.contains(item.node.id) else {
                return nil
            }
            return item.node.id
        }
    }

    private var selectedNewCategoriesInOrder: [SaveToLibraryNewCategory] {
        let selectedIDs = selectedNewCategoryIDs.union(newCategoryAncestorIDs(for: selectedNewCategoryIDs))
        return allFolderItems.compactMap { item in
            guard item.node.isNew,
                  selectedIDs.contains(item.node.id),
                  let category = pendingNewCategories.first(where: { $0.id == item.node.id }) else {
                return nil
            }
            return category
        }
    }

    private var trimmedNewCategoryName: String {
        newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func folderItems(
        parentID: String?,
        depth: Int = 0,
        respectingCollapse: Bool,
        visited: Set<String> = [],
        ancestorContinuations: [Bool] = []
    ) -> [SaveToLibraryFolderItem] {
        let children = childNodes(parentID: parentID)
        return children.enumerated().flatMap { index, node -> [SaveToLibraryFolderItem] in
            guard !visited.contains(node.id) else {
                return []
            }
            let isLast = index == children.count - 1
            let connectorContinuations = depth == 0 ? [] : ancestorContinuations + [!isLast]
            let item = SaveToLibraryFolderItem(
                node: node,
                depth: depth,
                connectorContinuations: connectorContinuations
            )
            if respectingCollapse && collapsedCategoryIDs.contains(node.id) {
                return [item]
            }
            return [item] + folderItems(
                parentID: node.id,
                depth: depth + 1,
                respectingCollapse: respectingCollapse,
                visited: visited.union([node.id]),
                ancestorContinuations: connectorContinuations
            )
        }
    }

    private func childNodes(parentID: String?) -> [SaveToLibraryFolderNode] {
        allFolderNodes
            .filter { $0.parentID == parentID }
            .sorted { left, right in
                if left.isPinned != right.isPinned {
                    return left.isPinned
                }
                if left.sortOrder == right.sortOrder {
                    if left.isNew != right.isNew {
                        return !left.isNew
                    }
                    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                }
                return left.sortOrder < right.sortOrder
            }
    }

    private func hasChildren(_ categoryID: String) -> Bool {
        !childNodes(parentID: categoryID).isEmpty
    }

    private func isSelected(_ categoryID: String) -> Bool {
        if pendingNewCategories.contains(where: { $0.id == categoryID }) {
            return selectedNewCategoryIDs.contains(categoryID)
        }
        return selectedCategoryIDs.contains(categoryID)
    }

    private func toggleSelection(_ categoryID: String) {
        if pendingNewCategories.contains(where: { $0.id == categoryID }) {
            toggle(categoryID, in: &selectedNewCategoryIDs)
        } else {
            toggle(categoryID, in: &selectedCategoryIDs)
        }
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func toggleCollapsed(_ categoryID: String) {
        toggle(categoryID, in: &collapsedCategoryIDs)
    }

    private func beginNewCategory(parentID: String?) {
        activeNewCategoryParentID = parentID ?? saveToLibraryRootDraftParentID
        newCategoryName = ""
        if let parentID {
            collapsedCategoryIDs.remove(parentID)
        }
    }

    private func commitNewCategory(parentID: String?) {
        let trimmed = trimmedNewCategoryName
        guard !trimmed.isEmpty else {
            return
        }
        let category = SaveToLibraryNewCategory(
            id: "new-category-\(UUID().uuidString)",
            parentID: parentID,
            name: trimmed
        )
        pendingNewCategories.append(category)
        selectedNewCategoryIDs.insert(category.id)
        if let parentID {
            collapsedCategoryIDs.remove(parentID)
        }
        cancelNewCategory()
    }

    private func cancelNewCategory() {
        activeNewCategoryParentID = nil
        newCategoryName = ""
    }

    private func removeNewCategory(_ categoryID: String) {
        let idsToRemove = Set([categoryID]).union(descendantIDs(of: categoryID))
        pendingNewCategories.removeAll { idsToRemove.contains($0.id) }
        selectedNewCategoryIDs.subtract(idsToRemove)
        collapsedCategoryIDs.subtract(idsToRemove)
        if activeNewCategoryParentID.map({ idsToRemove.contains($0) }) == true {
            cancelNewCategory()
        }
    }

    private func descendantIDs(of categoryID: String) -> Set<String> {
        var result: Set<String> = []
        var didChange = true
        while didChange {
            didChange = false
            for node in allFolderNodes where node.parentID.map({ $0 == categoryID || result.contains($0) }) == true && !result.contains(node.id) {
                result.insert(node.id)
                didChange = true
            }
        }
        return result
    }

    private func newCategoryAncestorIDs(for categoryIDs: Set<String>) -> Set<String> {
        var result: Set<String> = []
        var queue = Array(categoryIDs)
        while let categoryID = queue.popLast(),
              let parentID = pendingNewCategories.first(where: { $0.id == categoryID })?.parentID {
            if pendingNewCategories.contains(where: { $0.id == parentID }),
               !result.contains(parentID) {
                result.insert(parentID)
                queue.append(parentID)
            }
        }
        return result
    }

    private func folderDisplayPath(for node: SaveToLibraryFolderNode) -> String {
        var names = [node.name]
        var visited = Set([node.id])
        var parentID = node.parentID
        while let id = parentID,
              !visited.contains(id),
              let parent = allFolderNodes.first(where: { $0.id == id }) {
            names.append(parent.name)
            visited.insert(parent.id)
            parentID = parent.parentID
        }
        return names.reversed().joined(separator: " / ")
    }
}

private struct SaveToLibraryFolderNode: Equatable, Identifiable {
    var id: String
    var parentID: String?
    var name: String
    var sortOrder: Int
    var isPinned: Bool
    var isNew: Bool
}

private struct SaveToLibraryFolderItem: Identifiable {
    var node: SaveToLibraryFolderNode
    var depth: Int
    var connectorContinuations: [Bool] = []

    var id: String { node.id }
}

private struct SaveToLibrarySelectedFolderSummary: Identifiable {
    var id: String
    var path: String
}

private struct SaveToLibraryFolderPickerRowModel: Identifiable, Equatable {
    enum Kind: Equatable {
        case folder
        case draft
    }

    var id: String
    var kind: Kind
    var parentID: String?
    var categoryID: String?
    var title: String
    var depth: Int
    var connectorContinuations: [Bool]
    var isSelected: Bool
    var isExpanded: Bool
    var hasChildren: Bool
    var isNew: Bool
    var canRemoveNewCategory: Bool

    static func folder(
        item: SaveToLibraryFolderItem,
        isSelected: Bool,
        isExpanded: Bool,
        hasChildren: Bool,
        canRemoveNewCategory: Bool
    ) -> SaveToLibraryFolderPickerRowModel {
        SaveToLibraryFolderPickerRowModel(
            id: "folder-\(item.node.id)",
            kind: .folder,
            parentID: item.node.parentID,
            categoryID: item.node.id,
            title: item.node.name,
            depth: item.depth,
            connectorContinuations: item.connectorContinuations,
            isSelected: isSelected,
            isExpanded: isExpanded,
            hasChildren: hasChildren,
            isNew: item.node.isNew,
            canRemoveNewCategory: canRemoveNewCategory
        )
    }

    static func draft(parentID: String?, depth: Int, connectorContinuations: [Bool]) -> SaveToLibraryFolderPickerRowModel {
        SaveToLibraryFolderPickerRowModel(
            id: "draft-\(parentID ?? "root")",
            kind: .draft,
            parentID: parentID,
            categoryID: nil,
            title: "New folder",
            depth: depth,
            connectorContinuations: connectorContinuations,
            isSelected: false,
            isExpanded: false,
            hasChildren: false,
            isNew: true,
            canRemoveNewCategory: false
        )
    }
}

private struct NativeSaveToLibraryFolderPicker: NSViewRepresentable {
    var rows: [SaveToLibraryFolderPickerRowModel]
    @Binding var draftName: String
    var onToggleExpanded: (String) -> Void
    var onToggleSelected: (String) -> Void
    var onCreateChild: (String?) -> Void
    var onRemoveNewCategory: (String) -> Void
    var onCommitDraft: (String?) -> Void
    var onCancelDraft: () -> Void

    func makeNSView(context: Context) -> NativeSaveToLibraryFolderPickerView {
        let view = NativeSaveToLibraryFolderPickerView()
        view.apply(
            rows: rows,
            draftName: draftName,
            onDraftNameChange: { draftName = $0 },
            onToggleExpanded: onToggleExpanded,
            onToggleSelected: onToggleSelected,
            onCreateChild: onCreateChild,
            onRemoveNewCategory: onRemoveNewCategory,
            onCommitDraft: onCommitDraft,
            onCancelDraft: onCancelDraft
        )
        return view
    }

    func updateNSView(_ view: NativeSaveToLibraryFolderPickerView, context: Context) {
        view.apply(
            rows: rows,
            draftName: draftName,
            onDraftNameChange: { draftName = $0 },
            onToggleExpanded: onToggleExpanded,
            onToggleSelected: onToggleSelected,
            onCreateChild: onCreateChild,
            onRemoveNewCategory: onRemoveNewCategory,
            onCommitDraft: onCommitDraft,
            onCancelDraft: onCancelDraft
        )
    }
}

private final class NativeSaveToLibraryFolderPickerView: NSScrollView {
    private let tableView = NativeSaveToLibraryFolderPickerTableView()
    private let controller = NativeSaveToLibraryFolderPickerController()

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

    func apply(
        rows: [SaveToLibraryFolderPickerRowModel],
        draftName: String,
        onDraftNameChange: @escaping (String) -> Void,
        onToggleExpanded: @escaping (String) -> Void,
        onToggleSelected: @escaping (String) -> Void,
        onCreateChild: @escaping (String?) -> Void,
        onRemoveNewCategory: @escaping (String) -> Void,
        onCommitDraft: @escaping (String?) -> Void,
        onCancelDraft: @escaping () -> Void
    ) {
        let shouldReload = controller.apply(
            rows: rows,
            draftName: draftName,
            onDraftNameChange: onDraftNameChange,
            onToggleExpanded: onToggleExpanded,
            onToggleSelected: onToggleSelected,
            onCreateChild: onCreateChild,
            onRemoveNewCategory: onRemoveNewCategory,
            onCommitDraft: onCommitDraft,
            onCancelDraft: onCancelDraft
        )
        if shouldReload {
            tableView.reloadData()
            if let draftIndex = rows.firstIndex(where: { $0.kind == .draft }) {
                tableView.scrollRowToVisible(draftIndex)
            }
        }
        fitColumnToVisibleWidth()
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

        let column = NSTableColumn(identifier: NativeSaveToLibraryFolderPickerController.columnIdentifier)
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
        tableView.intercellSpacing = NSSize(width: 0, height: 6)
        tableView.style = .plain
        tableView.dataSource = controller
        tableView.delegate = controller
        controller.attach(tableView: tableView)

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

private final class NativeSaveToLibraryFolderPickerTableView: NSTableView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

@MainActor private final class NativeSaveToLibraryFolderPickerController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let columnIdentifier = NSUserInterfaceItemIdentifier("save-to-library-folder")

    private static let folderCellIdentifier = NSUserInterfaceItemIdentifier("SaveToLibraryFolderCell")
    private static let draftCellIdentifier = NSUserInterfaceItemIdentifier("SaveToLibraryFolderDraftCell")

    private weak var tableView: NSTableView?
    private var rows: [SaveToLibraryFolderPickerRowModel] = []
    private var draftName = ""
    private var onDraftNameChange: (String) -> Void = { _ in }
    private var onToggleExpanded: (String) -> Void = { _ in }
    private var onToggleSelected: (String) -> Void = { _ in }
    private var onCreateChild: (String?) -> Void = { _ in }
    private var onRemoveNewCategory: (String) -> Void = { _ in }
    private var onCommitDraft: (String?) -> Void = { _ in }
    private var onCancelDraft: () -> Void = {}

    func attach(tableView: NSTableView) {
        self.tableView = tableView
    }

    @discardableResult
    func apply(
        rows: [SaveToLibraryFolderPickerRowModel],
        draftName: String,
        onDraftNameChange: @escaping (String) -> Void,
        onToggleExpanded: @escaping (String) -> Void,
        onToggleSelected: @escaping (String) -> Void,
        onCreateChild: @escaping (String?) -> Void,
        onRemoveNewCategory: @escaping (String) -> Void,
        onCommitDraft: @escaping (String?) -> Void,
        onCancelDraft: @escaping () -> Void
    ) -> Bool {
        let shouldReload = rows != self.rows
        self.rows = rows
        self.draftName = draftName
        self.onDraftNameChange = onDraftNameChange
        self.onToggleExpanded = onToggleExpanded
        self.onToggleSelected = onToggleSelected
        self.onCreateChild = onCreateChild
        self.onRemoveNewCategory = onRemoveNewCategory
        self.onCommitDraft = onCommitDraft
        self.onCancelDraft = onCancelDraft
        return shouldReload
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else {
            return SaveToLibraryLayout.treeConnectorHeight
        }
        return rows[row].kind == .draft ? 46 : SaveToLibraryLayout.treeConnectorHeight
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NativeSaveToLibraryFolderPickerRowView()
        rowView.isEmphasized = false
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else {
            return nil
        }
        let rowModel = rows[row]
        switch rowModel.kind {
        case .folder:
            let cell = (tableView.makeView(withIdentifier: Self.folderCellIdentifier, owner: self) as? NativeSaveToLibraryFolderRowCellView)
                ?? NativeSaveToLibraryFolderRowCellView(identifier: Self.folderCellIdentifier)
            cell.configure(
                row: rowModel,
                onToggleExpanded: onToggleExpanded,
                onToggleSelected: onToggleSelected,
                onCreateChild: onCreateChild,
                onRemoveNewCategory: onRemoveNewCategory
            )
            return cell
        case .draft:
            let cell = (tableView.makeView(withIdentifier: Self.draftCellIdentifier, owner: self) as? NativeSaveToLibraryFolderDraftCellView)
                ?? NativeSaveToLibraryFolderDraftCellView(identifier: Self.draftCellIdentifier)
            cell.configure(
                row: rowModel,
                draftName: draftName,
                onDraftNameChange: onDraftNameChange,
                onCommitDraft: onCommitDraft,
                onCancelDraft: onCancelDraft
            )
            return cell
        }
    }
}

private final class NativeSaveToLibraryFolderPickerRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {}

    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}

private final class NativeSaveToLibraryFolderRowCellView: NSTableCellView {
    private let connectorView = NativeSaveToLibraryTreeConnectorView()
    private let expandButton = NativeSaveToLibraryFolderIconButtonView()
    private let selectionButton = NativeSaveToLibraryFolderSelectionButtonView()
    private let createButton = NativeSaveToLibraryFolderIconButtonView()
    private let removeButton = NativeSaveToLibraryFolderIconButtonView()
    private var contentLeadingConstraint: NSLayoutConstraint?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(
        row: SaveToLibraryFolderPickerRowModel,
        onToggleExpanded: @escaping (String) -> Void,
        onToggleSelected: @escaping (String) -> Void,
        onCreateChild: @escaping (String?) -> Void,
        onRemoveNewCategory: @escaping (String) -> Void
    ) {
        connectorView.apply(depth: row.depth, connectorContinuations: row.connectorContinuations)
        contentLeadingConstraint?.constant = CGFloat(row.depth) * SaveToLibraryLayout.treeIndentWidth

        if row.hasChildren, let categoryID = row.categoryID {
            expandButton.isHidden = false
            expandButton.apply(
                title: row.isExpanded ? "Collapse" : "Expand",
                systemImage: row.isExpanded ? "chevron.down" : "chevron.right",
                tint: .secondary,
                width: SaveToLibraryLayout.chevronWidth,
                height: 24,
                symbolSize: 9,
                action: { onToggleExpanded(categoryID) }
            )
        } else {
            expandButton.isHidden = true
            expandButton.apply(
                title: "",
                systemImage: "chevron.right",
                tint: .secondary,
                width: SaveToLibraryLayout.chevronWidth,
                height: 24,
                symbolSize: 9,
                action: {}
            )
        }

        if let categoryID = row.categoryID {
            selectionButton.apply(
                title: row.title,
                isSelected: row.isSelected,
                isNew: row.isNew,
                action: { onToggleSelected(categoryID) }
            )
            createButton.apply(
                title: "New subfolder",
                systemImage: "plus",
                tint: .accentColor,
                width: 22,
                height: 22,
                symbolSize: 11,
                action: { onCreateChild(categoryID) }
            )
            removeButton.isHidden = !row.canRemoveNewCategory
            removeButton.apply(
                title: row.canRemoveNewCategory ? "Remove new folder" : "",
                systemImage: "trash",
                tint: .red,
                width: row.canRemoveNewCategory ? 22 : 0,
                height: 22,
                symbolSize: 11,
                action: row.canRemoveNewCategory ? { onRemoveNewCategory(categoryID) } : {}
            )
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        connectorView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(connectorView)

        [expandButton, selectionButton, createButton, removeButton].forEach { view in
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        let leading = expandButton.leadingAnchor.constraint(equalTo: leadingAnchor)
        contentLeadingConstraint = leading
        NSLayoutConstraint.activate([
            connectorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            connectorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            connectorView.topAnchor.constraint(equalTo: topAnchor),
            connectorView.bottomAnchor.constraint(equalTo: bottomAnchor),

            leading,
            expandButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            selectionButton.leadingAnchor.constraint(equalTo: expandButton.trailingAnchor, constant: SaveToLibraryLayout.chevronFolderSpacing),
            selectionButton.trailingAnchor.constraint(equalTo: createButton.leadingAnchor, constant: -4),
            selectionButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            createButton.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -4),
            createButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private final class NativeSaveToLibraryFolderDraftCellView: NSTableCellView, NSTextFieldDelegate {
    private let connectorView = NativeSaveToLibraryTreeConnectorView()
    private let cardView = NSView()
    private let chevronSpacer = NSView()
    private let iconView = NSImageView()
    private let nameField = NSTextField()
    private let addButton = NativeSaveToLibraryFolderIconButtonView()
    private let cancelButton = NativeSaveToLibraryFolderIconButtonView()
    private var cardLeadingConstraint: NSLayoutConstraint?
    private var parentID: String?
    private var onDraftNameChange: (String) -> Void = { _ in }
    private var onCommitDraft: (String?) -> Void = { _ in }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(
        row: SaveToLibraryFolderPickerRowModel,
        draftName: String,
        onDraftNameChange: @escaping (String) -> Void,
        onCommitDraft: @escaping (String?) -> Void,
        onCancelDraft: @escaping () -> Void
    ) {
        parentID = row.parentID
        self.onDraftNameChange = onDraftNameChange
        self.onCommitDraft = onCommitDraft
        connectorView.apply(depth: row.depth, connectorContinuations: row.connectorContinuations)
        cardLeadingConstraint?.constant = CGFloat(row.depth) * SaveToLibraryLayout.treeIndentWidth
        if nameField.stringValue != draftName,
           window?.firstResponder !== nameField.currentEditor() {
            nameField.stringValue = draftName
        }
        updateCommitEnabled()
        addButton.apply(
            title: "Add Folder",
            systemImage: "checkmark",
            tint: .accentColor,
            width: 24,
            height: 24,
            symbolSize: 12,
            action: { [weak self] in self?.commitDraft() }
        )
        cancelButton.apply(
            title: "Cancel",
            systemImage: "xmark",
            tint: .secondary,
            width: 24,
            height: 24,
            symbolSize: 12,
            action: onCancelDraft
        )
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.window?.firstResponder !== self.nameField.currentEditor(),
                  self.nameField.stringValue.isEmpty else {
                return
            }
            self.window?.makeFirstResponder(self.nameField)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        onDraftNameChange(nameField.stringValue)
        updateCommitEnabled()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        connectorView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(connectorView)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 7
        cardView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        addSubview(cardView)

        chevronSpacer.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(chevronSpacer)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "New folder")
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.contentTintColor = .controlAccentColor
        iconView.imageScaling = .scaleProportionallyDown
        cardView.addSubview(iconView)

        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.placeholderString = "New folder"
        nameField.font = .systemFont(ofSize: 12.5, weight: .medium)
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(commitDraft)
        cardView.addSubview(nameField)

        addButton.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(addButton)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(cancelButton)

        let cardLeading = cardView.leadingAnchor.constraint(equalTo: leadingAnchor)
        cardLeadingConstraint = cardLeading
        NSLayoutConstraint.activate([
            connectorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            connectorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            connectorView.topAnchor.constraint(equalTo: topAnchor),
            connectorView.bottomAnchor.constraint(equalTo: bottomAnchor),

            cardLeading,
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            cardView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            chevronSpacer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            chevronSpacer.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            chevronSpacer.widthAnchor.constraint(equalToConstant: SaveToLibraryLayout.chevronWidth),
            chevronSpacer.heightAnchor.constraint(equalToConstant: 24),

            iconView.leadingAnchor.constraint(equalTo: chevronSpacer.trailingAnchor, constant: SaveToLibraryLayout.chevronFolderSpacing),
            iconView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: SaveToLibraryLayout.folderIconWidth),
            iconView.heightAnchor.constraint(equalToConstant: SaveToLibraryLayout.folderIconWidth),

            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -8),
            nameField.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            nameField.heightAnchor.constraint(equalToConstant: 28),

            addButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -4),
            addButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),

            cancelButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor)
        ])
    }

    @objc private func commitDraft() {
        guard !nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        onCommitDraft(parentID)
    }

    private func updateCommitEnabled() {
        addButton.isEnabled = !nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private final class NativeSaveToLibraryTreeConnectorView: NSView {
    private var depth = 0
    private var connectorContinuations: [Bool] = []

    override var isFlipped: Bool {
        true
    }

    func apply(depth: Int, connectorContinuations: [Bool]) {
        guard self.depth != depth || self.connectorContinuations != connectorContinuations else {
            return
        }
        self.depth = depth
        self.connectorContinuations = connectorContinuations
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard depth > 0, !connectorContinuations.isEmpty else {
            return
        }
        let path = NSBezierPath()
        path.lineWidth = SaveToLibraryLayout.treeConnectorLineWidth
        path.lineCapStyle = .butt
        path.lineJoinStyle = .round
        path.setLineDash([], count: 0, phase: 0)

        let rect = bounds
        let midY = rect.midY
        let currentIconX = SaveToLibraryLayout.folderIconCenterX(depth: depth)
        let currentTargetX = currentIconX - SaveToLibraryLayout.treeConnectorTargetInset
        let parentIconX = SaveToLibraryLayout.folderIconCenterX(depth: depth - 1)
        let currentBranchContinues = connectorContinuations.indices.contains(depth - 1)
            ? connectorContinuations[depth - 1]
            : false

        if depth > 1 {
            for level in 0..<(depth - 1) where connectorContinuations.indices.contains(level) && connectorContinuations[level] {
                let ancestorIconX = SaveToLibraryLayout.folderIconCenterX(depth: level)
                path.move(to: CGPoint(x: ancestorIconX, y: rect.minY))
                path.line(to: CGPoint(x: ancestorIconX, y: rect.maxY))
            }
        }

        path.move(to: CGPoint(x: parentIconX, y: rect.minY))
        path.line(to: CGPoint(x: parentIconX, y: currentBranchContinues ? rect.maxY : midY))
        path.move(to: CGPoint(x: parentIconX, y: midY))
        path.line(to: CGPoint(x: currentTargetX, y: midY))

        NSColor.labelColor.withAlphaComponent(SaveToLibraryLayout.treeConnectorOpacity).setStroke()
        path.stroke()
    }
}

private struct SaveToLibraryDestinationHeader: View {
    var folders: [SaveToLibrarySelectedFolderSummary]
    var onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Destination", systemImage: "target")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(folders.isEmpty ? "Choose destination" : "\(folders.count) selected")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if folders.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .foregroundStyle(.secondary)
                    Text("No folder selected")
                        .font(.paperCodexSystem(size: 12.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                PaperCodexNativeScrollView {
                    SaveToLibraryFlowLayout(spacing: 6) {
                        ForEach(folders) { folder in
                            SaveToLibraryFolderPathChip(folder: folder) {
                                onRemove(folder.id)
                            }
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(maxHeight: SaveToLibraryLayout.destinationChipMaxHeight)
            }
        }
    }
}

private struct SaveToLibraryFolderPathChip: View {
    var folder: SaveToLibrarySelectedFolderSummary
    var onRemove: () -> Void

    var body: some View {
        PaperCodexPathChipButton(title: folder.path) {
            onRemove()
        }
    }
}

private struct SaveToLibraryFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews).rows
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
            }
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, rows: [SaveToLibraryFlowRow]) {
        let maxWidth = proposal.width ?? 520
        var rows: [SaveToLibraryFlowRow] = []
        var currentItems: [SaveToLibraryFlowItem] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                rows.append(SaveToLibraryFlowRow(items: currentItems))
                currentY += rowHeight + spacing
                currentItems = []
                currentX = 0
                rowHeight = 0
            }
            currentItems.append(SaveToLibraryFlowItem(index: index, origin: CGPoint(x: currentX, y: currentY), size: size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        if !currentItems.isEmpty {
            rows.append(SaveToLibraryFlowRow(items: currentItems))
        }
        let height = rows.last?.items.map { $0.origin.y + $0.size.height }.max() ?? 0
        return (CGSize(width: maxWidth, height: height), rows)
    }
}

private struct SaveToLibraryFlowRow {
    var items: [SaveToLibraryFlowItem]
}

private struct SaveToLibraryFlowItem {
    var index: Int
    var origin: CGPoint
    var size: CGSize
}

private final class NativeSaveToLibraryFolderSelectionButtonView: NSButton {
    private let folderIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let newBadgeLabel = NSTextField(labelWithString: "")
    private let checkIconView = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var pressHandler: () -> Void = {}
    private var isSelected = false
    private var isNew = false
    private var isHovering = false
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 30)
    }

    func apply(title: String, isSelected: Bool, isNew: Bool, action: @escaping () -> Void) {
        pressHandler = action
        self.isSelected = isSelected
        self.isNew = isNew
        let localizedTitle = NSLocalizedString(title, comment: "")
        titleLabel.stringValue = localizedTitle
        titleLabel.font = .systemFont(ofSize: 12.5, weight: isSelected ? .semibold : .medium)
        newBadgeLabel.stringValue = isNew ? NSLocalizedString("New", comment: "") : ""
        folderIconView.image = NSImage(
            systemSymbolName: isNew ? "folder.badge.plus" : "folder",
            accessibilityDescription: localizedTitle
        )
        checkIconView.image = NSImage(
            systemSymbolName: isSelected ? "checkmark.circle.fill" : "circle",
            accessibilityDescription: localizedTitle
        )
        toolTip = localizedTitle
        setAccessibilityLabel(localizedTitle)
        setAccessibilityValue(isSelected ? NSLocalizedString("Selected", comment: "") : NSLocalizedString("Not selected", comment: ""))
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        focusRingType = .none
        setButtonType(.momentaryChange)
        target = self
        action = #selector(performPress)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = false

        folderIconView.translatesAutoresizingMaskIntoConstraints = false
        folderIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        folderIconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        newBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        newBadgeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        newBadgeLabel.lineBreakMode = .byTruncatingTail
        newBadgeLabel.maximumNumberOfLines = 1
        newBadgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        checkIconView.translatesAutoresizingMaskIntoConstraints = false
        checkIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        checkIconView.imageScaling = .scaleProportionallyDown

        [folderIconView, titleLabel, newBadgeLabel, checkIconView].forEach(addSubview(_:))
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            folderIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            folderIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            folderIconView.widthAnchor.constraint(equalToConstant: 17),
            folderIconView.heightAnchor.constraint(equalToConstant: 17),
            titleLabel.leadingAnchor.constraint(equalTo: folderIconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            newBadgeLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            newBadgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            newBadgeLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkIconView.leadingAnchor, constant: -8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkIconView.leadingAnchor, constant: -8),
            checkIconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            checkIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkIconView.widthAnchor.constraint(equalToConstant: 15),
            checkIconView.heightAnchor.constraint(equalToConstant: 15)
        ])
        updateAppearance()
    }

    @objc private func performPress() {
        pressHandler()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let tint = NSColor.controlAccentColor
        let background: NSColor
        let border: NSColor
        let shadowOpacity: Float

        if isSelected {
            background = tint.withAlphaComponent(isPressed ? 0.18 : 0.11)
            border = isPressed ? tint.withAlphaComponent(0.40) : tint.withAlphaComponent(0.25)
            shadowOpacity = isPressed ? 0.10 : 0
        } else if isPressed {
            background = tint.withAlphaComponent(0.10)
            border = tint.withAlphaComponent(0.40)
            shadowOpacity = 0.10
        } else if isHovering {
            background = .labelColor.withAlphaComponent(0.045)
            border = .clear
            shadowOpacity = 0
        } else {
            background = .clear
            border = .clear
            shadowOpacity = 0
        }

        titleLabel.textColor = .labelColor
        newBadgeLabel.textColor = tint
        folderIconView.contentTintColor = isSelected || isNew ? tint : .secondaryLabelColor
        checkIconView.contentTintColor = isSelected ? tint : .secondaryLabelColor.withAlphaComponent(0.65)
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = border == .clear ? 0 : 1
        layer?.borderColor = border.cgColor
        layer?.shadowColor = tint.cgColor
        layer?.shadowOpacity = shadowOpacity
        layer?.shadowRadius = isPressed ? 3 : 5
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? -1 : -2)

        CATransaction.begin()
        CATransaction.setAnimationDuration(isPressed ? 0.05 : 0.12)
        layer?.transform = CATransform3DMakeScale(isPressed ? 0.988 : 1, isPressed ? 0.988 : 1, 1)
        CATransaction.commit()
    }
}

private final class NativeSaveToLibraryFolderIconButtonView: NSButton {
    private let iconView = NSImageView()
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var trackingArea: NSTrackingArea?
    private var pressHandler: () -> Void = {}
    private var tintColor = NSColor.controlAccentColor
    private var isHovering = false
    private var isPressed = false
    private var buttonSize = CGSize(width: 22, height: 22)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        buttonSize
    }

    func apply(
        title: String,
        systemImage: String,
        tint: Color,
        width: CGFloat,
        height: CGFloat,
        symbolSize: CGFloat,
        action: @escaping () -> Void
    ) {
        let localizedTitle = NSLocalizedString(title, comment: "")
        pressHandler = action
        tintColor = NSColor(tint)
        buttonSize = CGSize(width: width, height: height)
        widthConstraint?.constant = width
        heightConstraint?.constant = height
        let iconSide = min(width, height, max(symbolSize + 4, symbolSize))
        iconWidthConstraint?.constant = iconSide
        iconHeightConstraint?.constant = iconSide
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: localizedTitle)
        toolTip = localizedTitle
        setAccessibilityLabel(localizedTitle)
        invalidateIntrinsicContentSize()
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        focusRingType = .none
        setButtonType(.momentaryChange)
        target = self
        action = #selector(performPress)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.masksToBounds = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        let widthConstraint = widthAnchor.constraint(equalToConstant: buttonSize.width)
        let heightConstraint = heightAnchor.constraint(equalToConstant: buttonSize.height)
        let iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 15)
        let iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 15)
        self.widthConstraint = widthConstraint
        self.heightConstraint = heightConstraint
        self.iconWidthConstraint = iconWidthConstraint
        self.iconHeightConstraint = iconHeightConstraint
        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint
        ])
        updateAppearance()
    }

    @objc private func performPress() {
        pressHandler()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let tint = tintColor
        let foreground = isPressed ? tint : tint.withAlphaComponent(isHovering ? 0.92 : 0.78)
        let background = isPressed ? tint.withAlphaComponent(0.17) : (isHovering ? tint.withAlphaComponent(0.10) : .clear)
        let border = isPressed ? tint.withAlphaComponent(0.36) : .clear

        iconView.contentTintColor = foreground
        layer?.cornerRadius = min(buttonSize.width, buttonSize.height) / 2
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = border == .clear ? 0 : 1
        layer?.borderColor = border.cgColor
        layer?.shadowColor = tint.cgColor
        layer?.shadowOpacity = isPressed ? 0.10 : 0
        layer?.shadowRadius = 3
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? -1 : -1)

        CATransaction.begin()
        CATransaction.setAnimationDuration(isPressed ? 0.05 : 0.12)
        layer?.transform = CATransform3DMakeScale(isPressed ? 0.88 : 1, isPressed ? 0.88 : 1, 1)
        CATransaction.commit()
    }
}
