import AppKit
import ImageIO
import PaperCodexCore
import SwiftUI

private let discoverMediaHorizontalPadding: CGFloat = 14
private let discoverRouteToolbarMinHeight: CGFloat = 126
private let discoverPaperGridHorizontalPadding: CGFloat = 10
private let discoverPaperGridVerticalPadding: CGFloat = 8
private let discoverPaperGridColumnSpacing: CGFloat = 16
private let discoverPaperGridRowSpacing: CGFloat = 14

private enum DiscoverImagePreloadPolicy {
    static let visiblePaperLimit = 36
    static let scrollRestoreSettleNanoseconds: UInt64 = 320_000_000
    static let scrollPositionCommitDelayNanoseconds: UInt64 = 550_000_000
}

private struct DiscoverLayoutSignature: Hashable {
    var columnCount: Int
    var paperCount: Int
    var paperIDHash: Int
}

private struct DiscoverImageWarmupSignature: Hashable {
    var layout: DiscoverLayoutSignature
    var imageCount: Int
}

private func discoverPaperGridColumnWidth(for containerWidth: CGFloat, columnCount: Int) -> CGFloat {
    let safeColumnCount = max(columnCount, 1)
    let totalHorizontalPadding = discoverPaperGridHorizontalPadding * 2
    let totalColumnSpacing = discoverPaperGridColumnSpacing * CGFloat(safeColumnCount - 1)
    let availableWidth = max(0, containerWidth - totalHorizontalPadding - totalColumnSpacing)
    return floor(availableWidth / CGFloat(safeColumnCount))
}

struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedCategory: String?
    @State private var selectedTag: String?
    @State private var selectedProcessingFilter: DiscoverProcessingFilter = .all
    @State private var selectedLibraryFilter: DiscoverLibraryFilter = .all
    @State private var requiresProjectLink = false
    @State private var selectedSimilarityBucket: DiscoverSimilarityBucket = .all
    @State private var paperPendingSave: ArxivFeedPaper?
    @State private var previewPaper: ArxivFeedPaper?
    @State private var isShowingProcessSelection = false
    @State private var visibleDiscoverPaperID: String?
    @State private var isRestoringDiscoverScrollPosition = false
    @State private var discoverScrollPositionCommitTask: Task<Void, Never>?

    private var papers: [ArxivFeedPaper] {
        var result = model.arxivFeed?.papers ?? []
        if let selectedCategory {
            result = result.filter {
                $0.categories.contains(selectedCategory) || $0.listCategories.contains(selectedCategory)
            }
        }
        if let selectedTag {
            result = result.filter { tags(for: $0).contains(selectedTag) }
        }
        switch selectedProcessingFilter {
        case .all:
            break
        case .processed:
            result = result.filter { model.discoverEnrichment(for: $0)?.error == nil && model.discoverEnrichment(for: $0)?.isCurrent == true }
        case .unprocessed:
            result = result.filter { model.discoverEnrichment(for: $0) == nil }
        case .failed:
            result = result.filter { model.discoverEnrichment(for: $0)?.error != nil }
        }
        switch selectedLibraryFilter {
        case .all:
            break
        case .newOnly:
            result = result.filter { model.libraryPaper(for: $0) == nil }
        case .inLibrary:
            result = result.filter { model.libraryPaper(for: $0) != nil }
        }
        if requiresProjectLink {
            result = result.filter { $0.links.github != nil || $0.links.project != nil || $0.links.huggingFace != nil || !(model.discoverEnrichment(for: $0)?.links.isEmpty ?? true) }
        }
        if selectedSimilarityBucket != .all {
            result = result.filter { selectedSimilarityBucket.contains($0.similarity) }
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
        Dictionary((model.arxivFeed?.papers ?? []).flatMap { tags(for: $0) }.map { ($0, 1) }, uniquingKeysWith: +)
    }

    private var commonCategories: [String] {
        ["cs.CV", "cs.CL", "cs.AI", "cs.LG", "cs.RO", "stat.ML", "cs.HC", "cs.IR", "cs.SE"]
    }

    private func tags(for paper: ArxivFeedPaper) -> [String] {
        let generated = model.discoverEnrichment(for: paper)?.tags ?? []
        let combined = generated + paper.tags + Array(paper.categories.prefix(2))
        var seen: Set<String> = []
        var result: [String] = []
        for tag in combined {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
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
                    paperTitle: paper.displayTitle(language: model.globalLanguageMode.discoverLanguageCode),
                    detail: paper.authors.prefix(4).joined(separator: ", "),
                    libraryCategories: model.categories,
                    initialCategoryIDs: model.suggestedCategoryIDsForDiscoverSave(),
                    onSave: { selection in
                        paperPendingSave = nil
                        Task {
                            await model.addArxivPaperToLibrary(
                                paper,
                                selectedCategoryIDs: selection.categoryIDs,
                                newCategoryNames: selection.newCategoryNames,
                                newCategories: selection.newCategories
                            )
                        }
                    },
                    onCancel: {
                        paperPendingSave = nil
                    }
                )
            }
            .sheet(isPresented: $isShowingProcessSelection) {
                DiscoverProcessActionSheet(
                    paperCount: papers.count,
                    availableModelIDs: model.availableCodexModelIDs,
                    defaultModelID: model.codexDefaultModelID,
                    defaultModelOverride: model.discoverCodexModelOverride,
                    defaultReasoningEffort: model.discoverCodexReasoningEffort,
                    isRefreshingModels: model.isRefreshingCodexModels,
                    onRefreshModels: {
                        Task {
                            await model.refreshAvailableCodexModels()
                        }
                    },
                    onConfirm: { actions, modelOverride, reasoningEffort in
                        isShowingProcessSelection = false
                        Task {
                            await model.processCurrentDiscoverResults(
                                papers,
                                actions: Set(actions),
                                modelOverride: modelOverride,
                                reasoningEffort: reasoningEffort
                            )
                        }
                    },
                    onCancel: {
                        isShowingProcessSelection = false
                    }
                )
            }
    }

    private var mainLayout: some View {
        SidebarSplitLayout(minContentWidth: 760) {
            sidebar
        } content: {
            feed
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Episteme")
                .font(.paperCodexSystem(size: 24, weight: .semibold))

            PrimaryNavigationSection()

            Divider()

            Label("探索筛选", systemImage: "line.3.horizontal.decrease.circle")
                .font(.headline)
                .foregroundStyle(.secondary)

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
                        Label("Status", systemImage: "checklist")
                            .font(.headline)
                        ForEach(DiscoverProcessingFilter.allCases) { filter in
                            filterButton(title: filter.title, selected: selectedProcessingFilter == filter) {
                                selectedProcessingFilter = filter
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Library", systemImage: "books.vertical")
                            .font(.headline)
                        ForEach(DiscoverLibraryFilter.allCases) { filter in
                            filterButton(title: filter.title, selected: selectedLibraryFilter == filter) {
                                selectedLibraryFilter = filter
                            }
                        }
                        filterButton(title: "Has Code / Project", selected: requiresProjectLink) {
                            requiresProjectLink.toggle()
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Similarity", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.headline)
                        ForEach(DiscoverSimilarityBucket.allCases) { bucket in
                            filterButton(title: bucket.title, selected: selectedSimilarityBucket == bucket) {
                                selectedSimilarityBucket = bucket
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
        .paperCodexSidebarChromePadding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 14) {
            let visiblePapers = papers
            toolbar

            if (model.isLoadingArxivFeed && model.arxivFeed == nil)
                || (model.isSearchingDiscover && model.arxivFeed == nil) {
                DiscoverRouteLoadingPlaceholder(
                    title: "Loading Explore",
                    detail: "Preparing cached papers and previews"
                )
            } else if visiblePapers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let columnCount = gridColumnCount(for: proxy.size.width)
                    let columnWidth = discoverPaperGridColumnWidth(for: proxy.size.width, columnCount: columnCount)
                    let rows = paperRows(visiblePapers, columnCount: columnCount)
                    let layoutSignature = rowLayoutSignature(papers: visiblePapers, columnCount: columnCount)
                    let imagePreloadURLs = discoverImagePreloadURLs(for: visiblePapers)
                    let warmupSignature = DiscoverImageWarmupSignature(
                        layout: layoutSignature,
                        imageCount: imagePreloadURLs.count
                    )

                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: discoverPaperGridRowSpacing) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowPapers in
                                    HStack(alignment: .top, spacing: discoverPaperGridColumnSpacing) {
                                        ForEach(rowPapers) { paper in
                                            discoverCard(for: paper, rowIndex: rowIndex)
                                                .frame(width: columnWidth, alignment: .topLeading)
                                                .id(paper.id)
                                        }
                                        ForEach(0..<max(0, columnCount - rowPapers.count), id: \.self) { _ in
                                            Color.clear
                                                .frame(width: columnWidth)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(rowPapers.first?.id)
                                    .onAppear {
                                        markDiscoverVisibleRow(rowPapers.first?.id, in: visiblePapers)
                                    }
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, discoverPaperGridHorizontalPadding)
                            .padding(.vertical, discoverPaperGridVerticalPadding)
                            .task(id: warmupSignature) {
                                await warmDiscoverLocalImages(imagePreloadURLs)
                            }
                        }
                        .onAppear {
                            restoreDiscoverScrollPosition(scrollProxy, in: visiblePapers)
                        }
                        .onChange(of: layoutSignature) { _, _ in
                            restoreDiscoverScrollPosition(scrollProxy, in: visiblePapers)
                        }
                        .onDisappear {
                            commitDiscoverScrollPosition(fallbackPaperID: visibleDiscoverPaperID, in: visiblePapers)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func gridColumnCount(for width: CGFloat) -> Int {
        if width >= 1120 {
            return 3
        }
        if width >= 760 {
            return 2
        }
        return 1
    }

    private func paperRows(_ papers: [ArxivFeedPaper], columnCount: Int) -> [[ArxivFeedPaper]] {
        let count = max(columnCount, 1)
        return stride(from: 0, to: papers.count, by: count).map { start in
            Array(papers[start..<min(start + count, papers.count)])
        }
    }

    private func rowLayoutSignature(papers: [ArxivFeedPaper], columnCount: Int) -> DiscoverLayoutSignature {
        var hasher = Hasher()
        for paper in papers {
            hasher.combine(paper.id)
        }
        return DiscoverLayoutSignature(
            columnCount: columnCount,
            paperCount: papers.count,
            paperIDHash: hasher.finalize()
        )
    }

    private func discoverImagePreloadURLs(for papers: [ArxivFeedPaper]) -> [URL] {
        papers.prefix(DiscoverImagePreloadPolicy.visiblePaperLimit).flatMap { paper in
            var urls: [URL] = []
            if let assetURL = model.cachedArxivAssetURL(for: paper.assets.small) {
                urls.append(assetURL)
            }
            urls.append(contentsOf: model.cachedArxivPDFThumbnailURLs(for: paper))
            return urls
        }
    }

    private func discoverCard(for paper: ArxivFeedPaper, rowIndex: Int) -> some View {
        ArxivPaperCard(
            paper: paper,
            enrichment: model.discoverEnrichment(for: paper),
            imageURL: model.cachedArxivAssetURL(for: paper.assets.small),
            thumbnailURLs: model.cachedArxivPDFThumbnailURLs(for: paper),
            inLibrary: model.libraryPaper(for: paper) != nil,
            isBusy: model.isDownloadingArxivPaper(paper),
            downloadProgress: model.arxivDownloadProgress(for: paper),
            interactionState: model.discoverPaperInteractionStateByID[paper.id],
            languageMode: model.globalLanguageMode,
            onPreview: {
                previewPaper = paper
            },
            onSave: {
                paperPendingSave = paper
            },
            onOpen: {
                commitDiscoverScrollPosition(fallbackPaperID: paper.id)
                Task {
                    await model.openArxivPaper(paper)
                }
            }
        )
    }

    private func restoreDiscoverScrollPosition(_ scrollProxy: ScrollViewProxy, in visiblePapers: [ArxivFeedPaper]) {
        guard let paperID = model.discoverScrollPositionPaperID,
              visiblePapers.contains(where: { $0.id == paperID }) else {
            return
        }
        discoverScrollPositionCommitTask?.cancel()
        visibleDiscoverPaperID = paperID
        isRestoringDiscoverScrollPosition = true
        scrollProxy.scrollTo(paperID, anchor: .top)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: DiscoverImagePreloadPolicy.scrollRestoreSettleNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            isRestoringDiscoverScrollPosition = false
        }
    }

    private func markDiscoverVisibleRow(_ paperID: String?, in visiblePapers: [ArxivFeedPaper]) {
        guard !isRestoringDiscoverScrollPosition,
              let paperID,
              visiblePapers.contains(where: { $0.id == paperID }) else {
            return
        }
        visibleDiscoverPaperID = paperID
        scheduleDiscoverScrollPositionCommit(paperID, in: visiblePapers)
    }

    private func scheduleDiscoverScrollPositionCommit(_ paperID: String?, in visiblePapers: [ArxivFeedPaper]) {
        guard let paperID,
              visiblePapers.contains(where: { $0.id == paperID }) else {
            return
        }
        discoverScrollPositionCommitTask?.cancel()
        discoverScrollPositionCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: DiscoverImagePreloadPolicy.scrollPositionCommitDelayNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            model.recordDiscoverScrollPosition(paperID)
        }
    }

    private func commitDiscoverScrollPosition(fallbackPaperID: String? = nil, in visiblePapers: [ArxivFeedPaper]? = nil) {
        discoverScrollPositionCommitTask?.cancel()
        guard let paperID = visibleDiscoverPaperID ?? fallbackPaperID,
              (visiblePapers ?? papers).contains(where: { $0.id == paperID }) else {
            return
        }
        model.recordDiscoverScrollPosition(paperID)
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("探索")
                        .font(.paperCodexSystem(size: 28, weight: .semibold))
                    Text("\(papers.count) visible · \(model.arxivFeed?.count ?? 0) found · \(model.selectedArxivDate ?? "\(model.discoverStartDate)...\(model.discoverEndDate)")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                searchAndActionRow

                FlowLayout(spacing: 8) {
                    DiscoverDateControls(start: $model.discoverStartDate, end: $model.discoverEndDate) { range in
                        model.applyDiscoverQuickRange(range)
                    }

                    DiscoverCategoryMenu(
                        categories: commonCategories,
                        selected: model.discoverSelectedCategories.first ?? "cs.CV"
                    ) { category in
                        model.discoverSelectedCategories = [category]
                    }

                    SimilaritySourceMenu()
                        .environmentObject(model)

                }
                .frame(maxWidth: .infinity, alignment: .leading)

                activeFilterChips

                if (model.isSearchingDiscover || model.isPreloadingArxivAssets),
                   let progress = model.arxivCacheProgress {
                    ArxivCacheProgressStrip(progress: progress)
                }
                if model.isProcessingDiscoverResults,
                   let progress = model.discoverProcessingProgress {
                    ArxivCacheProgressStrip(progress: progress)
                }
                if model.isCachingDiscoverPDFs,
                   let progress = model.discoverPDFCacheProgress {
                    ArxivCacheProgressStrip(progress: progress)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: discoverRouteToolbarMinHeight, alignment: .topLeading)
    }

    private var searchAndActionRow: some View {
        HStack(spacing: 8) {
            DiscoverSearchField(
                text: $model.discoverKeyword,
                placeholder: "Keyword, method, author, arXiv ID",
                searchFocusRequestID: model.searchFocusRequestID,
                isActiveForFocus: model.route == .discover
            ) {
                model.startDiscoverSearch()
            }
                .frame(minWidth: 260, maxWidth: .infinity)
                .layoutPriority(1)

            PaperCodexToolbarButton(
                title: model.isSearchingDiscover ? "Searching" : "Search",
                systemImage: "magnifyingglass",
                tint: .blue,
                disabled: model.isSearchingDiscover || model.isProcessingDiscoverResults || model.isCachingDiscoverPDFs
            ) {
                model.startDiscoverSearch()
            }
            .fixedSize(horizontal: true, vertical: false)

            if model.isSearchingDiscover || model.isProcessingDiscoverResults || model.isCachingDiscoverPDFs {
                PaperCodexToolbarButton(title: "Stop", systemImage: "stop.circle", tint: .red) {
                    if model.isSearchingDiscover {
                        model.cancelDiscoverSearch()
                    }
                    if model.isProcessingDiscoverResults {
                        model.cancelDiscoverProcessing()
                    }
                    if model.isCachingDiscoverPDFs {
                        model.cancelDiscoverPDFCache()
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            } else {
                PaperCodexToolbarButton(
                    title: "Process",
                    systemImage: "sparkles",
                    tint: .indigo,
                    disabled: papers.isEmpty || model.isSearchingDiscover
                ) {
                    isShowingProcessSelection = true
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .lineLimit(1)
        .controlSize(.small)
    }

    private func filterButton(title: String, detail: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        SidebarFilterButton(title: title, detail: detail, selected: selected, action: action)
    }

    private var activeFilterChips: some View {
        FlowLayout(spacing: 8) {
            if let selectedCategory {
                DiscoverFilterChip(title: selectedCategory) {
                    self.selectedCategory = nil
                }
            }
            if let selectedTag {
                DiscoverFilterChip(title: selectedTag) {
                    self.selectedTag = nil
                }
            }
            if selectedProcessingFilter != .all {
                DiscoverFilterChip(title: selectedProcessingFilter.title) {
                    selectedProcessingFilter = .all
                }
            }
            if selectedLibraryFilter != .all {
                DiscoverFilterChip(title: selectedLibraryFilter.title) {
                    selectedLibraryFilter = .all
                }
            }
            if requiresProjectLink {
                DiscoverFilterChip(title: "Has Code / Project") {
                    requiresProjectLink = false
                }
            }
            if selectedSimilarityBucket != .all {
                DiscoverFilterChip(title: selectedSimilarityBucket.title) {
                    selectedSimilarityBucket = .all
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ArxivSearchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedCategory: String?
    @State private var selectedLibraryFilter: DiscoverLibraryFilter = .all
    @State private var paperPendingSave: ArxivFeedPaper?
    @State private var previewPaper: ArxivFeedPaper?
    @State private var isShowingProcessSelection = false

    private var papers: [ArxivFeedPaper] {
        var result = model.arxivSearchFeed?.papers ?? []
        if let selectedCategory {
            result = result.filter { $0.categories.contains(selectedCategory) || $0.listCategories.contains(selectedCategory) }
        }
        switch selectedLibraryFilter {
        case .all:
            break
        case .newOnly:
            result = result.filter { model.libraryPaper(for: $0) == nil }
        case .inLibrary:
            result = result.filter { model.libraryPaper(for: $0) != nil }
        }
        return result
    }

    private var resultCategories: [String] {
        let all = (model.arxivSearchFeed?.papers ?? []).flatMap { $0.listCategories.isEmpty ? $0.categories : $0.listCategories }
        return Array(Set(all)).sorted()
    }

    private var requiredCategoryOptions: [String] {
        let configured = model.localDiscoverPreferences.normalized.categories
        let common = ["cs.CV", "cs.CL", "cs.AI", "cs.LG", "cs.RO", "stat.ML", "cs.HC", "cs.IR", "cs.SE"]
        return LocalArxivClient.normalizedSearchCategories(model.arxivSearchRequiredCategories + configured + common)
    }

    private var trimmedSearchFromYear: String {
        model.arxivSearchFromYear.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSearchThroughYear: String {
        model.arxivSearchThroughYear.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sortOrderTitle: String {
        model.arxivSearchSortOrderRawValue == ArxivAPISortOrder.descending.rawValue ? "Sort descending" : "Sort ascending"
    }

    private var sortOrderSystemImage: String {
        model.arxivSearchSortOrderRawValue == ArxivAPISortOrder.descending.rawValue ? "arrow.down" : "arrow.up"
    }

    var body: some View {
        SidebarSplitLayout(minContentWidth: 760) {
            sidebar
        } content: {
            feed
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
                paperTitle: paper.displayTitle(language: model.globalLanguageMode.discoverLanguageCode),
                detail: paper.authors.prefix(4).joined(separator: ", "),
                libraryCategories: model.categories,
                initialCategoryIDs: [],
                onSave: { selection in
                    paperPendingSave = nil
                    Task {
                        await model.addArxivPaperToLibrary(
                            paper,
                            selectedCategoryIDs: selection.categoryIDs,
                            newCategoryNames: selection.newCategoryNames,
                            newCategories: selection.newCategories
                        )
                    }
                },
                onCancel: {
                    paperPendingSave = nil
                }
            )
        }
        .sheet(isPresented: $isShowingProcessSelection) {
            DiscoverProcessActionSheet(
                paperCount: papers.count,
                availableModelIDs: model.availableCodexModelIDs,
                defaultModelID: model.codexDefaultModelID,
                defaultModelOverride: model.discoverCodexModelOverride,
                defaultReasoningEffort: model.discoverCodexReasoningEffort,
                isRefreshingModels: model.isRefreshingCodexModels,
                onRefreshModels: {
                    Task {
                        await model.refreshAvailableCodexModels()
                    }
                },
                onConfirm: { actions, modelOverride, reasoningEffort in
                    isShowingProcessSelection = false
                    let searchPapers = papers
                    Task {
                        await model.processCurrentDiscoverResults(searchPapers, actions: Set(actions), modelOverride: modelOverride, reasoningEffort: reasoningEffort)
                    }
                },
                onCancel: {
                    isShowingProcessSelection = false
                }
            )
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Episteme")
                .font(.paperCodexSystem(size: 24, weight: .semibold))

            PrimaryNavigationSection()

            Divider()

            Label("搜索筛选", systemImage: "line.3.horizontal.decrease.circle")
                .font(.headline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("至少包含类别", systemImage: "checklist.checked")
                            .font(.headline)

                        SidebarFilterButton(title: "不限制", selected: model.arxivSearchRequiredCategories.isEmpty) {
                            model.arxivSearchRequiredCategories = []
                        }

                        ForEach(requiredCategoryOptions, id: \.self) { category in
                            SidebarFilterButton(title: category, selected: model.arxivSearchRequiredCategories.contains(category)) {
                                toggleRequiredCategory(category)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("结果类别", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.headline)
                        SidebarFilterButton(title: "All", selected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(resultCategories, id: \.self) { category in
                            SidebarFilterButton(title: category, selected: selectedCategory == category) {
                                selectedCategory = category
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Library", systemImage: "books.vertical")
                            .font(.headline)
                        ForEach(DiscoverLibraryFilter.allCases) { filter in
                            SidebarFilterButton(title: filter.title, selected: selectedLibraryFilter == filter) {
                                selectedLibraryFilter = filter
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .paperCodexSidebarChromePadding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbar

            if model.isSearchingArxivSearch && model.arxivSearchFeed == nil {
                DiscoverRouteLoadingPlaceholder(
                    title: "Searching arXiv",
                    detail: "Results will appear in this space"
                )
            } else if papers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let columnCount = gridColumnCount(for: proxy.size.width)
                    let columnWidth = discoverPaperGridColumnWidth(for: proxy.size.width, columnCount: columnCount)
                    let rows = paperRows(papers, columnCount: columnCount)
                    let imagePreloadURLs = discoverImagePreloadURLs(for: papers)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: discoverPaperGridRowSpacing) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowPapers in
                                HStack(alignment: .top, spacing: discoverPaperGridColumnSpacing) {
                                    ForEach(rowPapers) { paper in
                                        discoverCard(for: paper, rowIndex: rowIndex)
                                            .frame(width: columnWidth, alignment: .topLeading)
                                    }
                                    ForEach(0..<max(0, columnCount - rowPapers.count), id: \.self) { _ in
                                        Color.clear
                                            .frame(width: columnWidth)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, discoverPaperGridHorizontalPadding)
                        .padding(.vertical, discoverPaperGridVerticalPadding)
                        .task(id: imagePreloadURLs.map(\.path).joined(separator: "|")) {
                            await warmDiscoverLocalImages(imagePreloadURLs)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("搜索")
                        .font(.paperCodexSystem(size: 28, weight: .semibold))
                    Text("\(papers.count) visible · \(model.arxivSearchFeed?.count ?? 0) found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                DiscoverSearchField(
                    text: $model.arxivSearchQuery,
                    placeholder: "all:diffusion AND cat:cs.CV",
                    searchFocusRequestID: model.searchFocusRequestID,
                    isActiveForFocus: model.route == .search
                ) {
                    model.startArxivSearch()
                }
                    .frame(minWidth: 280, maxWidth: .infinity)
                    .layoutPriority(1)

                DiscoverSortPopup(selection: $model.arxivSearchSortRawValue)
                    .frame(width: 116, height: 28)

                PaperCodexIconButton(
                    title: sortOrderTitle,
                    systemImage: sortOrderSystemImage,
                    tint: .secondary
                ) {
                    toggleSearchSortOrder()
                }
                .fixedSize()

                PaperCodexToolbarButton(
                    title: model.isSearchingArxivSearch ? "Searching" : "Search",
                    systemImage: "magnifyingglass",
                    tint: .blue,
                    disabled: model.isSearchingArxivSearch || model.isProcessingDiscoverResults
                ) {
                    model.startArxivSearch()
                }
                .fixedSize(horizontal: true, vertical: false)

                if model.isSearchingArxivSearch || model.isProcessingDiscoverResults {
                    PaperCodexToolbarButton(title: "Stop", systemImage: "stop.circle", tint: .red) {
                        if model.isSearchingArxivSearch {
                            model.cancelArxivSearch()
                        }
                        if model.isProcessingDiscoverResults {
                            model.cancelDiscoverProcessing()
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                } else {
                    PaperCodexToolbarButton(
                        title: "Process",
                        systemImage: "sparkles",
                        tint: .indigo,
                        disabled: papers.isEmpty
                    ) {
                        isShowingProcessSelection = true
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .lineLimit(1)
            .controlSize(.small)

            FlowLayout(spacing: 8) {
                ArxivSearchYearField(title: "From", placeholder: "YYYY", text: $model.arxivSearchFromYear)
                ArxivSearchYearField(title: "To", placeholder: "YYYY", text: $model.arxivSearchThroughYear)

                ForEach(model.arxivSearchRequiredCategories, id: \.self) { category in
                    DiscoverFilterChip(title: "cat:\(category)") {
                        removeRequiredCategory(category)
                    }
                }
                if !trimmedSearchFromYear.isEmpty {
                    DiscoverFilterChip(title: "from \(trimmedSearchFromYear)") {
                        model.arxivSearchFromYear = ""
                    }
                }
                if !trimmedSearchThroughYear.isEmpty {
                    DiscoverFilterChip(title: "to \(trimmedSearchThroughYear)") {
                        model.arxivSearchThroughYear = ""
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if (model.isSearchingArxivSearch || model.isProcessingDiscoverResults),
               let progress = model.arxivCacheProgress {
                ArxivCacheProgressStrip(progress: progress)
            }
        }
        .frame(maxWidth: .infinity, minHeight: discoverRouteToolbarMinHeight, alignment: .topLeading)
    }

    private func toggleRequiredCategory(_ category: String) {
        var categories = model.arxivSearchRequiredCategories
        if categories.contains(category) {
            categories.removeAll { $0 == category }
        } else {
            categories.append(category)
        }
        model.arxivSearchRequiredCategories = categories
    }

    private func removeRequiredCategory(_ category: String) {
        model.arxivSearchRequiredCategories = model.arxivSearchRequiredCategories.filter { $0 != category }
    }

    private func toggleSearchSortOrder() {
        model.arxivSearchSortOrderRawValue = model.arxivSearchSortOrderRawValue == ArxivAPISortOrder.descending.rawValue
            ? ArxivAPISortOrder.ascending.rawValue
            : ArxivAPISortOrder.descending.rawValue
    }

    private func gridColumnCount(for width: CGFloat) -> Int {
        if width >= 1120 {
            return 3
        }
        if width >= 760 {
            return 2
        }
        return 1
    }

    private func paperRows(_ papers: [ArxivFeedPaper], columnCount: Int) -> [[ArxivFeedPaper]] {
        let count = max(columnCount, 1)
        return stride(from: 0, to: papers.count, by: count).map { start in
            Array(papers[start..<min(start + count, papers.count)])
        }
    }

    private func discoverImagePreloadURLs(for papers: [ArxivFeedPaper]) -> [URL] {
        papers.prefix(DiscoverImagePreloadPolicy.visiblePaperLimit).flatMap { paper in
            var urls: [URL] = []
            if let assetURL = model.cachedArxivAssetURL(for: paper.assets.small) {
                urls.append(assetURL)
            }
            urls.append(contentsOf: model.cachedArxivPDFThumbnailURLs(for: paper))
            return urls
        }
    }

    private func discoverCard(for paper: ArxivFeedPaper, rowIndex: Int) -> some View {
        ArxivPaperCard(
            paper: paper,
            enrichment: model.discoverEnrichment(for: paper),
            imageURL: model.cachedArxivAssetURL(for: paper.assets.small),
            thumbnailURLs: model.cachedArxivPDFThumbnailURLs(for: paper),
            inLibrary: model.libraryPaper(for: paper) != nil,
            isBusy: model.isDownloadingArxivPaper(paper),
            downloadProgress: model.arxivDownloadProgress(for: paper),
            interactionState: model.discoverPaperInteractionStateByID[paper.id],
            languageMode: model.globalLanguageMode,
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

private enum DiscoverProcessingFilter: String, CaseIterable, Identifiable {
    case all
    case processed
    case unprocessed
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .processed:
            "Processed"
        case .unprocessed:
            "Unprocessed"
        case .failed:
            "Failed"
        }
    }
}

private enum DiscoverLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case newOnly
    case inLibrary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All Papers"
        case .newOnly:
            "New Only"
        case .inLibrary:
            "In Library"
        }
    }
}

private enum DiscoverSimilarityBucket: String, CaseIterable, Identifiable {
    case all
    case high
    case medium
    case low
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All Scores"
        case .high:
            "High"
        case .medium:
            "Medium"
        case .low:
            "Low"
        case .none:
            "No Similarity"
        }
    }

    func contains(_ value: Double?) -> Bool {
        switch self {
        case .all:
            true
        case .high:
            (value ?? 0) >= 0.78
        case .medium:
            (value ?? 0) >= 0.62 && (value ?? 0) < 0.78
        case .low:
            value != nil && (value ?? 0) < 0.62
        case .none:
            value == nil
        }
    }
}

private enum NativeSidebarFilterMetrics {
    static let rowHeight: CGFloat = 31
    static let iconWidth: CGFloat = 18
    static let horizontalInset: CGFloat = 9
    static let cornerRadius: CGFloat = PaperCodexCornerRadius.control
}

private struct SidebarFilterButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var title: String
    var detail: String?
    var selected: Bool
    var action: () -> Void

    var body: some View {
        NativeSidebarFilterButton(
            title: title,
            detail: detail,
            selected: selected,
            reduceMotion: reduceMotion,
            action: action
        )
        .frame(maxWidth: .infinity, minHeight: NativeSidebarFilterMetrics.rowHeight, maxHeight: NativeSidebarFilterMetrics.rowHeight)
    }
}

private struct NativeSidebarFilterButton: NSViewRepresentable {
    var title: String
    var detail: String?
    var selected: Bool
    var reduceMotion: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NativeSidebarFilterButtonView {
        let view = NativeSidebarFilterButtonView()
        view.apply(title: title, detail: detail, selected: selected, reduceMotion: reduceMotion, action: action)
        return view
    }

    func updateNSView(_ view: NativeSidebarFilterButtonView, context: Context) {
        view.apply(title: title, detail: detail, selected: selected, reduceMotion: reduceMotion, action: action)
    }
}

private final class NativeSidebarFilterButtonView: NSButton {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var pressHandler: () -> Void = {}
    private var isHovering = false
    private var isPressed = false
    private var isSelectedRow = false
    private var reduceMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NativeSidebarFilterMetrics.rowHeight)
    }

    func apply(title: String, detail: String?, selected: Bool, reduceMotion: Bool, action: @escaping () -> Void) {
        pressHandler = action
        self.reduceMotion = reduceMotion
        isSelectedRow = selected

        let localizedTitle = NSLocalizedString(title, comment: "")
        titleLabel.stringValue = localizedTitle
        detailLabel.stringValue = detail ?? ""
        detailLabel.isHidden = detail == nil
        iconView.image = NSImage(
            systemSymbolName: selected ? "checkmark.circle.fill" : "circle",
            accessibilityDescription: localizedTitle
        )
        toolTip = detail.map { "\(localizedTitle) \($0)" } ?? localizedTitle
        setAccessibilityLabel(localizedTitle)
        setAccessibilityValue(selected ? NSLocalizedString("Selected", comment: "") : nil)
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        focusRingType = .none
        setButtonType(.momentaryChange)
        target = self
        action = #selector(performPress)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        wantsLayer = true
        layer?.cornerRadius = NativeSidebarFilterMetrics.cornerRadius
        layer?.masksToBounds = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.alignment = .right
        detailLabel.setContentHuggingPriority(.required, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        [iconView, titleLabel, detailLabel].forEach(addSubview(_:))
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: NativeSidebarFilterMetrics.horizontalInset),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: NativeSidebarFilterMetrics.iconWidth),
            iconView.heightAnchor.constraint(equalToConstant: NativeSidebarFilterMetrics.iconWidth),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailLabel.leadingAnchor, constant: -8),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -NativeSidebarFilterMetrics.horizontalInset)
        ])
        updateAppearance()
    }

    @objc private func performPress() {
        pressHandler()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let accent = NSColor.controlAccentColor
        let iconColor: NSColor = isSelectedRow ? accent : .secondaryLabelColor
        iconView.contentTintColor = iconColor
        titleLabel.textColor = isSelectedRow ? .labelColor : .labelColor.withAlphaComponent(0.90)
        detailLabel.textColor = .secondaryLabelColor

        let background: NSColor
        let border: NSColor
        if isSelectedRow || isPressed {
            background = accent.withAlphaComponent(isPressed ? 0.16 : 0.12)
            border = isPressed ? accent.withAlphaComponent(0.42) : .clear
        } else if isHovering {
            background = NSColor.textBackgroundColor
            border = accent.withAlphaComponent(0.20)
        } else {
            background = .clear
            border = .clear
        }

        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = border == .clear ? 0 : 1
        layer?.borderColor = border.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = isPressed ? 0.10 : (isHovering ? 0.06 : 0)
        layer?.shadowRadius = isPressed ? 3 : (isHovering ? 5 : 0)
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? -1 : -2)

        let targetScale: CGFloat
        if reduceMotion {
            targetScale = 1
        } else if isPressed {
            targetScale = 0.982
        } else {
            targetScale = isHovering && !isSelectedRow ? 1.01 : 1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
    }
}

private struct DiscoverFilterChip: View {
    @State private var isHovering = false

    var title: String
    var onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            Label(title, systemImage: "xmark.circle.fill")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(DiscoverFilterChipStyle(isHovering: isHovering))
        .help("Remove \(title) filter")
        .onHover { hovering in
            withAnimation(PaperCodexMotion.hover) {
                isHovering = hovering
            }
        }
    }
}

private struct DiscoverFilterChipStyle: ButtonStyle {
    var isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        configuration.label
            .foregroundStyle(Color.accentColor.opacity(isPressed ? 1 : (isHovering ? 0.96 : 0.88)))
            .background(
                Capsule()
                    .fill(backgroundFill(isPressed: isPressed))
            )
            .overlay(
                Capsule()
                    .stroke(borderColor(isPressed: isPressed), lineWidth: isPressed || isHovering ? 1 : 0)
            )
            .shadow(color: shadowColor(isPressed: isPressed), radius: isPressed ? 3 : 5, y: isPressed ? 1 : 2)
            .scaleEffect(isPressed ? 0.965 : (isHovering ? 1.025 : 1), anchor: .center)
            .contentShape(Capsule())
            .animation(PaperCodexMotion.press, value: configuration.isPressed)
            .animation(PaperCodexMotion.hover, value: isHovering)
    }

    private func backgroundFill(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(0.18)
        }
        return Color.accentColor.opacity(isHovering ? 0.14 : 0.10)
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(0.56)
        }
        return Color.accentColor.opacity(isHovering ? 0.36 : 0)
    }

    private func shadowColor(isPressed: Bool) -> Color {
        isPressed || isHovering ? Color.accentColor.opacity(isPressed ? 0.10 : 0.13) : .clear
    }
}

private struct ArxivSearchYearField: View {
    var title: String
    var placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            DiscoverSearchField(text: $text, placeholder: placeholder)
                .frame(width: 70)
        }
        .controlSize(.small)
    }
}

private struct DiscoverSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var searchFocusRequestID: UUID?
    var isActiveForFocus = false
    var onSubmit: () -> Void = {}

    func makeCoordinator() -> DiscoverSearchFieldCoordinator {
        DiscoverSearchFieldCoordinator(self)
    }

    func makeNSView(context: Context) -> NativeDiscoverSearchFieldView {
        let searchField = NativeDiscoverSearchFieldView()
        context.coordinator.parent = self
        context.coordinator.lastSearchFocusRequestID = searchFocusRequestID
        searchField.delegate = context.coordinator
        searchField.apply(text: text, placeholder: placeholder)
        return searchField
    }

    func updateNSView(_ searchField: NativeDiscoverSearchFieldView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdatingFromSwiftUI = true
        searchField.apply(text: text, placeholder: placeholder)
        context.coordinator.isUpdatingFromSwiftUI = false
        context.coordinator.applyFocusIfNeeded(to: searchField)
    }
}

@MainActor private final class DiscoverSearchFieldCoordinator: NSObject, NSSearchFieldDelegate {
    var parent: DiscoverSearchField
    var isUpdatingFromSwiftUI = false
    var lastSearchFocusRequestID: UUID?

    init(_ parent: DiscoverSearchField) {
        self.parent = parent
        super.init()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !isUpdatingFromSwiftUI,
              let searchField = notification.object as? NSSearchField else {
            return
        }
        parent.text = searchField.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
            return false
        }
        parent.onSubmit()
        return true
    }

    func applyFocusIfNeeded(to searchField: NativeDiscoverSearchFieldView) {
        guard let searchFocusRequestID = parent.searchFocusRequestID,
              searchFocusRequestID != lastSearchFocusRequestID else {
            return
        }
        lastSearchFocusRequestID = searchFocusRequestID
        guard parent.isActiveForFocus else {
            return
        }
        searchField.window?.makeFirstResponder(searchField)
    }
}

private final class NativeDiscoverSearchFieldView: NSSearchField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 28)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(text: String, placeholder: String) {
        let fieldEditorHasMarkedText = (currentEditor() as? NSTextView)?.hasMarkedText() == true
        if stringValue != text && !fieldEditorHasMarkedText {
            stringValue = text
        }
        placeholderString = placeholder
        toolTip = placeholder
        setAccessibilityLabel(placeholder)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        controlSize = .regular
        font = .systemFont(ofSize: 14)
        isBordered = true
        isBezeled = true
        focusRingType = .default
        usesSingleLineMode = true
        lineBreakMode = .byTruncatingTail
        sendsSearchStringImmediately = false
        sendsWholeSearchString = true
    }
}

private struct DiscoverSortPopup: NSViewRepresentable {
    @Binding var selection: String

    private let items: [(title: String, value: String)] = [
        ("Relevance", ArxivAPISort.relevance.rawValue),
        ("Submitted", ArxivAPISort.submittedDate.rawValue),
        ("Updated", ArxivAPISort.lastUpdatedDate.rawValue)
    ]

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NativeDiscoverSortPopupButton {
        let popup = NativeDiscoverSortPopupButton()
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        popup.apply(items: items, selection: selection)
        return popup
    }

    func updateNSView(_ popup: NativeDiscoverSortPopupButton, context: Context) {
        context.coordinator.selection = $selection
        popup.apply(items: items, selection: selection)
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<String>

        init(selection: Binding<String>) {
            self.selection = selection
            super.init()
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let value = sender.selectedItem?.representedObject as? String else {
                return
            }
            selection.wrappedValue = value
        }
    }
}

private final class NativeDiscoverSortPopupButton: NSPopUpButton {
    private var itemValues: [String] = []

    init() {
        super.init(frame: .zero, pullsDown: false)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 116, height: 28)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(items: [(title: String, value: String)], selection: String) {
        let values = items.map(\.value)
        if values != itemValues || numberOfItems != items.count {
            removeAllItems()
            for item in items {
                addItem(withTitle: item.title)
                lastItem?.representedObject = item.value
            }
            itemValues = values
        }

        if let index = items.firstIndex(where: { $0.value == selection }) {
            selectItem(at: index)
        } else if !items.isEmpty {
            selectItem(at: 0)
        }
        setAccessibilityLabel("Sort")
        setAccessibilityValue(selectedItem?.title ?? "")
        toolTip = selectedItem?.title
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        controlSize = .regular
        font = .systemFont(ofSize: 13)
        focusRingType = .none
    }
}

private struct NativeCompactDiscoverDatePicker: NSViewRepresentable {
    var title: String
    @Binding var selection: Date

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NativeCompactDiscoverDatePickerView {
        let datePicker = NativeCompactDiscoverDatePickerView()
        datePicker.target = context.coordinator
        datePicker.action = #selector(Coordinator.dateChanged(_:))
        datePicker.apply(title: title, date: selection)
        return datePicker
    }

    func updateNSView(_ datePicker: NativeCompactDiscoverDatePickerView, context: Context) {
        context.coordinator.selection = $selection
        datePicker.apply(title: title, date: selection)
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<Date>

        init(selection: Binding<Date>) {
            self.selection = selection
            super.init()
        }

        @objc func dateChanged(_ sender: NSDatePicker) {
            selection.wrappedValue = sender.dateValue
        }
    }
}

private final class NativeCompactDiscoverDatePickerView: NSDatePicker {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 118, height: 28)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(title: String, date: Date) {
        if abs(dateValue.timeIntervalSince(date)) > 0.5 {
            dateValue = date
        }
        toolTip = title
        setAccessibilityLabel(title)
        setAccessibilityValue(DiscoverDateStrings.string(from: dateValue))
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        datePickerElements = [.yearMonthDay]
        datePickerStyle = .textFieldAndStepper
        controlSize = .small
        font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        isBezeled = true
        drawsBackground = true
        focusRingType = .default
    }
}

private struct DiscoverRouteLoadingPlaceholder: View {
    var title: String
    var detail: String

    var body: some View {
        GeometryReader { proxy in
            let columnCount = placeholderColumnCount(for: proxy.size.width)
            let rows = Array(0..<3)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(title))
                                .font(.paperCodexSystem(size: 13, weight: .semibold))
                            Text(LocalizedStringKey(detail))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)

                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(rows, id: \.self) { _ in
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(0..<columnCount, id: \.self) { _ in
                                    DiscoverRouteLoadingCard()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private func placeholderColumnCount(for width: CGFloat) -> Int {
        if width >= 1120 {
            return 3
        }
        if width >= 760 {
            return 2
        }
        return 1
    }
}

private struct DiscoverRouteLoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .separatorColor).opacity(0.16))
                .aspectRatio(1.65, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.22))
                            .frame(width: 8, height: 8)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(0.18))
                            .frame(width: 70, height: 6)
                    }
                    .padding(10)
                }

            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 190, height: 9)
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 56, height: 11)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange.opacity(0.14))
                        .frame(width: 76, height: 11)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct DiscoverPaperStatusBadge: View {
    var state: DiscoverPaperInteractionState

    var body: some View {
        Label {
            Text(LocalizedStringKey(title))
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.10), in: Capsule())
            .help(title)
    }

    private var title: String {
        switch state {
        case .queued:
            "Queued"
        case .processing:
            "Processing"
        case .processed:
            "Processed"
        case .cached:
            "Cached"
        case .failed:
            "Failed"
        case .cancelled:
            "Stopped"
        case .downloading:
            "Caching PDF"
        case .pdfCached:
            "PDF Cached"
        }
    }

    private var systemImage: String {
        switch state {
        case .queued:
            "clock"
        case .processing:
            "sparkles"
        case .processed:
            "checkmark.circle.fill"
        case .cached:
            "archivebox.fill"
        case .failed:
            "xmark.octagon.fill"
        case .cancelled:
            "stop.circle.fill"
        case .downloading:
            "arrow.down.circle.fill"
        case .pdfCached:
            "doc.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .queued:
            .secondary
        case .processing:
            .indigo
        case .processed, .cached, .pdfCached:
            .green
        case .failed:
            .red
        case .cancelled:
            .orange
        case .downloading:
            .blue
        }
    }
}

