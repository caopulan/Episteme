import Foundation

public struct UserSourceAttachment: Codable, Equatable, Sendable {
    public var anchorID: String
    public var paperID: String
    public var page: Int
    public var selectedText: String

    public init(anchorID: String, paperID: String, page: Int, selectedText: String) {
        self.anchorID = anchorID
        self.paperID = paperID
        self.page = page
        self.selectedText = selectedText
    }
}

public struct ParsedUserSourceMessage: Codable, Equatable, Sendable {
    public var visibleContent: String
    public var attachment: UserSourceAttachment?

    public init(visibleContent: String, attachment: UserSourceAttachment?) {
        self.visibleContent = visibleContent
        self.attachment = attachment
    }
}

public enum UserSourceAttachmentParser {
    private static let marker = "[selected source]"

    public static func parse(_ content: String) -> ParsedUserSourceMessage {
        guard let markerRange = content.range(of: marker) else {
            return ParsedUserSourceMessage(visibleContent: content, attachment: nil)
        }

        let visibleContent = String(content[..<markerRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = String(content[markerRange.upperBound...])

        guard let anchorID = lineValue(named: "anchor_id", in: metadata),
              let paperID = lineValue(named: "paper_id", in: metadata),
              let pageText = lineValue(named: "page", in: metadata),
              let page = Int(pageText),
              let selectedText = selectedTextValue(in: metadata) else {
            return ParsedUserSourceMessage(visibleContent: content, attachment: nil)
        }

        return ParsedUserSourceMessage(
            visibleContent: visibleContent,
            attachment: UserSourceAttachment(
                anchorID: anchorID,
                paperID: paperID,
                page: page,
                selectedText: selectedText
            )
        )
    }

    private static func lineValue(named name: String, in metadata: String) -> String? {
        let prefix = "\(name):"
        for rawLine in metadata.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(prefix) else {
                continue
            }
            return String(line.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func selectedTextValue(in metadata: String) -> String? {
        guard let textRange = metadata.range(of: "text:") else {
            return nil
        }
        let valueStart = metadata[textRange.upperBound...]
            .drop(while: { $0 == " " || $0 == "\t" })
            .startIndex
        let searchStart = valueStart
        let endRange = metadata[searchStart...].range(of: "\nnearby_spans:")
        let valueEnd = endRange?.lowerBound ?? metadata.endIndex
        var value = String(metadata[valueStart..<valueEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\"") {
            value.removeFirst()
        }
        if value.hasSuffix("\"") {
            value.removeLast()
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
