import SwiftUI

private let routeCacheWarmupDelayNanoseconds: UInt64 = 120_000_000
private let persistentRouteOrder: [AppRoute] = [.library, .discover, .search, .settings, .reader]

@main
struct PaperCodexApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.navigation)
                .frame(minWidth: 1100, minHeight: 720)
                .background(WindowChromeConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            PaperCodexCommands(model: model, navigation: model.navigation)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @State private var mountedRoutes: Set<AppRoute> = [.library]
    @State private var routeCacheWarmupTask: Task<Void, Never>?
    @State private var isShowingSaveToLibrarySheet = false

    var body: some View {
        VStack(spacing: 0) {
            PaperCodexWindowTabBar {
                isShowingSaveToLibrarySheet = true
            }
            .environmentObject(model)
            .environmentObject(navigation)
            .zIndex(2)

            persistentRoutedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.locale, Locale(identifier: model.globalLanguageMode.appLocaleIdentifier))
        .paperCodexTypographyScale()
        .overlay(alignment: .topTrailing) {
            InteractionNoticeStack(notices: model.notices) { noticeID in
                model.dismissNotice(id: noticeID)
            }
            .padding(.top, PaperCodexWindowChrome.tabBarHeight + 10)
        }
        .overlay(alignment: .bottom) {
            if let status = model.globalOperationStatus {
                GlobalOperationStatusView(status: status)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: model.errorMessage) { _, message in
            guard let message else {
                return
            }
            model.postNotice(kind: .error, title: "Paper Codex", message: message, autoDismissAfter: nil)
            model.errorMessage = nil
        }
        .onAppear {
            mountRoute(navigation.route)
            scheduleRouteCacheWarmup()
            model.refreshMCPActiveContextSnapshot()
        }
        .onChange(of: navigation.route) { _, newRoute in
            mountRoute(newRoute)
            model.refreshMCPActiveContextSnapshot()
        }
        .onChange(of: model.selectedPaper?.id) { _, _ in
            model.refreshMCPActiveContextSnapshot()
        }
        .onChange(of: model.selectedSession?.id) { _, _ in
            model.refreshMCPActiveContextSnapshot()
        }
        .onChange(of: model.currentSelection) { _, _ in
            model.refreshMCPActiveContextSnapshot()
        }
        .onDisappear {
            routeCacheWarmupTask?.cancel()
            routeCacheWarmupTask = nil
        }
        .sheet(isPresented: $isShowingSaveToLibrarySheet) {
            if let paper = model.selectedPaper {
                SaveToLibrarySheet(
                    paperTitle: paper.title,
                    detail: paper.authors.prefix(4).joined(separator: ", "),
                    libraryCategories: model.categories,
                    initialCategoryIDs: model.paperCategoryIDsByID[paper.id, default: []],
                    onSave: { selection in
                        isShowingSaveToLibrarySheet = false
                        model.saveCachedPaperToLibrary(
                            paper,
                            selectedCategoryIDs: selection.categoryIDs,
                            newCategoryNames: selection.newCategoryNames,
                            newCategories: selection.newCategories
                        )
                    },
                    onCancel: {
                        isShowingSaveToLibrarySheet = false
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var persistentRoutedContent: some View {
        ZStack {
            ForEach(persistentRouteOrder, id: \.self) { route in
                if mountedRoutes.contains(route) {
                    RouteVisibilityHost(route: route, activeRoute: navigation.route) {
                        routedContent(for: route)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if !mountedRoutes.contains(navigation.route) {
                RouteTransitionPlaceholder(route: navigation.route)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func routedContent(for route: AppRoute) -> some View {
        switch route {
        case .library:
            LibraryView()
        case .discover:
            DiscoverView()
        case .search:
            ArxivSearchView()
        case .settings:
            SettingsView()
        case .reader:
            ReaderView()
        }
    }

    private func scheduleRouteCacheWarmup() {
        routeCacheWarmupTask?.cancel()
        routeCacheWarmupTask = Task { @MainActor in
            await Task.yield()
            for route in persistentRouteOrder {
                guard !Task.isCancelled else {
                    return
                }
                if !mountedRoutes.contains(route) {
                    try? await Task.sleep(nanoseconds: routeCacheWarmupDelayNanoseconds)
                    guard !Task.isCancelled else {
                        return
                    }
                    mountRoute(route)
                }
            }
            routeCacheWarmupTask = nil
        }
    }

    private func mountRoute(_ route: AppRoute) {
        guard !mountedRoutes.contains(route) else {
            return
        }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            _ = mountedRoutes.insert(route)
        }
    }
}

private struct RouteVisibilityHost<Content: View>: View {
    var route: AppRoute
    var activeRoute: AppRoute
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .opacity(route == activeRoute ? 1 : 0)
            .allowsHitTesting(route == activeRoute)
            .accessibilityHidden(route != activeRoute)
            .zIndex(route == activeRoute ? 1 : 0)
            .animation(PaperCodexMotion.route, value: activeRoute)
    }
}

private struct RouteTransitionPlaceholder: View {
    var route: AppRoute

    var body: some View {
        SidebarSplitLayout(minContentWidth: minContentWidth) {
            sidebar
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.paperCodexSystem(size: 28, weight: .semibold))
                ProgressView()
                    .controlSize(.small)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Codex")
                .font(.paperCodexSystem(size: 24, weight: .semibold))

            PrimaryNavigationSection()

            Spacer()
        }
        .paperCodexSidebarChromePadding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var title: String {
        switch route {
        case .library:
            "文库"
        case .discover:
            "探索"
        case .search:
            "搜索"
        case .settings:
            "设置"
        case .reader:
            "阅读"
        }
    }

    private var minContentWidth: CGFloat {
        switch route {
        case .library:
            840
        case .discover, .search, .settings, .reader:
            760
        }
    }
}

struct PaperCodexCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: AppNavigation

    var body: some Commands {
        CommandMenu("Paper Codex") {
            Button("Library") {
                model.goToLibrary()
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("探索") {
                model.showDiscover()
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("搜索") {
                model.showSearch()
            }
            .keyboardShortcut("3", modifiers: [.command])

            Button("Reader") {
                if model.selectedPaper != nil {
                    model.route = .reader
                }
            }
            .keyboardShortcut("4", modifiers: [.command])
            .disabled(model.selectedPaper == nil)

            Divider()

            Button("New Session") {
                model.newSessionButtonTapped()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(model.selectedPaper == nil || navigation.route != .reader)

            Button("Stop Codex") {
                model.cancelActiveCodexRun()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(!model.isSessionSending(model.selectedSession?.id))

            Divider()

            Button("Focus Search") {
                model.requestSearchFocus()
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Focus Chat Composer") {
                model.requestChatComposerFocus()
            }
            .keyboardShortcut("l", modifiers: [.command])
            .disabled(!canUseReaderChatCommand)

            Button("Show Reader Chat") {
                model.showReaderSessionPanel(.chat)
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            .disabled(!canUseReaderPanelCommand)

            Button("Show Reader Terminal") {
                model.showReaderSessionPanel(.terminal)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            .disabled(!canUseReaderPanelCommand)

            Button("Show Reader Notes") {
                model.showReaderSessionPanel(.notes)
            }
            .keyboardShortcut("3", modifiers: [.command, .option])
            .disabled(!canUseReaderPanelCommand)

            Button("Select Previous Reader Tab") {
                model.selectPreviousReaderTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(!canUseReaderTabSwitchCommand)

            Button("Select Next Reader Tab") {
                model.selectNextReaderTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(!canUseReaderTabSwitchCommand)

            Button("Read Selected Paper") {
                model.openSelectedLibraryPaperForReading()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!canUseSelectedLibraryPaperCommand)

            Button("Chat With Selected Paper") {
                model.openSelectedLibraryPaperForChat()
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(!canUseSelectedLibraryPaperCommand)

            Divider()

            Button("Previous PDF Page") {
                model.sendPDFKitCommand(.previousPage)
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])
            .disabled(!canUseReaderPDFCommand)

            Button("Next PDF Page") {
                model.sendPDFKitCommand(.nextPage)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command])
            .disabled(!canUseReaderPDFCommand)

            Button("Zoom PDF In") {
                model.sendPDFKitCommand(.zoomIn)
            }
            .keyboardShortcut("=", modifiers: [.command])
            .disabled(!canUseReaderPDFCommand)

            Button("Zoom PDF Out") {
                model.sendPDFKitCommand(.zoomOut)
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(!canUseReaderPDFCommand)

            Button("Fit PDF Width") {
                model.sendPDFKitCommand(.fitWidth)
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(!canUseReaderPDFCommand)

            Divider()

            Button("Settings") {
                model.showSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }

    private var canUseSelectedLibraryPaperCommand: Bool {
        navigation.route == .library
            && model.selectedLibrarySurface == .papers
            && model.canOpenSelectedLibraryPaper
    }

    private var canUseReaderPDFCommand: Bool {
        navigation.route == .reader && model.selectedPaper != nil
    }

    private var canUseReaderChatCommand: Bool {
        navigation.route == .reader && model.selectedPaper != nil
    }

    private var canUseReaderPanelCommand: Bool {
        navigation.route == .reader && model.selectedPaper != nil
    }

    private var canUseReaderTabSwitchCommand: Bool {
        navigation.route == .reader
            && model.selectedPaper != nil
            && model.readerTabState.tabs.count > 1
    }
}
