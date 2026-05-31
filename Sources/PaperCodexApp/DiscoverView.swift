import AppKit
import PaperCodexCore
import SwiftUI

private let discoverRouteToolbarMinHeight: CGFloat = 126

private enum DiscoverScrollPolicy {
    static let scrollRestoreSettleNanoseconds: UInt64 = 320_000_000
    static let scrollPositionCommitDelayNanoseconds: UInt64 = 550_000_000
}

private struct DiscoverLayoutSignature: Hashable {
    var columnCount: Int
    var paperCount: Int
    var paperIDHash: Int
}

@MainActor
private enum NativeDiscoverCardModelBuilder {
    static func models(for papers: [ArxivFeedPaper], model: AppModel) -> [NativeDiscoverCardModel] {
        let libraryArxivPaperIDs = model.libraryArxivPaperIDs()
        return papers.map { paper in
            let enrichment = model.discoverEnrichment(for: paper)
            let languageCode = model.globalLanguageMode.discoverLanguageCode
            let primaryTitle: String
            let secondaryTitle: String
            if languageCode == "zh" {
                let enrichedTitle = enrichment?.titleZH.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                primaryTitle = enrichedTitle.isEmpty ? paper.displayTitle(language: "zh") : enrichedTitle
                secondaryTitle = paper.title.en
            } else {
                primaryTitle = paper.title.en
                secondaryTitle = ""
            }

            let summary: String
            if languageCode == "zh" {
                let enrichedSummary = enrichment?.summaryZH.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !enrichedSummary.isEmpty {
                    summary = enrichedSummary
                } else if !paper.summary.zh.isEmpty {
                    summary = paper.summary.zh
                } else if !paper.summary.en.isEmpty {
                    summary = paper.summary.en
                } else {
                    summary = paper.abstract.en
                }
            } else if !paper.summary.en.isEmpty {
                summary = paper.summary.en
            } else {
                summary = paper.abstract.en
            }

            return NativeDiscoverCardModel(
                id: paper.id,
                primaryCategory: paper.primaryCategory ?? paper.categories.first ?? "arXiv",
                arxivID: paper.id,
                primaryTitle: primaryTitle,
                secondaryTitle: secondaryTitle,
                summary: summary,
                contribution: enrichment?.contribution,
                error: enrichment?.error,
                tags: tags(for: paper, enrichment: enrichment),
                links: links(for: paper, enrichment: enrichment),
                imageURL: model.cachedArxivAssetURL(for: paper.assets.small),
                thumbnailURLs: model.cachedArxivPDFThumbnailURLs(for: paper),
                inLibrary: libraryArxivPaperIDs.contains(paper.id),
                isBusy: model.isDownloadingArxivPaper(paper),
                downloadProgress: model.arxivDownloadProgress(for: paper),
                interactionState: model.discoverPaperInteractionStateByID[paper.id]
            )
        }
    }

