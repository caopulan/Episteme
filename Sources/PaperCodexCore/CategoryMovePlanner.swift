import Foundation

public enum CategoryMovePlacement: Equatable, Sendable {
    case before
    case after
    case inside
}

public enum CategoryMovePlannerError: Error, CustomStringConvertible, Equatable {
    case categoryNotFound(String)
    case invalidMove

    public var description: String {
        switch self {
        case let .categoryNotFound(categoryID):
            "No folder was found for \(categoryID)."
        case .invalidMove:
            "A category cannot be moved into itself or one of its subcategories."
        }
    }
}

public enum CategoryMovePlanner {
    public static func canMoveCategory(
        _ movingCategoryID: String,
        toParent parentID: String?,
        in categories: [Category]
    ) -> Bool {
        guard let updatedCategories = try? movedCategories(
            movingCategoryID: movingCategoryID,
            toParent: parentID,
            in: categories
        ) else {
            return false
        }
        return updatedCategories != categories
    }

    public static func canDropCategory(
        _ movingCategoryID: String,
        ontoCategory targetCategoryID: String,
        placement: CategoryMovePlacement,
        in categories: [Category]
    ) -> Bool {
        switch placement {
        case .inside:
            return canMoveCategory(movingCategoryID, toParent: targetCategoryID, in: categories)
        case .before, .after:
            guard let updatedCategories = try? reorderedCategories(
                movingCategoryID: movingCategoryID,
                relativeTo: targetCategoryID,
                placement: placement,
                in: categories
            ) else {
                return false
            }
            return updatedCategories != categories
        }
    }

    public static func movedCategories(
        movingCategoryID: String,
        toParent parentID: String?,
        in categories: [Category]
    ) throws -> [Category] {
        var categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        guard var movingCategory = categoriesByID[movingCategoryID] else {
            throw CategoryMovePlannerError.categoryNotFound(movingCategoryID)
        }
        if let parentID, categoriesByID[parentID] == nil {
            throw CategoryMovePlannerError.categoryNotFound(parentID)
        }
        guard isValidParent(parentID, for: movingCategoryID, in: categories) else {
            throw CategoryMovePlannerError.invalidMove
        }
        guard movingCategory.parentID != parentID else {
            return categories
        }

        movingCategory.parentID = parentID
        movingCategory.sortOrder = nextSortOrder(parentID: parentID, movingCategoryID: movingCategoryID, categories: categories)
        categoriesByID[movingCategoryID] = movingCategory
        return categories.map { categoriesByID[$0.id] ?? $0 }
    }

    public static func reorderedCategories(
        movingCategoryID: String,
        relativeTo targetCategoryID: String,
        placement: CategoryMovePlacement,
        in categories: [Category]
    ) throws -> [Category] {
        if placement == .inside {
            return try movedCategories(movingCategoryID: movingCategoryID, toParent: targetCategoryID, in: categories)
        }
        var categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        guard var movingCategory = categoriesByID[movingCategoryID] else {
            throw CategoryMovePlannerError.categoryNotFound(movingCategoryID)
        }
        guard let targetCategory = categoriesByID[targetCategoryID] else {
            throw CategoryMovePlannerError.categoryNotFound(targetCategoryID)
        }
        guard movingCategoryID != targetCategoryID else {
            throw CategoryMovePlannerError.invalidMove
        }

        let newParentID = targetCategory.parentID
        guard isValidParent(newParentID, for: movingCategoryID, in: categories) else {
            throw CategoryMovePlannerError.invalidMove
        }

        movingCategory.parentID = newParentID
        movingCategory.isPinned = targetCategory.isPinned
        var siblings = sortedSiblings(parentID: newParentID, categories: categories)
            .filter { $0.id != movingCategoryID }
        guard let targetIndex = siblings.firstIndex(where: { $0.id == targetCategoryID }) else {
            throw CategoryMovePlannerError.categoryNotFound(targetCategoryID)
        }
        let insertionIndex = placement == .before ? targetIndex : targetIndex + 1
        siblings.insert(movingCategory, at: insertionIndex)

        for (index, sibling) in siblings.enumerated() {
            var updated = sibling
            updated.sortOrder = (index + 1) * 10
            categoriesByID[updated.id] = updated
        }
        return categories.map { categoriesByID[$0.id] ?? $0 }
    }

    private static func isValidParent(_ parentID: String?, for movingCategoryID: String, in categories: [Category]) -> Bool {
        guard parentID != movingCategoryID else {
            return false
        }
        guard let parentID else {
            return true
        }
        return !descendantIDs(of: movingCategoryID, in: categories).contains(parentID)
    }

    private static func descendantIDs(of categoryID: String, in categories: [Category]) -> Set<String> {
        var descendants: Set<String> = []
        var didChange = true
        while didChange {
            didChange = false
            for category in categories where category.parentID.map({ $0 == categoryID || descendants.contains($0) }) == true && !descendants.contains(category.id) {
                descendants.insert(category.id)
                didChange = true
            }
        }
        return descendants
    }

    private static func sortedSiblings(parentID: String?, categories: [Category]) -> [Category] {
        categories
            .filter { $0.parentID == parentID }
            .sorted(by: categorySortPrecedes)
    }

    private static func categorySortPrecedes(_ left: Category, _ right: Category) -> Bool {
        if left.isPinned != right.isPinned {
            return left.isPinned
        }
        if left.sortOrder != right.sortOrder {
            return left.sortOrder < right.sortOrder
        }
        let nameComparison = left.name.localizedCaseInsensitiveCompare(right.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return left.id < right.id
    }

    private static func nextSortOrder(parentID: String?, movingCategoryID: String, categories: [Category]) -> Int {
        let maxSortOrder = categories
            .filter { $0.parentID == parentID && $0.id != movingCategoryID }
            .map(\.sortOrder)
            .max() ?? 0
        return maxSortOrder + 10
    }
}
