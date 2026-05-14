import Foundation

public enum ArxivIDExtractor {
    private static let versionedIDRegex = try! NSRegularExpression(
        pattern: #"(?i)(?:arxiv:\s*|arxiv\.org/(?:abs|pdf|html)/)?((?:\d{4}\.\d{4,5})|(?:[a-z-]+(?:\.[a-z-]+)?/\d{7}))(v\d+)?(?:\.pdf)?"#
    )
    private static let versionSuffixRegex = try! NSRegularExpression(pattern: #"(?i)v\d+$"#)

    public static func extractVersionedIDs(from text: String) -> [String] {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var seenCanonicalIDs: Set<String> = []
        var ids: [String] = []
        for match in versionedIDRegex.matches(in: text, range: nsRange) {
            guard let idRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let rawID = String(text[idRange])
            let version = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            let versionedID = "\(rawID)\(version)"
            let canonicalID = canonicalID(from: versionedID)
            let key = canonicalID.lowercased()
            guard !seenCanonicalIDs.contains(key) else {
                continue
            }
            seenCanonicalIDs.insert(key)
            ids.append(versionedID)
        }
        return ids
    }

    public static func extractCanonicalIDs(from text: String) -> [String] {
        extractVersionedIDs(from: text).map(canonicalID(from:))
    }

    public static func firstCanonicalID(in text: String) -> String? {
        extractCanonicalIDs(from: text).first
    }

    public static func canonicalID(from id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return versionSuffixRegex.stringByReplacingMatches(
            in: trimmed,
            range: range,
            withTemplate: ""
        )
    }
}
