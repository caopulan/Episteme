import AppKit
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
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(isHovering ? 0.80 : 0.55))
                .frame(width: 5)
            Capsule()
                .fill(isHovering ? Color.accentColor.opacity(0.72) : Color.clear)
                .frame(width: 3, height: 52)
                .shadow(color: isHovering ? Color.accentColor.opacity(0.32) : .clear, radius: 6)
        }
        .frame(width: 10)
        .overlay(
            Rectangle()
                .fill(Color.clear)
                .frame(width: 22)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onDisappear {
            if isHovering {
                NSCursor.arrow.set()
            }
        }
        .help("Resize sidebar")
    }
}
