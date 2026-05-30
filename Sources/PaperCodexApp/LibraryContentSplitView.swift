import AppKit
import SwiftUI

struct LibraryContentSplitView<Primary: View, Secondary: View>: NSViewRepresentable {
    var primaryMinimumWidth: CGFloat
    var secondaryMinimumWidth: CGFloat
    var secondaryIdealWidth: CGFloat
    var secondaryMaximumWidth: CGFloat
    private var primary: Primary
    private var secondary: Secondary

    init(
        primaryMinimumWidth: CGFloat,
        secondaryMinimumWidth: CGFloat,
        secondaryIdealWidth: CGFloat,
        secondaryMaximumWidth: CGFloat,
        @ViewBuilder _ primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.primaryMinimumWidth = primaryMinimumWidth
        self.secondaryMinimumWidth = secondaryMinimumWidth
        self.secondaryIdealWidth = secondaryIdealWidth
        self.secondaryMaximumWidth = secondaryMaximumWidth
        self.primary = primary()
        self.secondary = secondary()
    }

    func makeNSView(context: Context) -> LibraryContentSplitContainerView {
        let view = LibraryContentSplitContainerView()
        view.apply(
            primary: AnyView(primary),
            secondary: AnyView(secondary),
            primaryMinimumWidth: primaryMinimumWidth,
            secondaryMinimumWidth: secondaryMinimumWidth,
            secondaryIdealWidth: secondaryIdealWidth,
            secondaryMaximumWidth: secondaryMaximumWidth
        )
        return view
    }

    func updateNSView(_ view: LibraryContentSplitContainerView, context: Context) {
        view.apply(
            primary: AnyView(primary),
            secondary: AnyView(secondary),
            primaryMinimumWidth: primaryMinimumWidth,
            secondaryMinimumWidth: secondaryMinimumWidth,
            secondaryIdealWidth: secondaryIdealWidth,
            secondaryMaximumWidth: secondaryMaximumWidth
        )
    }
}

final class LibraryContentSplitContainerView: NSView, NSSplitViewDelegate {
    private let splitView = NSSplitView()
    private let primaryHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let secondaryHost = NSHostingView(rootView: AnyView(EmptyView()))
    private var primaryMinimumWidth: CGFloat = 330
    private var secondaryMinimumWidth: CGFloat = 220
    private var secondaryIdealWidth: CGFloat = 300
    private var secondaryMaximumWidth: CGFloat = 380
    private var didApplyInitialDivider = false

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

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func layout() {
        super.layout()
        applyDividerIfNeeded()
    }

    func apply(
        primary: AnyView,
        secondary: AnyView,
        primaryMinimumWidth: CGFloat,
        secondaryMinimumWidth: CGFloat,
        secondaryIdealWidth: CGFloat,
        secondaryMaximumWidth: CGFloat
    ) {
        primaryHost.rootView = primary
        secondaryHost.rootView = secondary
        self.primaryMinimumWidth = primaryMinimumWidth
        self.secondaryMinimumWidth = secondaryMinimumWidth
        self.secondaryIdealWidth = secondaryIdealWidth
        self.secondaryMaximumWidth = max(secondaryMaximumWidth, secondaryMinimumWidth)
        applyDividerIfNeeded()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.setAccessibilityLabel("Library Content Split")

        primaryHost.setContentHuggingPriority(.defaultLow, for: .horizontal)
        primaryHost.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        secondaryHost.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        secondaryHost.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        splitView.addArrangedSubview(primaryHost)
        splitView.addArrangedSubview(secondaryHost)
        addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func applyDividerIfNeeded() {
        guard splitView.bounds.width > 0, splitView.arrangedSubviews.count == 2 else {
            return
        }
        let minimumPosition = minimumDividerPosition()
        let maximumPosition = maximumDividerPosition()
        guard maximumPosition >= minimumPosition else {
            return
        }

        if didApplyInitialDivider {
            let currentPosition = primaryHost.frame.width
            if currentPosition < minimumPosition || currentPosition > maximumPosition {
                splitView.setPosition(min(max(currentPosition, minimumPosition), maximumPosition), ofDividerAt: 0)
            }
            return
        }

        didApplyInitialDivider = true
        let preferredPosition = splitView.bounds.width - secondaryIdealWidth - splitView.dividerThickness
        let dividerPosition = min(max(preferredPosition, minimumPosition), maximumPosition)
        splitView.setPosition(dividerPosition, ofDividerAt: 0)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        false
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        minimumDividerPosition()
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        maximumDividerPosition()
    }

    private func minimumDividerPosition() -> CGFloat {
        guard splitView.bounds.width > 0 else {
            return primaryMinimumWidth
        }
        return max(primaryMinimumWidth, splitView.bounds.width - secondaryMaximumWidth - splitView.dividerThickness)
    }

    private func maximumDividerPosition() -> CGFloat {
        guard splitView.bounds.width > 0 else {
            return primaryMinimumWidth
        }
        return max(primaryMinimumWidth, splitView.bounds.width - secondaryMinimumWidth - splitView.dividerThickness)
    }
}
