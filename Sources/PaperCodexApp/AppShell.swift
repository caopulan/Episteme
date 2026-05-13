import SwiftUI

struct PrimaryNavigationSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            SidebarRowButton(
                title: "Recent Conversations",
                systemImage: "clock",
                selected: model.route == .library && model.selectedLibrarySurface == .recentConversations
            ) {
                model.showRecentConversations()
            }
        }
    }
}
