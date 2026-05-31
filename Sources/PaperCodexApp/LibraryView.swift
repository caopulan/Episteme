import PaperCodexCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingWatchedFolders = false
    @State private var isShowingArxivImport = false
    @State private var isCreatingCategory = false
    @State private var isCreatingTag = false
    @State private var newCategoryName = ""
    @State private var newCategoryParentID = ""
    @State private var newTagName = ""
    @State private var selectedPaperIDs: Set<String> = []
    @State private var lastSelectedPaperID: String?
    @State private var lastPaperRowClick: LibraryPaperRowClick?
    @State private var isShowingBulkCopy = false
    @State private var isShowingBulkTag = false
    @State private var isConfirmingBulkDelete = false
    @State private var collapsedCategoryIDs: Set<String> = []
    @State private var categoryPendingManagement: PaperCodexCore.Category?
    @State private var categoryPendingDelete: PaperCodexCore.Category?
    @State private var tagPendingManagement: PaperTag?
    @State private var tagPendingDelete: PaperTag?
    @State private var outlineDraggedCategoryID: String?
    @State private var watchedFolderPendingRemoval: WatchedFolder?
    @State private var noteTitle = ""
    @State private var noteBody = ""
    @State private var editingNoteID: String?
    @State private var selectedRecentSessionID: String?
    @State private var selectedPaperRevealRequestID: UUID?
    @State private var paperTableFocusRequestID: UUID?
    @State private var inspectorDetailsPaperID: String?
    @State private var inspectorDetailsRequestID: UUID?
    @AppStorage("PaperCodexLibrarySortOption") private var librarySortRawValue = LibrarySortOption.addedNewest.rawValue
    @AppStorage("PaperCodexLibrarySortAscending") private var librarySortAscending = false
    @AppStorage("PaperCodexLibraryIncludeSubfolders") private var libraryIncludeSubfolders = true

    private var searchText: String {
        get { model.librarySearchText }
        nonmutating set { model.librarySearchText = newValue }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { model.librarySearchText },
            set: { model.librarySearchText = $0 }
        )
    }

    private var selectedCategoryID: String? {
        get { model.librarySelectedCategoryID }
        nonmutating set { model.librarySelectedCategoryID = newValue }
    }

    private var selectedTagID: String? {
        get { model.librarySelectedTagID }
        nonmutating set { model.librarySelectedTagID = newValue }
    }

    private var selectedLibrarySurface: LibrarySurface {
        get { model.selectedLibrarySurface }
        nonmutating set { model.selectedLibrarySurface = newValue }
    }

    private var filteredPaperIDs: [String] {
        makePaperListState().paperIDs
    }

    private var sidebarCategories: [PaperCodexCore.Category] {
        model.categories
    }

    private var sortedPapers: [Paper] {
        makePaperListState().papers
    }

    private var selectedPaperIDsInOrder: [String] {
        let selected = selectedPaperIDs
        return sortedPapers.map(\.id).filter { selected.contains($0) }
    }

    private var selectedReadablePaperIDsInOrder: [String] {
        selectedPaperIDsInOrder.filter { paperID in
            sortedPapers.first(where: { $0.id == paperID })?.isArxivImportPlaceholder == false
        }
    }

    private var selectedRecentSession: PaperSession? {
        if let selectedRecentSessionID,
           let session = model.recentSessions.first(where: { $0.id == selectedRecentSessionID }) {
            return session
        }
        return model.recentSessions.first
    }

    private func makePaperListState() -> LibraryPaperListState {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let derivedState = model.libraryDerivedState
        var paperIDFilter: Set<String>?

        if let selectedCategoryID {
            paperIDFilter = derivedState.paperIDsForCategoryFilter(
                selectedCategoryID,
                includeDescendants: libraryIncludeSubfolders
            )
        }

        if let selectedTagID {
            let tagPaperIDs = derivedState.paperIDsForTag(selectedTagID)
            if let existingFilter = paperIDFilter {
                paperIDFilter = existingFilter.intersection(tagPaperIDs)
            } else {
                paperIDFilter = tagPaperIDs
            }
        }

        var papers = model.papers
        if let paperIDFilter {
            papers = papers.filter { paperIDFilter.contains($0.id) }
        }
        if !query.isEmpty {
            papers = papers.filter { paper in
                derivedState.matchesSearch(paperID: paper.id, query: query)
            }
        }

        let option = LibrarySortOption(rawValue: librarySortRawValue) ?? .addedNewest
        let sortedPapers = option.sorted(papers, ascending: librarySortAscending)
        return LibraryPaperListState(
            papers: sortedPapers,
            paperIDs: sortedPapers.map(\.id),
            readablePaperIDs: sortedPapers.filter { !$0.isArxivImportPlaceholder }.map(\.id),
            hasActiveFilters: selectedCategoryID != nil || selectedTagID != nil || !query.isEmpty
        )
    }

    var body: some View {
        SidebarSplitLayout(minContentWidth: LibraryLayout.libraryContentMinimumWidth) {
            sidebar
        } content: {
            contentPane
        }
        .onChange(of: filteredPaperIDs) { _, _ in
            prunePaperSelection()
        }
        .onChange(of: model.recentSessions.map(\.id)) { _, _ in
            pruneRecentSessionSelection()
        }
        .onChange(of: model.selectedLibraryPaper?.id) { _, _ in
            if let paper = model.selectedLibraryPaper {
                scheduleInspectorDetailsAfterSelectionSettles(for: paper)
            } else {
                scheduleInspectorDetailsAfterSelectionSettles(for: nil)
            }
        }
        .onAppear {
            if let paper = model.selectedLibraryPaper {
                scheduleInspectorDetailsAfterSelectionSettles(for: paper)
            }
        }
        .alert("Delete selected papers?", isPresented: $isConfirmingBulkDelete) {
            Button("Delete", role: .destructive) {
                deleteSelectedPapers()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(selectedPaperIDs.count) papers from the local library and deletes app-managed PDF/cache files. This cannot be undone.")
        }
        .alert("Delete category?", isPresented: Binding(
            get: { categoryPendingDelete != nil },
            set: { if !$0 { categoryPendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let categoryPendingDelete {
                    model.deleteCategory(categoryPendingDelete.id)
                    selectedCategoryID = nil
                }
                categoryPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                categoryPendingDelete = nil
            }
        } message: {
            Text("This removes the category, its subcategories, and their assignments. Papers stay in the library.")
        }
        .alert("Delete tag?", isPresented: Binding(
            get: { tagPendingDelete != nil },
            set: { if !$0 { tagPendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let tagPendingDelete {
                    model.deleteTag(tagPendingDelete.id)
                    selectedTagID = nil
                }
                tagPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                tagPendingDelete = nil
            }
        } message: {
            Text("This removes the tag from every paper. Papers stay in the library.")
        }
        .alert("Remove watched folder?", isPresented: Binding(
            get: { watchedFolderPendingRemoval != nil },
            set: { if !$0 { watchedFolderPendingRemoval = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let watchedFolderPendingRemoval {
                    model.removeWatchedFolder(watchedFolderPendingRemoval)
                }
                watchedFolderPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                watchedFolderPendingRemoval = nil
            }
        } message: {
            Text("The folder will stop being scanned. Imported papers remain in the library.")
        }
        .sheet(isPresented: $isCreatingCategory) {
            CategoryEditorSheet(
                categoryItems: flattenedCategoryItems(),
                name: $newCategoryName,
                parentID: $newCategoryParentID
            ) { name, parentID in
                model.createCategory(name: name, parentID: parentID.isEmpty ? nil : parentID)
                newCategoryName = ""
                newCategoryParentID = ""
                isCreatingCategory = false
            } onCancel: {
                newCategoryName = ""
                newCategoryParentID = ""
                isCreatingCategory = false
            }
        }
        .sheet(isPresented: $isCreatingTag) {
            TagEditorSheet(name: $newTagName) { name in
                model.createTag(name: name)
                newTagName = ""
                isCreatingTag = false
            } onCancel: {
                newTagName = ""
                isCreatingTag = false
            }
        }
        .sheet(item: $categoryPendingManagement) { category in
            categoryManagementSheet(category)
        }
        .sheet(item: $tagPendingManagement) { tag in
            tagManagementSheet(tag)
        }
        .sheet(isPresented: $isShowingWatchedFolders) {
            WatchedFoldersSheet {
                presentWatchedFolderPanel()
            } onClose: {
                isShowingWatchedFolders = false
            } onRemove: { folder in
                watchedFolderPendingRemoval = folder
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $isShowingArxivImport) {
            LibraryArxivImportSheet(
                categoryItems: flattenedCategoryItems(),
                initialCategoryID: selectedCategoryID
            ) {
                isShowingArxivImport = false
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $isShowingBulkCopy) {
            LibraryBulkCopySheet(
                categoryItems: flattenedCategoryItems(),
                selectedCount: selectedPaperIDs.count
            ) { categoryID in
                if let categoryID {
                    model.copyPapers(selectedPaperIDsInOrder, toCategory: categoryID)
                    selectedCategoryID = categoryID
                    selectedTagID = nil
                }
                selectedPaperIDs.removeAll()
                lastSelectedPaperID = nil
                isShowingBulkCopy = false
            } onCancel: {
                isShowingBulkCopy = false
            }
        }
        .sheet(isPresented: $isShowingBulkTag) {
            LibraryBulkTagSheet(
                tags: model.tags,
                selectedCount: selectedPaperIDs.count
            ) { tagIDs in
                model.assignPapers(selectedPaperIDsInOrder, toTags: tagIDs)
                selectedPaperIDs.removeAll()
                lastSelectedPaperID = nil
                isShowingBulkTag = false
            } onCancel: {
                isShowingBulkTag = false
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            dropPDFs(from: providers)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Episteme")
                .font(.paperCodexSystem(size: 24, weight: .semibold))

            PrimaryNavigationSection()

            Divider()

            Label("Library Context", systemImage: "books.vertical")
                .font(.headline)
                .foregroundStyle(.secondary)

            ScrollView(.vertical) {
                sidebarLists
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .paperCodexSidebarChromePadding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sidebarLists: some View {
        VStack(alignment: .leading, spacing: 18) {
            categorySidebarSection
            Divider()
            tagSidebarSection
        }
        .padding(.trailing, 2)
        .padding(.bottom, 8)
    }

    private var categorySidebarSection: some View {
        let categoryTree = LibraryCategoryTreeSnapshot(
            categories: sidebarCategories,
            collapsedCategoryIDs: collapsedCategoryIDs
        )

        return VStack(alignment: .leading, spacing: 8) {
            sidebarHeader("Folders", systemImage: "folder") {
                startCreatingCategory(parentID: selectedCategoryID)
            }
            LibraryRootFolderRow(
                countText: "\(model.papers.count)",
                isSelected: selectedLibrarySurface == .papers && selectedCategoryID == nil && selectedTagID == nil,
                canDropCategory: {
                    guard let outlineDraggedCategoryID else {
                        return true
                    }
                    return CategoryMovePlanner.canMoveCategory(
                        outlineDraggedCategoryID,
                        toParent: nil,
                        in: sidebarCategories
                    )
                },
                onDropPapers: { paperIDs in
                    outlineDraggedCategoryID = nil
                    model.movePapers(paperIDs, toCategory: nil)
                    selectRootLibrary()
                },
                onDropCategory: { droppedCategoryID in
                    guard CategoryMovePlanner.canMoveCategory(
                        droppedCategoryID,
                        toParent: nil,
                        in: sidebarCategories
                    ) else {
                        return
                    }
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        model.moveCategory(droppedCategoryID, toParent: nil)
                    }
                    outlineDraggedCategoryID = nil
                }
            ) {
                selectRootLibrary()
            }
            if sidebarCategories.isEmpty {
                SidebarEmptyText("No categories")
            } else {
                LibraryCategoryOutlineView(
                    categories: sidebarCategories,
                    selectedCategoryID: selectedLibrarySurface == .papers ? selectedCategoryID : nil,
                    collapsedCategoryIDs: $collapsedCategoryIDs,
                    paperCountsByCategoryID: model.libraryDerivedState.categoryPaperCountsByID,
                    categoryDragPayloadPrefix: LibraryLayout.categoryDragPayloadPrefix,
                    onSelect: selectLibraryCategory,
                    onCreateChild: { category in
                        newCategoryParentID = category.id
                        startCreatingCategory(parentID: category.id)
                    },
                    onManage: { category in
                        categoryPendingManagement = category
                    },
                    onTogglePinned: { category in
                        model.setCategoryPinned(category.id, pinned: !category.isPinned)
                    },
                    onBeginCategoryDrag: { categoryID in
                        outlineDraggedCategoryID = categoryID
                    },
                    onEndCategoryDrag: {
                        outlineDraggedCategoryID = nil
                    },
                    canDropCategory: canDropCategory(_:to:),
                    onDropCategory: dropCategory(_:to:),
                    onDropPapers: { paperIDs, category in
                        dropPaperIDs(paperIDs, ontoCategory: category.id)
                        selectLibraryCategory(category.id)
                    }
                )
                .frame(height: max(1, CGFloat(categoryTree.visibleItems.count)) * LibraryLayout.categoryTreeConnectorHeight)
            }
        }
    }

    private var tagSidebarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sidebarHeader("Tags", systemImage: "tag") {
                isCreatingTag = true
            }
            if model.tags.isEmpty {
                SidebarEmptyText("No tags")
            } else {
                ForEach(model.tags) { tag in
                    TagSidebarRow(
                        title: tag.name,
                        countText: "\(paperCount(forTag: tag.id))",
                        isSelected: selectedLibrarySurface == .papers && selectedTagID == tag.id
                    ) {
                        selectLibraryTag(tag.id)
                    } onManage: {
                        tagPendingManagement = tag
                    }
                }
            }
        }
    }

    private var contentPane: some View {
        GeometryReader { proxy in
            if isCompactLibraryContent(width: proxy.size.width) {
                primaryContentPane
                    .padding(.top, LibraryLayout.splitPaneTopInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LibraryContentSplitView(
                    primaryMinimumWidth: LibraryLayout.libraryPrimaryPaneMinimumWidth,
                    secondaryMinimumWidth: LibraryLayout.libraryInspectorMinimumWidth,
                    secondaryIdealWidth: LibraryLayout.libraryInspectorIdealWidth,
                    secondaryMaximumWidth: LibraryLayout.libraryInspectorMaximumWidth,
                    {
                        primaryContentPane
                            .padding(.top, LibraryLayout.splitPaneTopInset)
                            .frame(minWidth: LibraryLayout.libraryPrimaryPaneMinimumWidth)
                    },
                    secondary: {
                        secondaryContentPane
                            .padding(.top, LibraryLayout.splitPaneTopInset)
                            .frame(
                                minWidth: LibraryLayout.libraryInspectorMinimumWidth,
                                idealWidth: LibraryLayout.libraryInspectorIdealWidth,
                                maxWidth: LibraryLayout.libraryInspectorMaximumWidth
                            )
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var primaryContentPane: some View {
        switch selectedLibrarySurface {
        case .papers:
            paperList
        case .recentConversations:
            RecentConversationsContent(
                sessions: model.recentSessions,
                papersBySessionID: model.recentSessionPapersByID,
                selectedSessionID: Binding(
                    get: { selectedRecentSessionID ?? model.recentSessions.first?.id },
                    set: { selectedRecentSessionID = $0 }
                ),
                onOpen: { session in
                    model.openRecentSession(session)
                }
            )
        }
    }

    @ViewBuilder
    private var secondaryContentPane: some View {
        switch selectedLibrarySurface {
        case .papers:
            inspector
        case .recentConversations:
            RecentConversationDetailPanel(
                session: selectedRecentSession,
                papers: selectedRecentSession.map { model.papersForSession($0) } ?? [],
                onOpen: { session in
                    model.openRecentSession(session)
                }
            )
        }
    }

    private var paperList: some View {
        let listState = makePaperListState()
        return VStack(alignment: .leading, spacing: 16) {
            LibraryNativeToolbarView(
                searchText: searchTextBinding,
                sortRawValue: $librarySortRawValue,
                sortAscending: $librarySortAscending,
                includeSubfolders: $libraryIncludeSubfolders,
                paperCount: listState.papers.count,
                showsFolderScope: selectedCategoryID != nil,
                showsReadActions: selectedCategoryID != nil,
                canRead: !listState.readablePaperIDs.isEmpty,
                hasActiveFilters: listState.hasActiveFilters,
                isLibraryActive: model.route == .library,
                searchFocusRequestID: model.searchFocusRequestID,
                onRead: {
                    model.openPapersForReading(listState.readablePaperIDs)
                },
                onChat: {
                    model.openPapersForChat(listState.readablePaperIDs)
                },
                onClearFilters: clearLibraryFilters,
                onShowWatchedFolders: {
                    isShowingWatchedFolders = true
                },
                onShowArxivImport: {
                    isShowingArxivImport = true
                },
                onImportPDF: presentPDFImportPanel
            )
            .frame(maxWidth: .infinity, minHeight: 36, idealHeight: 36, maxHeight: 36)

            if listState.papers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let paperTableRows = paperTableRows(for: listState.papers)
                LibraryPaperTableView(
                    rows: paperTableRows,
                    selectedPaperID: model.selectedLibraryPaper?.id,
                    revealRequestID: selectedPaperRevealRequestID,
                    focusRequestID: paperTableFocusRequestID,
                    onMoveSelection: moveFocusedPaperSelection(by:)
                ) { row in
                    let paper = row.paper
                    PaperRow(
                        paper: paper,
                        categories: row.categories,
                        tags: row.tags,
                        thumbnailURLs: row.thumbnailURLs,
                        isImportPlaceholder: row.isImportPlaceholder,
                        placeholderDetail: row.placeholderDetail,
                        isSelected: row.isSelected,
                        isMultiSelected: row.isMultiSelected,
                        onToggleStar: {
                            model.togglePaperStar(paper)
                        },
                        onRead: {
                            model.openPaper(paper)
                        }
                    )
                    .contentShape(Rectangle())
                    .onDrag {
                        outlineDraggedCategoryID = nil
                        return NSItemProvider(object: paperDragPayload(for: paper) as NSString)
                    } preview: {
                        PaperDragPreview(
                            paper: paper,
                            selectedCount: dragPreviewPaperIDs(for: paper).count
                        )
                    }
                    .onTapGesture {
                        paperTableFocusRequestID = UUID()
                        handlePaperRowClick(paper)
                    }
                }
                .overlay(alignment: .top) {
                    bulkActionBarOverlay
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 24)
    }

    private var bulkActionBarOverlay: some View {
        Group {
            if selectedPaperIDs.count > 1 {
                BulkLibraryActionBar(
                    selectedCount: selectedPaperIDs.count,
                    canMove: true,
                    canTag: !model.tags.isEmpty,
                    canOpenConversation: !selectedReadablePaperIDsInOrder.isEmpty,
                    onRead: openSelectedPapersForReading,
                    onChat: openSelectedPapersForChat,
                    onCopy: {
                        isShowingBulkCopy = true
                    },
                    onTag: {
                        isShowingBulkTag = true
                    },
                    onDelete: {
                        isConfirmingBulkDelete = true
                    },
                    onClear: {
                        selectedPaperIDs.removeAll()
                        lastSelectedPaperID = nil
                    }
                )
                .padding(.horizontal, 10)
                .padding(.top, LibraryLayout.bulkActionBarOverlayYOffset)
                .opacity(LibraryLayout.bulkActionBarOverlayOpacity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .shadow(color: Color.black.opacity(0.10), radius: 12, y: 5)
            }
        }
        .animation(.easeOut(duration: 0.16), value: selectedPaperIDs.count > 1)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paper Details")
                .font(.paperCodexSystem(size: 20, weight: .semibold))

            if let paper = model.selectedLibraryPaper {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Text(paper.title)
                                    .font(.headline)
                                Spacer(minLength: 8)
                                PaperCodexIconButton(
                                    title: paper.isStarred ? "Remove Star" : "Star Paper",
                                    systemImage: paper.isStarred ? "star.fill" : "star",
                                    tint: paper.isStarred ? .yellow : .secondary,
                                    disabled: paper.isArxivImportPlaceholder
                                ) {
                                    model.togglePaperStar(paper)
                                }
                            }
                            Text(paper.isArxivImportPlaceholder ? model.arxivImportPlaceholderDetail(for: paper) : (paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", ")))
                                .foregroundStyle(.secondary)
                            Text(paper.isArxivImportPlaceholder ? (paper.sourceURL ?? paper.title) : paper.filePath)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }

                        PaperCodexPanelButton(
                            title: "Read",
                            systemImage: "book",
                            kind: .primary,
                            disabled: paper.isArxivImportPlaceholder,
                            fillsWidth: true
                        ) {
                            model.openPaper(paper)
                        }

                        if inspectorDetailsPaperID == paper.id {
                            Divider()

                            let metadata = model.libraryArxivMetadata(for: paper)
                            if let metadata {
                                paperMetadataSection(for: paper, metadata: metadata)
                                Divider()
                            }

                            categoryAssignments(for: paper)
                            Divider()
                            tagAssignments(for: paper)
                            Divider()
                            paperNotesSection(for: paper)
                        }
                    }
                    .padding(.trailing, 4)
                }
            } else {
                ContentUnavailableView("Select Paper", systemImage: "sidebar.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func paperMetadataSection(for paper: Paper, metadata: LibraryPaperArxivMetadata) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("解析信息", systemImage: "sparkles")
                .font(.headline)
            if !metadata.titleZH.isEmpty, metadata.titleZH != paper.title {
                LibraryMetadataBlock(title: "中文标题", text: metadata.titleZH)
            }
            if !metadata.summaryZH.isEmpty {
                LibraryMetadataBlock(title: "中文摘要", text: metadata.summaryZH)
            }
            if !metadata.contribution.isEmpty {
                LibraryMetadataBlock(title: "贡献总结", text: metadata.contribution)
            }
            if !metadata.abstractZH.isEmpty {
                LibraryMetadataBlock(title: "中文 Abstract", text: metadata.abstractZH)
            }
            if !metadata.abstractEN.isEmpty {
                LibraryMetadataBlock(title: "Abstract", text: metadata.abstractEN)
            }
            if !metadata.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(metadata.tags.prefix(10), id: \.self) { tag in
                        SmallChip(title: tag, systemImage: "tag")
                    }
                }
            }
        }
    }

    private func categoryAssignments(for paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Categories", systemImage: "folder")
                    .font(.headline)
                Spacer()
                Button {
                    newCategoryParentID = ""
                    isCreatingCategory = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New Category")
            }

            if model.categories.isEmpty {
                SidebarEmptyText("No categories")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(flattenedCategoryItems()) { item in
                        Toggle(isOn: Binding(
                            get: {
                                model.paperCategoryIDsByID[paper.id, default: []].contains(item.category.id)
                            },
                            set: { isAssigned in
                                model.setCategory(item.category.id, assigned: isAssigned, for: paper)
                            }
                        )) {
                            Text(item.category.name)
                                .padding(.leading, CGFloat(item.depth * 14))
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    private func tagAssignments(for paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Tags", systemImage: "tag")
                    .font(.headline)
                Spacer()
                Button {
                    isCreatingTag = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New Tag")
            }

            if model.tags.isEmpty {
                SidebarEmptyText("No tags")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(model.tags) { tag in
                        let assigned = model.paperTagsByID[paper.id, default: []].contains { $0.id == tag.id }
                        TagToggleChip(tag: tag, isAssigned: assigned) {
                            model.setTag(tag.id, assigned: !assigned, for: paper)
                        }
                    }
                }
            }
        }
    }

    private func paperNotesSection(for paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Notes", systemImage: "note.text")
                    .font(.headline)
                Spacer()
                if editingNoteID != nil {
                    Button("New") {
                        clearNoteDraft()
                    }
                    .buttonStyle(.borderless)
                }
            }

            let notes = model.paperNotesByID[paper.id, default: []]
            if notes.isEmpty {
                SidebarEmptyText("No notes")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(notes) { note in
                        PaperNoteRow(note: note) {
                            editingNoteID = note.id
                            noteTitle = note.title
                            noteBody = note.bodyMarkdown
                        } onDelete: {
                            model.deleteNote(note)
                            if editingNoteID == note.id {
                                clearNoteDraft()
                            }
                        }
                    }
                }
            }

            TextField("Note title", text: $noteTitle)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $noteBody)
                .font(.paperCodexSystem(size: 12.5))
                .frame(minHeight: 72)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
            HStack {
                Button {
                    model.saveNote(paperID: paper.id, noteID: editingNoteID, title: noteTitle, bodyMarkdown: noteBody)
                    clearNoteDraft()
                } label: {
                    Label(editingNoteID == nil ? "Add Note" : "Save Note", systemImage: "checkmark")
                }
                .buttonStyle(.bordered)
                .disabled(noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if editingNoteID != nil {
                    Button("Cancel") {
                        clearNoteDraft()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func sidebarHeader(_ title: String, systemImage: String, onAdd: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New \(title.dropLast())")
        }
    }

    private func filterButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        depth: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        SidebarRowButton(
            title: title,
            systemImage: systemImage,
            selected: isSelected,
            depth: depth,
            action: action
        )
    }

    private func startCreatingCategory(parentID: String?) {
        newCategoryParentID = parentID ?? ""
        isCreatingCategory = true
    }

    private func handlePaperRowClick(_ paper: Paper) {
        let modifiers = NSEvent.modifierFlags.intersection([.command, .shift])
        let canOpenOnSecondClick = modifiers.isEmpty
        let clickedAt = Date()
        handlePaperRowTap(paper)

        guard canOpenOnSecondClick else {
            lastPaperRowClick = nil
            return
        }

        if let lastPaperRowClick,
           lastPaperRowClick.paperID == paper.id,
           clickedAt.timeIntervalSince(lastPaperRowClick.clickedAt) <= 0.38,
           !paper.isArxivImportPlaceholder {
            model.openPaper(paper)
            self.lastPaperRowClick = nil
        } else {
            lastPaperRowClick = LibraryPaperRowClick(paperID: paper.id, clickedAt: clickedAt)
        }
    }

    private func handlePaperRowTap(_ paper: Paper) {
        let modifiers = NSEvent.modifierFlags.intersection([.command, .shift])
        if modifiers.contains(.shift) {
            selectPaperRange(through: paper)
        } else if modifiers.contains(.command) {
            togglePaperSelection(paper)
        } else {
            clearPaperMultiSelection()
            lastSelectedPaperID = paper.id
            focusLibraryPaper(paper)
        }
    }

    private func moveFocusedPaperSelection(by offset: Int) {
        guard selectedLibrarySurface == .papers else {
            return
        }
        let visiblePapers = sortedPapers
        guard !visiblePapers.isEmpty else {
            return
        }
        let currentIndex = model.selectedLibraryPaper.flatMap { selectedPaper in
            visiblePapers.firstIndex { $0.id == selectedPaper.id }
        }
        let lastIndex = visiblePapers.index(before: visiblePapers.endIndex)
        let nextIndex: Int
        if let currentIndex {
            nextIndex = min(max(currentIndex + offset, visiblePapers.startIndex), lastIndex)
        } else {
            nextIndex = offset < 0 ? lastIndex : visiblePapers.startIndex
        }
        let nextPaper = visiblePapers[nextIndex]
        clearPaperMultiSelection()
        lastSelectedPaperID = nextPaper.id
        selectedPaperRevealRequestID = UUID()
        focusLibraryPaper(nextPaper)
        paperTableFocusRequestID = UUID()
    }

    private func togglePaperSelection(_ paper: Paper) {
        var nextSelection = seedSelectionForCommandToggle(startingWith: paper)
        if nextSelection.contains(paper.id) {
            nextSelection.remove(paper.id)
        } else {
            nextSelection.insert(paper.id)
        }
        applyPaperSelection(nextSelection, focusedPaper: paper)
    }

    private func seedSelectionForCommandToggle(startingWith paper: Paper) -> Set<String> {
        guard selectedPaperIDs.isEmpty else {
            return selectedPaperIDs
        }
        guard let focusedPaper = model.selectedLibraryPaper,
              sortedPapers.contains(where: { $0.id == focusedPaper.id }) else {
            return []
        }
        return [focusedPaper.id]
    }

    private func applyPaperSelection(_ paperIDs: Set<String>, focusedPaper: Paper) {
        let visibleIDs = Set(sortedPapers.map(\.id))
        let visibleSelection = paperIDs.intersection(visibleIDs)
        if visibleSelection.count > 1 {
            selectedPaperIDs = visibleSelection
            lastSelectedPaperID = focusedPaper.id
            focusLibraryPaper(focusedPaper)
            return
        }

        clearPaperMultiSelection()
        if let remainingID = visibleSelection.first,
           let remainingPaper = sortedPapers.first(where: { $0.id == remainingID }) {
            lastSelectedPaperID = remainingID
            focusLibraryPaper(remainingPaper)
        } else if visibleIDs.contains(focusedPaper.id) {
            lastSelectedPaperID = focusedPaper.id
            focusLibraryPaper(focusedPaper)
        } else {
            lastSelectedPaperID = nil
            clearFocusedLibraryPaper()
        }
    }

    private func clearPaperMultiSelection() {
        selectedPaperIDs.removeAll()
    }

    private func selectPaperRange(through paper: Paper) {
        let visibleIDs = sortedPapers.map(\.id)
        guard let currentIndex = visibleIDs.firstIndex(of: paper.id) else {
            togglePaperSelection(paper)
            return
        }
        let anchorID = lastSelectedPaperID ?? paper.id
        guard let anchorIndex = visibleIDs.firstIndex(of: anchorID) else {
            applyPaperSelection([paper.id], focusedPaper: paper)
            return
        }
        let lower = min(anchorIndex, currentIndex)
        let upper = max(anchorIndex, currentIndex)
        applyPaperSelection(Set(visibleIDs[lower...upper]), focusedPaper: paper)
    }

    private func prunePaperSelection() {
        let visibleIDs = Set(sortedPapers.map(\.id))
        selectedPaperIDs = selectedPaperIDs.intersection(visibleIDs)
        if selectedPaperIDs.count < 2 {
            clearPaperMultiSelection()
        }
        if let lastSelectedPaperID, !selectedPaperIDs.isEmpty, !selectedPaperIDs.contains(lastSelectedPaperID) {
            self.lastSelectedPaperID = selectedPaperIDsInOrder.last
        }
    }

    private func pruneRecentSessionSelection() {
        if let selectedRecentSessionID,
           model.recentSessions.contains(where: { $0.id == selectedRecentSessionID }) {
            return
        }
        selectedRecentSessionID = model.recentSessions.first?.id
    }

    private func deleteSelectedPapers() {
        let paperIDs = selectedPaperIDsInOrder
        guard !paperIDs.isEmpty else {
            return
        }
        model.deletePapers(paperIDs)
        selectedPaperIDs.removeAll()
        lastSelectedPaperID = nil
    }

    private func openSelectedPapersForReading() {
        let paperIDs = selectedReadablePaperIDsInOrder
        guard !paperIDs.isEmpty else {
            return
        }
        model.openPapersForReading(paperIDs)
    }

    private func openSelectedPapersForChat() {
        let paperIDs = selectedReadablePaperIDsInOrder
        guard !paperIDs.isEmpty else {
            return
        }
        model.openPapersForChat(paperIDs)
    }

    private func clearNoteDraft() {
        editingNoteID = nil
        noteTitle = ""
        noteBody = ""
    }

    private func focusLibraryPaper(_ paper: Paper) {
        applyFastLibrarySelection {
            model.selectLibraryPaper(paper)
        }
    }

    private func clearFocusedLibraryPaper() {
        applyFastLibrarySelection {
            model.selectedLibraryPaper = nil
        }
    }

    private func scheduleInspectorDetailsAfterSelectionSettles(for paper: Paper?) {
        inspectorDetailsPaperID = nil
        let requestID = UUID()
        inspectorDetailsRequestID = requestID
        guard let paper else {
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: LibraryLayout.inspectorDetailSettleDelayNanoseconds)
            guard inspectorDetailsRequestID == requestID,
                  model.selectedLibraryPaper?.id == paper.id else {
                return
            }
            inspectorDetailsPaperID = paper.id
            model.loadPaperNotes(for: paper)
        }
    }

    private func applyFastLibrarySelection(_ update: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            update()
        }
    }

    private func selectRootLibrary() {
        applyFastLibrarySelection {
            model.setLibrarySelection(surface: .papers, categoryID: nil, tagID: nil)
        }
    }

    private func selectLibraryCategory(_ categoryID: String) {
        applyFastLibrarySelection {
            model.setLibrarySelection(surface: .papers, categoryID: categoryID, tagID: nil)
        }
    }

    private func selectLibraryTag(_ tagID: String) {
        applyFastLibrarySelection {
            model.setLibrarySelection(surface: .papers, categoryID: nil, tagID: tagID)
        }
    }

    private func clearLibraryFilters() {
        applyFastLibrarySelection {
            searchText = ""
            model.setLibrarySelection(surface: .papers, categoryID: nil, tagID: nil)
        }
    }

    private func isCompactLibraryContent(width: CGFloat) -> Bool {
        width < LibraryLayout.compactContentWidthThreshold
    }

    private func dropPaperIDs(_ paperIDs: [String], ontoCategory categoryID: String) {
        if shouldMoveDroppedPapers(toCategory: categoryID) {
            model.movePapers(paperIDs, toCategory: categoryID)
        } else {
            model.copyPapers(paperIDs, toCategory: categoryID)
        }
    }

    private func canDropCategory(_ categoryID: String, to target: LibraryCategoryOutlineDropTarget) -> Bool {
        switch target.placement {
        case .inside:
            return CategoryMovePlanner.canMoveCategory(
                categoryID,
                toParent: target.targetCategoryID,
                in: sidebarCategories
            )
        case .before, .after:
            guard let targetCategoryID = target.targetCategoryID else {
                return false
            }
            return CategoryMovePlanner.canDropCategory(
                categoryID,
                ontoCategory: targetCategoryID,
                placement: target.placement,
                in: sidebarCategories
            )
        }
    }

    private func dropCategory(_ categoryID: String, to target: LibraryCategoryOutlineDropTarget) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            switch target.placement {
            case .inside:
                model.moveCategory(categoryID, toParent: target.targetCategoryID)
            case .before, .after:
                guard let targetCategoryID = target.targetCategoryID else {
                    return
                }
                model.reorderCategory(
                    categoryID,
                    relativeTo: targetCategoryID,
                    placement: target.placement
                )
            }
        }
    }

    private func shouldMoveDroppedPapers(toCategory categoryID: String) -> Bool {
        guard let selectedCategoryID else {
            return false
        }
        return categoryID == selectedCategoryID || model.categoryIsDescendant(categoryID, of: selectedCategoryID)
    }

    private func paperCount(forTag tagID: String) -> Int {
        model.libraryDerivedState.tagPaperCountsByID[tagID, default: 0]
    }

    private func dropPDFs(from providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else {
            return false
        }
        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let itemURL = item as? URL {
                    url = itemURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let nsURL = item as? NSURL {
                    url = nsURL as URL
                } else {
                    url = nil
                }
                guard let url else {
                    return
                }
                DispatchQueue.main.async {
                    model.importPDFs(from: [url])
                }
            }
        }
        return true
    }

    private func paperIDsForDrag(startingWith paper: Paper) -> [String] {
        if selectedPaperIDs.count > 1, selectedPaperIDs.contains(paper.id) {
            return selectedPaperIDsInOrder
        }
        return [paper.id]
    }

    private func dragPreviewPaperIDs(for paper: Paper) -> [String] {
        paperIDsForDrag(startingWith: paper)
    }

    private func paperDragPayload(for paper: Paper) -> String {
        paperIDsForDrag(startingWith: paper).joined(separator: "\n")
    }

    private func categories(for paper: Paper) -> [PaperCodexCore.Category] {
        let ids = Set(model.paperCategoryIDsByID[paper.id, default: []])
        return model.categories.filter { ids.contains($0.id) }
    }

    private func paperTableRows(for papers: [Paper]) -> [LibraryPaperTableRow] {
        papers.map { paper in
            LibraryPaperTableRow(
                paper: paper,
                categories: categories(for: paper),
                tags: model.paperTagsByID[paper.id, default: []],
                thumbnailURLs: model.paperThumbnailURLsByID[paper.id, default: []],
                isImportPlaceholder: paper.isArxivImportPlaceholder,
                placeholderDetail: model.arxivImportPlaceholderDetail(for: paper),
                isSelected: model.selectedLibraryPaper?.id == paper.id,
                isMultiSelected: selectedPaperIDs.contains(paper.id)
            )
        }
    }

    private func presentPDFImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import PDF"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        beginOpenPanel(panel) { url in
            model.importPDF(from: url)
        }
    }

    private func presentWatchedFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add Watched Folder"
        panel.prompt = "Add Folder"
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.resolvesAliases = true
        beginOpenPanel(panel) { url in
            model.addWatchedFolder(from: url)
        }
    }

    private func beginOpenPanel(_ panel: NSOpenPanel, onSelection: @escaping (URL) -> Void) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else {
                    return
                }
                onSelection(url)
            }
        } else {
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    return
                }
                onSelection(url)
            }
        }
    }

    private func flattenedCategoryItems(parentID: String? = nil, depth: Int = 0) -> [CategoryListItem] {
        model.categories
            .filter { $0.parentID == parentID }
            .sorted { left, right in
                if left.isPinned != right.isPinned {
                    return left.isPinned
                }
                if left.sortOrder == right.sortOrder {
                    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                }
                return left.sortOrder < right.sortOrder
            }
            .flatMap { category in
                [CategoryListItem(category: category, depth: depth)]
                    + flattenedCategoryItems(parentID: category.id, depth: depth + 1)
            }
    }

    private func categoryManagementSheet(_ category: PaperCodexCore.Category) -> some View {
        CategoryManagementSheet(
            category: category,
            categoryItems: flattenedCategoryItems().filter { $0.category.id != category.id },
            onSave: { name, parentID in
                model.updateCategory(category.id, name: name, parentID: parentID)
                categoryPendingManagement = nil
            },
            onDelete: {
                categoryPendingManagement = nil
                categoryPendingDelete = category
            },
            onCancel: {
                categoryPendingManagement = nil
            }
        )
    }

    private func tagManagementSheet(_ tag: PaperTag) -> some View {
        TagManagementSheet(
            tag: tag,
            onSave: { name in
                model.updateTag(tag.id, name: name)
                tagPendingManagement = nil
            },
            onDelete: {
                tagPendingManagement = nil
                tagPendingDelete = tag
            },
            onCancel: {
                tagPendingManagement = nil
            }
        )
    }
}

