import SwiftUI

private let persistentRouteOrder: [AppRoute] = [.library, .discover, .search, .settings, .reader]
private let initiallyMountedRoutes: Set<AppRoute> = []

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @State private var mountedRoutes: Set<AppRoute> = initiallyMountedRoutes
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
            model.postNotice(kind: .error, title: "Episteme", message: message, autoDismissAfter: nil)
            model.errorMessage = nil
        }
        .onAppear {
            mountRoute(navigation.route)
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
        .paperCodexNativeSheet(isPresented: $isShowingSaveToLibrarySheet, title: "Save to Library", minimumSize: CGSize(width: 620, height: 520)) {
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
            .transaction { transaction in
                transaction.animation = nil
            }
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
                PaperCodexNativeSpinner()
                    .frame(width: 16, height: 16)
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
            Text("Episteme")
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
