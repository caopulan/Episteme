import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                pdfPane
                    .frame(minWidth: 560)
                ChatView()
                    .frame(minWidth: 330, idealWidth: 380, maxWidth: 460)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                model.goToLibrary()
            } label: {
                Label("Library", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedPaper?.title ?? "Reader")
                    .font(.system(size: 18, weight: .semibold))
                Text(model.selectedPaper?.filePath ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var pdfPane: some View {
        ZStack {
            if let paper = model.selectedPaper {
                PDFKitView(filePath: paper.filePath, jumpTarget: model.pdfJumpTarget) { selection in
                    model.updateSelection(selection)
                }
            } else {
                ContentUnavailableView("No Paper Selected", systemImage: "doc.text")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