private struct WatchedFoldersSheet: View {
    @EnvironmentObject private var model: AppModel
    var onAdd: () -> Void
    var onClose: () -> Void
    var onRemove: (WatchedFolder) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Watched Folders")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: onAdd) {
                    Label("Add Folder", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                Button {
                    model.scanWatchedFolders()
                } label: {
                    Label(model.isScanningWatchedFolders ? "Scanning" : "Scan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(model.watchedFolders.isEmpty || model.isScanningWatchedFolders)
            }

            if model.watchedFolders.isEmpty {
                ContentUnavailableView("No Folders", systemImage: "folder")
                    .frame(width: 520, height: 220)
            } else {
                List {
                    ForEach(model.watchedFolders) { folder in
                        WatchedFolderRow(folder: folder) {
                            onRemove(folder)
                        }
                    }
                }
                .listStyle(.inset)
                .frame(width: 560, height: 260)
            }

            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 600)
    }
}

private struct WatchedFolderRow: View {
    var folder: WatchedFolder
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(folderExists ? Color.accentColor : Color.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: folder.path).lastPathComponent)
                    .font(.paperCodexSystem(size: 13, weight: .medium))
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(lastScannedText)
                    .font(.caption2)
                    .foregroundStyle(folderExists ? Color.secondary.opacity(0.72) : Color.orange)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove Folder")
        }
        .padding(.vertical, 4)
    }

    private var lastScannedText: String {
        guard folderExists else {
            return "Folder missing"
        }
        guard let date = folder.lastScannedAt else {
            return "Not scanned"
        }
        return "Scanned \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var folderExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private struct CategoryListItem: Identifiable {
    var category: PaperCodexCore.Category
    var depth: Int

    var id: String { category.id }
}

