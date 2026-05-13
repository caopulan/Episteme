import SwiftUI

struct AppShell<RoutedContent: View>: View {
    @ViewBuilder var routedContent: () -> RoutedContent

    var body: some View {
        HStack(spacing: 0) {
            PrimarySidebar()
                .frame(width: AppShellLayout.primarySidebarWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipped()

            Divider()

            routedContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private enum AppShellLayout {
    static let primarySidebarWidth: CGFloat = 220
}

struct PrimarySidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Codex")
                .font(.paperCodexSystem(size: 24, weight: .semibold))
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 8) {
                SidebarRowButton(
                    title: "Recent Conversations",
                    systemImage: "clock",
                    selected: model.route == .library && model.selectedLibrarySurface == .recentConversations
                ) {
                    model.showRecentConversations()
                }

                SidebarRowButton(
                    title: "Library",
                    systemImage: model.route == .library && model.selectedLibrarySurface == .papers ? "books.vertical.fill" : "books.vertical",
                    selected: model.route == .library && model.selectedLibrarySurface == .papers
                ) {
                    model.goToLibrary()
                }

                SidebarRowButton(
                    title: "Discover",
                    systemImage: "sparkle.magnifyingglass",
                    selected: model.route == .discover
                ) {
                    model.showDiscover()
                }

                SidebarRowButton(
                    title: "Settings",
                    systemImage: "gearshape",
                    selected: model.route == .settings
                ) {
                    model.showSettings()
                }
            }

            Spacer(minLength: 0)
        }
        .paperCodexSidebarChromePadding()
    }
}