private struct DiscoverDateControls: View {
    @Binding var start: String
    @Binding var end: String
    var onQuickRange: (DiscoverQuickRange) -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
            CompactDiscoverDatePicker(title: "Start", dateString: $start) { value in
                if DiscoverDateStrings.date(from: value) > DiscoverDateStrings.date(from: end) {
                    end = value
                }
            }
            Text(LocalizedStringKey("to"))
                .font(.caption)
                .foregroundStyle(.secondary)
            CompactDiscoverDatePicker(title: "End", dateString: $end) { value in
                if DiscoverDateStrings.date(from: value) < DiscoverDateStrings.date(from: start) {
                    start = value
                }
            }
            QuickRangeButtons(onSelect: onQuickRange)
        }
        .help("arXiv date range")
    }
}

private struct CompactDiscoverDatePicker: View {
    var title: String
    @Binding var dateString: String
    var onChange: (String) -> Void

    private var dateBinding: Binding<Date> {
        Binding {
            DiscoverDateStrings.date(from: dateString)
        } set: { newDate in
            let value = DiscoverDateStrings.string(from: newDate)
            dateString = value
            onChange(value)
        }
    }

    var body: some View {
        NativeCompactDiscoverDatePicker(title: title, selection: dateBinding)
            .frame(width: 118)
            .help(title)
    }
}

