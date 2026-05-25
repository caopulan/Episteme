import Foundation

public struct LibraryCategoryRequest: Equatable, Identifiable, Sendable {
    public var id: String
    public var parentID: String?
    public var name: String

    public init(id: String, parentID: String?, name: String) {
        self.id = id
        self.parentID = parentID
        self.name = name
    }
}

public enum LibraryCategoryAssignmentError: Error, CustomStringConvertible, Equatable {
    case emptyName
    case categoryNotFound(String)
    case invalidCategoryHierarchy

    public var description: String {
        switch self {
        case .emptyName:
            "Folder name is empty."
        case let .categoryNotFound(categoryID):
            "Folder was not found: \(categoryID)."
        case .invalidCategoryHierarchy:
            "Folder hierarchy is invalid."
        }
    }
}

public struct LibraryCategoryAssigner {
    public typealias IDFactory = (_ prefix: String, _ name: String) -> String

    private let idFactory: IDFactory

    public init(idFactory: @escaping IDFactory = LibraryCategoryAssigner.defaultID(prefix:name:)) {
        self.idFactory = idFactory
    }

    public func assign(
        paperID: String,
        existingCategoryIDs: [String],
        newCategoryNames: [String],
        newCategories: [LibraryCategoryRequest],
        repository: PaperRepository,
        onCategoryCreated: ((Category) -> Void)? = nil
    ) throws {
        var categories = try repository.fetchCategories()
        let existingIDs = Set(categories.map(\.id))

        for categoryID in normalizedIdentifiers(existingCategoryIDs) where existingIDs.contains(categoryID) {
            try repository.assignPaper(paperID, toCategory: categoryID)
        }

        let requests = normalizedRequests(newCategories)
        var createdCategoryIDsByRequestID: [String: String] = [:]

        func createCategory(from request: LibraryCategoryRequest, stack: Set<String> = []) throws -> Category {
            if let categoryID = createdCategoryIDsByRequestID[request.id],
               let category = categories.first(where: { $0.id == categoryID }) {
                return category
            }
            guard !stack.contains(request.id) else {
                throw LibraryCategoryAssignmentError.invalidCategoryHierarchy
            }

            let resolvedParentID: String?
            if let parentID = request.parentID {
                if existingIDs.contains(parentID) || categories.contains(where: { $0.id == parentID }) {
                    resolvedParentID = parentID
                } else if let parentRequest = requests.first(where: { $0.id == parentID }) {
                    resolvedParentID = try createCategory(from: parentRequest, stack: stack.union([request.id])).id
                } else {
                    throw LibraryCategoryAssignmentError.categoryNotFound(parentID)
                }
            } else {
                resolvedParentID = nil
            }

            let category = try ensureCategory(
                named: request.name,
                parentID: resolvedParentID,
                repository: repository,
                categories: &categories,
                onCategoryCreated: onCategoryCreated
            )
            createdCategoryIDsByRequestID[request.id] = category.id
            return category
        }

        for request in requests {
            let category = try createCategory(from: request)
            try repository.assignPaper(paperID, toCategory: category.id)
        }

        for name in normalizedNames(newCategoryNames) {
            let category = try ensureCategory(
                named: name,
                parentID: nil,
                repository: repository,
                categories: &categories,
                onCategoryCreated: onCategoryCreated
            )
            try repository.assignPaper(paperID, toCategory: category.id)
        }
    }

    private func ensureCategory(
        named name: String,
        parentID: String?,
        repository: PaperRepository,
        categories: inout [Category],
        onCategoryCreated: ((Category) -> Void)?
    ) throws -> Category {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LibraryCategoryAssignmentError.emptyName
        }
        if let existing = categories.first(where: { category in
            category.parentID == parentID
                && category.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    == trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }) {
            return existing
        }

        let category = Category(
            id: uniqueID(prefix: "cat", name: trimmed, categories: categories),
            parentID: parentID,
            name: trimmed,
            sortOrder: (categories.map(\.sortOrder).max() ?? 0) + 1
        )
        try repository.upsertCategory(category)
        categories.append(category)
        onCategoryCreated?(category)
        return category
    }

    private func uniqueID(prefix: String, name: String, categories: [Category]) -> String {
        let baseID = idFactory(prefix, name)
        let existingIDs = Set(categories.map(\.id))
        guard existingIDs.contains(baseID) else {
            return baseID
        }
        var suffix = 2
        while existingIDs.contains("\(baseID)-\(suffix)") {
            suffix += 1
        }
        return "\(baseID)-\(suffix)"
    }

    public static func defaultID(prefix: String, name: String) -> String {
        let slug = slug(from: name)
        return "\(prefix)-\(slug.isEmpty ? "item" : slug)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private static func slug(from text: String) -> String {
        var slug = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                slug.append(character)
            } else if slug.last != "-" {
                slug.append("-")
            }
        }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func normalizedRequests(_ values: [LibraryCategoryRequest]) -> [LibraryCategoryRequest] {
        var result: [LibraryCategoryRequest] = []
        var seenIDs: Set<String> = []
        for value in values {
            let id = value.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let parentID = value.parentID?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !name.isEmpty, !seenIDs.contains(id) else {
                continue
            }
            seenIDs.insert(id)
            result.append(
                LibraryCategoryRequest(
                    id: id,
                    parentID: parentID?.isEmpty == false ? parentID : nil,
                    name: name
                )
            )
        }
        return result
    }

    private func normalizedIdentifiers(_ values: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    private func normalizedNames(_ values: [String]) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            names.append(trimmed)
        }
        return names
    }
}
