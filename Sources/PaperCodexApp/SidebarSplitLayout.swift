import SwiftUI

struct SidebarSplitLayout<Sidebar: View, Content: View>: View {
    @EnvironmentObject private var model: AppModel
    @State private var dragStartWidth: CGFloat?
    @State private var liveSidebarWidth: CGFloat?

    var minContentWidth: CGFloat
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var content: () -> Content

    init(
        minContentWidth: CGFloat = 720,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.minContentWidth = minContentWidth
        self.sidebar = sidebar
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar()
                .frame(width: liveSidebarWidth ?? model.librarySidebarWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            SplitterHandle()
                .frame(maxHeight: .infinity)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if dragStartWidth == nil {
                                dragStartWidth = model.librarySidebarWidth
                            }
                            liveSidebarWidth = clampedSidebarWidth((dragStartWidth ?? model.librarySidebarWidth) + value.translation.width)
                        }
                        .onEnded { _ in
                            if let liveSidebarWidth {
                                model.setLibrarySidebarWidth(liveSidebarWidth)
                            }
                            dragStartWidth = nil
                            liveSidebarWidth = nil
                        }
                )
            content()
                .frame(minWidth: minContentWidth, maxWidth: .infinity, maxHeight: .infinity)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, 220), 420)
    }
}

struct SplitterHandle: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.55))
            .frame(width: 5)
            .overlay(
                Rectangle()
                    .fill(Color.accentColor.opacity(0.0))
                    .frame(width: 18)
            )
            .contentShape(Rectangle())
    }
}