private enum DiscoverDateStrings {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    static func date(from value: String) -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: parts[0],
                month: parts[1],
                day: parts[2],
                hour: 12
              )) else {
            return Date()
        }
        return date
    }

    static func string(from date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}

private struct QuickRangeButtons: View {
    var onSelect: (DiscoverQuickRange) -> Void
    private let ranges: [DiscoverQuickRange] = [DiscoverQuickRange.today, .last7Days, .last30Days]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                quickButtons
            }
            Menu {
                ForEach(ranges) { range in
                    Button(range.title) {
                        onSelect(range)
                    }
                }
            } label: {
                Label("Ranges", systemImage: "calendar.badge.clock")
                    .font(.paperCodexSystem(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var quickButtons: some View {
        ForEach(ranges) { range in
            DiscoverQuickRangeButton(range: range) {
                onSelect(range)
            }
        }
    }
}

private struct DiscoverQuickRangeButton: View {
    var range: DiscoverQuickRange
    var action: () -> Void

    var body: some View {
        PaperCodexQuickRangeButton(title: range.title) {
            action()
        }
    }
}

private struct DiscoverProcessActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var paperCount: Int
    var availableModelIDs: [String]
    var defaultModelID: String
    var defaultModelOverride: String
    var defaultReasoningEffort: CodexReasoningEffort
    var isRefreshingModels: Bool
    var onRefreshModels: () -> Void
    var onConfirm: ([DiscoverProcessAction], String, CodexReasoningEffort) -> Void
    var onCancel: () -> Void

    @State private var selectedActions: Set<DiscoverProcessAction>
    @State private var draftModelOverride: String
    @State private var draftReasoningEffort: CodexReasoningEffort

    init(
        paperCount: Int,
        availableModelIDs: [String],
        defaultModelID: String,
        defaultModelOverride: String,
        defaultReasoningEffort: CodexReasoningEffort,
        isRefreshingModels: Bool,
        onRefreshModels: @escaping () -> Void,
        onConfirm: @escaping ([DiscoverProcessAction], String, CodexReasoningEffort) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.paperCount = paperCount
        self.availableModelIDs = availableModelIDs
        self.defaultModelID = defaultModelID
        self.defaultModelOverride = defaultModelOverride
        self.defaultReasoningEffort = defaultReasoningEffort
        self.isRefreshingModels = isRefreshingModels
        self.onRefreshModels = onRefreshModels
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _selectedActions = State(initialValue: Set(DiscoverProcessAction.allCases))
        _draftModelOverride = State(initialValue: defaultModelOverride)
        _draftReasoningEffort = State(initialValue: defaultReasoningEffort)
    }

    private var selectedOrderedActions: [DiscoverProcessAction] {
        DiscoverProcessAction.allCases.filter { selectedActions.contains($0) }
    }

    private var codexDefaultModelLabel: String {
        let trimmed = defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Codex default" : "Codex default (\(trimmed))"
    }

    private var canProcessResults: Bool {
        !selectedOrderedActions.isEmpty && paperCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Processing Steps")
                    .font(.paperCodexSystem(size: 20, weight: .semibold))
                Text("\(paperCount) visible results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button("Select All") {
                        selectedActions = Set(DiscoverProcessAction.allCases)
                    }
                    Button("Clear") {
                        selectedActions = []
                    }
                    Spacer()
                    Text("\(selectedOrderedActions.count)/\(DiscoverProcessAction.allCases.count) steps")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .controlSize(.small)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(DiscoverProcessAction.allCases) { action in
                        DiscoverProcessActionRow(
                            action: action,
                            isSelected: Binding(get: {
                                selectedActions.contains(action)
                            }, set: { selected in
                                if selected {
                                    selectedActions.insert(action)
                                } else {
                                    selectedActions.remove(action)
                                }
                            })
                        )
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Label("Processing Runtime", systemImage: "cpu")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            onRefreshModels()
                        } label: {
                            Label(isRefreshingModels ? "Refreshing" : "Refresh Models", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(isRefreshingModels)
                    }

                    Picker("Model", selection: $draftModelOverride) {
                        Text(codexDefaultModelLabel).tag("")
                        ForEach(availableModelIDs, id: \.self) { modelID in
                            Text(modelID).tag(modelID)
                        }
                        if !draftModelOverride.isEmpty,
                           !availableModelIDs.contains(draftModelOverride) {
                            Text("\(draftModelOverride) (custom)").tag(draftModelOverride)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Custom model override", text: $draftModelOverride)
                        .textFieldStyle(.roundedBorder)

                    Picker("Thinking", selection: $draftReasoningEffort) {
                        ForEach(CodexReasoningEffort.allCases, id: \.self) { effort in
                            Text(effort.displayName).tag(effort)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(20)

            Divider()

            HStack {
                Spacer()
                PaperCodexPanelButton(title: "Cancel", systemImage: "xmark") {
                    onCancel()
                    dismiss()
                }

                PaperCodexPanelButton(
                    title: "Process Results",
                    systemImage: "sparkles",
                    kind: .primary,
                    disabled: !canProcessResults,
                    keyEquivalent: "\r"
                ) {
                    if canProcessResults {
                        onConfirm(selectedOrderedActions, draftModelOverride, draftReasoningEffort)
                        dismiss()
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 500)
        .onAppear(perform: onRefreshModels)
    }
}

private struct DiscoverProcessActionRow: View {
    var action: DiscoverProcessAction
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(action.title))
                        .font(.paperCodexSystem(size: 14, weight: .semibold))
                    Text(LocalizedStringKey(action.detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: action.systemImage)
                    .font(.paperCodexSystem(size: 15, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 24)
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DiscoverCategoryMenu: View {
    var categories: [String]
    var selected: String
    var onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(categories, id: \.self) { category in
                Button {
                    onSelect(category)
                } label: {
                    if category == selected {
                        Label(category, systemImage: "checkmark")
                    } else {
                        Text(category)
                    }
                }
            }
        } label: {
            Label(selected, systemImage: "tray.full")
                .font(.paperCodexSystem(size: 12.5, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Primary arXiv category")
    }
}

private struct SimilaritySourceMenu: View {
    @EnvironmentObject private var model: AppModel

    private var selectedTitle: String {
        guard let first = model.discoverSelectedSimilaritySourceIDs.first else {
            return "Similarity"
        }
        if let category = model.categories.first(where: { "category:\($0.id)" == first }) {
            return category.name
        }
        return "\(model.discoverSelectedSimilaritySourceIDs.count) sources"
    }

    private func selectSources(_ sourceIDs: [String]) {
        model.discoverSelectedSimilaritySourceIDs = sourceIDs
        Task {
            await model.rerankCurrentDiscoverResults()
        }
    }

    var body: some View {
        Menu {
            Button {
                selectSources([])
            } label: {
                if model.discoverSelectedSimilaritySourceIDs.isEmpty {
                    Label("Settings default", systemImage: "checkmark")
                } else {
                    Text("Settings default")
                }
            }
            if !model.categories.isEmpty {
                Divider()
                Section("Folders") {
                    ForEach(model.categories) { category in
                        Button {
                            selectSources(["category:\(category.id)"])
                        } label: {
                            if model.discoverSelectedSimilaritySourceIDs == ["category:\(category.id)"] {
                                Label(category.name, systemImage: "checkmark")
                            } else {
                                Text(category.name)
                            }
                        }
                    }
                }
            }
        } label: {
            Label(selectedTitle, systemImage: "point.3.connected.trianglepath.dotted")
                .font(.paperCodexSystem(size: 12.5, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Similarity source")
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
                    .font(.paperCodexSystem(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.paperCodexSystem(size: 12.5, weight: .semibold))
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
                    .font(.paperCodexSystem(size: 12.5, weight: .semibold))
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
    var enrichment: DiscoverPaperEnrichment?
    var imageURL: URL?
    var thumbnailURLs: [URL]
    var inLibrary: Bool
    var isBusy: Bool
    var downloadProgress: Double?
    var interactionState: DiscoverPaperInteractionState?
    var languageMode: PaperCodexLanguageMode
    var onPreview: () -> Void
    var onSave: () -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if imageURL != nil || !thumbnailURLs.isEmpty {
                PaperCodexMediaPreviewButton(
                    disabled: imageURL == nil && isBusy,
                    help: imageURL == nil ? "Open cached PDF" : "Open image preview"
                ) {
                    if imageURL != nil {
                        onPreview()
                    } else {
                        onOpen()
                    }
                } content: {
                    if imageURL != nil {
                        ArxivPreviewImage(url: imageURL)
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .clipped()
                    } else {
                        DiscoverPDFThumbnailHero(urls: thumbnailURLs)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, discoverMediaHorizontalPadding)
                .padding(.top, discoverMediaHorizontalPadding)
                .padding(.bottom, 8)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    metadataRow
                    Spacer()
                    if let interactionState {
                        DiscoverPaperStatusBadge(state: interactionState)
                    }
                }

                Text(primaryTitle)
                    .font(.paperCodexSystem(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !secondaryTitle.isEmpty, secondaryTitle != primaryTitle {
                    Text(secondaryTitle)
                        .font(.paperCodexSystem(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(summaryText)
                    .font(.paperCodexSystem(size: 13.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                if let contribution = enrichment?.contribution,
                   !contribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(contribution)
                        .font(.paperCodexSystem(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = enrichment?.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .lineLimit(3)
                }

                FlowTags(tags: Array(displayTags.prefix(7)))
            }
            .padding(14)
            .padding(.bottom, footerReservedHeight)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .overlay(alignment: .bottomLeading) {
                cardFooter
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var cardFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 8) {
                ResourceLinkButtons(links: resourceLinks, compact: true)
                Spacer(minLength: 10)
                actionGroup
            }
            VStack(alignment: .leading, spacing: 8) {
                ResourceLinkButtons(links: resourceLinks, compact: true)
                HStack(alignment: .bottom) {
                    Spacer(minLength: 0)
                    actionGroup
                }
            }
        }
    }

    private var actionGroup: some View {
        HStack(spacing: 8) {
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
        .fixedSize()
    }

    private var footerReservedHeight: CGFloat {
        38
    }

    private var previewHeight: CGFloat {
        guard imageURL != nil || !thumbnailURLs.isEmpty else {
            return 0
        }
        return imageURL != nil ? 150 : 154
    }

    private var metadataRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                metadataPills
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if let similarity = paper.similarity {
                    SimilarityMeter(value: similarity)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                metadataPills
                if let similarity = paper.similarity {
                    SimilarityMeter(value: similarity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataPills: some View {
        HStack(alignment: .center, spacing: 6) {
            MetadataPill(
                title: paper.primaryCategory ?? paper.categories.first ?? "arXiv",
                foreground: .teal,
                background: Color.teal.opacity(0.12)
            )
            ArxivIDPill(id: paper.id)
        }
    }

    private var primaryTitle: String {
        if languageMode.discoverLanguageCode == "zh" {
            if let title = enrichment?.titleZH.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                return title
            }
            return paper.displayTitle(language: "zh")
        }
        return paper.title.en
    }

    private var secondaryTitle: String {
        guard languageMode.discoverLanguageCode == "zh" else {
            return ""
        }
        return paper.title.en
    }

    private var summaryText: String {
        if languageMode.discoverLanguageCode == "zh" {
            if let summary = enrichment?.summaryZH.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                return summary
            }
            if !paper.summary.zh.isEmpty {
                return paper.summary.zh
            }
        }
        if !paper.summary.en.isEmpty {
            return paper.summary.en
        }
        return paper.abstract.en
    }

    private var displayTags: [String] {
        let generated = enrichment?.tags ?? []
        let fallback = paper.tags.isEmpty ? paper.categories : paper.tags
        var seen: Set<String> = []
        var result: [String] = []
        for tag in generated + fallback {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    private var resourceLinks: [PaperResourceLink] {
        var result = paper.externalLinks
        func append(id: String, title: String, systemImage: String, key: String) {
            guard let value = enrichment?.links[key] else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !result.contains(where: { $0.urlString.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
                return
            }
            result.append(PaperResourceLink(id: id, title: title, systemImage: systemImage, urlString: trimmed))
        }
        append(id: "github-enriched", title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right", key: "github")
        append(id: "project-enriched", title: "Project", systemImage: "globe", key: "project")
        append(id: "hf-enriched", title: "HF", systemImage: "shippingbox", key: "hugging_face")
        return result
    }
}


private struct MetadataPill: View {
    var title: String
    var foreground: Color
    var background: Color

    var body: some View {
        Text(title)
            .font(.paperCodexSystem(size: 12, weight: .semibold))
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
            .font(.paperCodexSystem(size: 12, weight: .medium))
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
            .font(.paperCodexSystem(size: 13, weight: .semibold))
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
    var isBusy: Bool
    var action: () -> Void

    var body: some View {
        PaperCodexCardActionButton(
            title: "Add",
            systemImage: "tray.and.arrow.down",
            kind: .success,
            disabled: isBusy,
            help: "Add to Library",
            action: action
        )
        .fixedSize()
        .layoutPriority(1)
    }
}

private struct StableOpenButton: View {
    var isBusy: Bool
    var action: () -> Void

    var body: some View {
        PaperCodexCardActionButton(
            title: "Open",
            systemImage: "book",
            kind: .primary,
            disabled: isBusy,
            help: "Open in reader",
            action: action
        )
        .fixedSize()
        .layoutPriority(2)
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
                .font(.paperCodexSystem(size: 12, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help("Similarity score")
    }
}

@MainActor
private final class DiscoverLocalImageCache {
    static let shared = DiscoverLocalImageCache()

    private let cache = NSCache<NSURL, CachedDiscoverImage>()

    private init() {
        cache.countLimit = 420
        cache.totalCostLimit = 180 * 1024 * 1024
    }

    func image(for url: URL) -> CGImage? {
        cache.object(forKey: url as NSURL)?.image
    }

    func contains(_ url: URL) -> Bool {
        cache.object(forKey: url as NSURL) != nil
    }

    func insert(_ image: CGImage, for url: URL) {
        cache.setObject(
            CachedDiscoverImage(image),
            forKey: url as NSURL,
            cost: image.bytesPerRow * image.height
        )
    }
}

private final class CachedDiscoverImage {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

private struct DecodedDiscoverImage: @unchecked Sendable {
    let image: CGImage
}

private struct LocalCachedImage<Placeholder: View>: View {
    var url: URL
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        if let cached = DiscoverLocalImageCache.shared.image(for: url) {
            image = cached
            return
        }

        let imageURL = url
        guard let decoded = await decodeDiscoverLocalImage(at: imageURL, priority: .userInitiated) else {
            image = nil
            return
        }
        DiscoverLocalImageCache.shared.insert(decoded.image, for: url)
        image = decoded.image
    }
}

private func warmDiscoverLocalImages(_ urls: [URL], limit: Int = 360) async {
    do {
        try await Task.sleep(nanoseconds: 600_000_000)
    } catch {
        return
    }

    var seen: Set<URL> = []
    var warmed = 0

    for url in urls {
        guard !Task.isCancelled, warmed < limit else {
            return
        }
        guard seen.insert(url).inserted else {
            continue
        }
        let isCached = await MainActor.run {
            DiscoverLocalImageCache.shared.contains(url)
        }
        guard !isCached else {
            continue
        }
        guard let decoded = await decodeDiscoverLocalImage(at: url, priority: .utility) else {
            continue
        }
        await MainActor.run {
            DiscoverLocalImageCache.shared.insert(decoded.image, for: url)
        }
        warmed += 1
        do {
            try await Task.sleep(nanoseconds: 8_000_000)
        } catch {
            return
        }
    }
}

private actor DiscoverImageDecodeGate {
    static let shared = DiscoverImageDecodeGate(maxConcurrent: 2)

    private let maxConcurrent: Int
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    func wait() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            activeCount = max(0, activeCount - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private func decodeDiscoverLocalImage(at url: URL, priority: TaskPriority) async -> DecodedDiscoverImage? {
    await DiscoverImageDecodeGate.shared.wait()
    if Task.isCancelled {
        await DiscoverImageDecodeGate.shared.signal()
        return nil
    }

    let result = await Task.detached(priority: priority) { () -> DecodedDiscoverImage? in
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 900
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return DecodedDiscoverImage(image: image)
    }.value
    await DiscoverImageDecodeGate.shared.signal()
    return result
}

private struct DiscoverPDFThumbnailHero: View {
    var urls: [URL]

    var body: some View {
        GeometryReader { proxy in
            let visibleURLs = Array(urls.prefix(5))
            let itemCount = max(visibleURLs.count, 1)
            let itemWidth = max(proxy.size.width / CGFloat(itemCount), 1)

            HStack(spacing: 0) {
                ForEach(Array(visibleURLs.enumerated()), id: \.offset) { _, url in
                    LocalCachedImage(url: url, contentMode: .fill) {
                        Color(nsColor: .controlBackgroundColor)
                            .frame(width: itemWidth, height: proxy.size.height)
                    }
                    .frame(width: itemWidth, height: proxy.size.height)
                    .clipped()
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 1)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .clipped()
        }
        .frame(height: 154)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ArxivPreviewImage: View {
    var url: URL?

    var body: some View {
        Group {
            if let url {
                LocalCachedImage(url: url, contentMode: .fill) {
                    ZStack {
                        Color(nsColor: .separatorColor).opacity(0.22)
                        ProgressView()
                            .controlSize(.small)
                    }
                    .aspectRatio(4.7, contentMode: .fit)
                }
            } else {
                ZStack {
                    Color(nsColor: .separatorColor).opacity(0.22)
                    Image(systemName: "doc.richtext")
                        .font(.paperCodexSystem(size: 24))
                        .foregroundStyle(.secondary)
                }
                .aspectRatio(4.7, contentMode: .fit)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
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
    var link: PaperResourceLink
    var compact: Bool

    var body: some View {
        PaperCodexResourceLinkButton(
            title: link.title,
            systemImage: link.systemImage,
            compact: compact
        ) {
            openExternalURL(link.urlString)
        }
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
        NSSound.beep()
        return
    }
    if !NSWorkspace.shared.open(url) {
        NSSound.beep()
    }
}

private struct FlowTags: View {
    var tags: [String]

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.paperCodexSystem(size: 12))
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
