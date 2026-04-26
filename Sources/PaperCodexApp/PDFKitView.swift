import PDFKit
import PaperCodexCore
import SwiftUI

struct PDFKitView: NSViewRepresentable {
    var filePath: String
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
        }
        context.coordinator.onSelection = onSelection
    }

    private func loadDocument(in view: PDFView) {
        view.document = PDFDocument(url: URL(fileURLWithPath: filePath))
    }

    final class Coordinator: NSObject {
        weak var pdfView: PDFView?
        var onSelection: (PDFSelectionInfo?) -> Void

        init(onSelection: @escaping (PDFSelectionInfo?) -> Void) {
            self.onSelection = onSelection
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
