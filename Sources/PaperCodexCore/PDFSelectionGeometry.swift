import Foundation
import PDFKit

public struct CapturedPDFSelection: Equatable, Sendable {
    public var text: String
    public var page: Int
    public var bboxList: [BoundingBox]

    public init(text: String, page: Int, bboxList: [BoundingBox]) {
        self.text = text
        self.page = page
        self.bboxList = bboxList
    }
}

public enum PDFSelectionGeometry {
    public static func capture(selection: PDFSelection, in document: PDFDocument) -> CapturedPDFSelection? {
        guard let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let page = selection.pages.first else {
            return nil
        }

        let pageIndex = document.index(for: page) + 1
        let lineBoxes = selection.selectionsByLine()
            .filter { lineSelection in
                lineSelection.pages.first === page
            }
            .map { lineSelection in
                lineSelection.bounds(for: page)
            }
            .filter { !$0.isNull && !$0.isEmpty }
            .map { rect in
                BoundingBox(
                    x: rect.origin.x,
                    y: rect.origin.y,
                    width: rect.width,
                    height: rect.height
                )
            }

        let boxes: [BoundingBox]
        if lineBoxes.isEmpty {
            let rect = selection.bounds(for: page)
            boxes = rect.isNull || rect.isEmpty ? [] : [
                BoundingBox(
                    x: rect.origin.x,
                    y: rect.origin.y,
                    width: rect.width,
                    height: rect.height
                )
            ]
        } else {
            boxes = lineBoxes
        }

        return CapturedPDFSelection(text: text, page: pageIndex, bboxList: boxes)
    }
}
