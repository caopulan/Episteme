import SwiftUI

private let routePresentationDelayNanoseconds: UInt64 = 16_000_000

@main
struct PaperCodexApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 720)
                .background(WindowChromeConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            PaperCodexCommands(model: model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var renderedRoute: AppRoute = .library
    @State private var routePresentationTask: Task<Void, Never>?

    var body: some View {
        routedContent
        .environment(\.locale, Locale(identifier: model.globalLanguageMode.appLocaleIdentifier))
        .paperCodexTypographyScale()
        .overlay(alignment: .topTrailing) {
            InteractionNoticeStack(notices: model.notices) { noticeID in
                model.dismissNotice(id: noticeID)
            }
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
            renderedRoute = model.route
        }
        .onChange(of: model.route) { _, newRoute in
            scheduleRenderedRouteUpdate(to: newRoute)
        }
        .onDisappear {
            routePresentationTask?.cancel()
            routePresentationTask = nil
        }
    }

    @ViewBuilder
    private var routedContent: some View {
        if model.route == renderedRoute {
            routedContent(for: renderedRoute)
        } else {
            RouteTransitionPlaceholder(route: model.route)
        }
    }

    @ViewBuilder
    private func routedContent(for route: AppRoute) -> some View {
        switch route {
        case .library:
            LibraryView()
        case .discover:
            DiscoverView()
        case .settings:
            SettingsView()
        case .reader:
            ReaderView()
        }
    }

    private func scheduleRenderedRouteUpdate(to route: AppRoute) {
        routePresentationTask?.cancel()
        routePresentationTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: routePresentationDelayNanoseconds)
            guard !Task.isCancelled, model.route == route else {
                return
            }
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                renderedRoute = route
            }
            routePresentationTask = nil
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
            "发现"
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
        case .discover, .settings, .reader:
            760
        }
    }
}

struct PaperCodexCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandMenu("Paper Codex") {
            Button("Library") {
                model.goToLibrary()
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Discover") {
                model.showDiscover()
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Reader") {
                if model.selectedPaper != nil {
                    model.route = .reader
                }
            }
            .keyboardShortcut("3", modifiers: [.command])
            .disabled(model.selectedPaper == nil)

            Divider()

            Button("New Session") {
                model.newSessionButtonTapped()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(model.selectedPaper == nil || model.route != .reader)

            Button("Stop Codex") {
                model.cancelActiveCodexRun()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(!model.isSessionSending(model.selectedSession?.id))

            Divider()

            Button("Settings") {
                model.showSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
