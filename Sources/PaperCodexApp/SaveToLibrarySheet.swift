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

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if activeNewCategoryParentID == saveToLibraryRootDraftParentID {
                        newCategoryInlineRow(parentID: nil, depth: 0, connectorContinuations: [])
                    }

                    if visibleFolderItems.isEmpty && activeNewCategoryParentID == nil {
                        Text("No folders yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    } else {
                        ForEach(visibleFolderItems) { item in
                            SaveToLibraryFolderRow(
                                item: item,
                                isSelected: isSelected(item.node.id),
                                isExpanded: !collapsedCategoryIDs.contains(item.node.id),
                                hasChildren: hasChildren(item.node.id),
                                onToggleExpanded: {
                                    toggleCollapsed(item.node.id)
                                },
                                onToggleSelected: {
                                    toggleSelection(item.node.id)
                                },
                                onCreateChild: {
                                    beginNewCategory(parentID: item.node.id)
                                },
                                onRemoveNewCategory: item.node.isNew ? {
                                    removeNewCategory(item.node.id)
                                } : nil
                            )
                            if activeNewCategoryParentID == item.node.id {
                                newCategoryInlineRow(
                                    parentID: item.node.id,
                                    depth: item.depth + 1,
                                    connectorContinuations: item.connectorContinuations + [hasChildren(item.node.id)]
                                )
                            }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func newCategoryInlineRow(parentID: String?, depth: Int, connectorContinuations: [Bool]) -> some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: SaveToLibraryLayout.chevronWidth, height: 24)
            Image(systemName: "folder.badge.plus")
                .frame(width: SaveToLibraryLayout.folderIconWidth)
                .foregroundStyle(Color.accentColor)
            PaperCodexNativeTextField(text: $newCategoryName, placeholder: "New folder")
                .frame(height: 30)
            PaperCodexIconButton(
                title: "Add Folder",
                systemImage: "checkmark",
                tint: .accentColor,
                disabled: trimmedNewCategoryName.isEmpty
            ) {
                commitNewCategory(parentID: parentID)
            }
            PaperCodexIconButton(title: "Cancel", systemImage: "xmark") {
                cancelNewCategory()
            }
        }
        .padding(.leading, CGFloat(depth) * SaveToLibraryLayout.treeIndentWidth)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .background(alignment: .leading) {
            SaveToLibraryTreeConnector(
                depth: depth,
                connectorContinuations: connectorContinuations
            )
            .allowsHitTesting(false)
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
                ScrollView(.vertical) {
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

private struct SaveToLibraryFolderRow: View {
    var item: SaveToLibraryFolderItem
    var isSelected: Bool
    var isExpanded: Bool
    var hasChildren: Bool
    var onToggleExpanded: () -> Void
    var onToggleSelected: () -> Void
    var onCreateChild: () -> Void
    var onRemoveNewCategory: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            if hasChildren {
                SaveToLibraryFolderIconButton(
                    title: isExpanded ? "Collapse" : "Expand",
                    systemImage: isExpanded ? "chevron.down" : "chevron.right",
                    tint: .secondary,
                    width: 16,
                    height: 24,
                    symbolSize: 9,
                    action: onToggleExpanded
                )
            } else {
                Color.clear
                    .frame(width: 16, height: 24)
            }

            SaveToLibraryFolderSelectionButton(
                title: item.node.name,
                isSelected: isSelected,
                isNew: item.node.isNew,
                action: onToggleSelected
            )

            SaveToLibraryFolderIconButton(
                title: "New subfolder",
                systemImage: "plus",
                tint: .accentColor,
                action: onCreateChild
            )

            if let onRemoveNewCategory {
                SaveToLibraryFolderIconButton(
                    title: "Remove new folder",
                    systemImage: "trash",
                    tint: .red,
                    action: onRemoveNewCategory
                )
            }
        }
        .padding(.leading, CGFloat(item.depth) * SaveToLibraryLayout.treeIndentWidth)
        .frame(minHeight: SaveToLibraryLayout.treeConnectorHeight)
        .background(alignment: .leading) {
            SaveToLibraryTreeConnector(
                depth: item.depth,
                connectorContinuations: item.connectorContinuations
            )
            .allowsHitTesting(false)
        }
    }
}

private struct SaveToLibraryFolderSelectionButton: View {
    var title: String
    var isSelected: Bool
    var isNew: Bool
    var action: () -> Void

    var body: some View {
        NativeSaveToLibraryFolderSelectionButton(
            title: title,
            isSelected: isSelected,
            isNew: isNew,
            action: action
        )
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct SaveToLibraryFolderIconButton: View {
    var title: String
    var systemImage: String
    var tint: Color
    var width: CGFloat = 22
    var height: CGFloat = 22
    var symbolSize: CGFloat = 11
    var action: () -> Void

    var body: some View {
        NativeSaveToLibraryFolderIconButton(
            title: title,
            systemImage: systemImage,
            tint: tint,
            width: width,
            height: height,
            symbolSize: symbolSize,
            action: action
        )
        .frame(width: width, height: height)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct NativeSaveToLibraryFolderSelectionButton: NSViewRepresentable {
    var title: String
    var isSelected: Bool
    var isNew: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NativeSaveToLibraryFolderSelectionButtonView {
        let view = NativeSaveToLibraryFolderSelectionButtonView()
        view.apply(title: title, isSelected: isSelected, isNew: isNew, action: action)
        return view
    }

    func updateNSView(_ view: NativeSaveToLibraryFolderSelectionButtonView, context: Context) {
        view.apply(title: title, isSelected: isSelected, isNew: isNew, action: action)
    }
}

private struct NativeSaveToLibraryFolderIconButton: NSViewRepresentable {
    var title: String
    var systemImage: String
    var tint: Color
    var width: CGFloat
    var height: CGFloat
    var symbolSize: CGFloat
    var action: () -> Void

    func makeNSView(context: Context) -> NativeSaveToLibraryFolderIconButtonView {
        let view = NativeSaveToLibraryFolderIconButtonView()
        view.apply(
            title: title,
            systemImage: systemImage,
            tint: tint,
            width: width,
            height: height,
            symbolSize: symbolSize,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativeSaveToLibraryFolderIconButtonView, context: Context) {
        view.apply(
            title: title,
            systemImage: systemImage,
            tint: tint,
            width: width,
            height: height,
            symbolSize: symbolSize,
            action: action
        )
    }
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

private struct SaveToLibraryTreeConnector: View {
    var depth: Int
    var connectorContinuations: [Bool]

    var body: some View {
        if depth == 0 || connectorContinuations.isEmpty {
            Color.clear
                .frame(height: SaveToLibraryLayout.treeConnectorHeight)
        } else {
            SaveToLibraryTreeConnectorLevel(
                depth: depth,
                connectorContinuations: connectorContinuations
            )
            .stroke(
                Color.primary.opacity(SaveToLibraryLayout.treeConnectorOpacity),
                style: StrokeStyle(
                    lineWidth: SaveToLibraryLayout.treeConnectorLineWidth,
                    lineCap: .butt,
                    lineJoin: .round
                )
            )
            .frame(
                width: SaveToLibraryLayout.folderIconCenterX(depth: depth) + 1,
                height: SaveToLibraryLayout.treeConnectorHeight
            )
        }
    }
}

private struct SaveToLibraryTreeConnectorLevel: Shape {
    var depth: Int
    var connectorContinuations: [Bool]

    func path(in rect: CGRect) -> Path {
        Path { path in
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
                    path.addLine(to: CGPoint(x: ancestorIconX, y: rect.maxY))
                }
            }

            path.move(to: CGPoint(x: parentIconX, y: rect.minY))
            path.addLine(to: CGPoint(x: parentIconX, y: currentBranchContinues ? rect.maxY : midY))
            path.move(to: CGPoint(x: parentIconX, y: midY))
            path.addLine(to: CGPoint(x: currentTargetX, y: midY))
        }
    }
}
