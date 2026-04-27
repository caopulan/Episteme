import Foundation

public struct AnchorResolver: Sendable {
    public init() {}

    public func resolve(
        paperID: String,
        page: Int,
        selectedText: String,
        bboxList: [BoundingBox],
        spans: [Span],
        anchorID: String,
        sessionID: String,
        createdAt: Date
    ) -> Anchor? {
        let pageSpans = spans
            .filter { $0.paperID == paperID && $0.page == page }
            .sorted { left, right in
                if left.charRange.location == right.charRange.location {
                    return left.id < right.id
                }
                return left.charRange.location < right.charRange.location
            }

        let scoredMatches = pageSpans.compactMap { span -> (span: Span, score: Double)? in
            let score = matchScore(span: span, selectedText: selectedText, bboxList: bboxList)
            return score > 0 ? (span, score) : nil
        }
        let matchedSpans = scoredMatches
            .sorted { left, right in
                if left.score == right.score {
                    return left.span.charRange.location < right.span.charRange.location
                }
                return left.score > right.score
            }
            .map(\.span)

        guard !matchedSpans.isEmpty else {
            return nil
        }

        let contextIndexes = matchedSpans.compactMap { match in
            pageSpans.firstIndex { $0.id == match.id }
        }
        let beforeContext = contextIndexes.min().flatMap { index in
            index > 0 ? pageSpans[index - 1].text : nil
        } ?? ""
        let afterContext = contextIndexes.max().flatMap { index in
            index + 1 < pageSpans.count ? pageSpans[index + 1].text : nil
        } ?? ""

        let best = scoredMatches.map(\.score).max() ?? 0
        let confidence = min(0.98, max(0.55, best))

        return Anchor(
            id: anchorID,
            paperID: paperID,
            page: page,
            selectedText: selectedText,
            bboxList: bboxList,
            matchedSpanIDs: matchedSpans.map(\.id),
            beforeContext: beforeContext,
            afterContext: afterContext,
            createdSessionID: sessionID,
            createdAt: createdAt,
            confidence: confidence
        )
    }

    private func matchScore(span: Span, selectedText: String, bboxList: [BoundingBox]) -> Double {
        let selected = normalized(selectedText)
        let spanText = normalized(span.text)
        let textScore: Double
        if selected.isEmpty || spanText.isEmpty {
            textScore = 0
        } else if spanText.contains(selected) || selected.contains(spanText) {
            textScore = 0.65
        } else {
            textScore = tokenOverlapScore(left: selected, right: spanText) * 0.55
        }

        let overlapScore = bboxList
            .map { intersectionRatio($0, span.bbox) }
            .max() ?? 0

        let geometryScore = overlapScore > 0 ? min(0.35, overlapScore * 0.35) : 0
        let score = textScore + geometryScore
        return score >= 0.18 ? score : 0
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func tokenOverlapScore(left: String, right: String) -> Double {
        let leftTokens = Set(left.split(separator: " ").map(String.init))
        let rightTokens = Set(right.split(separator: " ").map(String.init))
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else {
            return 0
        }
        let shared = leftTokens.intersection(rightTokens).count
        return Double(shared) / Double(min(leftTokens.count, rightTokens.count))
    }

    private func intersectionRatio(_ lhs: BoundingBox, _ rhs: BoundingBox) -> Double {
        let left = max(lhs.x, rhs.x)
        let right = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let bottom = max(lhs.y, rhs.y)
        let top = min(lhs.y + lhs.height, rhs.y + rhs.height)
        let width = max(0, right - left)
        let height = max(0, top - bottom)
        let intersection = width * height
        let lhsArea = max(0, lhs.width * lhs.height)
        guard lhsArea > 0 else {
            return 0
        }
        return intersection / lhsArea
    }
}
