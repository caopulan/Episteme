import PDFKit
import PaperCodexCore
import SwiftUI

struct PDFKitView: NSViewRepresentable {
    var filePath: String
    var jumpTarget: PDFJumpTarget?
    var onSelection: (PDFSelectionInfo?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .textBackgroundColor
        context.coordinator.pdfView = view
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: view
        )
        loadDocument(in: view)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL?.path != filePath {
            loadDocument(in: nsView)
            context.coordinator.clearHighlights()
        }
        context.coordinator.onSelection = onSelection
        context.coordinator.applyJumpTarget(jumpTarget)
    }

    private func loadDocument(in view: PDFView) {
        view.document = PDFDocument(url: URL(fileURLWithPath: filePath))
    }

    final class Coordinator: NSObject {
        weak var pdfView: PDFView?
        var onSelection: (PDFSelectionInfo?) -> Void
        private var highlightedAnnotations: [(PDFPage, PDFAnnotation)] = []
        private var lastJumpTarget: PDFJumpTarget?

        init(onSelection: @escaping (PDFSelectionInfo?) -> Void) {
            self.onSelection = onSelection
        }

        @MainActor
        func applyJumpTarget(_ target: PDFJumpTarget?) {
            guard target != lastJumpTarget else {
                return
            }
            lastJumpTarget = target
            clearHighlights()

            guard let target,
                  let pdfView,
                  let document = pdfView.document,
                  let page = document.page(at: target.page - 1) else {
                return
            }

            let boxes = target.bboxList.filter { $0.width > 0 && $0.height > 0 }
            for box in boxes {
                let annotation = PDFAnnotation(
                    bounds: CGRect(x: box.x, y: box.y, width: box.width, height: box.height),
                    forType: .highlight,
                    withProperties: nil
                )
                annotation.color = NSColor.systemYellow.withAlphaComponent(0.45)
                page.addAnnotation(annotation)
                highlightedAnnotations.append((page, annotation))
            }

            if let first = boxes.first {
                let point = NSPoint(x: first.x, y: first.y + first.height)
                pdfView.go(to: PDFDestination(page: page, at: point))
            } else {
                pdfView.go(to: page)
            }
        }

        @MainActor
        func clearHighlights() {
            for (page, annotation) in highlightedAnnotations {
                page.removeAnnotation(annotation)
            }
            highlightedAnnotations.removeAll()
        }

        @MainActor
        @objc func selectionChanged(_ notification: Notification) {
            guard let pdfView,
                  let selection = pdfView.currentSelection,
                  let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty,
                  let page = selection.pages.first,
                  let document = pdfView.document else {
                onSelection(nil)
                return
            }

            let pageIndex = document.index(for: page) + 1
            let rect = selection.bounds(for: page)
            onSelection(PDFSelectionInfo(
                text: text,
                page: pageIndex,
                bbox: BoundingBox(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
            ))
        }
    }
}
