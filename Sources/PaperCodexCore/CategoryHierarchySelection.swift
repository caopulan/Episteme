import Foundation

public enum CategoryHierarchySelectionState: Sendable, Equatable {
    case none
    case partial
    case all
}

public struct CategoryHierarchySelection: Sendable {
    public let categories: [Category]

    private let categoriesByID: [String: Category]
    private let rootIDs: [String]
    private let childIDsByParentID: [String: [String]]
    private let parentIDByID: [String: String]

    public init(categories: [Category]) {
        self.categories = categories
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let knownIDs = Set(categories.map(\.id))
        var rootIDs: [String] = []
        var childIDsByParentID: [String: [String]] = [:]
        var parentIDByID: [String: String] = [:]

        for category in categories {
            if let parentID = category.parentID, knownIDs.contains(parentID) {
                childIDsByParentID[parentID, default: []].append(category.id)
                parentIDByID[category.id] = parentID
            } else {
                rootIDs.append(category.id)
            }
        }

        rootIDs.sort { Self.sortCategories(categoriesByID[$0], categoriesByID[$1]) }
        for parentID in childIDsByParentID.keys {
            childIDsByParentID[parentID, default: []].sort {
                Self.sortCategories(categoriesByID[$0], categoriesByID[$1])
            }
        }

        self.categoriesByID = categoriesByID
        self.rootIDs = rootIDs
        self.childIDsByParentID = childIDsByParentID
        self.parentIDByID = parentIDByID
    }

    public func defaultCollapsedRootCategoryIDs() -> Set<String> {
        Set(rootIDs.filter(hasChildren))
    }

    public func hasChildren(_ categoryID: String) -> Bool {
        childIDsByParentID[categoryID]?.isEmpty == false
    }

    public func selectionState(
        for categoryID: String,
        selectedIDs: Set<String>
    ) -> CategoryHierarchySelectionState {
        guard categoriesByID[categoryID] != nil else {
            return .none
        }
        let selected = expandedSelection(selectedIDs)
        let coverage = selectionCoverageIDs(categoryID)
        guard !coverage.isEmpty else {
            return .none
        }
        if coverage.isSubset(of: selected) {
            return .all
        }
        return selected.isDisjoint(with: coverage) ? .none : .partial
    }

    public func toggledSelection(
        categoryID: String,
        selectedIDs: Set<String>
    ) -> Set<String> {
        guard categoriesByID[categoryID] != nil else {
            return normalizedSelection(selectedIDs)
        }

        var next = expandedSelection(selectedIDs)
        let subtree = subtreeIDs(categoryID)
        switch selectionState(for: categoryID, selectedIDs: next) {
        case .all:
            next.subtract(subtree)
            next.subtract(ancestorIDs(of: categoryID))
        case .partial, .none:
            next.formUnion(subtree)
        }
        return normalizedSelection(next)
    }

    public func normalizedSelection(_ selectedIDs: Set<String>) -> Set<String> {
        var selected = expandedSelection(selectedIDs)
        for categoryID in categories.map(\.id) {
            let coverage = selectionCoverageIDs(categoryID)
            if !coverage.isEmpty, coverage.isSubset(of: selected) {
                selected.insert(categoryID)
            }
        }
        return selected
    }

    public func orderedSelectedIDs(_ selectedIDs: Set<String>) -> [String] {
        let normalized = normalizedSelection(selectedIDs)
        return categories.map(\.id).filter { normalized.contains($0) }
    }

    public func expandedSelection(_ selectedIDs: Set<String>) -> Set<String> {
        var result: Set<String> = []
        for categoryID in selectedIDs where categoriesByID[categoryID] != nil {
            result.formUnion(subtreeIDs(categoryID))
        }
        return result
    }

    private func subtreeIDs(_ categoryID: String) -> Set<String> {
        var result: Set<String> = []
        collectSubtreeIDs(categoryID, into: &result)
        return result
    }

    private func selectionCoverageIDs(_ categoryID: String) -> Set<String> {
        let subtree = subtreeIDs(categoryID)
        guard hasChildren(categoryID) else {
            return subtree
        }
        return subtree.subtracting([categoryID])
    }

    private func collectSubtreeIDs(_ categoryID: String, into result: inout Set<String>) {
        guard categoriesByID[categoryID] != nil, result.insert(categoryID).inserted else {
            return
        }
        for childID in childIDsByParentID[categoryID, default: []] {
            collectSubtreeIDs(childID, into: &result)
        }
    }

    private func ancestorIDs(of categoryID: String) -> Set<String> {
        var result: Set<String> = []
        var currentID = categoryID
        while let parentID = parentIDByID[currentID], result.insert(parentID).inserted {
            currentID = parentID
        }
        return result
    }

    private static func sortCategories(_ left: Category?, _ right: Category?) -> Bool {
        guard let left, let right else {
            return left != nil
        }
        if left.isPinned != right.isPinned {
            return left.isPinned && !right.isPinned
        }
        if left.sortOrder != right.sortOrder {
            return left.sortOrder < right.sortOrder
        }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }
}
