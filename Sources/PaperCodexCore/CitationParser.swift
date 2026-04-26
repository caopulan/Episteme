import Foundation

public struct SourceCitation: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var marker: String
    public var displayIndex: Int

    public init(id: String, marker: String, displayIndex: Int) {
        self.id = id
        self.marker = marker
        self.displayIndex = displayIndex
    }
}

public struct ParsedCitationText: Codable, Equatable, Sendable {
    public var displayText: String
    public var citations: [SourceCitation]
    public var brokenMarkers: [String]

    public init(displayText: String, citations: [SourceCitation], brokenMarkers: [String]) {
        self.displayText = displayText
        self.citations = citations
        self.brokenMarkers = brokenMarkers
    }
}

public enum CitationParser {
    public static func parse(_ text: String) -> ParsedCitationText {
        var output = ""
        var citations: [SourceCitation] = []
        var brokenMarkers: [String] = []
        var cursor = text.startIndex

        while let start = text[cursor...].range(of: "[[cite:")?.lowerBound {
            output.append(contentsOf: text[cursor..<start])
            guard let end = text[start...].range(of: "]]")?.upperBound else {
                let marker = String(text[start...])
                brokenMarkers.append(marker)
                output.append(marker)
                cursor = text.endIndex
                break
            }

            let marker = String(text[start..<end])
            let citationIDStart = text.index(start, offsetBy: 7)
            let citationIDEnd = text.index(end, offsetBy: -2)
            let citationID = String(text[citationIDStart..<citationIDEnd])

            if isValidCitationID(citationID) {
                let displayIndex = citations.count + 1
                citations.append(SourceCitation(id: citationID, marker: marker, displayIndex: displayIndex))
                output.append("[\(displayIndex)]")
            } else {
                brokenMarkers.append(marker)
                output.append(marker)
            }
            cursor = end
        }

        output.append(contentsOf: text[cursor...])
        return ParsedCitationText(displayText: output, citations: citations, brokenMarkers: brokenMarkers)
    }

    private static func isValidCitationID(_ id: String) -> Bool {
        let parts = id.split(separator: ":").map(String.init)
        guard parts.count == 4 else {
            return false
        }
        guard parts[0] == "paper" else {
            return false
        }
        guard parts[2].first == "p", Int(parts[2].dropFirst()) != nil else {
            return false
        }
        return parts[3].first == "b" || parts[3].first == "a"
    }
}
