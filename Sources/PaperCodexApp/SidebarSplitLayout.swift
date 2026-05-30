import AppKit
import SwiftUI

private let sidebarMinimumWidth: CGFloat = 220
private let sidebarMaximumWidth: CGFloat = 420

struct SidebarSplitLayout<Sidebar: View, Content: View>: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @Environment(\.locale) private var locale

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
        AppKitSidebarSplitView(
            sidebarWidth: model.librarySidebarWidth,
            minContentWidth: minContentWidth,
            onSidebarWidthChange: model.setLibrarySidebarWidth
        ) {
            AnyView(
                sidebar()
                    .environmentObject(model)
                    .environmentObject(navigation)
                    .environment(\.locale, locale)
                    .paperCodexTypographyScale()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            )
        } content: {
            AnyView(
                content()
                    .environmentObject(model)
                    .environmentObject(navigation)
                    .environment(\.locale, locale)
                    .paperCodexTypographyScale()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            )
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct AppKitSidebarSplitView: NSViewRepresentable {
    var sidebarWidth: CGFloat
    var minContentWidth: CGFloat
    var onSidebarWidthChange: (CGFloat) -> Void
    var sidebar: () -> AnyView
    var content: () -> AnyView

    func makeNSView(context: Context) -> SidebarSplitContainerView {
        let view = SidebarSplitContainerView()
        view.update(
            sidebar: sidebar(),
            content: content(),
            sidebarWidth: sidebarWidth,
            minContentWidth: minContentWidth,
            onSidebarWidthChange: onSidebarWidthChange
        )
        return view
    }

    func updateNSView(_ view: SidebarSplitContainerView, context: Context) {
        view.update(
            sidebar: sidebar(),
            content: content(),
            sidebarWidth: sidebarWidth,
            minContentWidth: minContentWidth,
            onSidebarWidthChange: onSidebarWidthChange
        )
    }
}

private final class SidebarSplitContainerView: NSView, NSSplitViewDelegate {
    private let splitView = NSSplitView()
    private let sidebarHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let contentHost = NSHostingView(rootView: AnyView(EmptyView()))
    private var preferredSidebarWidth: CGFloat = 280
    private var minContentWidth: CGFloat = 720
    private var onSidebarWidthChange: (CGFloat) -> Void = { _ in }
    private var lastReportedSidebarWidth: CGFloat?
    private var isApplyingSidebarWidth = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSplitView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func layout() {
        super.layout()
        applySidebarWidthIfNeeded()
    }

    func update(
        sidebar: AnyView,
        content: AnyView,
        sidebarWidth: CGFloat,
        minContentWidth: CGFloat,
        onSidebarWidthChange: @escaping (CGFloat) -> Void
    ) {
        sidebarHost.rootView = sidebar
        contentHost.rootView = content
        preferredSidebarWidth = sidebarWidth
        self.minContentWidth = minContentWidth
        self.onSidebarWidthChange = onSidebarWidthChange
        applySidebarWidthIfNeeded()
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.autosaveName = nil

        sidebarHost.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        sidebarHost.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        contentHost.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentHost.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(splitView)
        splitView.addArrangedSubview(sidebarHost)
        splitView.addArrangedSubview(contentHost)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func applySidebarWidthIfNeeded() {
        guard splitView.arrangedSubviews.count == 2, splitView.bounds.width > 0 else {
            return
        }
        let targetWidth = clampedSidebarWidth(preferredSidebarWidth)
        guard abs(sidebarHost.frame.width - targetWidth) > 0.5 || contentHost.frame.width <= 0 else {
            return
        }

        isApplyingSidebarWidth = true
        splitView.setPosition(targetWidth, ofDividerAt: 0)
        isApplyingSidebarWidth = false
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        false
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        sidebarMinimumWidth
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        maxSidebarWidth()
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isApplyingSidebarWidth, splitView.bounds.width > 0 else {
            return
        }
        let width = clampedSidebarWidth(sidebarHost.frame.width)
        preferredSidebarWidth = width
        guard abs((lastReportedSidebarWidth ?? -1) - width) > 0.5 else {
            return
        }
        lastReportedSidebarWidth = width
        onSidebarWidthChange(width)
    }

    private func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, sidebarMinimumWidth), maxSidebarWidth())
    }

    private func maxSidebarWidth() -> CGFloat {
        guard splitView.bounds.width > 0 else {
            return sidebarMaximumWidth
        }
        let contentAwareMaximum = splitView.bounds.width - minContentWidth - splitView.dividerThickness
        return max(sidebarMinimumWidth, min(sidebarMaximumWidth, contentAwareMaximum))
    }
}
