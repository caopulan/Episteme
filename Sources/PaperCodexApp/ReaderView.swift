import PaperCodexCore
import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingSessionPapers = false
    @State private var isShowingSaveToLibrarySheet = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ReaderTabBar()
                .environmentObject(model)
            Divider()
            HSplitView {
                pdfPane
                    .frame(minWidth: 560)
                ChatView()
                    .frame(minWidth: 330, idealWidth: 420, maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isShowingSaveToLibrarySheet) {
            if let paper = model.selectedPaper {
                SaveToLibrarySheet(
                    paperTitle: paper.title,
                    detail: paper.authors.prefix(4).joined(separator: ", "),
                    libraryTags: model.tags,
                    suggestedTagNames: model.suggestedTagNames(for: paper),
                    onSave: { tagNames in
                        isShowingSaveToLibrarySheet = false
                        model.saveCachedPaperToLibrary(paper, selectedTagNames: tagNames)
                    },
                    onCancel: {
                        isShowingSaveToLibrarySheet = false
                    }
                )
            }
        }
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

            if let paper = model.selectedPaper, !paper.isSaved {
                Button {
                    isShowingSaveToLibrarySheet = true
                } label: {
                    Label("Save to Library", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                isShowingSessionPapers.toggle()
            } label: {
                Label(sessionPaperCountLabel, systemImage: "rectangle.stack")
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $isShowingSessionPapers, arrowEdge: .bottom) {
                SessionPapersPopover()
                    .environmentObject(model)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var sessionPaperCountLabel: String {
        let count = model.selectedSession?.paperIDs.count ?? 0
        return count == 1 ? "1 Paper" : "\(count) Papers"
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

private struct ReaderTabBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.readerTabState.tabs) { tab in
                    ReaderTabItem(
                        tab: tab,
                        isActive: model.selectedPaper?.id == tab.paperID
                            || model.readerTabState.activePaperID == tab.paperID
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .scrollIndicators(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ReaderTabItem: View {
    @EnvironmentObject private var model: AppModel
    var tab: ReaderPaperTab
    var isActive: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.selectReaderTab(tab)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isActive ? "doc.text.fill" : "doc.text")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

                    Text(tab.title)
                        .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if !tab.isSaved {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .help("Cached paper")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tab.detail.isEmpty ? tab.title : "\(tab.title)\n\(tab.detail)")

            Button {
                model.closeReaderTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isActive ? Color.secondary : Color.secondary.opacity(0.58))
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close tab")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(width: isActive ? 268 : 224, height: 34)
        .background(tabBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tabBorder, lineWidth: isActive ? 1.1 : 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(
            color: isHovering ? Color.black.opacity(0.12) : Color.black.opacity(0.04),
            radius: isHovering ? 6 : 2,
            x: 0,
            y: isHovering ? 2 : 1
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var tabBackground: Color {
        if isActive {
            return Color(nsColor: .textBackgroundColor)
        }
        return isHovering ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .windowBackgroundColor)
    }

    private var tabBorder: Color {
        if isActive {
            return Color.accentColor.opacity(0.38)
        }
        return isHovering ? Color.primary.opacity(0.16) : Color.primary.opacity(0.08)
    }
}

private struct SessionPapersPopover: View {
    @EnvironmentObject private var model: AppModel

    private var sessionPaperIDs: Set<String> {
        Set(model.selectedSession?.paperIDs ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Papers")
                .font(.headline)

            if model.papers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text")
                    .frame(width: 320, height: 160)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.papers) { paper in
                            SessionPaperRow(
                                paper: paper,
                                isIncluded: sessionPaperIDs.contains(paper.id),
                                isFocused: model.selectedPaper?.id == paper.id,
                                canRemove: sessionPaperIDs.count > 1
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(width: 360)
                .frame(maxHeight: 360)
            }
        }
        .padding(16)
    }
}

private struct SessionPaperRow: View {
    @EnvironmentObject private var model: AppModel
    var paper: Paper
    var isIncluded: Bool
    var isFocused: Bool
    var canRemove: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: Binding(
                get: { isIncluded },
                set: { isOn in
                    model.setPaper(paper, includedInCurrentSession: isOn)
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .disabled(isIncluded && !canRemove)

            VStack(alignment: .leading, spacing: 4) {
                Text(paper.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Text(paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isIncluded {
                Button {
                    model.selectReaderPaper(paper)
                } label: {
                    Image(systemName: isFocused ? "eye.fill" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isFocused ? "Reading" : "Read This Paper")
            }
        }
        .padding(8)
        .background(isFocused ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
