import Foundation

public struct PaperLibraryDerivedState: Equatable, Sendable {
    public static let empty = PaperLibraryDerivedState(
        categoryPaperCountsByID: [:],
        tagPaperCountsByID: [:],
        searchTextByPaperID: [:]
    )

    public var categoryPaperCountsByID: [String: Int]
    public var tagPaperCountsByID: [String: Int]
    public var searchTextByPaperID: [String: String]

    public static func build(
        papers: [Paper],
        categories: [Category],
        categoryIDsByPaperID: [String: [String]],
        tagsByPaperID: [String: [PaperTag]]
    ) -> PaperLibraryDerivedState {
        let categoryNamesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        var categoryCounts: [String: Int] = [:]
        var tagCounts: [String: Int] = [:]
        var searchText: [String: String] = [:]

        for paper in papers {
            let categoryIDs = categoryIDsByPaperID[paper.id, default: []]
            let paperTags = tagsByPaperID[paper.id, default: []]
            for categoryID in Set(categoryIDs) {
                categoryCounts[categoryID, default: 0] += 1
            }
            for tagID in Set(paperTags.map(\.id)) {
                tagCounts[tagID, default: 0] += 1
            }

            let categoryNames = categoryIDs.compactMap { categoryNamesByID[$0] }
            let components = [
                paper.id,
                paper.title,
                paper.authors.joined(separator: " "),
                paper.year.map(String.init) ?? "",
                paper.sourceURL ?? "",
                categoryNames.joined(separator: " "),
                paperTags.map(\.name).joined(separator: " ")
            ]
            searchText[paper.id] = components
                .joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
        }

        return PaperLibraryDerivedState(
            categoryPaperCountsByID: categoryCounts,
            tagPaperCountsByID: tagCounts,
            searchTextByPaperID: searchText
        )
    }

    public func matchesSearch(paperID: String, query: String) -> Bool {
        let terms = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else {
            return true
        }
        guard let haystack = searchTextByPaperID[paperID] else {
            return true
        }
        return terms.allSatisfy { haystack.contains($0) }
    }
}
