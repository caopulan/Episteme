import Foundation

public enum DiscoverSaveCategorySuggestion {
    public static func categoryIDs(
        fromExplicitSimilaritySourceIDs sourceIDs: [String],
        existingCategoryIDs: Set<String>
    ) -> [String] {
        let normalizedSources = normalizedIdentifiers(sourceIDs)
        guard normalizedSources.count == 1,
              let sourceID = normalizedSources.first,
              sourceID.hasPrefix("category:") else {
            return []
        }

        let categoryID = String(sourceID.dropFirst("category:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !categoryID.isEmpty, existingCategoryIDs.contains(categoryID) else {
            return []
        }
        return [categoryID]
    }

    private static func normalizedIdentifiers(_ values: [String]) -> [String] {
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
}
