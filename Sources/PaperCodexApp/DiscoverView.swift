import AppKit
import PaperCodexCore
import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var selectedTag: String?
    @State private var paperPendingSave: ArxivFeedPaper?
    @State private var previewPaper: ArxivFeedPaper?

    private var papers: [ArxivFeedPaper] {
        var result = model.arxivFeed?.papers ?? []
        if let selectedCategory {
            result = result.filter {
                $0.categories.contains(selectedCategory) || $0.listCategories.contains(selectedCategory)
            }
        }
        if let selectedTag {
            result = result.filter { $0.tags.contains(selectedTag) }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { paper in
                paper.displayTitle(language: "zh").localizedCaseInsensitiveContains(query)
                    || paper.displayTitle(language: "en").localizedCaseInsensitiveContains(query)
                    || paper.authors.joined(separator: " ").localizedCaseInsensitiveContains(query)
                    || paper.tags.joined(separator: " ").localizedCaseInsensitiveContains(query)
                    || paper.id.localizedCaseInsensitiveContains(query)
            }
        }
        return result
    }

    private var categories: [String] {
        let all = (model.arxivFeed?.papers ?? []).flatMap { $0.listCategories.isEmpty ? $0.categories : $0.listCategories }
        return Array(Set(all)).sorted()
    }

    private var tags: [String] {
        let counts = tagCounts
        return counts.keys.sorted { left, right in
            let leftCount = counts[left, default: 0]
            let rightCount = counts[right, default: 0]
            if leftCount == rightCount {
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
            return leftCount > rightCount
        }
    }

    private var tagCounts: [String: Int] {
        Dictionary((model.arxivFeed?.papers ?? []).flatMap(\.tags).map { ($0, 1) }, uniquingKeysWith: +)
    }

    var body: some View {
        mainLayout
            .overlay {
                if let previewPaper {
                    ArxivImagePreviewOverlay(paper: previewPaper) {
                        self.previewPaper = nil
                    }
                    .environmentObject(model)
                }
            }
            .sheet(item: $paperPendingSave) { paper in
                SaveToLibrarySheet(
                    paperTitle: paper.displayTitle(language: "zh"),
                    detail: paper.authors.prefix(4).joined(separator: ", "),
                    libraryTags: model.tags,
                    suggestedTagNames: model.suggestedTagNames(for: paper),
                    onSave: { tagNames in
                        paperPendingSave = nil
                        Task {
                            await model.addArxivPaperToLibrary(paper, selectedTagNames: tagNames)
                        }
                    },
                    onCancel: {
                        paperPendingSave = nil
                    }
                )
            }
    }

    private var mainLayout: some View {
        SidebarSplitLayout(minContentWidth: 720) {
            sidebar
        } content: {
            feed
                .frame(minWidth: 760, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            guard model.arxivFeed == nil, !model.isLoadingArxivFeed else {
                return
            }
            Task {
                await model.refreshArxivDatesAndFeed()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Codex")
                .font(.system(size: 24, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                navButton(title: "Library", systemImage: "books.vertical") {
                    model.goToLibrary()
                }
                navButton(title: "Discover", systemImage: "sparkle.magnifyingglass", selected: true) {}
                navButton(title: "Settings", systemImage: "gearshape") {
                    model.showSettings()
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Categories", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.headline)
                        filterButton(title: "All", selected: selectedCategory == nil && selectedTag == nil) {
                            selectedCategory = nil
                            selectedTag = nil
                        }
                        ForEach(categories, id: \.self) { category in
                            filterButton(title: category, selected: selectedCategory == category) {
                                selectedCategory = category
                                selectedTag = nil
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Tags", systemImage: "tag")
                            .font(.headline)
                        filterButton(
                            title: "All Tags",
                            detail: "\(tagCounts.values.reduce(0, +))",
                            selected: selectedTag == nil
                        ) {
                            selectedTag = nil
                        }
                        ForEach(tags.prefix(18), id: \.self) { tag in
                            filterButton(
                                title: tag,
                                detail: "\(tagCounts[tag, default: 0])",
                                selected: selectedTag == tag
                            ) {
                                selectedTag = tag
                                selectedCategory = nil
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbar

            if model.isLoadingArxivFeed && model.arxivFeed == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if papers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    ScrollView {
                        LazyVGrid(
                            columns: gridColumns(for: proxy.size.width),
                            alignment: .leading,
                            spacing: 14
                        ) {
                            ForEach(papers) { paper in
                                ArxivPaperCard(
                                    paper: paper,
                                    imageURL: model.cachedArxivAssetURL(for: paper.assets.small),
                                    inLibrary: model.libraryPaper(for: paper) != nil,
                                    isBusy: model.isDownloadingArxivPaper(paper),
                                    downloadProgress: model.arxivDownloadProgress(for: paper),
                                    onPreview: {
                                        previewPaper = paper
                                    },
                                    onSave: {
                                        paperPendingSave = paper
                                    },
                                    onOpen: {
                                        Task {
                                            await model.openArxivPaper(paper)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let count: Int
        if width >= 1280 {
            count = 3
        } else if width >= 700 {
            count = 2
        } else {
            count = 1
        }
        return Array(
            repeating: GridItem(.flexible(minimum: 320), spacing: 16, alignment: .top),
            count: count
        )
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily arXiv")
                        .font(.system(size: 28, weight: .semibold))
                    Text("\(model.arxivFeed?.count ?? 0) papers · \(model.selectedArxivDate ?? "No date")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Search title, author, tag, arXiv ID", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .layoutPriority(-1)

                HStack(spacing: 8) {
                    DateMenuButton()
                        .environmentObject(model)

                    ArxivSourceBadge()

                    ToolbarActionButton(title: "Refresh", systemImage: "arrow.clockwise", tint: .blue) {
                        Task {
                            await model.refreshArxivDatesAndFeed()
                        }
                    }

                    ToolbarActionButton(
                        title: model.isPreloadingArxivAssets ? "Loading" : "Thumbs",
                        systemImage: "photo.on.rectangle.angled",
                        tint: .teal,
                        disabled: model.arxivFeed == nil || model.isPreloadingArxivAssets
                    ) {
                        Task {
                            await model.preloadArxivAssets(includeLarge: false)
                        }
                    }

                    ToolbarActionButton(
                        title: "Full Images",
                        systemImage: "photo.stack",
                        tint: .indigo,
                        disabled: model.arxivFeed == nil || model.isPreloadingArxivAssets
                    ) {
                        Task {
                            await model.preloadArxivAssets(includeLarge: true)
                        }
                    }

                    Spacer()
                }

                if let progress = model.arxivCacheProgress {
                    ArxivCacheProgressStrip(progress: progress)
                }
            }
        }
    }

    private func navButton(title: String, systemImage: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        SidebarRowButton(title: title, systemImage: systemImage, selected: selected, action: action)
    }

    private func filterButton(title: String, detail: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        SidebarFilterButton(title: title, detail: detail, selected: selected, action: action)
    }
}

private struct SidebarFilterButton: View {
    @State private var isHovering = false

    var title: String
    var detail: String?
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                Text(title)
                    .lineLimit(1)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: isHovering ? Color.black.opacity(0.06) : .clear, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.12) : (isHovering ? Color(nsColor: .textBackgroundColor) : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovering ? Color.accentColor.opacity(0.20) : Color.clear, lineWidth: 1)
            )
    }
}

private struct ArxivSourceBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("ar")
                .font(.system(size: 11, weight: .bold, design: .serif))
            Text("Xiv")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color(nsColor: .systemRed))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .systemRed).opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .systemRed).opacity(0.24), lineWidth: 1)
                )
        )
        .help("Daily arXiv source")
    }
}

private struct ToolbarActionButton: View {
    @State private var isHovering = false

    var title: String
    var systemImage: String
    var tint: Color
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(disabled ? Color.secondary.opacity(0.55) : (isHovering ? tint : Color.primary.opacity(0.82)))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(disabled ? Color(nsColor: .controlBackgroundColor).opacity(0.55) : (isHovering ? tint.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(disabled ? Color.black.opacity(0.06) : (isHovering ? tint.opacity(0.45) : Color.black.opacity(0.10)), lineWidth: 1)
                        )
                )
                .shadow(color: isHovering && !disabled ? tint.opacity(0.18) : .clear, radius: 7, y: 3)
                .scaleEffect(isHovering && !disabled ? 1.035 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(title)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct DateMenuButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var isHovering = false

    var body: some View {
        Menu {
            Button {
                Task {
                    await model.refreshArxivDates()
                }
            } label: {
                Label(model.isRefreshingArxivDates ? "Refreshing dates" : "Refresh dates", systemImage: "arrow.clockwise")
            }
            Divider()
            ForEach(Array(model.arxivDates.reversed()), id: \.self) { date in
                Button {
                    Task {
                        await model.loadArxivFeed(date: date)
                    }
                } label: {
                    if date == model.selectedArxivDate {
                        Label(date, systemImage: "checkmark")
                    } else {
                        Text(date)
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: model.isRefreshingArxivDates ? "arrow.clockwise.circle" : "calendar")
                Text(model.selectedArxivDate ?? "Date")
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(isHovering ? Color.accentColor : Color.primary.opacity(0.84))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.accentColor.opacity(0.11) : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isHovering ? Color.accentColor.opacity(0.36) : Color.black.opacity(0.10), lineWidth: 1)
                    )
            )
            .shadow(color: isHovering ? Color.accentColor.opacity(0.14) : .clear, radius: 7, y: 3)
            .scaleEffect(isHovering ? 1.025 : 1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Choose feed date")
        .simultaneousGesture(TapGesture().onEnded {
            Task {
                await model.refreshArxivDates()
            }
        })
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct ArxivCacheProgressStrip: View {
    var progress: ArxivCacheProgress

    var body: some View {
        HStack(spacing: 10) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .frame(width: 150)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 150)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(progress.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(progress.date)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct ArxivPaperCard: View {
    @State private var isHovering = false

    var paper: ArxivFeedPaper
    var imageURL: URL?
    var inLibrary: Bool
    var isBusy: Bool
    var downloadProgress: Double?
    var onPreview: () -> Void
    var onSave: () -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onPreview()
            } label: {
                ArxivPreviewImage(url: imageURL)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(paper.assets.large == nil && paper.assets.small == nil)
            .help("Open image preview")

            VStack(alignment: .leading, spacing: 10) {
                metadataRow

                Text(paper.displayTitle(language: "zh"))
                    .font(.system(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(paper.title.en)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(paper.displaySummary(language: "zh"))
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                FlowTags(tags: Array(paper.tags.prefix(5)))

                HStack(alignment: .bottom, spacing: 8) {
                    ResourceLinkButtons(links: paper.externalLinks, compact: true)
                        .layoutPriority(0)
                    Spacer(minLength: 10)
                    if isBusy {
                        ProgressView(value: downloadProgress)
                            .frame(width: 78)
                    }
                    if inLibrary {
                        SavedActionBadge()
                    } else {
                        SaveActionButton(isBusy: isBusy, action: onSave)
                    }
                    StableOpenButton(isBusy: isBusy, action: onOpen)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovering ? Color.accentColor.opacity(0.36) : Color.black.opacity(0.08), lineWidth: isHovering ? 1.3 : 1)
        )
        .shadow(color: isHovering ? Color.black.opacity(0.15) : Color.black.opacity(0.035), radius: isHovering ? 14 : 2, y: isHovering ? 7 : 1)
        .scaleEffect(isHovering ? 1.008 : 1)
        .offset(y: isHovering ? -1 : 0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
    }

    private var metadataRow: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                MetadataPill(
                    title: paper.primaryCategory ?? paper.categories.first ?? "arXiv",
                    foreground: .teal,
                    background: Color.teal.opacity(0.12)
                )
                ArxivIDPill(id: paper.id)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if let similarity = paper.similarity {
                SimilarityMeter(value: similarity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetadataPill: View {
    var title: String
    var foreground: Color
    var background: Color

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 23)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ArxivIDPill: View {
    var id: String

    var body: some View {
        Text(id)
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(height: 23)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .help("arXiv ID")
    }
}

private struct SavedActionBadge: View {
    var body: some View {
        Label("Saved", systemImage: "checkmark.seal.fill")
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .foregroundStyle(Color(nsColor: .systemGreen))
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .systemGreen).opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(nsColor: .systemGreen).opacity(0.34), lineWidth: 1)
                    )
            )
            .help("Already in Library")
            .fixedSize()
            .layoutPriority(1)
    }
}

private struct SaveActionButton: View {
    @State private var isHovering = false

    var isBusy: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add", systemImage: "tray.and.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .foregroundStyle(isBusy ? Color.secondary.opacity(0.6) : (isHovering ? Color(nsColor: .systemGreen) : Color.primary.opacity(0.86)))
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovering && !isBusy ? Color(nsColor: .systemGreen).opacity(0.13) : Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(isHovering && !isBusy ? Color(nsColor: .systemGreen).opacity(0.44) : Color.black.opacity(0.12), lineWidth: 1)
                        )
                )
                .shadow(color: isHovering && !isBusy ? Color(nsColor: .systemGreen).opacity(0.18) : .clear, radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help("Add to Library")
        .fixedSize()
        .layoutPriority(1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct StableOpenButton: View {
    @State private var isHovering = false

    var isBusy: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Open", systemImage: "book")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(isBusy ? Color.gray.opacity(0.55) : (isHovering ? Color(nsColor: .systemBlue).opacity(0.92) : Color(nsColor: .systemBlue)))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .shadow(color: isHovering && !isBusy ? Color(nsColor: .systemBlue).opacity(0.26) : .clear, radius: 8, y: 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.65 : 1)
        .help("Open in reader")
        .fixedSize()
        .layoutPriority(2)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct SimilarityMeter: View {
    var value: Double

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }

    private var color: Color {
        if clampedValue >= 0.78 {
            return .green
        }
        if clampedValue >= 0.62 {
            return .blue
        }
        return .orange
    }

    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.16))
                Capsule()
                    .fill(color)
                    .frame(width: 34 * clampedValue)
            }
            .frame(width: 34, height: 5)
            Text("\(Int((clampedValue * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help("Similarity score")
    }
}

private struct ArxivPreviewImage: View {
    var url: URL?

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(imageAspectRatio(image), contentMode: .fit)
            } else {
                ZStack {
                    Color(nsColor: .separatorColor).opacity(0.22)
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
                .aspectRatio(4.7, contentMode: .fit)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func imageAspectRatio(_ image: NSImage) -> CGFloat {
        guard image.size.width > 0, image.size.height > 0 else {
            return 4.7
        }
        return image.size.width / image.size.height
    }
}

private struct ArxivImagePreviewOverlay: View {
    @EnvironmentObject private var model: AppModel
    var paper: ArxivFeedPaper
    var onDismiss: () -> Void

    private var imageURL: URL? {
        model.cachedArxivAssetURL(for: paper.assets.large) ?? model.cachedArxivAssetURL(for: paper.assets.small)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.56)
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
                }
            if let imageURL {
                ZoomableImageScrollView(imageURL: imageURL) {
                    onDismiss()
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 24, y: 16)
                .padding(24)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: paper.id) {
            await model.ensureArxivAssetCached(paper.assets.large ?? paper.assets.small)
        }
        .onExitCommand {
            onDismiss()
        }
    }
}

private struct ResourceLinkButtons: View {
    var links: [PaperResourceLink]
    var compact: Bool

    var body: some View {
        if !links.isEmpty {
            HStack(spacing: compact ? 5 : 8) {
                ForEach(links) { link in
                    ResourceLinkButton(link: link, compact: compact)
                }
            }
        }
    }
}

private struct ResourceLinkButton: View {
    @State private var isHovering = false
    var link: PaperResourceLink
    var compact: Bool

    var body: some View {
        Button {
            openExternalURL(link.urlString)
        } label: {
            labelContent
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if compact && isHovering {
                Text(link.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .textBackgroundColor))
                            .shadow(color: Color.black.opacity(0.16), radius: 7, y: 3)
                    )
                    .offset(y: -28)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .zIndex(isHovering ? 10 : 0)
        .help("Open \(link.title)")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    private var labelContent: some View {
        Group {
            if compact {
                Label(link.title, systemImage: link.systemImage)
                    .labelStyle(.iconOnly)
                    .frame(width: 22, height: 22)
            } else {
                Label(link.title, systemImage: link.systemImage)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            }
        }
        .font(.system(size: compact ? 11.5 : 13, weight: .semibold))
        .foregroundStyle(isHovering ? Color.accentColor : Color.primary.opacity(0.82))
        .background(buttonBackground)
        .scaleEffect(isHovering ? 1.06 : 1)
    }

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isHovering ? Color.accentColor.opacity(0.13) : Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovering ? Color.accentColor.opacity(0.45) : Color.black.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct PaperResourceLink: Identifiable {
    var id: String
    var title: String
    var systemImage: String
    var urlString: String
}

private extension ArxivFeedPaper {
    var externalLinks: [PaperResourceLink] {
        var result: [PaperResourceLink] = []
        var seen: Set<String> = []

        func append(id: String, title: String, systemImage: String, urlString: String?) {
            guard let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            let key = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !seen.contains(key) else {
                return
            }
            seen.insert(key)
            result.append(PaperResourceLink(id: id, title: title, systemImage: systemImage, urlString: urlString))
        }

        append(id: "github", title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right", urlString: links.github ?? links.code)
        append(id: "project", title: "Project", systemImage: "globe", urlString: links.project)
        append(id: "hf", title: "HF", systemImage: "shippingbox", urlString: links.huggingFace)
        append(id: "arxiv", title: "arXiv", systemImage: "doc.text", urlString: links.abs)
        append(id: "pdf", title: "PDF", systemImage: "doc.richtext", urlString: links.pdf)
        return result
    }
}

private func openExternalURL(_ urlString: String) {
    guard let url = URL(string: urlString) else {
        return
    }
    NSWorkspace.shared.open(url)
}

private struct FlowTags: View {
    var tags: [String]

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 12))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