struct LibraryPaperArxivMetadata: Equatable {
    var arxivID: String
    var titleZH: String
    var summaryZH: String
    var contribution: String
    var abstractZH: String
    var abstractEN: String
    var tags: [String]
}

private struct LibraryRootFolderRow: View {
    @State private var isHovering = false
    @State private var isDropTargeted = false

    var countText: String
    var isSelected: Bool
    var canDropCategory: () -> Bool
    var onDropPapers: ([String]) -> Void
    var onDropCategory: (String) -> Void
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .trailing) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "tray.full.fill" : "tray.full")
                        .frame(width: 18)
                        .foregroundStyle(isSelected || isDropTargeted ? Color.accentColor : Color.secondary)
                    Text("All Papers")
                        .font(.paperCodexSystem(size: 13, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)

                if isDropTargeted {
                    Label("Top Level", systemImage: "arrow.up.to.line")
                        .font(.paperCodexSystem(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .foregroundStyle(Color.accentColor)
                        .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                        .padding(.trailing, 6)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    Text(countText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .padding(.trailing, 9)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : (isSelected ? Color.accentColor.opacity(0.13) : (isHovering ? Color.primary.opacity(0.045) : Color.clear)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTargeted ? Color.accentColor.opacity(0.55) : (isSelected ? Color.accentColor.opacity(0.22) : (isHovering ? Color.accentColor.opacity(0.18) : Color.clear)), lineWidth: isDropTargeted ? 1.5 : 1)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(Color.accentColor.opacity(0.72))
                    .frame(width: 3, height: 18)
                    .padding(.leading, 3)
                    .transition(.opacity.combined(with: .scale(scale: 0.82)))
            }
        }
        .scaleEffect(isDropTargeted ? 1.02 : (isHovering ? 1.01 : 1), anchor: .center)
        .animation(PaperCodexMotion.hover, value: isHovering)
        .animation(PaperCodexMotion.hover, value: isDropTargeted)
        .animation(PaperCodexMotion.selection, value: isSelected)
        .contentShape(Rectangle())
        .onDrop(
            of: LibraryLayout.categoryDropContentTypes,
            delegate: LibraryRootFolderDropDelegate(
                isTargeted: $isDropTargeted,
                canDropCategory: canDropCategory,
                onDrop: loadDroppedItems(from:)
            )
        )
        .help("Show all papers or drop a folder here to move it to the top level")
        .onHover { hovering in
            withAnimation(PaperCodexMotion.hover) {
                isHovering = hovering
            }
        }
    }

    private func loadDroppedItems(from providers: [NSItemProvider]) -> Bool {
        let textProviders = providers.filter { $0.canLoadObject(ofClass: NSString.self) }
        guard !textProviders.isEmpty else {
            return false
        }
        for provider in textProviders {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let payload = (object as? NSString).map(String.init) else {
                    return
                }
                let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                if let droppedCategoryID = LibraryLayout.droppedCategoryID(from: trimmedPayload) {
                    DispatchQueue.main.async {
                        onDropCategory(droppedCategoryID)
                    }
                    return
                }
                let paperIDs = trimmedPayload
                    .components(separatedBy: .whitespacesAndNewlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !paperIDs.isEmpty else {
                    return
                }
                DispatchQueue.main.async {
                    onDropPapers(paperIDs)
                }
            }
        }
        return true
    }
}

private struct LibraryPaperListState {
    var papers: [Paper]
    var paperIDs: [String]
    var readablePaperIDs: [String]
    var hasActiveFilters: Bool
}

private struct LibraryCategoryTreeSnapshot {
    var visibleItems: [CategoryListItem]

    init(categories: [PaperCodexCore.Category], collapsedCategoryIDs: Set<String>) {
        var rootCategories: [PaperCodexCore.Category] = []
        var childrenByParentID: [String: [PaperCodexCore.Category]] = [:]

        for category in categories {
            if let parentID = category.parentID {
                childrenByParentID[parentID, default: []].append(category)
            } else {
                rootCategories.append(category)
            }
        }

        rootCategories.sort(by: Self.sortCategories)
        for parentID in Array(childrenByParentID.keys) {
            childrenByParentID[parentID, default: []].sort(by: Self.sortCategories)
        }

        self.visibleItems = Self.visibleItems(
            categories: rootCategories,
            childrenByParentID: childrenByParentID,
            collapsedCategoryIDs: collapsedCategoryIDs,
            depth: 0
        )
    }

    private static func visibleItems(
        categories: [PaperCodexCore.Category],
        childrenByParentID: [String: [PaperCodexCore.Category]],
        collapsedCategoryIDs: Set<String>,
        depth: Int
    ) -> [CategoryListItem] {
        categories.flatMap { category in
            let item = CategoryListItem(
                category: category,
                depth: depth
            )
            guard !collapsedCategoryIDs.contains(category.id) else {
                return [item]
            }
            return [item] + visibleItems(
                categories: childrenByParentID[category.id, default: []],
                childrenByParentID: childrenByParentID,
                collapsedCategoryIDs: collapsedCategoryIDs,
                depth: depth + 1
            )
        }
    }

    private static func sortCategories(_ left: PaperCodexCore.Category, _ right: PaperCodexCore.Category) -> Bool {
        if left.isPinned != right.isPinned {
            return left.isPinned
        }
        if left.sortOrder == right.sortOrder {
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
        return left.sortOrder < right.sortOrder
    }
}

private struct LibraryPaperRowClick: Equatable {
    var paperID: String
    var clickedAt: Date
}

private enum LibraryLayout {
    static let libraryContentMinimumWidth: CGFloat = 560
    static let libraryPrimaryPaneMinimumWidth: CGFloat = 330
    static let libraryInspectorMinimumWidth: CGFloat = 220
    static let libraryInspectorIdealWidth: CGFloat = 300
    static let libraryInspectorMaximumWidth: CGFloat = 380
    static let compactContentWidthThreshold: CGFloat = 860
    static let splitPaneTopInset: CGFloat = 0
    static let bulkActionBarOverlayYOffset: CGFloat = 148
    static let bulkActionBarOverlayOpacity = 0.66
    static let paperRowThumbnailLimit = 3
    static let paperRowThumbnailMaxPixelSize = 128
    static let inspectorDetailSettleDelayNanoseconds: UInt64 = 80_000_000
    static let categoryTreeConnectorHeight: CGFloat = 32
    static let categoryDropContentTypes: [UTType] = [.plainText]
    static let categoryDragPayloadPrefix = "papercodex-category-id:"

    static func droppedCategoryID(from payload: String) -> String? {
        guard payload.hasPrefix(categoryDragPayloadPrefix) else {
            return nil
        }
        let categoryID = String(payload.dropFirst(categoryDragPayloadPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return categoryID.isEmpty ? nil : categoryID
    }
}

private struct PaperRow: View {
    var paper: Paper
    var categories: [PaperCodexCore.Category]
    var tags: [PaperTag]
    var thumbnailURLs: [URL]
    var isImportPlaceholder: Bool
    var placeholderDetail: String
    var isSelected: Bool
    var isMultiSelected: Bool
    var onToggleStar: () -> Void
    var onRead: () -> Void

    @State private var isHovering = false
    @State private var isPressing = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ThumbnailStrip(urls: Array(thumbnailURLs.prefix(LibraryLayout.paperRowThumbnailLimit)))
                .frame(width: 132, height: 54)
                .opacity(isImportPlaceholder ? 0.45 : 1)

            VStack(alignment: .leading, spacing: 7) {
                Text(paper.title)
                    .font(.headline)
                    .foregroundStyle(isImportPlaceholder ? .secondary : .primary)
                    .lineLimit(2)
                Text(isImportPlaceholder ? placeholderDetail : (paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", ")))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let arxivDisplayID {
                        SmallChip(title: arxivDisplayID, systemImage: "number")
                    }
                    ForEach(categories.prefix(2)) { category in
                        SmallChip(title: category.name, systemImage: "folder")
                    }
                    ForEach(tags.prefix(3)) { tag in
                        SmallChip(title: tag.name, systemImage: "tag")
                    }
                }
            }

            Spacer()

            PaperCodexIconButton(
                title: paper.isStarred ? "Remove Star" : "Star Paper",
                systemImage: paper.isStarred ? "star.fill" : "star",
                tint: paper.isStarred ? .yellow : .secondary,
                disabled: isImportPlaceholder,
                action: onToggleStar
            )

            PaperCodexIconButton(title: "Read", systemImage: "book", tint: .secondary, disabled: isImportPlaceholder, action: onRead)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 21)
        .background(rowBackground)
        .opacity(isImportPlaceholder ? 0.66 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rowBorderColor, lineWidth: isMultiSelected ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: rowShadowColor, radius: isPressing ? 4 : 6, y: isPressing ? 1 : 2)
        .scaleEffect(rowScale, anchor: .center)
        .overlay(alignment: .leading) {
            if isSelected || isMultiSelected || isPressing {
                Capsule()
                    .fill(Color.accentColor.opacity(leadingIndicatorOpacity))
                    .frame(width: 4)
                    .padding(.vertical, 12)
                    .padding(.leading, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .onLongPressGesture(
            minimumDuration: .infinity,
            maximumDistance: 16,
            pressing: { isPressing in
                withAnimation(PaperCodexMotion.press) {
                    self.isPressing = isPressing && !isImportPlaceholder
                }
            },
            perform: {}
        )
        .animation(PaperCodexMotion.press, value: isPressing)
        .animation(PaperCodexMotion.hover, value: isHovering)
        .animation(PaperCodexMotion.selection, value: isSelected)
        .animation(PaperCodexMotion.selection, value: isMultiSelected)
        .onHover { hovering in
            withAnimation(PaperCodexMotion.hover) {
                isHovering = hovering
            }
        }
    }

    private var arxivDisplayID: String? {
        paper.arxivImportPlaceholderCanonicalID
            ?? paper.sourceURL.flatMap(ArxivIDExtractor.firstCanonicalID(in:))
    }

    private var rowBackground: Color {
        if isMultiSelected {
            return Color.accentColor.opacity(0.16)
        }
        if isPressing && !isImportPlaceholder {
            return Color.accentColor.opacity(0.12)
        }
        if isSelected {
            return Color.accentColor.opacity(0.10)
        }
        if isHovering {
            return Color(nsColor: .textBackgroundColor)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var rowBorderColor: Color {
        if isMultiSelected {
            return Color.accentColor.opacity(0.62)
        }
        if isPressing && !isImportPlaceholder {
            return Color.accentColor.opacity(0.48)
        }
        if isSelected {
            return Color.accentColor.opacity(0.38)
        }
        if isHovering {
            return Color.primary.opacity(0.10)
        }
        return Color.clear
    }

    private var rowShadowColor: Color {
        if isImportPlaceholder {
            return .clear
        }
        if isPressing {
            return Color.accentColor.opacity(0.12)
        }
        return isHovering ? Color.black.opacity(0.10) : .clear
    }

    private var rowScale: CGFloat {
        if isImportPlaceholder {
            return 1
        }
        return isPressing ? 0.992 : (isHovering ? 1.006 : 1)
    }

    private var leadingIndicatorOpacity: Double {
        if isMultiSelected {
            return 0.82
        }
        return isPressing ? 0.70 : 0.62
    }
}

private struct PaperDragPreview: View {
    var paper: Paper
    var selectedCount: Int = 1

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.paperCodexSystem(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(paper.title)
                    .font(.paperCodexSystem(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if selectedCount > 1 {
                    Text("\(selectedCount) papers")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct ThumbnailStrip: View {
    var urls: [URL]

    var body: some View {
        HStack(spacing: -18) {
            if urls.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .windowBackgroundColor))
                    Image(systemName: "doc.richtext")
                        .foregroundStyle(.blue)
                }
                .frame(width: 42, height: 54)
            } else {
                let visibleURLs = Array(urls.prefix(LibraryLayout.paperRowThumbnailLimit))
                ForEach(Array(visibleURLs.enumerated()), id: \.offset) { index, url in
                    LocalThumbnailImage(url: url, maxPixelSize: LibraryLayout.paperRowThumbnailMaxPixelSize) {
                        Color(nsColor: .textBackgroundColor)
                    }
                    .padding(2)
                    .frame(width: 42, height: 54)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .zIndex(Double(visibleURLs.count - index))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SmallChip: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.paperCodexSystem(size: 12.5, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct LibraryMetadataBlock: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.paperCodexSystem(size: 12.8))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

private struct TagToggleChip: View {
    var tag: PaperTag
    var isAssigned: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(tag.name, systemImage: isAssigned ? "checkmark.circle.fill" : "circle")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(isAssigned ? .accentColor : .secondary)
    }
}

private struct SidebarEmptyText: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(LocalizedStringKey(text))
            .foregroundStyle(.secondary)
            .padding(.vertical, 5)
    }
}

private struct RecentConversationsContent: View {
    var sessions: [PaperSession]
    var papersBySessionID: [String: [Paper]]
    @Binding var selectedSessionID: String?
    var onOpen: (PaperSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Recent Conversations")
                    .font(.paperCodexSystem(size: 28, weight: .semibold))
                Spacer()
            }

            if sessions.isEmpty {
                ContentUnavailableView("No Conversations", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sessions) { session in
                            RecentConversationRow(
                                session: session,
                                papers: papersBySessionID[session.id, default: []],
                                isSelected: selectedSessionID == session.id,
                                onSelect: {
                                    selectedSessionID = session.id
                                },
                                onOpen: {
                                    onOpen(session)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
    }
}

private struct RecentConversationRow: View {
    var session: PaperSession
    var papers: [Paper]
    var isSelected: Bool
    var onSelect: () -> Void
    var onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RecentConversationSelectionButton(
                title: session.title,
                detail: detailText,
                timeText: Self.relativeFormatter.localizedString(for: session.updatedAt, relativeTo: Date()),
                usesStackIcon: session.paperIDs.count > 1,
                isSelected: isSelected,
                action: onSelect
            )

            PaperCodexIconButton(title: "Open Session", systemImage: "arrow.forward.circle", tint: .accentColor, action: onOpen)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .help(session.title)
    }

    private var detailText: String {
        guard session.paperIDs.count > 1 else {
            return papers.first?.title ?? "Single paper"
        }
        let firstTitle = papers.first?.title ?? "Multiple papers"
        return "\(session.paperIDs.count) papers · \(firstTitle)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct RecentConversationSelectionButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var detail: String
    var timeText: String
    var usesStackIcon: Bool
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        NativeRecentConversationSelectionButton(
            title: title,
            detail: detail,
            timeText: timeText,
            usesStackIcon: usesStackIcon,
            isSelected: isSelected,
            reduceMotion: reduceMotion,
            action: action
        )
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct NativeRecentConversationSelectionButton: NSViewRepresentable {
    var title: String
    var detail: String
    var timeText: String
    var usesStackIcon: Bool
    var isSelected: Bool
    var reduceMotion: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NativeRecentConversationSelectionButtonView {
        let view = NativeRecentConversationSelectionButtonView()
        view.apply(
            title: title,
            detail: detail,
            timeText: timeText,
            usesStackIcon: usesStackIcon,
            isSelected: isSelected,
            reduceMotion: reduceMotion,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativeRecentConversationSelectionButtonView, context: Context) {
        view.apply(
            title: title,
            detail: detail,
            timeText: timeText,
            usesStackIcon: usesStackIcon,
            isSelected: isSelected,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private final class NativeRecentConversationSelectionButtonView: NSButton {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var pressHandler: () -> Void = {}
    private var isSelected = false
    private var isHovering = false
    private var isPressed = false
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
        NSSize(width: NSView.noIntrinsicMetric, height: 52)
    }

    func apply(
        title: String,
        detail: String,
        timeText: String,
        usesStackIcon: Bool,
        isSelected: Bool,
        reduceMotion: Bool,
        action: @escaping () -> Void
    ) {
        let localizedTitle = NSLocalizedString(title, comment: "")
        pressHandler = action
        self.isSelected = isSelected
        self.reduceMotion = reduceMotion
        titleLabel.stringValue = localizedTitle
        detailLabel.stringValue = NSLocalizedString(detail, comment: "")
        timeLabel.stringValue = NSLocalizedString(timeText, comment: "")
        iconView.image = NSImage(
            systemSymbolName: usesStackIcon ? "square.stack.3d.up.fill" : "doc.text",
            accessibilityDescription: localizedTitle
        )
        toolTip = localizedTitle
        setAccessibilityLabel(localizedTitle)
        setAccessibilityValue(isSelected ? NSLocalizedString("Selected", comment: "") : NSLocalizedString("Not selected", comment: ""))
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
        layer?.cornerRadius = 7
        layer?.masksToBounds = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.lineBreakMode = .byTruncatingTail
        timeLabel.maximumNumberOfLines = 1
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        [iconView, titleLabel, timeLabel, detailLabel].forEach(addSubview(_:))
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            iconView.widthAnchor.constraint(equalToConstant: 17),
            iconView.heightAnchor.constraint(equalToConstant: 17),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            timeLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -7)
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
        let tint = NSColor.controlAccentColor
        let background: NSColor
        let border: NSColor
        let shadowOpacity: Float

        if isSelected {
            background = tint.withAlphaComponent(isPressed ? 0.18 : 0.12)
            border = isPressed ? tint.withAlphaComponent(0.40) : tint.withAlphaComponent(0.25)
            shadowOpacity = isPressed ? 0.10 : 0
        } else if isPressed {
            background = tint.withAlphaComponent(0.10)
            border = tint.withAlphaComponent(0.40)
            shadowOpacity = 0.10
        } else if isHovering {
            background = .labelColor.withAlphaComponent(0.045)
            border = .clear
            shadowOpacity = 0
        } else {
            background = .clear
            border = .clear
            shadowOpacity = 0
        }

        iconView.contentTintColor = tint
        titleLabel.textColor = .labelColor
        detailLabel.textColor = .secondaryLabelColor
        timeLabel.textColor = .tertiaryLabelColor
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = border == .clear ? 0 : 1
        layer?.borderColor = border.cgColor
        layer?.shadowColor = tint.cgColor
        layer?.shadowOpacity = shadowOpacity
        layer?.shadowRadius = isPressed ? 3 : 5
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? -1 : -2)

        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(isPressed ? 0.988 : 1, isPressed ? 0.988 : 1, 1)
        CATransaction.commit()
    }
}

private struct RecentConversationDetailPanel: View {
    var session: PaperSession?
    var papers: [Paper]
    var onOpen: (PaperSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Conversation Details")
                .font(.paperCodexSystem(size: 20, weight: .semibold))

            if let session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: session.paperIDs.count > 1 ? "square.stack.3d.up.fill" : "doc.text")
                                    .foregroundStyle(Color.accentColor)
                                Text(session.title)
                                    .font(.headline)
                                    .lineLimit(3)
                            }
                            Text("\(session.paperIDs.count) paper\(session.paperIDs.count == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                            Text(Self.relativeFormatter.localizedString(for: session.updatedAt, relativeTo: Date()))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }

                        PaperCodexPanelButton(
                            title: "Open Session",
                            systemImage: "arrow.forward.circle",
                            kind: .primary,
                            fillsWidth: true
                        ) {
                            onOpen(session)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Papers", systemImage: "doc.on.doc")
                                .font(.headline)
                            if papers.isEmpty {
                                SidebarEmptyText("No papers")
                            } else {
                                ForEach(papers) { paper in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(paper.title)
                                                .font(.paperCodexSystem(size: 13, weight: .semibold))
                                                .lineLimit(2)
                                            Text(paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
            } else {
                ContentUnavailableView("Select Conversation", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct BulkLibraryActionBar: View {
    var selectedCount: Int
    var canMove: Bool
    var canTag: Bool
    var canOpenConversation: Bool
    var onRead: () -> Void
    var onChat: () -> Void
    var onCopy: () -> Void
    var onTag: () -> Void
    var onDelete: () -> Void
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label("\(selectedCount) selected", systemImage: "checkmark.circle.fill")
                .font(.paperCodexSystem(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .contentTransition(.numericText())
            Spacer()
            Button(action: onRead) {
                Label("Read", systemImage: "book")
            }
            .disabled(!canOpenConversation)
            .help("Read selected papers together")
            Button(action: onChat) {
                Label("Chat", systemImage: "text.bubble")
            }
            .disabled(!canOpenConversation)
            .help("Chat with selected papers together")
            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(!canMove)
            .help("Copy selected papers to a folder")
            Button(action: onTag) {
                Label("Tag", systemImage: "tag")
            }
            .disabled(!canTag)
            .help("Add tags to selected papers")
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete selected papers")
            Button(action: onClear) {
                Label("Clear", systemImage: "xmark.circle")
            }
            .help("Clear selection")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct LibraryBulkCopySheet: View {
    var categoryItems: [CategoryListItem]
    var selectedCount: Int
    var onCopy: (String?) -> Void
    var onCancel: () -> Void

    @State private var targetCategoryID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Copy Papers", systemImage: "doc.on.doc")
                .font(.title3.weight(.semibold))
            Text("\(selectedCount) selected papers")
                .foregroundStyle(.secondary)
            Picker("Destination", selection: $targetCategoryID) {
                Text("No folder").tag("")
                ForEach(categoryItems) { item in
                    Text(String(repeating: "  ", count: item.depth) + item.category.name)
                        .tag(item.category.id)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button {
                    onCopy(targetCategoryID.isEmpty ? nil : targetCategoryID)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(targetCategoryID.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

private struct LibraryBulkTagSheet: View {
    var tags: [PaperTag]
    var selectedCount: Int
    var onApply: ([String]) -> Void
    var onCancel: () -> Void

    @State private var selectedTagIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Add Tags", systemImage: "tag")
                .font(.title3.weight(.semibold))
            Text("\(selectedCount) selected papers")
                .foregroundStyle(.secondary)
            if tags.isEmpty {
                ContentUnavailableView("No Tags", systemImage: "tag")
                    .frame(width: 380, height: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(tags) { tag in
                        Button {
                            toggle(tag.id)
                        } label: {
                            Label(tag.name, systemImage: selectedTagIDs.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedTagIDs.contains(tag.id) ? .accentColor : .secondary)
                    }
                }
                .frame(width: 420)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button {
                    onApply(Array(selectedTagIDs))
                } label: {
                    Label("Apply", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTagIDs.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 470)
    }

    private func toggle(_ tagID: String) {
        if selectedTagIDs.contains(tagID) {
            selectedTagIDs.remove(tagID)
        } else {
            selectedTagIDs.insert(tagID)
        }
    }
}

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case addedNewest
    case title
    case arxivID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addedNewest:
            "Added"
        case .title:
            "Title"
        case .arxivID:
            "arXiv ID"
        }
    }

    var systemImage: String {
        switch self {
        case .addedNewest:
            "clock.arrow.circlepath"
        case .title:
            "textformat"
        case .arxivID:
            "number"
        }
    }

    func sorted(_ papers: [Paper], ascending: Bool) -> [Paper] {
        let arxivIDsByPaperID: [String: String]
        if self == .arxivID {
            arxivIDsByPaperID = Dictionary(
                uniqueKeysWithValues: papers.compactMap { paper in
                    arxivID(for: paper).map { (paper.id, $0) }
                }
            )
        } else {
            arxivIDsByPaperID = [:]
        }

        return papers.sorted { left, right in
            if left.isStarred != right.isStarred {
                return left.isStarred
            }
            switch self {
            case .addedNewest:
                if left.importedAt != right.importedAt {
                    return ascending ? left.importedAt < right.importedAt : left.importedAt > right.importedAt
                }
                return titleComesBefore(left, right, ascending: true)
            case .title:
                return titleComesBefore(left, right, ascending: ascending)
            case .arxivID:
                return arxivIDComesBefore(left, right, ascending: ascending, arxivIDsByPaperID: arxivIDsByPaperID)
            }
        }
    }

    private func titleComesBefore(_ left: Paper, _ right: Paper, ascending: Bool) -> Bool {
        let titleComparison = left.title.localizedStandardCompare(right.title)
        if titleComparison != .orderedSame {
            return ascending ? titleComparison == .orderedAscending : titleComparison == .orderedDescending
        }
        return left.id < right.id
    }

    private func arxivIDComesBefore(
        _ left: Paper,
        _ right: Paper,
        ascending: Bool,
        arxivIDsByPaperID: [String: String]
    ) -> Bool {
        let leftID = arxivIDsByPaperID[left.id]
        let rightID = arxivIDsByPaperID[right.id]
        switch (leftID, rightID) {
        case let (leftID?, rightID?):
            let comparison = leftID.localizedStandardCompare(rightID)
            if comparison != .orderedSame {
                return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
            return titleComesBefore(left, right, ascending: true)
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return titleComesBefore(left, right, ascending: true)
        }
    }

    private func arxivID(for paper: Paper) -> String? {
        paper.arxivImportPlaceholderCanonicalID
            ?? paper.sourceURL.flatMap(ArxivIDExtractor.firstCanonicalID(in:))
    }
}

private struct LibraryArxivImportSheet: View {
    @EnvironmentObject private var model: AppModel
    var categoryItems: [CategoryListItem]
    var onClose: () -> Void

    @State private var inputText = ""
    @State private var targetCategoryID: String
    @FocusState private var isInputFocused: Bool

    init(categoryItems: [CategoryListItem], initialCategoryID: String?, onClose: @escaping () -> Void) {
        self.categoryItems = categoryItems
        self.onClose = onClose
        _targetCategoryID = State(initialValue: initialCategoryID ?? "")
    }

    private var parsedIDs: [String] {
        ArxivIDExtractor.extractVersionedIDs(from: inputText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Add arXiv Papers", systemImage: "number")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Close", action: onClose)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $inputText)
                    .font(.paperCodexSystem(size: 13, design: .monospaced))
                    .frame(minHeight: 110)
                    .focused($isInputFocused)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                if parsedIDs.isEmpty {
                    Text("Paste arXiv IDs, links, PDFs, or any text containing one or more IDs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(parsedIDs, id: \.self) { id in
                            Text(id)
                                .font(.caption.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                    }
                }
            }

            Picker("Folder", selection: $targetCategoryID) {
                Text("No folder").tag("")
                ForEach(categoryItems) { item in
                    Text(String(repeating: "  ", count: item.depth) + item.category.name)
                        .tag(item.category.id)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                Button {
                    let ids = parsedIDs
                    model.enqueueArxivIDsForLibrary(
                        ids,
                        categoryID: targetCategoryID.isEmpty ? nil : targetCategoryID
                    )
                    onClose()
                } label: {
                    Label("Add", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsedIDs.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 540)
        .onAppear {
            isInputFocused = true
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

private struct LibraryRootFolderDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    var canDropCategory: () -> Bool
    var onDrop: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: LibraryLayout.categoryDropContentTypes) && canDropCategory()
    }

    func dropEntered(info: DropInfo) {
        isTargeted = updateDropState(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        isTargeted = updateDropState(info: info)
        return isTargeted ? DropProposal(operation: .move) : nil
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        guard canDropCategory() else {
            isTargeted = false
            return false
        }
        isTargeted = false
        return onDrop(info.itemProviders(for: LibraryLayout.categoryDropContentTypes))
    }

    private func updateDropState(info _: DropInfo) -> Bool {
        if isTargeted {
            return true
        }
        return canDropCategory()
    }
}

private struct TagSidebarRow: View {
    @State private var isHovering = false

    var title: String
    var countText: String
    var isSelected: Bool
    var onSelect: () -> Void
    var onManage: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            SidebarRowButton(
                title: title,
                systemImage: isSelected ? "tag.fill" : "tag",
                selected: isSelected,
                trailingReserve: 58,
                action: onSelect
            )
            HStack(spacing: 4) {
                Text(countText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                if isHovering || isSelected {
                    Button(action: onManage) {
                        Image(systemName: "ellipsis")
                            .font(.paperCodexSystem(size: 11, weight: .bold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Manage \(title)")
                }
            }
            .padding(.trailing, 6)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct CategoryManagementSheet: View {
    var category: PaperCodexCore.Category
    var categoryItems: [CategoryListItem]
    var onSave: (String, String?) -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var parentID: String

    init(
        category: PaperCodexCore.Category,
        categoryItems: [CategoryListItem],
        onSave: @escaping (String, String?) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.category = category
        self.categoryItems = categoryItems
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _name = State(initialValue: category.name)
        _parentID = State(initialValue: category.parentID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Manage Category", systemImage: "folder")
                .font(.title3.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("Parent", selection: $parentID) {
                Text("Top Level").tag("")
                ForEach(categoryItems) { item in
                    Text(String(repeating: "  ", count: item.depth) + item.category.name)
                        .tag(item.category.id)
                }
            }
            HStack {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(name, parentID.isEmpty ? nil : parentID)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 390)
    }
}

private struct TagManagementSheet: View {
    var tag: PaperTag
    var onSave: (String) -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void

    @State private var name: String

    init(tag: PaperTag, onSave: @escaping (String) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.tag = tag
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _name = State(initialValue: tag.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Manage Tag", systemImage: "tag")
                .font(.title3.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(name)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 340)
    }
}

private struct PaperNoteRow: View {
    var note: PaperNote
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title)
                        .font(.paperCodexSystem(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if !note.bodyMarkdown.isEmpty {
                        Text(note.bodyMarkdown)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete Note")
        }
        .padding(9)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct CategoryEditorSheet: View {
    var categoryItems: [CategoryListItem]
    @Binding var name: String
    @Binding var parentID: String
    var onCreate: (String, String) -> Void
    var onCancel: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Category")
                .font(.title3.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
            Picker("Parent", selection: $parentID) {
                Text("Top Level").tag("")
                ForEach(categoryItems) { item in
                    Text(String(repeating: "  ", count: item.depth) + item.category.name)
                        .tag(item.category.id)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create") {
                    onCreate(name, parentID)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
        .onAppear {
            isNameFocused = true
        }
    }
}

private struct TagEditorSheet: View {
    @Binding var name: String
    var onCreate: (String) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Tag")
                .font(.title3.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create") {
                    onCreate(name)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 320)
    }
}
