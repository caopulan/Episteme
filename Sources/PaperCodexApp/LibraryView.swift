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
    @State private var collapsedCategoryIDs: Set<String> = []
    @State private var categoryPendingManagement: PaperCodexCore.Category?
    @State private var tagPendingManagement: PaperTag?
    @State private var outlineDraggedCategoryID: String?
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

    private var isNoteDraftEmpty: Bool {
        noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private var currentPaperListState: LibraryPaperListState {
        model.libraryPaperListState(
            sortRawValue: librarySortRawValue,
            sortAscending: librarySortAscending,
            includeSubfolders: libraryIncludeSubfolders
        )
    }

    private var currentPaperSelectionState: LibraryPaperSelectionState {
        model.libraryPaperSelectionState(listState: currentPaperListState, selectedPaperIDs: selectedPaperIDs)
    }

    private var filteredPaperIDs: [String] {
        currentPaperSelectionState.visiblePaperIDs
    }

    private var activePaperSurfaceFilteredPaperIDs: [String] {
        selectedLibrarySurface == .papers ? filteredPaperIDs : []
    }

    private var sidebarCategories: [PaperCodexCore.Category] {
        model.categories
    }

    private var selectedPaperIDsInOrder: [String] {
        currentPaperSelectionState.selectedPaperIDsInOrder
    }

    private var selectedReadablePaperIDsInOrder: [String] {
        currentPaperSelectionState.selectedReadablePaperIDsInOrder
    }

    private var selectedRecentSession: PaperSession? {
        if let selectedRecentSessionID,
           let session = model.recentSessions.first(where: { $0.id == selectedRecentSessionID }) {
            return session
        }
        return model.recentSessions.first
    }

    private var tagSidebarRows: [LibraryTagSidebarRowModel] {
        model.tags.map { tag in
            LibraryTagSidebarRowModel(
                id: tag.id,
                title: tag.name,
                countText: "\(paperCount(forTag: tag.id))",
                isSelected: selectedLibrarySurface == .papers && selectedTagID == tag.id
            )
        }
    }

    var body: some View {
        SidebarSplitLayout(minContentWidth: LibraryLayout.libraryContentMinimumWidth) {
            sidebar
        } content: {
            contentPane
        }
        .onChange(of: activePaperSurfaceFilteredPaperIDs) { _, _ in
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
        .paperCodexNativeSheet(isPresented: $isCreatingCategory, title: "New Category", minimumSize: CGSize(width: 440, height: 240)) {
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
        .paperCodexNativeSheet(isPresented: $isCreatingTag, title: "New Tag", minimumSize: CGSize(width: 380, height: 180)) {
            TagEditorSheet(name: $newTagName) { name in
                model.createTag(name: name)
                newTagName = ""
                isCreatingTag = false
            } onCancel: {
                newTagName = ""
                isCreatingTag = false
            }
        }
        .paperCodexNativeSheet(item: $categoryPendingManagement, title: "Category", minimumSize: CGSize(width: 440, height: 260)) { category in
            categoryManagementSheet(category)
        }
        .paperCodexNativeSheet(item: $tagPendingManagement, title: "Tag", minimumSize: CGSize(width: 380, height: 220)) { tag in
            tagManagementSheet(tag)
        }
        .paperCodexNativeSheet(isPresented: $isShowingWatchedFolders, title: "Watched Folders", minimumSize: CGSize(width: 620, height: 420)) {
            WatchedFoldersSheet {
                presentWatchedFolderPanel()
            } onClose: {
                isShowingWatchedFolders = false
            } onRemove: { folder in
                confirmRemoveWatchedFolder(folder)
            }
            .environmentObject(model)
        }
        .paperCodexNativeSheet(isPresented: $isShowingArxivImport, title: "Import arXiv", minimumSize: CGSize(width: 620, height: 520)) {
            LibraryArxivImportSheet(
                categoryItems: flattenedCategoryItems(),
                initialCategoryID: selectedCategoryID
            ) {
                isShowingArxivImport = false
            }
            .environmentObject(model)
        }
        .paperCodexNativeSheet(isPresented: $isShowingBulkCopy, title: "Copy Papers", minimumSize: CGSize(width: 520, height: 360)) {
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
        .paperCodexNativeSheet(isPresented: $isShowingBulkTag, title: "Tag Papers", minimumSize: CGSize(width: 520, height: 360)) {
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

            sidebarContext
        }
        .paperCodexSidebarChromePadding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var sidebarContext: some View {
        switch selectedLibrarySurface {
        case .papers:
            Label("Library Context", systemImage: "books.vertical")
                .font(.headline)
                .foregroundStyle(.secondary)

            PaperCodexNativeScrollView {
                sidebarLists
            }
            .frame(maxHeight: .infinity, alignment: .top)
        case .recentConversations:
            NativeRecentConversationsSidebarContext(
                conversationCount: model.recentSessions.count,
                selectedTitle: selectedRecentSession?.title,
                onOpenLibrary: {
                    selectRootLibrary()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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
                LibraryTagSidebarList(
                    tagRows: tagSidebarRows,
                    onSelect: selectLibraryTag,
                    onManage: { tagID in
                        if let tag = model.tags.first(where: { $0.id == tagID }) {
                            tagPendingManagement = tag
                        }
                    }
                )
                .frame(maxWidth: .infinity, minHeight: LibraryTagSidebarList.height(for: tagSidebarRows.count))
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
            NativeRecentConversationsContent(
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
            NativeRecentConversationDetailPanel(
                session: selectedRecentSession,
                papers: selectedRecentSession.map { model.papersForSession($0) } ?? [],
                onOpen: { session in
                    model.openRecentSession(session)
                }
            )
        }
    }

    private var paperList: some View {
        let listState = currentPaperListState
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
                PaperCodexNativeEmptyState(title: "No Papers", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LibraryPaperTableView(
                    rows: model.libraryPaperTableRows(listState: listState, selectedPaperIDs: selectedPaperIDs),
                    selectedPaperID: model.selectedLibraryPaper?.id,
                    revealRequestID: selectedPaperRevealRequestID,
                    focusRequestID: paperTableFocusRequestID,
                    onMoveSelection: moveFocusedPaperSelection(by:),
                    onSelect: { row in
                        paperTableFocusRequestID = UUID()
                        handlePaperRowClick(row.paper)
                    },
                    onToggleStar: { row in
                        model.togglePaperStar(row.paper)
                    },
                    onRead: { row in
                        model.openPaper(row.paper)
                    },
                    onBeginDrag: { _ in
                        outlineDraggedCategoryID = nil
                    },
                    dragPayload: { row in
                        paperDragPayload(for: row.paper)
                    }
                )
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
                        confirmDeleteSelectedPapers()
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
                PaperCodexNativeScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        LibraryPaperInspectorSummaryView(
                            paper: paper,
                            placeholderDetail: model.arxivImportPlaceholderDetail(for: paper),
                            onToggleStar: {
                                model.togglePaperStar(paper)
                            },
                            onRead: {
                                model.openPaper(paper)
                            }
                        )
                        .frame(minHeight: 170)

                        if inspectorDetailsPaperID == paper.id {
                            Divider()

                            LibraryPaperInspectorDetailsView(
                                paper: paper,
                                metadata: model.libraryArxivMetadata(for: paper),
                                categories: flattenedCategoryItems(),
                                assignedCategoryIDs: Set(model.paperCategoryIDsByID[paper.id, default: []]),
                                tags: model.tags,
                                assignedTagIDs: Set(model.paperTagsByID[paper.id, default: []].map(\.id)),
                                notes: model.paperNotesByID[paper.id, default: []],
                                noteTitle: $noteTitle,
                                noteBody: $noteBody,
                                editingNoteID: editingNoteID,
                                onCreateCategory: {
                                    newCategoryParentID = ""
                                    isCreatingCategory = true
                                },
                                onSetCategory: { categoryID, isAssigned in
                                    model.setCategory(categoryID, assigned: isAssigned, for: paper)
                                },
                                onCreateTag: {
                                    isCreatingTag = true
                                },
                                onSetTag: { tagID, isAssigned in
                                    model.setTag(tagID, assigned: isAssigned, for: paper)
                                },
                                onCreateNote: {
                                    clearNoteDraft()
                                },
                                onEditNote: { note in
                                    editingNoteID = note.id
                                    noteTitle = note.title
                                    noteBody = note.bodyMarkdown
                                },
                                onDeleteNote: { note in
                                    model.deleteNote(note)
                                    if editingNoteID == note.id {
                                        clearNoteDraft()
                                    }
                                },
                                onSaveNote: {
                                    model.saveNote(paperID: paper.id, noteID: editingNoteID, title: noteTitle, bodyMarkdown: noteBody)
                                    clearNoteDraft()
                                },
                                onCancelNote: {
                                    clearNoteDraft()
                                }
                            )
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.trailing, 4)
                }
            } else {
                PaperCodexNativeEmptyState(title: "Select Paper", systemImage: "sidebar.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private struct LibraryPaperInspectorSummaryView: NSViewRepresentable {
        var paper: Paper
        var placeholderDetail: String
        var onToggleStar: () -> Void
        var onRead: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onToggleStar: onToggleStar, onRead: onRead)
        }

        func makeNSView(context: Context) -> NativeLibraryPaperInspectorSummaryView {
            let view = NativeLibraryPaperInspectorSummaryView()
            view.apply(
                paper: paper,
                placeholderDetail: placeholderDetail,
                onToggleStar: onToggleStar,
                onRead: onRead
            )
            return view
        }

        func updateNSView(_ view: NativeLibraryPaperInspectorSummaryView, context: Context) {
            context.coordinator.onToggleStar = onToggleStar
            context.coordinator.onRead = onRead
            view.apply(
                paper: paper,
                placeholderDetail: placeholderDetail,
                onToggleStar: context.coordinator.onToggleStar,
                onRead: context.coordinator.onRead
            )
        }

        @MainActor final class Coordinator {
            var onToggleStar: () -> Void
            var onRead: () -> Void

            init(onToggleStar: @escaping () -> Void, onRead: @escaping () -> Void) {
                self.onToggleStar = onToggleStar
                self.onRead = onRead
            }
        }
    }

    private final class NativeLibraryPaperInspectorSummaryView: NSView {
        private let titleLabel = NSTextField(labelWithString: "")
        private let detailLabel = NSTextField(labelWithString: "")
        private let pathLabel = NSTextField(labelWithString: "")
        private let starButton = NSButton()
        private let readButton = NativeInspectorReadButton()
        private let readButtonTitleLabel = NativeInspectorPassthroughLabel("Read")

        private var onToggleStar: () -> Void = {}
        private var onRead: () -> Void = {}

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            nil
        }

        func apply(
            paper: Paper,
            placeholderDetail: String,
            onToggleStar: @escaping () -> Void,
            onRead: @escaping () -> Void
        ) {
            self.onToggleStar = onToggleStar
            self.onRead = onRead

            titleLabel.stringValue = paper.title
            detailLabel.stringValue = paper.isArxivImportPlaceholder
                ? placeholderDetail
                : (paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "))
            pathLabel.stringValue = paper.isArxivImportPlaceholder ? (paper.sourceURL ?? paper.title) : paper.filePath

            configureSymbolButton(
                starButton,
                systemSymbolName: paper.isStarred ? "star.fill" : "star",
                accessibilityTitle: paper.isStarred ? "Remove Star" : "Star Paper",
                tint: paper.isStarred ? .systemYellow : .secondaryLabelColor
            )
            starButton.isEnabled = !paper.isArxivImportPlaceholder
            readButton.isEnabled = !paper.isArxivImportPlaceholder
            readButtonTitleLabel.textColor = paper.isArxivImportPlaceholder ? .secondaryLabelColor : .labelColor
            alphaValue = paper.isArxivImportPlaceholder ? 0.72 : 1
        }

        private func setup() {
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor

            titleLabel.font = .boldSystemFont(ofSize: 13.5)
            titleLabel.maximumNumberOfLines = 3
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.translatesAutoresizingMaskIntoConstraints = false

            detailLabel.font = .systemFont(ofSize: 12.5)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.maximumNumberOfLines = 2
            detailLabel.lineBreakMode = .byTruncatingTail
            detailLabel.translatesAutoresizingMaskIntoConstraints = false

            pathLabel.font = .systemFont(ofSize: 11.5)
            pathLabel.textColor = .tertiaryLabelColor
            pathLabel.maximumNumberOfLines = 2
            pathLabel.lineBreakMode = .byTruncatingMiddle
            pathLabel.isSelectable = true
            pathLabel.translatesAutoresizingMaskIntoConstraints = false

            configureSymbolButton(
                starButton,
                systemSymbolName: "star",
                accessibilityTitle: "Star Paper",
                tint: .secondaryLabelColor
            )
            starButton.target = self
            starButton.action = #selector(toggleStar)
            starButton.translatesAutoresizingMaskIntoConstraints = false

            readButton.target = self
            readButton.action = #selector(readPaper)
            readButton.setAccessibilityLabel("Read")
            readButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
            readButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            readButton.translatesAutoresizingMaskIntoConstraints = false

            readButtonTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            readButtonTitleLabel.alignment = .center
            readButtonTitleLabel.translatesAutoresizingMaskIntoConstraints = false

            addSubview(titleLabel)
            addSubview(detailLabel)
            addSubview(pathLabel)
            addSubview(starButton)
            addSubview(readButton)
            addSubview(readButtonTitleLabel)

            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                titleLabel.topAnchor.constraint(equalTo: topAnchor),
                titleLabel.trailingAnchor.constraint(equalTo: starButton.leadingAnchor, constant: -8),

                starButton.topAnchor.constraint(equalTo: topAnchor, constant: -2),
                starButton.trailingAnchor.constraint(equalTo: trailingAnchor),
                starButton.widthAnchor.constraint(equalToConstant: 30),
                starButton.heightAnchor.constraint(equalToConstant: 30),

                detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
                detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

                pathLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                pathLabel.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 6),
                pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

                readButton.leadingAnchor.constraint(equalTo: leadingAnchor),
                readButton.trailingAnchor.constraint(equalTo: trailingAnchor),
                readButton.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 14),
                readButton.heightAnchor.constraint(equalToConstant: 34),
                readButton.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

                readButtonTitleLabel.leadingAnchor.constraint(equalTo: readButton.leadingAnchor, constant: 12),
                readButtonTitleLabel.trailingAnchor.constraint(equalTo: readButton.trailingAnchor, constant: -12),
                readButtonTitleLabel.centerYAnchor.constraint(equalTo: readButton.centerYAnchor),
                readButtonTitleLabel.heightAnchor.constraint(equalToConstant: 18)
            ])
        }

        private func configureSymbolButton(
            _ button: NSButton,
            systemSymbolName: String,
            accessibilityTitle: String,
            tint: NSColor
        ) {
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: accessibilityTitle)
            button.contentTintColor = tint
            button.toolTip = accessibilityTitle
            button.setAccessibilityLabel(accessibilityTitle)
        }

        @objc private func toggleStar() {
            onToggleStar()
        }

        @objc private func readPaper() {
            onRead()
        }
    }

    private final class NativeInspectorPassthroughLabel: NSTextField {
        init(_ value: String) {
            super.init(frame: .zero)
            stringValue = value
            isEditable = false
            isSelectable = false
            isBordered = false
            drawsBackground = false
            setAccessibilityElement(false)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    private final class NativeInspectorReadButton: NSButton {
        private let buttonTitleLabel = NSTextField(labelWithString: "Read")

        private var isPressed = false {
            didSet {
                updateAppearance()
            }
        }

        override var isEnabled: Bool {
            didSet {
                updateAppearance()
            }
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: 34)
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else {
                return
            }

            isPressed = true
            super.mouseDown(with: event)
            isPressed = false
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        private func setup() {
            translatesAutoresizingMaskIntoConstraints = false
            title = ""
            isBordered = false
            bezelStyle = .regularSquare
            imagePosition = .noImage
            focusRingType = .none
            setButtonType(.momentaryChange)
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Read")
            toolTip = "Read"
            wantsLayer = true
            layer?.cornerRadius = 7
            layer?.masksToBounds = false

            buttonTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            buttonTitleLabel.alignment = .center
            buttonTitleLabel.lineBreakMode = .byClipping
            buttonTitleLabel.maximumNumberOfLines = 1
            buttonTitleLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(buttonTitleLabel)

            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 34),
                buttonTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                buttonTitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                buttonTitleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                buttonTitleLabel.heightAnchor.constraint(equalToConstant: 18)
            ])
            updateAppearance()
        }

        private func updateAppearance() {
            let background: NSColor
            let border: NSColor
            if !isEnabled {
                background = .controlBackgroundColor.withAlphaComponent(0.56)
                border = .black.withAlphaComponent(0.06)
                buttonTitleLabel.textColor = .secondaryLabelColor.withAlphaComponent(0.56)
            } else {
                background = isPressed ? NSColor.controlAccentColor.withAlphaComponent(0.18) : .controlBackgroundColor
                border = isPressed ? NSColor.controlAccentColor.withAlphaComponent(0.54) : .black.withAlphaComponent(0.10)
                buttonTitleLabel.textColor = isPressed ? .controlAccentColor : .labelColor
            }

            layer?.backgroundColor = background.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = border.cgColor
        }
    }

    private struct LibraryPaperInspectorDetailsView: NSViewRepresentable {
        var paper: Paper
        var metadata: LibraryPaperArxivMetadata?
        var categories: [CategoryListItem]
        var assignedCategoryIDs: Set<String>
        var tags: [PaperTag]
        var assignedTagIDs: Set<String>
        var notes: [PaperNote]
        @Binding var noteTitle: String
        @Binding var noteBody: String
        var editingNoteID: String?
        var onCreateCategory: () -> Void
        var onSetCategory: (String, Bool) -> Void
        var onCreateTag: () -> Void
        var onSetTag: (String, Bool) -> Void
        var onCreateNote: () -> Void
        var onEditNote: (PaperNote) -> Void
        var onDeleteNote: (PaperNote) -> Void
        var onSaveNote: () -> Void
        var onCancelNote: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(noteTitle: $noteTitle, noteBody: $noteBody)
        }

        func makeNSView(context: Context) -> NativeLibraryPaperInspectorDetailsView {
            let view = NativeLibraryPaperInspectorDetailsView()
            updateCoordinator(context.coordinator)
            view.apply(
                paper: paper,
                metadata: metadata,
                categories: categories,
                assignedCategoryIDs: assignedCategoryIDs,
                tags: tags,
                assignedTagIDs: assignedTagIDs,
                notes: notes,
                noteTitle: noteTitle,
                noteBody: noteBody,
                editingNoteID: editingNoteID,
                coordinator: context.coordinator
            )
            return view
        }

        func updateNSView(_ view: NativeLibraryPaperInspectorDetailsView, context: Context) {
            context.coordinator.noteTitle = $noteTitle
            context.coordinator.noteBody = $noteBody
            updateCoordinator(context.coordinator)
            view.apply(
                paper: paper,
                metadata: metadata,
                categories: categories,
                assignedCategoryIDs: assignedCategoryIDs,
                tags: tags,
                assignedTagIDs: assignedTagIDs,
                notes: notes,
                noteTitle: noteTitle,
                noteBody: noteBody,
                editingNoteID: editingNoteID,
                coordinator: context.coordinator
            )
        }

        private func updateCoordinator(_ coordinator: Coordinator) {
            coordinator.onCreateCategory = onCreateCategory
            coordinator.onSetCategory = onSetCategory
            coordinator.onCreateTag = onCreateTag
            coordinator.onSetTag = onSetTag
            coordinator.onCreateNote = onCreateNote
            coordinator.onEditNote = onEditNote
            coordinator.onDeleteNote = onDeleteNote
            coordinator.onSaveNote = onSaveNote
            coordinator.onCancelNote = onCancelNote
        }

        @MainActor final class Coordinator: NSObject {
            var noteTitle: Binding<String>
            var noteBody: Binding<String>
            var onCreateCategory: () -> Void = {}
            var onSetCategory: (String, Bool) -> Void = { _, _ in }
            var onCreateTag: () -> Void = {}
            var onSetTag: (String, Bool) -> Void = { _, _ in }
            var onCreateNote: () -> Void = {}
            var onEditNote: (PaperNote) -> Void = { _ in }
            var onDeleteNote: (PaperNote) -> Void = { _ in }
            var onSaveNote: () -> Void = {}
            var onCancelNote: () -> Void = {}

            init(noteTitle: Binding<String>, noteBody: Binding<String>) {
                self.noteTitle = noteTitle
                self.noteBody = noteBody
                super.init()
            }
        }
    }

    private final class NativeLibraryPaperInspectorDetailsView: NSView, NSTextFieldDelegate, NSTextViewDelegate {
        private let stackView = NSStackView()
        private let noteTitleField = NSTextField()
        private let noteBodyScrollView = NSScrollView()
        private let noteBodyTextView = NSTextView()
        private let saveNoteButton = NSButton()
        private let cancelNoteButton = NSButton()
        private let draftContainer = NSStackView()
        private var lastContentKey = ""
        private var isUpdatingDraft = false
        private weak var coordinator: LibraryPaperInspectorDetailsView.Coordinator?

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: max(stackView.fittingSize.height, 1))
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            nil
        }

        func apply(
            paper: Paper,
            metadata: LibraryPaperArxivMetadata?,
            categories: [CategoryListItem],
            assignedCategoryIDs: Set<String>,
            tags: [PaperTag],
            assignedTagIDs: Set<String>,
            notes: [PaperNote],
            noteTitle: String,
            noteBody: String,
            editingNoteID: String?,
            coordinator: LibraryPaperInspectorDetailsView.Coordinator
        ) {
            self.coordinator = coordinator
            let contentKey = Self.contentKey(
                paper: paper,
                metadata: metadata,
                categories: categories,
                assignedCategoryIDs: assignedCategoryIDs,
                tags: tags,
                assignedTagIDs: assignedTagIDs,
                notes: notes,
                editingNoteID: editingNoteID
            )
            if contentKey != lastContentKey {
                lastContentKey = contentKey
                rebuildContent(
                    paper: paper,
                    metadata: metadata,
                    categories: categories,
                    assignedCategoryIDs: assignedCategoryIDs,
                    tags: tags,
                    assignedTagIDs: assignedTagIDs,
                    notes: notes,
                    editingNoteID: editingNoteID
                )
            }
            updateDraft(noteTitle: noteTitle, noteBody: noteBody, editingNoteID: editingNoteID)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isUpdatingDraft,
                  let textField = notification.object as? NSTextField,
                  textField === noteTitleField else {
                return
            }
            coordinator?.noteTitle.wrappedValue = textField.stringValue
            updateDraftActionState()
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingDraft,
                  let textView = notification.object as? NSTextView,
                  textView === noteBodyTextView else {
                return
            }
            coordinator?.noteBody.wrappedValue = textView.string
            updateDraftActionState()
        }

        private func setup() {
            translatesAutoresizingMaskIntoConstraints = false
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.orientation = .vertical
            stackView.alignment = .width
            stackView.spacing = 13
            stackView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            stackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addSubview(stackView)

            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
                stackView.topAnchor.constraint(equalTo: topAnchor),
                stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])

            setupDraftContainer()
        }

        private func setupDraftContainer() {
            draftContainer.translatesAutoresizingMaskIntoConstraints = false
            draftContainer.orientation = .vertical
            draftContainer.alignment = .width
            draftContainer.spacing = 8

            noteTitleField.translatesAutoresizingMaskIntoConstraints = false
            noteTitleField.placeholderString = "Note title"
            noteTitleField.font = .systemFont(ofSize: 13)
            noteTitleField.isBordered = true
            noteTitleField.isBezeled = true
            noteTitleField.bezelStyle = .roundedBezel
            noteTitleField.delegate = self
            noteTitleField.setAccessibilityLabel("Note title")

            noteBodyScrollView.translatesAutoresizingMaskIntoConstraints = false
            noteBodyScrollView.borderType = .noBorder
            noteBodyScrollView.hasVerticalScroller = true
            noteBodyScrollView.drawsBackground = false
            noteBodyScrollView.wantsLayer = true
            noteBodyScrollView.layer?.cornerRadius = 7
            noteBodyScrollView.layer?.borderWidth = 1
            noteBodyScrollView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
            noteBodyScrollView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
            noteBodyScrollView.setAccessibilityLabel("Note body")

            noteBodyTextView.translatesAutoresizingMaskIntoConstraints = false
            noteBodyTextView.isRichText = false
            noteBodyTextView.isAutomaticQuoteSubstitutionEnabled = false
            noteBodyTextView.isAutomaticDashSubstitutionEnabled = false
            noteBodyTextView.allowsUndo = true
            noteBodyTextView.drawsBackground = false
            noteBodyTextView.font = .systemFont(ofSize: 12.5)
            noteBodyTextView.textContainerInset = NSSize(width: 8, height: 7)
            noteBodyTextView.textContainer?.widthTracksTextView = true
            noteBodyTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            noteBodyTextView.delegate = self
            noteBodyTextView.setAccessibilityLabel("Note body")
            noteBodyScrollView.documentView = noteBodyTextView

            saveNoteButton.translatesAutoresizingMaskIntoConstraints = false
            configurePanelButton(saveNoteButton, title: "Add Note", systemSymbolName: "checkmark", isPrimary: true)
            saveNoteButton.target = self
            saveNoteButton.action = #selector(saveNote)

            cancelNoteButton.translatesAutoresizingMaskIntoConstraints = false
            configurePanelButton(cancelNoteButton, title: "Cancel", systemSymbolName: "xmark", isPrimary: false)
            cancelNoteButton.target = self
            cancelNoteButton.action = #selector(cancelNote)

            let buttonRow = NSStackView()
            buttonRow.translatesAutoresizingMaskIntoConstraints = false
            buttonRow.orientation = .horizontal
            buttonRow.alignment = .centerY
            buttonRow.spacing = 8
            buttonRow.addArrangedSubview(saveNoteButton)
            buttonRow.addArrangedSubview(cancelNoteButton)

            draftContainer.addArrangedSubview(noteTitleField)
            draftContainer.addArrangedSubview(noteBodyScrollView)
            draftContainer.addArrangedSubview(buttonRow)

            NSLayoutConstraint.activate([
                noteTitleField.widthAnchor.constraint(equalTo: draftContainer.widthAnchor),
                noteTitleField.heightAnchor.constraint(equalToConstant: 30),
                noteBodyScrollView.widthAnchor.constraint(equalTo: draftContainer.widthAnchor),
                noteBodyScrollView.heightAnchor.constraint(equalToConstant: 78),
                saveNoteButton.heightAnchor.constraint(equalToConstant: 30),
                cancelNoteButton.heightAnchor.constraint(equalToConstant: 30)
            ])
        }

        private func rebuildContent(
            paper: Paper,
            metadata: LibraryPaperArxivMetadata?,
            categories: [CategoryListItem],
            assignedCategoryIDs: Set<String>,
            tags: [PaperTag],
            assignedTagIDs: Set<String>,
            notes: [PaperNote],
            editingNoteID: String?
        ) {
            for arrangedSubview in stackView.arrangedSubviews {
                stackView.removeArrangedSubview(arrangedSubview)
                arrangedSubview.removeFromSuperview()
            }

            let metadataBlocks = Self.metadataBlocks(for: paper, metadata: metadata)
            if !metadataBlocks.isEmpty {
                stackView.addArrangedSubview(sectionHeader(title: "解析信息", systemSymbolName: "sparkles"))
                for block in metadataBlocks {
                    stackView.addArrangedSubview(metadataBlock(title: block.title, text: block.text))
                }
                stackView.addArrangedSubview(separator())
            }

            stackView.addArrangedSubview(sectionHeader(title: "Categories", systemSymbolName: "folder", buttonTitle: "New Category", buttonSymbol: "plus", action: #selector(createCategory)))
            if categories.isEmpty {
                stackView.addArrangedSubview(emptyText("No categories"))
            } else {
                for item in categories {
                    stackView.addArrangedSubview(categoryRow(item: item, isAssigned: assignedCategoryIDs.contains(item.category.id)))
                }
            }
            stackView.addArrangedSubview(separator())

            stackView.addArrangedSubview(sectionHeader(title: "Tags", systemSymbolName: "tag", buttonTitle: "New Tag", buttonSymbol: "plus", action: #selector(createTag)))
            if tags.isEmpty {
                stackView.addArrangedSubview(emptyText("No tags"))
            } else {
                for tag in tags {
                    let button = NativeInspectorDetailsTagButton()
                    button.apply(title: tag.name, tagID: tag.id, isSelected: assignedTagIDs.contains(tag.id))
                    button.target = self
                    button.action = #selector(toggleTag(_:))
                    stackView.addArrangedSubview(button)
                    button.heightAnchor.constraint(equalToConstant: 30).isActive = true
                }
            }
            stackView.addArrangedSubview(separator())

            stackView.addArrangedSubview(sectionHeader(title: "Notes", systemSymbolName: "note.text", buttonTitle: editingNoteID == nil ? nil : "New Note", buttonSymbol: "plus", action: #selector(createNote)))
            if notes.isEmpty {
                stackView.addArrangedSubview(emptyText("No notes"))
            } else {
                for note in notes {
                    let row = NativeInspectorDetailsNoteRowView()
                    row.apply(note: note)
                    row.onEdit = { [weak self] note in
                        self?.coordinator?.onEditNote(note)
                    }
                    row.onDelete = { [weak self] note in
                        self?.coordinator?.onDeleteNote(note)
                    }
                    stackView.addArrangedSubview(row)
                }
            }
            stackView.addArrangedSubview(draftContainer)

            needsLayout = true
            layoutSubtreeIfNeeded()
            invalidateIntrinsicContentSize()
        }

        private func updateDraft(noteTitle: String, noteBody: String, editingNoteID: String?) {
            isUpdatingDraft = true
            if noteTitleField.stringValue != noteTitle,
               (noteTitleField.currentEditor() as? NSTextView)?.hasMarkedText() != true {
                noteTitleField.stringValue = noteTitle
            }
            if noteBodyTextView.string != noteBody,
               !noteBodyTextView.hasMarkedText() {
                noteBodyTextView.string = noteBody
            }
            isUpdatingDraft = false

            saveNoteButton.title = editingNoteID == nil ? "Add Note" : "Save Note"
            saveNoteButton.toolTip = saveNoteButton.title
            saveNoteButton.setAccessibilityLabel(saveNoteButton.title)
            cancelNoteButton.isHidden = editingNoteID == nil
            updateDraftActionState()
        }

        private func updateDraftActionState() {
            let title = noteTitleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = noteBodyTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            saveNoteButton.isEnabled = !title.isEmpty || !body.isEmpty
            saveNoteButton.alphaValue = saveNoteButton.isEnabled ? 1 : 0.54
        }

        private func sectionHeader(
            title: String,
            systemSymbolName: String,
            buttonTitle: String? = nil,
            buttonSymbol: String? = nil,
            action: Selector? = nil
        ) -> NSView {
            let row = NSStackView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 7

            let iconView = NSImageView()
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: nil)
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            iconView.contentTintColor = .secondaryLabelColor
            iconView.imageScaling = .scaleProportionallyDown

            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
            titleLabel.lineBreakMode = .byTruncatingTail

            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            row.addArrangedSubview(iconView)
            row.addArrangedSubview(titleLabel)
            row.addArrangedSubview(spacer)

            if let buttonTitle, let buttonSymbol, let action {
                let button = iconButton(title: buttonTitle, systemSymbolName: buttonSymbol, action: action)
                row.addArrangedSubview(button)
                button.widthAnchor.constraint(equalToConstant: 28).isActive = true
                button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            }

            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 16),
                iconView.heightAnchor.constraint(equalToConstant: 16)
            ])
            return row
        }

        private func metadataBlock(title: String, text: String) -> NSView {
            let stack = NSStackView()
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 4

            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
            titleLabel.textColor = .secondaryLabelColor

            let textLabel = NSTextField(wrappingLabelWithString: text)
            textLabel.font = .systemFont(ofSize: 12.8)
            textLabel.textColor = .labelColor
            textLabel.isSelectable = true
            textLabel.maximumNumberOfLines = 0

            stack.addArrangedSubview(titleLabel)
            stack.addArrangedSubview(textLabel)
            textLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return stack
        }

        private func categoryRow(item: CategoryListItem, isAssigned: Bool) -> NSView {
            let row = NSStackView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 0

            if item.depth > 0 {
                let spacer = NSView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                row.addArrangedSubview(spacer)
                spacer.widthAnchor.constraint(equalToConstant: CGFloat(item.depth * 14)).isActive = true
            }

            let checkbox = NSButton(checkboxWithTitle: item.category.name, target: self, action: #selector(toggleCategory(_:)))
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            checkbox.identifier = NSUserInterfaceItemIdentifier(item.category.id)
            checkbox.state = isAssigned ? .on : .off
            checkbox.font = .systemFont(ofSize: 12.5)
            checkbox.lineBreakMode = .byTruncatingTail
            checkbox.setAccessibilityLabel(item.category.name)
            checkbox.setAccessibilityValue(isAssigned ? "Selected" : "Not selected")
            row.addArrangedSubview(checkbox)
            row.heightAnchor.constraint(equalToConstant: 26).isActive = true
            return row
        }

        private func emptyText(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 12.5)
            label.textColor = .secondaryLabelColor
            return label
        }

        private func separator() -> NSBox {
            let box = NSBox()
            box.translatesAutoresizingMaskIntoConstraints = false
            box.boxType = .separator
            return box
        }

        private func iconButton(title: String, systemSymbolName: String, action: Selector) -> NSButton {
            let button = NSButton()
            button.translatesAutoresizingMaskIntoConstraints = false
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: title)
            button.contentTintColor = .secondaryLabelColor
            button.target = self
            button.action = action
            button.toolTip = title
            button.setAccessibilityLabel(title)
            return button
        }

        private func configurePanelButton(_ button: NSButton, title: String, systemSymbolName: String, isPrimary: Bool) {
            button.title = title
            button.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: title)
            button.imagePosition = .imageLeading
            button.bezelStyle = isPrimary ? .rounded : .regularSquare
            button.controlSize = .regular
            button.font = .systemFont(ofSize: 12.5, weight: .medium)
            button.toolTip = title
            button.setAccessibilityLabel(title)
        }

        @objc private func createCategory() {
            coordinator?.onCreateCategory()
        }

        @objc private func toggleCategory(_ sender: NSButton) {
            guard let categoryID = sender.identifier?.rawValue else {
                return
            }
            coordinator?.onSetCategory(categoryID, sender.state == .on)
        }

        @objc private func createTag() {
            coordinator?.onCreateTag()
        }

        @objc private func toggleTag(_ sender: NativeInspectorDetailsTagButton) {
            coordinator?.onSetTag(sender.tagID, !sender.isSelected)
        }

        @objc private func createNote() {
            coordinator?.onCreateNote()
        }

        @objc private func saveNote() {
            coordinator?.onSaveNote()
        }

        @objc private func cancelNote() {
            coordinator?.onCancelNote()
        }

        private static func contentKey(
            paper: Paper,
            metadata: LibraryPaperArxivMetadata?,
            categories: [CategoryListItem],
            assignedCategoryIDs: Set<String>,
            tags: [PaperTag],
            assignedTagIDs: Set<String>,
            notes: [PaperNote],
            editingNoteID: String?
        ) -> String {
            [
                paper.id,
                metadata.map(metadataKey) ?? "",
                categories.map { "\($0.category.id):\($0.category.name):\($0.depth)" }.joined(separator: "|"),
                assignedCategoryIDs.sorted().joined(separator: ","),
                tags.map { "\($0.id):\($0.name)" }.joined(separator: "|"),
                assignedTagIDs.sorted().joined(separator: ","),
                notes.map { "\($0.id):\($0.title):\($0.bodyMarkdown):\($0.updatedAt.timeIntervalSinceReferenceDate)" }.joined(separator: "|"),
                editingNoteID ?? ""
            ].joined(separator: "||")
        }

        private static func metadataKey(_ metadata: LibraryPaperArxivMetadata) -> String {
            [
                metadata.arxivID,
                metadata.titleZH,
                metadata.summaryZH,
                metadata.contribution,
                metadata.abstractZH,
                metadata.abstractEN,
                metadata.tags.joined(separator: ",")
            ].joined(separator: "|")
        }

        private static func metadataBlocks(for paper: Paper, metadata: LibraryPaperArxivMetadata?) -> [(title: String, text: String)] {
            guard let metadata else {
                return []
            }
            var blocks: [(title: String, text: String)] = []
            if !metadata.titleZH.isEmpty, metadata.titleZH != paper.title {
                blocks.append(("中文标题", metadata.titleZH))
            }
            if !metadata.summaryZH.isEmpty {
                blocks.append(("中文摘要", metadata.summaryZH))
            }
            if !metadata.contribution.isEmpty {
                blocks.append(("贡献总结", metadata.contribution))
            }
            if !metadata.abstractZH.isEmpty {
                blocks.append(("中文 Abstract", metadata.abstractZH))
            }
            if !metadata.abstractEN.isEmpty {
                blocks.append(("Abstract", metadata.abstractEN))
            }
            if !metadata.tags.isEmpty {
                blocks.append(("Tags", metadata.tags.prefix(10).joined(separator: ", ")))
            }
            return blocks
        }
    }

    private final class NativeInspectorDetailsTagButton: NSButton {
        private let iconView = NSImageView()
        private let titleLabel = NSTextField(labelWithString: "")
        private var trackingAreaToken: NSTrackingArea?
        private var isHovering = false
        private var isPressed = false
        private(set) var tagID = ""
        private(set) var isSelected = false

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: 30)
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingAreaToken {
                removeTrackingArea(trackingAreaToken)
            }
            let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
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

        func apply(title: String, tagID: String, isSelected: Bool) {
            self.tagID = tagID
            self.isSelected = isSelected
            titleLabel.stringValue = title
            toolTip = title
            setAccessibilityLabel(title)
            setAccessibilityRole(.checkBox)
            setAccessibilityValue(isSelected ? "Selected" : "Not selected")
            updateAppearance()
        }

        private func setup() {
            translatesAutoresizingMaskIntoConstraints = false
            wantsLayer = true
            isBordered = false
            title = ""
            bezelStyle = .regularSquare
            setButtonType(.momentaryChange)
            focusRingType = .none

            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)
            iconView.imageScaling = .scaleProportionallyDown

            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.maximumNumberOfLines = 1

            addSubview(iconView)
            addSubview(titleLabel)

            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 14),
                iconView.heightAnchor.constraint(equalToConstant: 14),
                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
                titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }

        private func updateAppearance() {
            layer?.cornerRadius = 7
            layer?.masksToBounds = false
            let accent = NSColor.controlAccentColor
            let foreground: NSColor
            let background: NSColor
            let border: NSColor
            if isSelected {
                foreground = accent
                background = accent.withAlphaComponent(isPressed ? 0.20 : isHovering ? 0.14 : 0.10)
                border = accent.withAlphaComponent(isHovering || isPressed ? 0.48 : 0.30)
                iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            } else {
                foreground = .secondaryLabelColor
                background = NSColor.controlBackgroundColor.withAlphaComponent(isHovering ? 0.88 : 0.64)
                border = NSColor.black.withAlphaComponent(isHovering || isPressed ? 0.16 : 0.08)
                iconView.image = NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
            }
            titleLabel.textColor = foreground
            iconView.contentTintColor = foreground
            layer?.backgroundColor = background.cgColor
            layer?.borderColor = border.cgColor
            layer?.borderWidth = 1
        }
    }

    private final class NativeInspectorDetailsNoteRowView: NSView {
        private let editButton = NSButton()
        private let deleteButton = NSButton()
        private let titleLabel = NSTextField(labelWithString: "")
        private let bodyLabel = NSTextField(labelWithString: "")
        private let dateLabel = NSTextField(labelWithString: "")
        private var note: PaperNote?
        var onEdit: (PaperNote) -> Void = { _ in }
        var onDelete: (PaperNote) -> Void = { _ in }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: bodyLabel.isHidden ? 48 : 62)
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            nil
        }

        func apply(note: PaperNote) {
            self.note = note
            titleLabel.stringValue = note.title
            bodyLabel.stringValue = note.bodyMarkdown
            bodyLabel.isHidden = note.bodyMarkdown.isEmpty
            dateLabel.stringValue = note.updatedAt.formatted(date: .abbreviated, time: .shortened)
            editButton.toolTip = note.bodyMarkdown.isEmpty ? note.title : "\(note.title)\n\(note.bodyMarkdown)"
            editButton.setAccessibilityLabel(note.title)
            editButton.setAccessibilityValue(note.bodyMarkdown)
            invalidateIntrinsicContentSize()
        }

        private func setup() {
            translatesAutoresizingMaskIntoConstraints = false
            wantsLayer = true
            layer?.cornerRadius = 7
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

            editButton.translatesAutoresizingMaskIntoConstraints = false
            editButton.isBordered = false
            editButton.title = ""
            editButton.bezelStyle = .regularSquare
            editButton.target = self
            editButton.action = #selector(editNote)

            deleteButton.translatesAutoresizingMaskIntoConstraints = false
            deleteButton.isBordered = false
            deleteButton.bezelStyle = .regularSquare
            deleteButton.imagePosition = .imageOnly
            deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete Note")
            deleteButton.contentTintColor = .systemRed
            deleteButton.target = self
            deleteButton.action = #selector(deleteNote)
            deleteButton.toolTip = "Delete Note"
            deleteButton.setAccessibilityLabel("Delete Note")

            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLabel.lineBreakMode = .byTruncatingTail
            bodyLabel.translatesAutoresizingMaskIntoConstraints = false
            bodyLabel.font = .systemFont(ofSize: 11.5)
            bodyLabel.textColor = .secondaryLabelColor
            bodyLabel.lineBreakMode = .byTruncatingTail
            bodyLabel.maximumNumberOfLines = 2
            dateLabel.translatesAutoresizingMaskIntoConstraints = false
            dateLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
            dateLabel.textColor = .tertiaryLabelColor

            addSubview(editButton)
            addSubview(titleLabel)
            addSubview(bodyLabel)
            addSubview(dateLabel)
            addSubview(deleteButton)

            NSLayoutConstraint.activate([
                editButton.leadingAnchor.constraint(equalTo: leadingAnchor),
                editButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -6),
                editButton.topAnchor.constraint(equalTo: topAnchor),
                editButton.bottomAnchor.constraint(equalTo: bottomAnchor),

                deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                deleteButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                deleteButton.widthAnchor.constraint(equalToConstant: 28),
                deleteButton.heightAnchor.constraint(equalToConstant: 28),

                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateLabel.leadingAnchor, constant: -8),
                titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),

                dateLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
                dateLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

                bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                bodyLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
                bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
                bodyLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -7)
            ])
        }

        @objc private func editNote() {
            guard let note else {
                return
            }
            onEdit(note)
        }

        @objc private func deleteNote() {
            guard let note else {
                return
            }
            onDelete(note)
        }
    }

    private func sidebarHeader(_ title: String, systemImage: String, onAdd: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            PaperCodexIconButton(title: "New \(title.dropLast())", systemImage: "plus") {
                onAdd()
            }
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
        let visiblePapers = currentPaperListState.papers
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
              currentPaperSelectionState.visiblePaperIDSet.contains(focusedPaper.id) else {
            return []
        }
        return [focusedPaper.id]
    }

    private func applyPaperSelection(_ paperIDs: Set<String>, focusedPaper: Paper) {
        let listState = currentPaperListState
        let selectionState = currentPaperSelectionState
        let visibleSelection = paperIDs.intersection(selectionState.visiblePaperIDSet)
        if visibleSelection.count > 1 {
            selectedPaperIDs = visibleSelection
            lastSelectedPaperID = focusedPaper.id
            focusLibraryPaper(focusedPaper)
            return
        }

        clearPaperMultiSelection()
        if let remainingID = visibleSelection.first,
           let remainingPaper = listState.papersByID[remainingID] {
            lastSelectedPaperID = remainingID
            focusLibraryPaper(remainingPaper)
        } else if selectionState.visiblePaperIDSet.contains(focusedPaper.id) {
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
        let visibleIDs = currentPaperSelectionState.visiblePaperIDs
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
        let selectionState = currentPaperSelectionState
        selectedPaperIDs = selectedPaperIDs.intersection(selectionState.visiblePaperIDSet)
        if selectedPaperIDs.count < 2 {
            clearPaperMultiSelection()
        }
        if let lastSelectedPaperID, !selectedPaperIDs.isEmpty, !selectedPaperIDs.contains(lastSelectedPaperID) {
            self.lastSelectedPaperID = selectionState.visiblePaperIDs.reversed().first { selectedPaperIDs.contains($0) }
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

    private func confirmDeleteSelectedPapers() {
        let count = selectedPaperIDs.count
        guard count > 0 else {
            return
        }
        PaperCodexNativeConfirmation.present(
            title: "Delete selected papers?",
            message: "This removes \(count) papers from the local library and deletes app-managed PDF/cache files. This cannot be undone.",
            confirmTitle: "Delete",
            style: .critical
        ) {
            deleteSelectedPapers()
        }
    }

    private func confirmDeleteCategory(_ category: PaperCodexCore.Category) {
        PaperCodexNativeConfirmation.present(
            title: "Delete category?",
            message: "This removes the category, its subcategories, and their assignments. Papers stay in the library.",
            confirmTitle: "Delete",
            style: .critical
        ) {
            model.deleteCategory(category.id)
            selectedCategoryID = nil
        }
    }

    private func confirmDeleteTag(_ tag: PaperTag) {
        PaperCodexNativeConfirmation.present(
            title: "Delete tag?",
            message: "This removes the tag from every paper. Papers stay in the library.",
            confirmTitle: "Delete",
            style: .critical
        ) {
            model.deleteTag(tag.id)
            selectedTagID = nil
        }
    }

    private func confirmRemoveWatchedFolder(_ folder: WatchedFolder) {
        PaperCodexNativeConfirmation.present(
            title: "Remove watched folder?",
            message: "The folder will stop being scanned. Imported papers remain in the library.",
            confirmTitle: "Remove",
            style: .warning
        ) {
            model.removeWatchedFolder(folder)
        }
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

    private func paperDragPayload(for paper: Paper) -> String {
        paperIDsForDrag(startingWith: paper).joined(separator: "\n")
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
                confirmDeleteCategory(category)
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
                confirmDeleteTag(tag)
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
                PaperCodexPanelButton(title: "Add Folder", systemImage: "plus", kind: .primary) {
                    onAdd()
                }
                PaperCodexPanelButton(
                    title: model.isScanningWatchedFolders ? "Scanning" : "Scan",
                    systemImage: "arrow.clockwise",
                    disabled: model.watchedFolders.isEmpty || model.isScanningWatchedFolders
                ) {
                    model.scanWatchedFolders()
                }
            }

            if model.watchedFolders.isEmpty {
                PaperCodexNativeEmptyState(title: "No Folders", systemImage: "folder")
                    .frame(width: 520, height: 220)
            } else {
                PaperCodexNativeScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.watchedFolders) { folder in
                            WatchedFolderRow(folder: folder) {
                                onRemove(folder)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(width: 560, height: 260)
            }

            HStack {
                Spacer()
                PaperCodexPanelButton(title: "Close", systemImage: "xmark", keyEquivalent: "\r") {
                    onClose()
                }
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
            PaperCodexIconButton(title: "Remove Folder", systemImage: "trash", tint: .red) {
                onRemove()
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false

    var countText: String
    var isSelected: Bool
    var canDropCategory: () -> Bool
    var onDropPapers: ([String]) -> Void
    var onDropCategory: (String) -> Void
    var onSelect: () -> Void

    var body: some View {
        LibraryRootFolderSelectionButton(
            countText: countText,
            isSelected: isSelected,
            isDropTargeted: isDropTargeted,
            reduceMotion: reduceMotion,
            action: onSelect
        )
        .frame(maxWidth: .infinity, minHeight: PaperCodexHitTarget.sidebarRowHeight, maxHeight: PaperCodexHitTarget.sidebarRowHeight)
        .id("library-root-folder-\(isSelected)-\(isDropTargeted)")
        .onDrop(
            of: LibraryLayout.categoryDropContentTypes,
            delegate: LibraryRootFolderDropDelegate(
                isTargeted: $isDropTargeted,
                canDropCategory: canDropCategory,
                onDrop: loadDroppedItems(from:)
            )
        )
        .help("Show all papers or drop a folder here to move it to the top level")
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

private struct LibraryRootFolderSelectionButton: View {
    var countText: String
    var isSelected: Bool
    var isDropTargeted: Bool
    var reduceMotion: Bool
    var action: () -> Void

    var body: some View {
        NativeLibraryRootFolderSelectionButton(
            countText: countText,
            isSelected: isSelected,
            isDropTargeted: isDropTargeted,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private struct NativeLibraryRootFolderSelectionButton: NSViewRepresentable {
    var countText: String
    var isSelected: Bool
    var isDropTargeted: Bool
    var reduceMotion: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NativeLibraryRootFolderSelectionButtonView {
        let view = NativeLibraryRootFolderSelectionButtonView()
        view.apply(
            countText: countText,
            isSelected: isSelected,
            isDropTargeted: isDropTargeted,
            reduceMotion: reduceMotion,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativeLibraryRootFolderSelectionButtonView, context: Context) {
        view.apply(
            countText: countText,
            isSelected: isSelected,
            isDropTargeted: isDropTargeted,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private final class NativeLibraryRootFolderSelectionButtonView: NSButton {
    private let selectionIndicator = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let trailingStack = NSStackView()
    private let countLabel = NSTextField(labelWithString: "")
    private let dropIconView = NSImageView()
    private let dropLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var pressHandler: () -> Void = {}
    private var isSelectedRow = false
    private var isDropTargetedRow = false
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
        NSSize(width: NSView.noIntrinsicMetric, height: PaperCodexHitTarget.sidebarRowHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(
        countText: String,
        isSelected: Bool,
        isDropTargeted: Bool,
        reduceMotion: Bool,
        action: @escaping () -> Void
    ) {
        pressHandler = action
        isSelectedRow = isSelected
        isDropTargetedRow = isDropTargeted
        self.reduceMotion = reduceMotion
        state = isSelected ? .on : .off
        title = ""
        titleLabel.stringValue = Self.localized("All Papers")
        countLabel.stringValue = countText
        dropLabel.stringValue = Self.localized("Top Level")
        iconView.image = NSImage(
            systemSymbolName: isSelected ? "tray.full.fill" : "tray.full",
            accessibilityDescription: Self.localized("All Papers")
        )
        setAccessibilityLabel(Self.localized("All Papers"))
        setAccessibilityValue(isSelected ? Self.localized("Selected") : Self.localized("Not selected"))
        toolTip = Self.localized("Show all papers or drop a folder here to move it to the top level")
        configureTrailingContent()
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
        pressHandler()
        isSelectedRow = true
        state = .on
        setPressed(false)
    }

    override func accessibilityValue() -> Any? {
        isSelectedRow ? Self.localized("Selected") : Self.localized("Not selected")
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
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
        layer?.cornerRadius = PaperCodexCornerRadius.control
        layer?.masksToBounds = false

        selectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        selectionIndicator.wantsLayer = true
        selectionIndicator.layer?.cornerRadius = PaperCodexHitTarget.sidebarSelectionIndicatorWidth / 2

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        trailingStack.orientation = .horizontal
        trailingStack.alignment = .centerY
        trailingStack.spacing = 4
        trailingStack.wantsLayer = true
        trailingStack.setContentHuggingPriority(.required, for: .horizontal)
        trailingStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right

        dropIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        dropIconView.image = NSImage(systemSymbolName: "arrow.up.to.line", accessibilityDescription: Self.localized("Top Level"))
        dropIconView.imageScaling = .scaleProportionallyDown

        dropLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        dropLabel.lineBreakMode = .byTruncatingTail
        dropLabel.maximumNumberOfLines = 1

        [selectionIndicator, iconView, titleLabel, trailingStack].forEach(addSubview(_:))
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: PaperCodexHitTarget.sidebarRowHeight),
            selectionIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PaperCodexHitTarget.sidebarSelectionIndicatorInset),
            selectionIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectionIndicator.widthAnchor.constraint(equalToConstant: PaperCodexHitTarget.sidebarSelectionIndicatorWidth),
            selectionIndicator.heightAnchor.constraint(equalToConstant: PaperCodexHitTarget.sidebarSelectionIndicatorHeight),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PaperCodexSpacing.sidebarRowLeading),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: PaperCodexHitTarget.sidebarIconWidth),
            iconView.heightAnchor.constraint(equalToConstant: PaperCodexHitTarget.sidebarIconWidth),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: PaperCodexHitTarget.sidebarIconTextSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -8),
            trailingStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PaperCodexSpacing.sidebarRowTrailing),
            trailingStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        configureTrailingContent()
        updateAppearance()
    }

    @objc private func performPress() {
        pressHandler()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func configureTrailingContent() {
        trailingStack.arrangedSubviews.forEach { view in
            trailingStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if isDropTargetedRow {
            trailingStack.edgeInsets = NSEdgeInsets(top: 4, left: 7, bottom: 4, right: 7)
            trailingStack.addArrangedSubview(dropIconView)
            trailingStack.addArrangedSubview(dropLabel)
        } else {
            trailingStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            trailingStack.addArrangedSubview(countLabel)
        }
    }

    private func updateAppearance() {
        let accent = NSColor.controlAccentColor
        let active = isSelectedRow || isDropTargetedRow
        iconView.contentTintColor = active ? accent : .secondaryLabelColor
        titleLabel.font = .systemFont(ofSize: 13, weight: isSelectedRow ? .semibold : .medium)
        titleLabel.textColor = .labelColor
        countLabel.textColor = .secondaryLabelColor
        dropIconView.contentTintColor = accent
        dropLabel.textColor = accent
        selectionIndicator.isHidden = !isSelectedRow
        selectionIndicator.layer?.backgroundColor = accent.withAlphaComponent(0.72).cgColor

        let background: NSColor
        let border: NSColor
        let borderWidth: CGFloat
        if isDropTargetedRow {
            background = accent.withAlphaComponent(isPressed ? 0.18 : 0.12)
            border = accent.withAlphaComponent(0.55)
            borderWidth = 1.5
        } else if isSelectedRow {
            background = accent.withAlphaComponent(isPressed ? 0.18 : 0.13)
            border = isPressed ? accent.withAlphaComponent(0.38) : accent.withAlphaComponent(0.22)
            borderWidth = 1
        } else if isPressed {
            background = accent.withAlphaComponent(0.10)
            border = accent.withAlphaComponent(0.38)
            borderWidth = 1
        } else if isHovering {
            background = .labelColor.withAlphaComponent(0.045)
            border = accent.withAlphaComponent(0.18)
            borderWidth = 1
        } else {
            background = .clear
            border = .clear
            borderWidth = 0
        }

        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = borderWidth
        layer?.borderColor = border.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = isPressed ? 0.12 : (isHovering ? 0.08 : 0)
        layer?.shadowRadius = isPressed ? 3 : (isHovering ? 6 : 0)
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? 1 : -2)

        trailingStack.layer?.cornerRadius = 10
        trailingStack.layer?.backgroundColor = isDropTargetedRow ? accent.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor

        let targetScale: CGFloat
        if reduceMotion {
            targetScale = 1
        } else if isDropTargetedRow {
            targetScale = 1.02
        } else if isPressed {
            targetScale = 0.985
        } else {
            targetScale = isHovering ? 1.01 : 1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
    }

    private static func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
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
    static let libraryContentMinimumWidth: CGFloat = 860
    static let libraryPrimaryPaneMinimumWidth: CGFloat = 330
    static let libraryInspectorMinimumWidth: CGFloat = 300
    static let libraryInspectorIdealWidth: CGFloat = 360
    static let libraryInspectorMaximumWidth: CGFloat = 460
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

private struct PaperCodexTagToggleButton: NSViewRepresentable {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NativePaperCodexTagToggleButtonView {
        let button = NativePaperCodexTagToggleButtonView()
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction(_:))
        button.apply(title: title, isSelected: isSelected)
        return button
    }

    func updateNSView(_ button: NativePaperCodexTagToggleButtonView, context: Context) {
        context.coordinator.action = action
        button.apply(title: title, isSelected: isSelected)
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

private final class NativePaperCodexTagToggleButtonView: NSButton {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingAreaToken: NSTrackingArea?
    private var isHovering = false
    private var isPressed = false
    private var selectedState = false

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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaToken {
            removeTrackingArea(trackingAreaToken)
        }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
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

    func apply(title: String, isSelected: Bool) {
        selectedState = isSelected
        titleLabel.stringValue = title
        toolTip = title
        setAccessibilityLabel(title)
        setAccessibilityValue(isSelected ? 1 : 0)
        updateAppearance()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        title = ""
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        addSubview(iconView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.cornerRadius = 7
        layer?.masksToBounds = false

        let accent = NSColor.controlAccentColor
        let secondary = NSColor.secondaryLabelColor
        let foreground: NSColor
        let background: NSColor
        let border: NSColor

        if selectedState {
            foreground = accent
            background = accent.withAlphaComponent(isPressed ? 0.20 : isHovering ? 0.14 : 0.10)
            border = accent.withAlphaComponent(isHovering || isPressed ? 0.48 : 0.30)
            iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        } else {
            foreground = isHovering || isPressed ? accent : secondary
            background = isPressed ? accent.withAlphaComponent(0.12) : NSColor.controlBackgroundColor
            border = isHovering ? accent.withAlphaComponent(0.28) : NSColor.separatorColor.withAlphaComponent(0.35)
            iconView.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        }

        iconView.contentTintColor = foreground
        titleLabel.textColor = selectedState ? NSColor.labelColor : NSColor.secondaryLabelColor
        layer?.backgroundColor = background.cgColor
        layer?.borderColor = border.cgColor
        layer?.borderWidth = 1
        alphaValue = isPressed ? 0.82 : 1
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

private struct NativeRecentConversationsSidebarContext: NSViewRepresentable {
    var conversationCount: Int
    var selectedTitle: String?
    var onOpenLibrary: () -> Void

    func makeNSView(context: Context) -> NativeRecentConversationsSidebarContextView {
        let view = NativeRecentConversationsSidebarContextView()
        view.apply(
            conversationCount: conversationCount,
            selectedTitle: selectedTitle,
            onOpenLibrary: onOpenLibrary
        )
        return view
    }

    func updateNSView(_ view: NativeRecentConversationsSidebarContextView, context: Context) {
        view.apply(
            conversationCount: conversationCount,
            selectedTitle: selectedTitle,
            onOpenLibrary: onOpenLibrary
        )
    }
}

private final class NativeRecentConversationsSidebarContextView: NSView {
    private let stackView = NSStackView()
    private let headerRow = NSStackView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Recent Context")
    private let countLabel = NSTextField(labelWithString: "")
    private let selectedHeaderLabel = NSTextField(labelWithString: "Selected")
    private let selectedTitleLabel = NSTextField(labelWithString: "")
    private let actionButton = NativeRecentConversationsSidebarActionButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func apply(
        conversationCount: Int,
        selectedTitle: String?,
        onOpenLibrary: @escaping () -> Void
    ) {
        countLabel.stringValue = "\(conversationCount) conversation\(conversationCount == 1 ? "" : "s")"
        selectedTitleLabel.stringValue = selectedTitle ?? "No conversation selected"
        actionButton.apply(title: "Show Library", onPress: onOpenLibrary)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.distribution = .fill
        stackView.spacing = 12

        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Recent Context")

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        countLabel.font = .systemFont(ofSize: 13, weight: .regular)
        countLabel.textColor = .secondaryLabelColor

        selectedHeaderLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        selectedHeaderLabel.textColor = .tertiaryLabelColor

        selectedTitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        selectedTitleLabel.textColor = .labelColor
        selectedTitleLabel.maximumNumberOfLines = 4
        selectedTitleLabel.lineBreakMode = .byWordWrapping
        selectedTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        headerRow.addArrangedSubview(iconView)
        headerRow.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(headerRow)
        stackView.addArrangedSubview(countLabel)
        stackView.addArrangedSubview(makeSeparator())
        stackView.addArrangedSubview(selectedHeaderLabel)
        stackView.addArrangedSubview(selectedTitleLabel)
        stackView.addArrangedSubview(actionButton)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }
}

private final class NativeRecentConversationsSidebarActionButton: NSButton {
    private var onPress: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(title: String, onPress: @escaping () -> Void) {
        self.title = title
        self.onPress = onPress
        image = NSImage(systemSymbolName: "books.vertical", accessibilityDescription: title)
        setAccessibilityLabel(title)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        target = self
        action = #selector(performPress(_:))
        bezelStyle = .rounded
        controlSize = .regular
        imagePosition = .imageLeading
        font = .systemFont(ofSize: 13, weight: .semibold)
        setButtonType(.momentaryPushIn)
        setAccessibilityRole(.button)
    }

    @objc private func performPress(_ sender: NSButton) {
        onPress()
    }
}

private struct NativeRecentConversationsContent: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var sessions: [PaperSession]
    var papersBySessionID: [String: [Paper]]
    @Binding var selectedSessionID: String?
    var onOpen: (PaperSession) -> Void

    func makeNSView(context: Context) -> NativeRecentConversationsContainerView {
        let view = NativeRecentConversationsContainerView()
        view.apply(
            sessions: sessions,
            papersBySessionID: papersBySessionID,
            selectedSessionID: selectedSessionID,
            reduceMotion: reduceMotion,
            onSelect: { selectedSessionID = $0 },
            onOpen: onOpen
        )
        return view
    }

    func updateNSView(_ view: NativeRecentConversationsContainerView, context: Context) {
        view.apply(
            sessions: sessions,
            papersBySessionID: papersBySessionID,
            selectedSessionID: selectedSessionID,
            reduceMotion: reduceMotion,
            onSelect: { selectedSessionID = $0 },
            onOpen: onOpen
        )
    }
}

private struct RecentConversationRowModel: Equatable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var timeText: String
    var usesStackIcon: Bool
    var isSelected: Bool
}

private final class NativeRecentConversationsContainerView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Recent Conversations")
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let emptyStateView = NativeLibraryEmptyStateView(title: "No Conversations", systemImage: "text.bubble")
    private var rowViewsByID: [String: NativeRecentConversationRowView] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func apply(
        sessions: [PaperSession],
        papersBySessionID: [String: [Paper]],
        selectedSessionID: String?,
        reduceMotion: Bool,
        onSelect: @escaping (String) -> Void,
        onOpen: @escaping (PaperSession) -> Void
    ) {
        let rows = sessions.map { session in
            RecentConversationRowModel(
                id: session.id,
                title: session.title,
                detail: Self.detailText(for: session, papers: papersBySessionID[session.id, default: []]),
                timeText: Self.relativeFormatter.localizedString(for: session.updatedAt, relativeTo: Date()),
                usesStackIcon: session.paperIDs.count > 1,
                isSelected: selectedSessionID == session.id
            )
        }
        emptyStateView.isHidden = !sessions.isEmpty
        scrollView.isHidden = sessions.isEmpty

        var reusableRows = rowViewsByID
        rowViewsByID.removeAll(keepingCapacity: true)
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, session) in sessions.enumerated() {
            let row = rows[index]
            let rowView = reusableRows.removeValue(forKey: row.id) ?? NativeRecentConversationRowView()
            rowView.apply(
                row: row,
                reduceMotion: reduceMotion,
                onSelect: { onSelect(session.id) },
                onOpen: { onOpen(session) }
            )
            stackView.addArrangedSubview(rowView)
            rowViewsByID[row.id] = rowView
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.distribution = .fill
        stackView.spacing = 8
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = stackView

        emptyStateView.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, scrollView, emptyStateView].forEach(addSubview(_:))
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 24),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            emptyStateView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            emptyStateView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            emptyStateView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            emptyStateView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24)
        ])
    }

    private static func detailText(for session: PaperSession, papers: [Paper]) -> String {
        guard session.paperIDs.count > 1 else {
            return papers.first?.title ?? "Single paper"
        }
        let firstTitle = papers.first?.title ?? "Multiple papers"
        return "\(session.paperIDs.count) papers - \(firstTitle)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private final class NativeRecentConversationRowView: NSView {
    private let selectionButton = NativeRecentConversationSelectionButtonView()
    private let openButton = NativeRecentConversationOpenButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 72)
    }

    func apply(
        row: RecentConversationRowModel,
        reduceMotion: Bool,
        onSelect: @escaping () -> Void,
        onOpen: @escaping () -> Void
    ) {
        selectionButton.apply(
            title: row.title,
            detail: row.detail,
            timeText: row.timeText,
            usesStackIcon: row.usesStackIcon,
            isSelected: row.isSelected,
            reduceMotion: reduceMotion,
            action: onSelect
        )
        openButton.apply(title: row.title, onPress: onOpen)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor

        selectionButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.translatesAutoresizingMaskIntoConstraints = false
        [selectionButton, openButton].forEach(addSubview(_:))
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
            selectionButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            selectionButton.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            selectionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            openButton.leadingAnchor.constraint(equalTo: selectionButton.trailingAnchor, constant: 10),
            openButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            openButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private final class NativeRecentConversationOpenButton: NSButton {
    private var onPress: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(title: String, onPress: @escaping () -> Void) {
        self.onPress = onPress
        image = NSImage(systemSymbolName: "arrow.forward.circle", accessibilityDescription: "Open Session")
        setAccessibilityLabel("Open Session")
        toolTip = "Open \(title)"
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        target = self
        action = #selector(performPress(_:))
        focusRingType = .none
        contentTintColor = .controlAccentColor
        setButtonType(.momentaryChange)
        setAccessibilityRole(.button)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    @objc private func performPress(_ sender: NSButton) {
        onPress()
    }
}

private final class NativeLibraryEmptyStateView: NSView {
    private let stackView = NSStackView()
    private let iconView = NSImageView()
    private let titleLabel: NSTextField

    init(title: String, systemImage: String) {
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        iconView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 10

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        iconView.contentTintColor = .tertiaryLabelColor
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleLabel)
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34)
        ])
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
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

private struct NativeRecentConversationDetailPanel: NSViewRepresentable {
    var session: PaperSession?
    var papers: [Paper]
    var onOpen: (PaperSession) -> Void

    func makeNSView(context: Context) -> NativeRecentConversationDetailView {
        let view = NativeRecentConversationDetailView()
        view.apply(session: session, papers: papers, onOpen: onOpen)
        return view
    }

    func updateNSView(_ view: NativeRecentConversationDetailView, context: Context) {
        view.apply(session: session, papers: papers, onOpen: onOpen)
    }
}

private final class NativeRecentConversationDetailView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Conversation Details")
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let emptyStateView = NativeLibraryEmptyStateView(title: "Select Conversation", systemImage: "text.bubble")
    private let openButton = NativeRecentConversationPrimaryActionButton()
    private var onOpen: (PaperSession) -> Void = { _ in }
    private var currentSession: PaperSession?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func apply(session: PaperSession?, papers: [Paper], onOpen: @escaping (PaperSession) -> Void) {
        currentSession = session
        self.onOpen = onOpen
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard let session else {
            scrollView.isHidden = true
            emptyStateView.isHidden = false
            return
        }
        emptyStateView.isHidden = true
        scrollView.isHidden = false

        stackView.addArrangedSubview(makeSessionSummary(session))
        openButton.apply(title: "Open Session") { [weak self] in
            guard let session = self?.currentSession else {
                return
            }
            self?.onOpen(session)
        }
        stackView.addArrangedSubview(openButton)
        stackView.addArrangedSubview(makeSeparator())
        stackView.addArrangedSubview(makePapersSection(papers))
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .labelColor

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.distribution = .fill
        stackView.spacing = 16
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 4)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = stackView

        emptyStateView.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, scrollView, emptyStateView].forEach(addSubview(_:))
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -22),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 22),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            emptyStateView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            emptyStateView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            emptyStateView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            emptyStateView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22)
        ])
    }

    private func makeSessionSummary(_ session: PaperSession) -> NSView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 7

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .top
        header.spacing = 8

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
        icon.image = NSImage(
            systemSymbolName: session.paperIDs.count > 1 ? "square.stack.3d.up.fill" : "doc.text",
            accessibilityDescription: session.title
        )
        let title = nativeLabel(session.title, font: .systemFont(ofSize: 15, weight: .semibold), color: .labelColor, lines: 3)
        header.addArrangedSubview(icon)
        header.addArrangedSubview(title)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(nativeLabel("\(session.paperIDs.count) paper\(session.paperIDs.count == 1 ? "" : "s")", font: .systemFont(ofSize: 13, weight: .regular), color: .secondaryLabelColor, lines: 1))
        stack.addArrangedSubview(nativeLabel(Self.relativeFormatter.localizedString(for: session.updatedAt, relativeTo: Date()), font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular), color: .tertiaryLabelColor, lines: 1))
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 17),
            icon.heightAnchor.constraint(equalToConstant: 17)
        ])
        return stack
    }

    private func makePapersSection(_ papers: [Paper]) -> NSView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.addArrangedSubview(makeSectionHeader(title: "Papers", systemImage: "doc.on.doc"))
        if papers.isEmpty {
            stack.addArrangedSubview(nativeLabel("No papers", font: .systemFont(ofSize: 13, weight: .regular), color: .secondaryLabelColor, lines: 1))
        } else {
            for paper in papers {
                stack.addArrangedSubview(NativeRecentConversationPaperRowView(paper: paper))
            }
        }
        return stack
    }

    private func makeSectionHeader(title: String, systemImage: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
        icon.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        row.addArrangedSubview(icon)
        row.addArrangedSubview(nativeLabel(title, font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor, lines: 1))
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16)
        ])
        return row
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func nativeLabel(_ text: String, font: NSFont, color: NSColor, lines: Int) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = lines
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private final class NativeRecentConversationPaperRowView: NSView {
    init(paper: Paper) {
        super.init(frame: .zero)
        setup(paper: paper)
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setup(paper: Paper) {
        translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: paper.title)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.addArrangedSubview(label(paper.title, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor, lines: 2))
        textStack.addArrangedSubview(label(paper.authors.isEmpty ? "Authors not set" : paper.authors.joined(separator: ", "), font: .systemFont(ofSize: 11.5, weight: .regular), color: .secondaryLabelColor, lines: 1))

        row.addArrangedSubview(icon)
        row.addArrangedSubview(textStack)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    private func label(_ text: String, font: NSFont, color: NSColor, lines: Int) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = lines
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}

private final class NativeRecentConversationPrimaryActionButton: NSButton {
    private var onPress: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(title: String, onPress: @escaping () -> Void) {
        self.title = title
        self.onPress = onPress
        image = NSImage(systemSymbolName: "arrow.forward.circle", accessibilityDescription: title)
        setAccessibilityLabel(title)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        target = self
        action = #selector(performPress(_:))
        bezelStyle = .rounded
        controlSize = .regular
        imagePosition = .imageLeading
        font = .systemFont(ofSize: 13, weight: .semibold)
        setButtonType(.momentaryPushIn)
        setAccessibilityRole(.button)
    }

    @objc private func performPress(_ sender: NSButton) {
        onPress()
    }
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
            PaperCodexToolbarButton(title: "Read", systemImage: "book", disabled: !canOpenConversation) {
                onRead()
            }
            PaperCodexToolbarButton(title: "Chat", systemImage: "text.bubble", disabled: !canOpenConversation) {
                onChat()
            }
            PaperCodexToolbarButton(title: "Copy", systemImage: "doc.on.doc", disabled: !canMove) {
                onCopy()
            }
            PaperCodexToolbarButton(title: "Tag", systemImage: "tag", disabled: !canTag) {
                onTag()
            }
            PaperCodexToolbarButton(title: "Delete", systemImage: "trash", tint: .red) {
                onDelete()
            }
            PaperCodexToolbarButton(title: "Clear", systemImage: "xmark.circle", tint: .secondary) {
                onClear()
            }
        }
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

    private var destinationItems: [PaperCodexNativePopupItem] {
        [PaperCodexNativePopupItem(title: "No folder", value: "")]
            + categoryItems.map { item in
                PaperCodexNativePopupItem(
                    title: String(repeating: "  ", count: item.depth) + item.category.name,
                    value: item.category.id
                )
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Copy Papers", systemImage: "doc.on.doc")
                .font(.title3.weight(.semibold))
            Text("\(selectedCount) selected papers")
                .foregroundStyle(.secondary)
            PaperCodexNativePopupButton(
                selection: $targetCategoryID,
                items: destinationItems,
                accessibilityLabel: "Destination"
            )
            .frame(height: 30)
            HStack {
                Spacer()
                PaperCodexPanelButton(title: "Cancel", systemImage: "xmark") {
                    onCancel()
                }
                PaperCodexPanelButton(
                    title: "Copy",
                    systemImage: "doc.on.doc",
                    kind: .primary,
                    disabled: targetCategoryID.isEmpty
                ) {
                    onCopy(targetCategoryID.isEmpty ? nil : targetCategoryID)
                }
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
                PaperCodexNativeEmptyState(title: "No Tags", systemImage: "tag")
                    .frame(width: 380, height: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(tags) { tag in
                        PaperCodexTagToggleButton(title: tag.name, isSelected: selectedTagIDs.contains(tag.id)) {
                            toggle(tag.id)
                        }
                        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
                    }
                }
                .frame(width: 420)
            }
            HStack {
                Spacer()
                PaperCodexPanelButton(title: "Cancel", systemImage: "xmark") {
                    onCancel()
                }
                PaperCodexPanelButton(
                    title: "Apply",
                    systemImage: "checkmark",
                    kind: .primary,
                    disabled: selectedTagIDs.isEmpty
                ) {
                    onApply(Array(selectedTagIDs))
                }
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
    @State private var inputFocusRequestID = UUID()
    @State private var shouldFocusInput = false

    init(categoryItems: [CategoryListItem], initialCategoryID: String?, onClose: @escaping () -> Void) {
        self.categoryItems = categoryItems
        self.onClose = onClose
        _targetCategoryID = State(initialValue: initialCategoryID ?? "")
    }

    private var parsedIDs: [String] {
        ArxivIDExtractor.extractVersionedIDs(from: inputText)
    }

    private var folderItems: [PaperCodexNativePopupItem] {
        [PaperCodexNativePopupItem(title: "No folder", value: "")]
            + categoryItems.map { item in
                PaperCodexNativePopupItem(
                    title: String(repeating: "  ", count: item.depth) + item.category.name,
                    value: item.category.id
                )
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Add arXiv Papers", systemImage: "number")
                    .font(.title3.weight(.semibold))
                Spacer()
                PaperCodexPanelButton(title: "Close", systemImage: "xmark") {
                    onClose()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                PaperCodexNativeTextEditor(
                    text: $inputText,
                    accessibilityLabel: "arXiv IDs",
                    font: .monospacedSystemFont(ofSize: 13, weight: .regular),
                    minHeight: 110,
                    focusRequestID: inputFocusRequestID,
                    isActiveForFocus: shouldFocusInput
                )
                .frame(minHeight: 110)
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

            PaperCodexNativePopupButton(
                selection: $targetCategoryID,
                items: folderItems,
                accessibilityLabel: "Folder"
            )
            .frame(height: 30)

            HStack {
                Spacer()
                PaperCodexPanelButton(title: "Cancel", systemImage: "xmark") {
                    onClose()
                }
                PaperCodexPanelButton(
                    title: "Add",
                    systemImage: "arrow.down.doc",
                    kind: .primary,
                    disabled: parsedIDs.isEmpty
                ) {
                    let ids = parsedIDs
                    model.enqueueArxivIDsForLibrary(
                        ids,
                        categoryID: targetCategoryID.isEmpty ? nil : targetCategoryID
                    )
                    onClose()
                }
            }
        }
        .padding(22)
        .frame(width: 540)
        .onAppear {
            shouldFocusInput = true
            inputFocusRequestID = UUID()
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

private struct LibraryTagSidebarRowModel: Equatable, Identifiable {
    var id: String
    var title: String
    var countText: String
    var isSelected: Bool
}

private struct LibraryTagSidebarList: NSViewRepresentable {
    var tagRows: [LibraryTagSidebarRowModel]
    var onSelect: (String) -> Void
    var onManage: (String) -> Void

    static func height(for rowCount: Int) -> CGFloat {
        CGFloat(rowCount) * PaperCodexHitTarget.sidebarRowHeight
    }

    func makeNSView(context: Context) -> NativeLibraryTagSidebarListView {
        let view = NativeLibraryTagSidebarListView()
        view.apply(rows: tagRows, onSelect: onSelect, onManage: onManage)
        return view
    }

    func updateNSView(_ view: NativeLibraryTagSidebarListView, context: Context) {
        view.apply(rows: tagRows, onSelect: onSelect, onManage: onManage)
    }
}

private final class NativeLibraryTagSidebarListView: NSView {
    private let stackView = NSStackView()
    private var rowViewsByID: [String: NativeLibraryTagSidebarRowView] = [:]
    private var rows: [LibraryTagSidebarRowModel] = []

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
        NSSize(width: NSView.noIntrinsicMetric, height: LibraryTagSidebarList.height(for: rows.count))
    }

    func apply(
        rows: [LibraryTagSidebarRowModel],
        onSelect: @escaping (String) -> Void,
        onManage: @escaping (String) -> Void
    ) {
        self.rows = rows
        var reusableRows = rowViewsByID
        rowViewsByID.removeAll(keepingCapacity: true)
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for row in rows {
            let rowView = reusableRows.removeValue(forKey: row.id) ?? NativeLibraryTagSidebarRowView()
            rowView.apply(
                row: row,
                onSelect: { onSelect(row.id) },
                onManage: { onManage(row.id) }
            )
            stackView.addArrangedSubview(rowView)
            rowViewsByID[row.id] = rowView
        }
        invalidateIntrinsicContentSize()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = 0
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }
}

private final class NativeLibraryTagSidebarRowView: NSView {
    private let selectionIndicator = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let trailingStack = NSStackView()
    private let countLabel = NSTextField(labelWithString: "")
    private let manageButton = NativeLibraryTagSidebarManageButton()
    private var trackingArea: NSTrackingArea?
    private var selectHandler: () -> Void = {}
    private var isSelectedRow = false
    private var isHovering = false
    private var isPressed = false

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
        NSSize(width: NSView.noIntrinsicMetric, height: PaperCodexHitTarget.sidebarRowHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(row: LibraryTagSidebarRowModel, onSelect: @escaping () -> Void, onManage: @escaping () -> Void) {
        selectHandler = onSelect
        isSelectedRow = row.isSelected
        iconView.image = NSImage(systemSymbolName: row.isSelected ? "tag.fill" : "tag", accessibilityDescription: row.title)
        titleLabel.stringValue = row.title
        countLabel.stringValue = row.countText
        manageButton.apply(title: row.title, onPress: onManage)
        setAccessibilityLabel(row.title)
        setAccessibilityValue(row.isSelected ? "Selected" : "Not selected")
        toolTip = row.title
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
        isPressed = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
        selectHandler()
        isSelectedRow = true
        isPressed = false
        updateAppearance()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = PaperCodexCornerRadius.control
        layer?.masksToBounds = false
        setAccessibilityElement(true)
        setAccessibilityRole(.button)

        selectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        selectionIndicator.wantsLayer = true
        selectionIndicator.layer?.cornerRadius = PaperCodexHitTarget.sidebarSelectionIndicatorWidth / 2

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.setContentHuggingPriority(.required, for: .horizontal)

        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        trailingStack.orientation = .horizontal
        trailingStack.alignment = .centerY
        trailingStack.distribution = .fill
        trailingStack.spacing = 4
        trailingStack.setContentHuggingPriority(.required, for: .horizontal)
        trailingStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        trailingStack.addArrangedSubview(countLabel)
        trailingStack.addArrangedSubview(manageButton)

        [selectionIndicator, iconView, titleLabel, trailingStack].forEach(addSubview(_:))
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: PaperCodexHitTarget.sidebarRowHeight),
            selectionIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PaperCodexHitTarget.sidebarSelectionIndicatorInset),
            selectionIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectionIndicator.widthAnchor.constraint(equalToConstant: PaperCodexHitTarget.sidebarSelectionIndicatorWidth),
            selectionIndicator.heightAnchor.constraint(equalToConstant: PaperCodexHitTarget.sidebarSelectionIndicatorHeight),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PaperCodexSpacing.sidebarRowLeading),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: PaperCodexHitTarget.sidebarIconWidth),
            iconView.heightAnchor.constraint(equalToConstant: PaperCodexHitTarget.sidebarIconWidth),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: PaperCodexHitTarget.sidebarIconTextSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -8),
            trailingStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            trailingStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }

    private func updateAppearance() {
        let accent = NSColor.controlAccentColor
        let showManageButton = isHovering || isSelectedRow
        selectionIndicator.isHidden = !isSelectedRow
        selectionIndicator.layer?.backgroundColor = accent.withAlphaComponent(0.72).cgColor
        iconView.contentTintColor = isSelectedRow ? accent : .secondaryLabelColor
        titleLabel.font = .systemFont(ofSize: 13, weight: isSelectedRow ? .semibold : .medium)
        titleLabel.textColor = .labelColor
        countLabel.textColor = .secondaryLabelColor
        manageButton.isHidden = !showManageButton

        let background: NSColor
        let border: NSColor
        if isSelectedRow {
            background = accent.withAlphaComponent(isPressed ? 0.18 : 0.13)
            border = isPressed ? accent.withAlphaComponent(0.38) : accent.withAlphaComponent(0.22)
        } else if isPressed {
            background = accent.withAlphaComponent(0.10)
            border = accent.withAlphaComponent(0.38)
        } else if isHovering {
            background = .textBackgroundColor
            border = accent.withAlphaComponent(0.18)
        } else {
            background = .clear
            border = .clear
        }
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = border == .clear ? 0 : 1
        layer?.borderColor = border.cgColor
    }
}

private final class NativeLibraryTagSidebarManageButton: NSButton {
    private var onPress: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        alphaValue = 0.72
        super.mouseDown(with: event)
        alphaValue = 1
    }

    func apply(title: String, onPress: @escaping () -> Void) {
        self.onPress = onPress
        image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Manage \(title)")
        setAccessibilityLabel("Manage \(title)")
        toolTip = "Manage \(title)"
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        target = self
        action = #selector(performPress(_:))
        focusRingType = .none
        setButtonType(.momentaryChange)
        setAccessibilityRole(.button)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @objc private func performPress(_ sender: NSButton) {
        onPress()
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

    private var parentItems: [PaperCodexNativePopupItem] {
        [PaperCodexNativePopupItem(title: "Top Level", value: "")]
            + categoryItems.map { item in
                PaperCodexNativePopupItem(
                    title: String(repeating: "  ", count: item.depth) + item.category.name,
                    value: item.category.id
                )
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Manage Category", systemImage: "folder")
                .font(.title3.weight(.semibold))
            PaperCodexNativeTextField(text: $name, placeholder: "Name")
                .frame(height: 30)
            PaperCodexNativePopupButton(
                selection: $parentID,
                items: parentItems,
                accessibilityLabel: "Parent"
            )
            .frame(height: 30)
            HStack {
                PaperCodexPanelButton(title: "Delete", systemImage: "trash", kind: .destructive) {
                    onDelete()
                }
                Spacer()
                PaperCodexPanelButton(title: "Cancel", systemImage: "xmark") {
                    onCancel()
                }
                PaperCodexPanelButton(
                    title: "Save",
                    systemImage: "checkmark",
                    kind: .primary,
                    disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    onSave(name, parentID.isEmpty ? nil : parentID)
                }
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
            PaperCodexNativeTextField(text: $name, placeholder: "Name")
                .frame(height: 30)
            HStack {
                PaperCodexPanelButton(title: "Delete", systemImage: "trash", kind: .destructive) {
                    onDelete()
                }
                Spacer()
                PaperCodexPanelButton(title: "Cancel", systemImage: "xmark") {
                    onCancel()
                }
                PaperCodexPanelButton(
                    title: "Save",
                    systemImage: "checkmark",
                    kind: .primary,
                    disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    onSave(name)
                }
            }
        }
        .padding(22)
        .frame(width: 340)
    }
}

private struct CategoryEditorSheet: View {
    var categoryItems: [CategoryListItem]
    @Binding var name: String
    @Binding var parentID: String
    var onCreate: (String, String) -> Void
    var onCancel: () -> Void
    @State private var nameFocusRequestID = UUID()
    @State private var shouldFocusName = false

    private var parentItems: [PaperCodexNativePopupItem] {
        [PaperCodexNativePopupItem(title: "Top Level", value: "")]
            + categoryItems.map { item in
                PaperCodexNativePopupItem(
                    title: String(repeating: "  ", count: item.depth) + item.category.name,
                    value: item.category.id
                )
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Category")
                .font(.title3.weight(.semibold))
            PaperCodexNativeTextField(
                text: $name,
                placeholder: "Name",
                focusRequestID: nameFocusRequestID,
                isActiveForFocus: shouldFocusName
            )
            .frame(height: 30)
            PaperCodexNativePopupButton(
                selection: $parentID,
                items: parentItems,
                accessibilityLabel: "Parent"
            )
            .frame(height: 30)
            HStack {
                Spacer()
                PaperCodexPanelButton(title: "Cancel", systemImage: "xmark") {
                    onCancel()
                }
                PaperCodexPanelButton(
                    title: "Create",
                    systemImage: "plus",
                    kind: .primary,
                    disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    onCreate(name, parentID)
                }
            }
        }
        .padding(22)
        .frame(width: 360)
        .onAppear {
            shouldFocusName = true
            nameFocusRequestID = UUID()
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
            PaperCodexNativeTextField(text: $name, placeholder: "Name")
                .frame(height: 30)
            HStack {
                Spacer()
                PaperCodexPanelButton(title: "Cancel", systemImage: "xmark") {
                    onCancel()
                }
                PaperCodexPanelButton(
                    title: "Create",
                    systemImage: "plus",
                    kind: .primary,
                    disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    onCreate(name)
                }
            }
        }
        .padding(22)
        .frame(width: 320)
    }
}
