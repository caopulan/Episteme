import Foundation
import PDFKit

public struct PDFIndexResult: Equatable, Sendable {
    public var pages: [PageIndex]
    public var spans: [Span]

    public init(pages: [PageIndex], spans: [Span]) {
        self.pages = pages
        self.spans = spans
    }
}

public enum PDFIndexExtractorError: Error, CustomStringConvertible, Equatable {
    case cannotOpenPDF(String)
    case noTextLayer(String)

    public var description: String {
        switch self {
        case let .cannotOpenPDF(path):
            "Could not open PDF at \(path)"
        case let .noTextLayer(path):
            "PDF has no usable text layer: \(path)"
        }
    }
}

public struct PDFIndexExtractor: Sendable {
    public init() {}

    public func extract(paperID: String, pdfURL: URL) throws -> PDFIndexResult {
        guard let document = PDFDocument(url: pdfURL) else {
            throw PDFIndexExtractorError.cannotOpenPDF(pdfURL.path)
        }

        var pages: [PageIndex] = []
        var spans: [Span] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }
            let pageNumber = pageIndex + 1
            let pageText = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if pageText.isEmpty {
                continue
            }

            pages.append(PageIndex(paperID: paperID, page: pageNumber, text: pageText, confidence: 1.0))
            let lines = pageText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let nsText = pageText as NSString
            var searchStart = 0
            for (lineIndex, line) in lines.enumerated() {
                let searchRange = NSRange(location: searchStart, length: max(0, nsText.length - searchStart))
                let foundRange = nsText.range(of: line, options: [], range: searchRange)
                let charRange = foundRange.location == NSNotFound
                    ? TextRange(location: 0, length: line.count)
                    : TextRange(location: foundRange.location, length: foundRange.length)
                if foundRange.location != NSNotFound {
                    searchStart = foundRange.location + foundRange.length
                }

                let bbox = bounds(for: page, range: NSRange(location: charRange.location, length: charRange.length))
                spans.append(Span(
                    id: Span.makeID(paperID: paperID, page: pageNumber, blockIndex: lineIndex + 1),
                    paperID: paperID,
                    page: pageNumber,
                    bbox: bbox,
                    text: line,
                    charRange: charRange,
                    sectionHint: nil,
                    confidence: bbox.width > 0 && bbox.height > 0 ? 0.95 : 0.65
                ))
            }
        }

        if pages.isEmpty {
            throw PDFIndexExtractorError.noTextLayer(pdfURL.path)
        }
        return PDFIndexResult(pages: pages, spans: spans)
    }

    private func bounds(for page: PDFPage, range: NSRange) -> BoundingBox {
        if let selection = page.selection(for: range) {
            let rect = selection.bounds(for: page)
            if rect.width > 0 && rect.height > 0 {
                return BoundingBox(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
            }
        }

        let fallback = page.bounds(for: .mediaBox)
        return BoundingBox(x: fallback.origin.x, y: fallback.origin.y, width: fallback.width, height: fallback.height)
    }
}