    private static func tags(for paper: ArxivFeedPaper, enrichment: DiscoverPaperEnrichment?) -> [String] {
        let fallback = paper.tags.isEmpty ? paper.categories : paper.tags
        var seen: Set<String> = []
        var result: [String] = []
        for tag in (enrichment?.tags ?? []) + fallback {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    private static func links(for paper: ArxivFeedPaper, enrichment: DiscoverPaperEnrichment?) -> [NativeDiscoverCardLink] {
        var result = baseLinks(for: paper)

        func append(id: String, title: String, systemImage: String, key: String) {
            guard let value = enrichment?.links[key] else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !result.contains(where: { $0.urlString.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
                return
            }
            result.append(NativeDiscoverCardLink(id: id, title: title, systemImage: systemImage, urlString: trimmed))
        }
        append(id: "github-enriched", title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right", key: "github")
        append(id: "project-enriched", title: "Project", systemImage: "globe", key: "project")
        append(id: "hf-enriched", title: "HF", systemImage: "shippingbox", key: "hugging_face")
        return result
    }

    private static func baseLinks(for paper: ArxivFeedPaper) -> [NativeDiscoverCardLink] {
        var result: [NativeDiscoverCardLink] = []
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
            result.append(NativeDiscoverCardLink(id: id, title: title, systemImage: systemImage, urlString: urlString))
        }

        append(id: "github", title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right", urlString: paper.links.github ?? paper.links.code)
        append(id: "project", title: "Project", systemImage: "globe", urlString: paper.links.project)
        append(id: "hf", title: "HF", systemImage: "shippingbox", urlString: paper.links.huggingFace)
        append(id: "arxiv", title: "arXiv", systemImage: "doc.text", urlString: paper.links.abs)
        append(id: "pdf", title: "PDF", systemImage: "doc.richtext", urlString: paper.links.pdf)
        return result
    }
}

@MainActor
private final class NativeDiscoverCardModelCache: ObservableObject {
    private struct Entry {
        var signature: Int
        var models: [NativeDiscoverCardModel]
    }

    private var entries: [String: Entry] = [:]

    func models(scope: String, for papers: [ArxivFeedPaper], model: AppModel) -> [NativeDiscoverCardModel] {
        let signature = Self.signature(scope: scope, papers: papers, model: model)
        if let entry = entries[scope], entry.signature == signature {
            return entry.models
        }
        let models = NativeDiscoverCardModelBuilder.models(for: papers, model: model)
        entries[scope] = Entry(signature: signature, models: models)
        return models
    }

    private static func signature(scope: String, papers: [ArxivFeedPaper], model: AppModel) -> Int {
        var hasher = Hasher()
        hasher.combine(scope)
        hasher.combine(model.globalLanguageMode.rawValue)
        combineLibrarySignature(model.papers, into: &hasher)
        for paper in papers {
            combinePaperSignature(paper, model: model, into: &hasher)
        }
        return hasher.finalize()
    }

    private static func combineLibrarySignature(_ papers: [Paper], into hasher: inout Hasher) {
        hasher.combine(papers.count)
        hasher.combine(papers.first?.id)
        hasher.combine(papers.last?.id)
        var latestUpdate: TimeInterval = 0
        for paper in papers {
            latestUpdate = max(latestUpdate, paper.updatedAt.timeIntervalSinceReferenceDate)
        }
        hasher.combine(latestUpdate)
    }

    private static func combinePaperSignature(_ paper: ArxivFeedPaper, model: AppModel, into hasher: inout Hasher) {
        hasher.combine(paper.id)
        hasher.combine(paper.thumbnailVersion)
        hasher.combine(paper.categories.count)
        hasher.combine(paper.tags.count)
        hasher.combine(paper.assets.small?.path)
        hasher.combine(paper.links.github != nil || paper.links.code != nil)
        hasher.combine(paper.links.project != nil)
        hasher.combine(paper.links.huggingFace != nil)

        if let enrichment = model.discoverEnrichment(for: paper) {
            hasher.combine(enrichment.generatedAt.timeIntervalSinceReferenceDate)
            hasher.combine(enrichment.error)
            hasher.combine(enrichment.tags.count)
            hasher.combine(enrichment.links.count)
        }

        hasher.combine(model.arxivAssetURLs[paper.assets.small?.path ?? ""] != nil)
        hasher.combine(model.arxivPDFThumbnailURLsByID[paper.id]?.count ?? 0)
        hasher.combine(model.arxivDownloadingPaperIDs.contains(paper.id))
        hasher.combine(model.arxivDownloadProgressByID[paper.id])
        combineInteractionState(model.discoverPaperInteractionStateByID[paper.id], into: &hasher)
    }

    private static func combineInteractionState(_ state: DiscoverPaperInteractionState?, into hasher: inout Hasher) {
        switch state {
        case nil:
            hasher.combine("none")
        case .queued:
            hasher.combine("queued")
        case .processing:
            hasher.combine("processing")
        case .processed:
            hasher.combine("processed")
        case .cached:
            hasher.combine("cached")
        case .failed:
            hasher.combine("failed")
        case .cancelled:
            hasher.combine("cancelled")
        case .downloading:
            hasher.combine("downloading")
        case .pdfCached:
            hasher.combine("pdfCached")
        }
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var cardModelCache = NativeDiscoverCardModelCache()
    @State private var nativeDiscoverCardModels: [NativeDiscoverCardModel] = []
    @State private var nativeDiscoverCardInputID: Int?
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
    @State private var discoverScrollRestoreTask: Task<Void, Never>?
    @State private var discoverScrollRequestToken = 0

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
        model.discoverSidebarFacets.categories
    }

    private var tags: [String] {
        model.discoverSidebarFacets.sortedTags
    }

    private var tagCounts: [String: Int] {
        model.discoverSidebarFacets.tagCounts
    }

    private var totalTagCount: Int {
        model.discoverSidebarFacets.totalTagCount
    }

    private var commonCategories: [String] {
        ["cs.CV", "cs.CL", "cs.AI", "cs.LG", "cs.RO", "stat.ML", "cs.HC", "cs.IR", "cs.SE"]
    }

    private var sidebarContentID: AnyHashable {
        var hasher = Hasher()
        hasher.combine("discover-sidebar")
        hasher.combine(selectedCategory)
        hasher.combine(selectedTag)
        hasher.combine(selectedProcessingFilter.rawValue)
        hasher.combine(selectedLibraryFilter.rawValue)
        hasher.combine(requiresProjectLink)
        hasher.combine(selectedSimilarityBucket.rawValue)
        hasher.combine(totalTagCount)
        for category in categories {
            hasher.combine(category)
        }
        for tag in tags.prefix(18) {
            hasher.combine(tag)
            hasher.combine(tagCounts[tag, default: 0])
        }
        return AnyHashable(hasher.finalize())
    }

    private func tags(for paper: ArxivFeedPaper) -> [String] {
        DiscoverSidebarFacets.tags(for: paper, enrichment: model.discoverEnrichment(for: paper))
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
            .paperCodexNativeSheet(item: $paperPendingSave, title: "Save to Library", minimumSize: CGSize(width: 620, height: 520)) { paper in
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
            .paperCodexNativeSheet(isPresented: $isShowingProcessSelection, title: "Process Papers", minimumSize: CGSize(width: 520, height: 420)) {
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

            PaperCodexNativeScrollView(contentID: sidebarContentID) {
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
                            detail: "\(totalTagCount)",
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
                PaperCodexNativeEmptyState(title: "No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let cardInputID = nativeDiscoverCardInputID(for: visiblePapers)
                let cardModels = nativeDiscoverCardModels
                GeometryReader { proxy in
                    let layoutSignature = rowLayoutSignature(
                        papers: visiblePapers,
                        columnCount: gridColumnCount(for: proxy.size.width)
                    )

                    NativeDiscoverCollectionView(
                        cards: cardModels,
                        restorePaperID: model.discoverScrollPositionPaperID,
                        restoreToken: discoverScrollRequestToken,
                        onVisiblePaperChange: { paperID in
                            markDiscoverVisibleRow(paperID, in: visiblePapers)
                        },
                        onPreview: { paperID in
                            guard let paper = visiblePapers.first(where: { $0.id == paperID }) else {
                                return
                            }
                            previewPaper = paper
                        },
                        onSave: { paperID in
                            guard let paper = visiblePapers.first(where: { $0.id == paperID }) else {
                                return
                            }
                            paperPendingSave = paper
                        },
                        onOpen: { paperID in
                            guard let paper = visiblePapers.first(where: { $0.id == paperID }) else {
                                return
                            }
                            commitDiscoverScrollPosition(fallbackPaperID: paper.id, in: visiblePapers)
                            Task {
                                await model.openArxivPaper(paper)
                            }
                        }
                    )
                    .onAppear {
                        updateNativeDiscoverCardModels(for: visiblePapers, inputID: cardInputID)
                        requestNativeDiscoverScrollRestore()
                    }
                    .onChange(of: cardInputID) { _, newInputID in
                        updateNativeDiscoverCardModels(for: visiblePapers, inputID: newInputID)
                    }
                    .onChange(of: layoutSignature) { _, _ in
                        requestNativeDiscoverScrollRestore()
                    }
                    .onDisappear {
                        commitDiscoverScrollPosition(fallbackPaperID: visibleDiscoverPaperID, in: visiblePapers)
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

    private func nativeDiscoverCardInputID(for papers: [ArxivFeedPaper]) -> Int {
        var hasher = Hasher()
        hasher.combine("discover")
        hasher.combine(model.globalLanguageMode.rawValue)
        hasher.combine(model.papers.count)
        hasher.combine(model.discoverEnrichmentsByID.count)
        hasher.combine(model.arxivAssetURLs.count)
        hasher.combine(model.arxivPDFThumbnailURLsByID.count)
        hasher.combine(model.arxivDownloadingPaperIDs.count)
        hasher.combine(model.arxivDownloadProgressByID.count)
        hasher.combine(model.discoverPaperInteractionStateByID.count)
        hasher.combine(papers.count)
        for paper in papers {
            hasher.combine(paper.id)
            hasher.combine(paper.thumbnailVersion)
        }
        return hasher.finalize()
    }

    private func updateNativeDiscoverCardModels(for papers: [ArxivFeedPaper], inputID: Int) {
        guard nativeDiscoverCardInputID != inputID else {
            return
        }
        nativeDiscoverCardInputID = inputID
        nativeDiscoverCardModels = cardModelCache.models(scope: "discover", for: papers, model: model)
    }

    private func requestNativeDiscoverScrollRestore() {
        discoverScrollPositionCommitTask?.cancel()
        discoverScrollRestoreTask?.cancel()
        visibleDiscoverPaperID = model.discoverScrollPositionPaperID
        isRestoringDiscoverScrollPosition = true
        discoverScrollRequestToken += 1
        discoverScrollRestoreTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: DiscoverScrollPolicy.scrollRestoreSettleNanoseconds)
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
        guard visibleDiscoverPaperID != paperID else {
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
            try? await Task.sleep(nanoseconds: DiscoverScrollPolicy.scrollPositionCommitDelayNanoseconds)
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
    @StateObject private var cardModelCache = NativeDiscoverCardModelCache()
    @State private var nativeSearchCardModels: [NativeDiscoverCardModel] = []
    @State private var nativeSearchCardInputID: Int?
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

    private var sidebarContentID: AnyHashable {
        var hasher = Hasher()
        hasher.combine("search-sidebar")
        hasher.combine(selectedCategory)
        hasher.combine(selectedLibraryFilter.rawValue)
        for category in model.arxivSearchRequiredCategories {
            hasher.combine(category)
        }
        for category in requiredCategoryOptions {
            hasher.combine(category)
        }
        for category in resultCategories {
            hasher.combine(category)
        }
        return AnyHashable(hasher.finalize())
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
        .paperCodexNativeSheet(item: $paperPendingSave, title: "Save to Library", minimumSize: CGSize(width: 620, height: 520)) { paper in
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
        .paperCodexNativeSheet(isPresented: $isShowingProcessSelection, title: "Process Papers", minimumSize: CGSize(width: 520, height: 420)) {
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

            PaperCodexNativeScrollView(contentID: sidebarContentID) {
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
                PaperCodexNativeEmptyState(title: "No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let cardInputID = nativeSearchCardInputID(for: papers)
                let cardModels = nativeSearchCardModels
                GeometryReader { _ in
                    NativeDiscoverCollectionView(
                        cards: cardModels,
                        restorePaperID: nil,
                        restoreToken: 0,
                        onVisiblePaperChange: { _ in },
                        onPreview: { paperID in
                            guard let paper = papers.first(where: { $0.id == paperID }) else {
                                return
                            }
                            previewPaper = paper
                        },
                        onSave: { paperID in
                            guard let paper = papers.first(where: { $0.id == paperID }) else {
                                return
                            }
                            paperPendingSave = paper
                        },
                        onOpen: { paperID in
                            guard let paper = papers.first(where: { $0.id == paperID }) else {
                                return
                            }
                            Task {
                                await model.openArxivPaper(paper)
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        updateNativeSearchCardModels(for: papers, inputID: cardInputID)
                    }
                    .onChange(of: cardInputID) { _, newInputID in
                        updateNativeSearchCardModels(for: papers, inputID: newInputID)
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

    private func nativeSearchCardInputID(for papers: [ArxivFeedPaper]) -> Int {
        var hasher = Hasher()
        hasher.combine("search")
        hasher.combine(model.globalLanguageMode.rawValue)
        hasher.combine(model.papers.count)
        hasher.combine(model.discoverEnrichmentsByID.count)
        hasher.combine(model.arxivAssetURLs.count)
        hasher.combine(model.arxivPDFThumbnailURLsByID.count)
        hasher.combine(model.arxivDownloadingPaperIDs.count)
        hasher.combine(model.arxivDownloadProgressByID.count)
        hasher.combine(model.discoverPaperInteractionStateByID.count)
        hasher.combine(papers.count)
        for paper in papers {
            hasher.combine(paper.id)
            hasher.combine(paper.thumbnailVersion)
        }
        return hasher.finalize()
    }

    private func updateNativeSearchCardModels(for papers: [ArxivFeedPaper], inputID: Int) {
        guard nativeSearchCardInputID != inputID else {
            return
        }
        nativeSearchCardInputID = inputID
        nativeSearchCardModels = cardModelCache.models(scope: "search", for: papers, model: model)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var onRemove: () -> Void

    var body: some View {
        NativeDiscoverFilterChipButton(title: title, reduceMotion: reduceMotion, action: onRemove)
            .fixedSize(horizontal: true, vertical: true)
        .help("Remove \(title) filter")
        .accessibilityLabel("Remove \(title) filter")
    }
}

private struct NativeDiscoverFilterChipButton: NSViewRepresentable {
    var title: String
    var reduceMotion: Bool
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NativeDiscoverFilterChipButtonView {
        let button = NativeDiscoverFilterChipButtonView()
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction(_:))
        button.apply(title: title, reduceMotion: reduceMotion)
        return button
    }

    func updateNSView(_ button: NativeDiscoverFilterChipButtonView, context: Context) {
        context.coordinator.action = action
        button.apply(title: title, reduceMotion: reduceMotion)
    }

    @MainActor final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
            super.init()
        }

        @objc func performAction(_ sender: NSButton) {
            action()
        }
    }
}

private final class NativeDiscoverFilterChipButtonView: NSButton {
    private var trackingAreaToken: NSTrackingArea?
    private var reduceMotion = false
    private var isHovering = false
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = (title as NSString).size(withAttributes: [.font: font ?? .systemFont(ofSize: 11, weight: .medium)]).width
        return NSSize(width: ceil(textWidth) + 34, height: 23)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaToken {
            removeTrackingArea(trackingAreaToken)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaToken = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressed = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
        super.mouseDown(with: event)
        isPressed = false
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func apply(title: String, reduceMotion: Bool) {
        self.title = title
        self.reduceMotion = reduceMotion
        toolTip = "Remove \(title) filter"
        setAccessibilityLabel("Remove \(title) filter")
        invalidateIntrinsicContentSize()
        updateAppearance()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        font = .systemFont(ofSize: 11, weight: .medium)
        alignment = .center
        imagePosition = .imageLeading
        imageScaling = .scaleProportionallyDown
        image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        image?.isTemplate = true
        layer?.cornerRadius = 11.5
        layer?.masksToBounds = false
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        updateAppearance()
    }

    private func updateAppearance() {
        let accent = NSColor.controlAccentColor
        let foreground = accent.withAlphaComponent(isPressed ? 1 : (isHovering ? 0.96 : 0.88))
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font ?? .systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: foreground
            ]
        )
        contentTintColor = foreground
        layer?.backgroundColor = accent.withAlphaComponent(isPressed ? 0.18 : (isHovering ? 0.14 : 0.10)).cgColor
        layer?.borderWidth = isPressed || isHovering ? 1 : 0
        layer?.borderColor = accent.withAlphaComponent(isPressed ? 0.56 : 0.36).cgColor
        layer?.shadowColor = accent.cgColor
        layer?.shadowOpacity = isPressed ? 0.10 : (isHovering ? 0.13 : 0)
        layer?.shadowRadius = isPressed ? 3 : 5
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? -1 : -2)

        let scale: CGFloat
        if reduceMotion {
            scale = 1
        } else if isPressed {
            scale = 0.965
        } else {
            scale = isHovering ? 1.025 : 1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
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

            PaperCodexNativeScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        PaperCodexNativeSpinner()
                            .frame(width: 16, height: 16)
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
            DiscoverQuickRangePopup(ranges: ranges, onSelect: onSelect)
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

private struct DiscoverQuickRangePopup: View {
    var ranges: [DiscoverQuickRange]
    var onSelect: (DiscoverQuickRange) -> Void

    private var items: [DiscoverMenuItem] {
        ranges.map { range in
            DiscoverMenuItem(title: range.title, value: range.rawValue)
        }
    }

    var body: some View {
        NativeDiscoverMenuButton(
            labelTitle: "Ranges",
            systemImage: "calendar.badge.clock",
            items: items,
            selectedValue: nil,
            accessibilityLabel: "Date ranges"
        ) { value in
            guard let range = ranges.first(where: { $0.rawValue == value }) else {
                return
            }
            onSelect(range)
        }
        .frame(width: 118, height: 28)
        .fixedSize()
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
                    PaperCodexPanelButton(title: "Select All", systemImage: "checkmark.circle") {
                        selectedActions = Set(DiscoverProcessAction.allCases)
                    }
                    PaperCodexPanelButton(title: "Clear", systemImage: "xmark.circle") {
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
                        PaperCodexPanelButton(
                            title: isRefreshingModels ? "Refreshing" : "Refresh Models",
                            systemImage: "arrow.clockwise",
                            disabled: isRefreshingModels
                        ) {
                            onRefreshModels()
                        }
                    }

                    HStack(spacing: 10) {
                        Text("Model")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        DiscoverProcessModelPopup(
                            selection: $draftModelOverride,
                            defaultModelLabel: codexDefaultModelLabel,
                            availableModelIDs: availableModelIDs
                        )
                        .frame(maxWidth: .infinity, minHeight: 30)
                    }

                    HStack(spacing: 10) {
                        Text("Override")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        DiscoverProcessTextField(
                            text: $draftModelOverride,
                            placeholder: "Custom model override"
                        )
                        .frame(maxWidth: .infinity, minHeight: 30)
                    }

                    HStack(spacing: 10) {
                        Text("Thinking")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        DiscoverProcessThinkingPopup(selection: $draftReasoningEffort)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
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
        DiscoverProcessActionToggleRow(action: action, isSelected: $isSelected)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }
}

private struct DiscoverMenuItem: Equatable {
    enum Kind: Equatable {
        case action
        case separator
        case heading
    }

    var title: String
    var value: String?
    var kind: Kind

    init(title: String, value: String) {
        self.title = title
        self.value = value
        self.kind = .action
    }

    static func separator() -> DiscoverMenuItem {
        DiscoverMenuItem(title: "", value: nil, kind: .separator)
    }

    static func heading(_ title: String) -> DiscoverMenuItem {
        DiscoverMenuItem(title: title, value: nil, kind: .heading)
    }

    private init(title: String, value: String?, kind: Kind) {
        self.title = title
        self.value = value
        self.kind = kind
    }
}

private struct NativeDiscoverMenuButton: View {
    var labelTitle: String?
    var systemImage: String?
    var items: [DiscoverMenuItem]
    var selectedValue: String?
    var accessibilityLabel: String
    var onSelect: (String) -> Void

    var body: some View {
        NativeDiscoverMenuButtonRepresentable(
            labelTitle: labelTitle,
            systemImage: systemImage,
            items: items,
            selectedValue: selectedValue,
            accessibilityLabel: accessibilityLabel,
            onSelect: onSelect
        )
    }
}

private struct NativeDiscoverMenuButtonRepresentable: NSViewRepresentable {
    var labelTitle: String?
    var systemImage: String?
    var items: [DiscoverMenuItem]
    var selectedValue: String?
    var accessibilityLabel: String
    var onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, isPullDown: labelTitle != nil)
    }

    func makeNSView(context: Context) -> NativeDiscoverMenuButtonView {
        let popup = NativeDiscoverMenuButtonView(pullsDown: labelTitle != nil)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        popup.apply(
            labelTitle: labelTitle,
            systemImage: systemImage,
            items: items,
            selectedValue: selectedValue,
            accessibilityLabel: accessibilityLabel
        )
        return popup
    }

    func updateNSView(_ popup: NativeDiscoverMenuButtonView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.isPullDown = labelTitle != nil
        popup.apply(
            labelTitle: labelTitle,
            systemImage: systemImage,
            items: items,
            selectedValue: selectedValue,
            accessibilityLabel: accessibilityLabel
        )
    }

    @MainActor final class Coordinator: NSObject {
        var onSelect: (String) -> Void
        var isPullDown: Bool

        init(onSelect: @escaping (String) -> Void, isPullDown: Bool) {
            self.onSelect = onSelect
            self.isPullDown = isPullDown
            super.init()
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let value = sender.selectedItem?.representedObject as? String else {
                if isPullDown {
                    sender.selectItem(at: 0)
                }
                return
            }
            onSelect(value)
            if isPullDown {
                sender.selectItem(at: 0)
            }
        }
    }
}

private final class NativeDiscoverMenuButtonView: NSPopUpButton {
    private let isPullDownMenu: Bool
    private var renderedItems: [DiscoverMenuItem] = []
    private var renderedLabelTitle: String?

    init(pullsDown: Bool) {
        self.isPullDownMenu = pullsDown
        super.init(frame: .zero, pullsDown: pullsDown)
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

    override func mouseDown(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.06
            animator().alphaValue = 0.72
        }
        super.mouseDown(with: event)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            animator().alphaValue = 1
        }
    }

    func apply(
        labelTitle: String?,
        systemImage: String?,
        items: [DiscoverMenuItem],
        selectedValue: String?,
        accessibilityLabel: String
    ) {
        if items != renderedItems || labelTitle != renderedLabelTitle || numberOfItems == 0 {
            removeAllItems()
            if let labelTitle {
                addItem(withTitle: labelTitle)
                lastItem?.image = systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: labelTitle) }
                lastItem?.representedObject = nil
            }
            for item in items {
                switch item.kind {
                case .separator:
                    menu?.addItem(.separator())
                case .heading:
                    let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                    menuItem.isEnabled = false
                    menu?.addItem(menuItem)
                case .action:
                    addItem(withTitle: item.title)
                    lastItem?.representedObject = item.value
                }
            }
            renderedItems = items
            renderedLabelTitle = labelTitle
        }

        for item in itemArray {
            guard let value = item.representedObject as? String else {
                item.state = .off
                continue
            }
            item.state = value == selectedValue ? .on : .off
        }

        if isPullDownMenu {
            selectItem(at: 0)
        } else if let selectedValue,
                  let selectedItem = itemArray.first(where: { $0.representedObject as? String == selectedValue }) {
            select(selectedItem)
        } else if let firstSelectable = itemArray.first(where: { $0.representedObject is String }) {
            select(firstSelectable)
        }
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityValue(selectedItem?.title ?? labelTitle ?? "")
        toolTip = accessibilityLabel
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        controlSize = .regular
        font = .systemFont(ofSize: 12.5, weight: .semibold)
        focusRingType = .default
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }
}

private struct DiscoverProcessModelPopup: NSViewRepresentable {
    @Binding var selection: String
    var defaultModelLabel: String
    var availableModelIDs: [String]

    private var items: [(title: String, value: String)] {
        var result: [(title: String, value: String)] = [(defaultModelLabel, "")]
        for modelID in availableModelIDs where !modelID.isEmpty {
            if !result.contains(where: { $0.value == modelID }) {
                result.append((modelID, modelID))
            }
        }
        if !selection.isEmpty,
           !result.contains(where: { $0.value == selection }) {
            result.append(("\(selection) (custom)", selection))
        }
        return result
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NativeDiscoverProcessPopupButton {
        let popup = NativeDiscoverProcessPopupButton()
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        popup.apply(items: items, selection: selection, accessibilityLabel: "Model")
        return popup
    }

    func updateNSView(_ popup: NativeDiscoverProcessPopupButton, context: Context) {
        context.coordinator.selection = $selection
        popup.apply(items: items, selection: selection, accessibilityLabel: "Model")
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

private struct DiscoverProcessThinkingPopup: NSViewRepresentable {
    @Binding var selection: CodexReasoningEffort

    private var items: [(title: String, value: String)] {
        CodexReasoningEffort.allCases.map { effort in
            (effort.displayName, effort.rawValue)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NativeDiscoverProcessPopupButton {
        let popup = NativeDiscoverProcessPopupButton()
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        popup.apply(items: items, selection: selection.rawValue, accessibilityLabel: "Thinking")
        return popup
    }

    func updateNSView(_ popup: NativeDiscoverProcessPopupButton, context: Context) {
        context.coordinator.selection = $selection
        popup.apply(items: items, selection: selection.rawValue, accessibilityLabel: "Thinking")
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<CodexReasoningEffort>

        init(selection: Binding<CodexReasoningEffort>) {
            self.selection = selection
            super.init()
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let value = sender.selectedItem?.representedObject as? String,
                  let effort = CodexReasoningEffort(rawValue: value) else {
                return
            }
            selection.wrappedValue = effort
        }
    }
}

private final class NativeDiscoverProcessPopupButton: NSPopUpButton {
    private var itemValues: [String] = []

    init() {
        super.init(frame: .zero, pullsDown: false)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 30)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(items: [(title: String, value: String)], selection: String, accessibilityLabel: String) {
        let values = items.map(\.value)
        if values != itemValues || numberOfItems != items.count {
            removeAllItems()
            for item in items {
                addItem(withTitle: item.title)
                lastItem?.representedObject = item.value
            }
            itemValues = values
        }

        if let index = values.firstIndex(of: selection) {
            selectItem(at: index)
        } else if !items.isEmpty {
            selectItem(at: 0)
        }
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityValue(selectedItem?.title ?? "")
        toolTip = selectedItem?.title
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        controlSize = .regular
        font = .systemFont(ofSize: 13)
        focusRingType = .default
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}

private struct DiscoverProcessTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NativeDiscoverProcessTextFieldView {
        let textField = NativeDiscoverProcessTextFieldView()
        textField.delegate = context.coordinator
        textField.apply(text: text, placeholder: placeholder)
        return textField
    }

    func updateNSView(_ textField: NativeDiscoverProcessTextFieldView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isUpdatingFromSwiftUI = true
        textField.apply(text: text, placeholder: placeholder)
        context.coordinator.isUpdatingFromSwiftUI = false
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var isUpdatingFromSwiftUI = false

        init(text: Binding<String>) {
            self.text = text
            super.init()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI,
                  let textField = notification.object as? NSTextField else {
                return
            }
            text.wrappedValue = textField.stringValue
        }
    }
}

private final class NativeDiscoverProcessTextFieldView: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 30)
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
        font = .systemFont(ofSize: 13)
        isBordered = true
        isBezeled = true
        bezelStyle = .roundedBezel
        focusRingType = .default
        usesSingleLineMode = true
        lineBreakMode = .byTruncatingTail
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}

private struct DiscoverProcessActionToggleRow: NSViewRepresentable {
    var action: DiscoverProcessAction
    @Binding var isSelected: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isSelected: $isSelected)
    }

    func makeNSView(context: Context) -> NativeDiscoverProcessActionToggleRowView {
        let row = NativeDiscoverProcessActionToggleRowView()
        row.apply(action: action, isSelected: isSelected) { selected in
            context.coordinator.selectionChanged(selected)
        }
        return row
    }

    func updateNSView(_ row: NativeDiscoverProcessActionToggleRowView, context: Context) {
        context.coordinator.isSelected = $isSelected
        row.apply(action: action, isSelected: isSelected) { selected in
            context.coordinator.selectionChanged(selected)
        }
    }

    @MainActor final class Coordinator: NSObject {
        var isSelected: Binding<Bool>

        init(isSelected: Binding<Bool>) {
            self.isSelected = isSelected
            super.init()
        }

        func selectionChanged(_ selected: Bool) {
            isSelected.wrappedValue = selected
        }
    }
}

private final class NativeDiscoverProcessActionToggleRowView: NSView {
    private let checkBox = NativeDiscoverProcessActionToggleButton()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var currentIsSelected = false
    private var toggleHandler: (Bool) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 64)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    override func mouseDown(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.06
            animator().alphaValue = 0.72
        }
        setSelected(!currentIsSelected, notify: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            animator().alphaValue = 1
        }
    }

    func apply(action: DiscoverProcessAction, isSelected: Bool, onToggle: @escaping (Bool) -> Void) {
        currentIsSelected = isSelected
        toggleHandler = onToggle
        checkBox.state = isSelected ? .on : .off
        checkBox.setAccessibilityLabel(action.title)
        checkBox.setAccessibilityValue(isSelected ? "Selected" : "Not selected")
        iconView.image = NSImage(systemSymbolName: action.systemImage, accessibilityDescription: action.title)
        titleLabel.stringValue = NSLocalizedString(action.title, comment: "")
        detailLabel.stringValue = NSLocalizedString(action.detail, comment: "")
        toolTip = "\(action.title)\n\(action.detail)"
        updateBackground()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        checkBox.translatesAutoresizingMaskIntoConstraints = false
        checkBox.target = self
        checkBox.action = #selector(checkBoxChanged(_:))
        checkBox.setContentHuggingPriority(.required, for: .horizontal)
        checkBox.setContentCompressionResistancePriority(.required, for: .horizontal)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        iconView.contentTintColor = .controlAccentColor
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1

        addSubview(checkBox)
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(detailLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 64),
            checkBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            checkBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkBox.widthAnchor.constraint(equalToConstant: 18),
            checkBox.heightAnchor.constraint(equalToConstant: 18),
            iconView.leadingAnchor.constraint(equalTo: checkBox.trailingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10)
        ])
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateBackground()
    }

    @objc private func checkBoxChanged(_ sender: NSButton) {
        setSelected(sender.state == .on, notify: true)
    }

    private func setSelected(_ selected: Bool, notify: Bool) {
        currentIsSelected = selected
        checkBox.state = selected ? .on : .off
        checkBox.setAccessibilityValue(selected ? "Selected" : "Not selected")
        updateBackground()
        if notify {
            toggleHandler(selected)
        }
    }

    private func updateBackground() {
        let backgroundColor = currentIsSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.10)
            : NSColor.controlBackgroundColor
        let borderColor = currentIsSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.32)
            : NSColor.separatorColor.withAlphaComponent(0.40)
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderColor = borderColor.cgColor
    }
}

private final class NativeDiscoverProcessActionToggleButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 18, height: 18)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.06
            animator().alphaValue = 0.72
        }
        super.mouseDown(with: event)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            animator().alphaValue = 1
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        title = ""
        isBordered = false
        controlSize = .regular
        focusRingType = .default
        setButtonType(.switch)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
    }
}

private struct DiscoverCategoryMenu: View {
    var categories: [String]
    var selected: String
    var onSelect: (String) -> Void

    private var items: [DiscoverMenuItem] {
        categories.map { DiscoverMenuItem(title: $0, value: $0) }
    }

    var body: some View {
        NativeDiscoverMenuButton(
            labelTitle: nil,
            systemImage: "tray.full",
            items: items,
            selectedValue: selected,
            accessibilityLabel: "Primary arXiv category",
            onSelect: onSelect
        )
        .frame(minWidth: 82, idealWidth: 94, maxWidth: 130, minHeight: 28, maxHeight: 28)
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

    private var selectedValue: String {
        if model.discoverSelectedSimilaritySourceIDs.count == 1 {
            return model.discoverSelectedSimilaritySourceIDs[0]
        }
        if model.discoverSelectedSimilaritySourceIDs.isEmpty {
            return ""
        }
        return "__selected_sources__"
    }

    private var items: [DiscoverMenuItem] {
        var result = [DiscoverMenuItem(title: "Settings default", value: "")]
        if selectedValue == "__selected_sources__" {
            result.append(DiscoverMenuItem(title: selectedTitle, value: "__selected_sources__"))
        }
        if !model.categories.isEmpty {
            result.append(.separator())
            result.append(.heading("Folders"))
            result += model.categories.map { category in
                DiscoverMenuItem(title: category.name, value: "category:\(category.id)")
            }
        }
        return result
    }

    var body: some View {
        NativeDiscoverMenuButton(
            labelTitle: nil,
            systemImage: "point.3.connected.trianglepath.dotted",
            items: items,
            selectedValue: selectedValue,
            accessibilityLabel: "Similarity source"
        ) { value in
            if value == "__selected_sources__" {
                return
            }
            selectSources(value.isEmpty ? [] : [value])
        }
        .frame(minWidth: 118, idealWidth: 148, maxWidth: 220, minHeight: 28, maxHeight: 28)
        .fixedSize()
        .help("Similarity source")
    }
}

private struct ArxivCacheProgressStrip: View {
    var progress: ArxivCacheProgress

    var body: some View {
        HStack(spacing: 10) {
            if let fraction = progress.fraction {
                PaperCodexNativeProgressBar(value: fraction)
                    .frame(width: 150)
            } else {
                PaperCodexNativeProgressBar(value: nil)
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
                PaperCodexNativeSpinner(controlSize: .large, tintColor: .white)
                    .frame(width: 28, height: 28)
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
