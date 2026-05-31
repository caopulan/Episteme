import AppKit
import SwiftUI

struct ReaderSplitView<Primary: View, Secondary: View>: NSViewRepresentable {
    private var primary: Primary
    private var secondary: Secondary
    private var primaryContentID: AnyHashable?
    private var secondaryContentID: AnyHashable?

    init(
        primaryContentID: AnyHashable? = nil,
        secondaryContentID: AnyHashable? = nil,
        @ViewBuilder _ primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.primaryContentID = primaryContentID
        self.secondaryContentID = secondaryContentID
        self.primary = primary()
        self.secondary = secondary()
    }

    func makeNSView(context: Context) -> ReaderSplitContainerView {
        let splitView = ReaderSplitContainerView()
        splitView.apply(
            primary: AnyView(primary),
            primaryContentID: primaryContentID,
            secondary: AnyView(secondary),
            secondaryContentID: secondaryContentID
        )
        return splitView
    }

    func updateNSView(_ splitView: ReaderSplitContainerView, context: Context) {
        splitView.apply(
            primary: AnyView(primary),
            primaryContentID: primaryContentID,
            secondary: AnyView(secondary),
            secondaryContentID: secondaryContentID
        )
    }
}

struct ReaderPDFSplitView<Primary: View, Secondary: View>: NSViewRepresentable {
    private var primary: Primary
    private var secondary: Secondary
    private var primaryContentID: AnyHashable?
    private var secondaryContentID: AnyHashable?

    init(
        primaryContentID: AnyHashable? = nil,
        secondaryContentID: AnyHashable? = nil,
        @ViewBuilder _ primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.primaryContentID = primaryContentID
        self.secondaryContentID = secondaryContentID
        self.primary = primary()
        self.secondary = secondary()
    }

    func makeNSView(context: Context) -> ReaderPDFSplitContainerView {
        let splitView = ReaderPDFSplitContainerView()
        splitView.apply(
            primary: AnyView(primary),
            primaryContentID: primaryContentID,
            secondary: AnyView(secondary),
            secondaryContentID: secondaryContentID
        )
        return splitView
    }

    func updateNSView(_ splitView: ReaderPDFSplitContainerView, context: Context) {
        splitView.apply(
            primary: AnyView(primary),
            primaryContentID: primaryContentID,
            secondary: AnyView(secondary),
            secondaryContentID: secondaryContentID
        )
    }
}

final class ReaderSplitContainerView: NSView, NSSplitViewDelegate {
    private let splitView = NSSplitView()
    private let primaryHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let secondaryHost = NSHostingView(rootView: AnyView(EmptyView()))
    private var didSetInitialDivider = false
    private var lastPrimaryContentID: AnyHashable?
    private var lastSecondaryContentID: AnyHashable?

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

    override func layout() {
        super.layout()
        guard !didSetInitialDivider, bounds.width > 0 else {
            return
        }
        let maximumPosition = bounds.width - ReaderSplitMetrics.minimumChatPaneWidth
        guard maximumPosition >= ReaderSplitMetrics.minimumReaderPaneWidth else {
            return
        }
        didSetInitialDivider = true
        let preferredPosition = bounds.width * 0.58
        let dividerPosition = min(
            max(ReaderSplitMetrics.minimumReaderPaneWidth, preferredPosition),
            maximumPosition
        )
        splitView.setPosition(dividerPosition, ofDividerAt: 0)
    }

    func apply(
        primary: AnyView,
        primaryContentID: AnyHashable?,
        secondary: AnyView,
        secondaryContentID: AnyHashable?
    ) {
        if ReaderSplitHostUpdate.shouldReplaceHostedContent(currentID: lastPrimaryContentID, nextID: primaryContentID) {
            primaryHost.rootView = primary
            lastPrimaryContentID = primaryContentID
        }
        if ReaderSplitHostUpdate.shouldReplaceHostedContent(currentID: lastSecondaryContentID, nextID: secondaryContentID) {
            secondaryHost.rootView = secondary
            lastSecondaryContentID = secondaryContentID
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.setAccessibilityLabel("Reader and Chat Split")

        [primaryHost, secondaryHost].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            splitView.addArrangedSubview($0)
        }
        addSubview(splitView)

        let minimumReaderWidth = primaryHost.widthAnchor.constraint(greaterThanOrEqualToConstant: ReaderSplitMetrics.minimumReaderPaneWidth)
        minimumReaderWidth.priority = .defaultHigh
        let minimumChatWidth = secondaryHost.widthAnchor.constraint(greaterThanOrEqualToConstant: ReaderSplitMetrics.minimumChatPaneWidth)
        minimumChatWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),
            minimumReaderWidth,
            minimumChatWidth
        ])
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        ReaderSplitMetrics.minimumReaderPaneWidth
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        max(ReaderSplitMetrics.minimumReaderPaneWidth, bounds.width - ReaderSplitMetrics.minimumChatPaneWidth)
    }
}

final class ReaderPDFSplitContainerView: NSView, NSSplitViewDelegate {
    private let splitView = NSSplitView()
    private let primaryHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let secondaryHost = NSHostingView(rootView: AnyView(EmptyView()))
    private var didSetInitialDivider = false
    private var lastPrimaryContentID: AnyHashable?
    private var lastSecondaryContentID: AnyHashable?

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

    override func layout() {
        super.layout()
        guard !didSetInitialDivider, bounds.height > 0 else {
            return
        }
        let maximumPosition = bounds.height - ReaderSplitMetrics.minimumPDFSplitPaneHeight
        guard maximumPosition >= ReaderSplitMetrics.minimumPDFSplitPaneHeight else {
            return
        }
        didSetInitialDivider = true
        let preferredPosition = bounds.height * 0.56
        let dividerPosition = min(
            max(ReaderSplitMetrics.minimumPDFSplitPaneHeight, preferredPosition),
            maximumPosition
        )
        splitView.setPosition(dividerPosition, ofDividerAt: 0)
    }

    func apply(
        primary: AnyView,
        primaryContentID: AnyHashable?,
        secondary: AnyView,
        secondaryContentID: AnyHashable?
    ) {
        if ReaderSplitHostUpdate.shouldReplaceHostedContent(currentID: lastPrimaryContentID, nextID: primaryContentID) {
            primaryHost.rootView = primary
            lastPrimaryContentID = primaryContentID
        }
        if ReaderSplitHostUpdate.shouldReplaceHostedContent(currentID: lastSecondaryContentID, nextID: secondaryContentID) {
            secondaryHost.rootView = secondary
            lastSecondaryContentID = secondaryContentID
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.setAccessibilityLabel("PDF Link Preview Split")

        [primaryHost, secondaryHost].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            splitView.addArrangedSubview($0)
        }
        addSubview(splitView)

        let minimumPrimaryHeight = primaryHost.heightAnchor.constraint(greaterThanOrEqualToConstant: ReaderSplitMetrics.minimumPDFSplitPaneHeight)
        minimumPrimaryHeight.priority = .defaultHigh
        let minimumSecondaryHeight = secondaryHost.heightAnchor.constraint(greaterThanOrEqualToConstant: ReaderSplitMetrics.minimumPDFSplitPaneHeight)
        minimumSecondaryHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),
            minimumPrimaryHeight,
            minimumSecondaryHeight
        ])
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        ReaderSplitMetrics.minimumPDFSplitPaneHeight
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        max(ReaderSplitMetrics.minimumPDFSplitPaneHeight, bounds.height - ReaderSplitMetrics.minimumPDFSplitPaneHeight)
    }
}

private enum ReaderSplitMetrics {
    static let minimumReaderPaneWidth: CGFloat = 360
    static let minimumChatPaneWidth: CGFloat = 330
    static let minimumPDFSplitPaneHeight: CGFloat = 220
}

private enum ReaderSplitHostUpdate {
    static func shouldReplaceHostedContent(currentID: AnyHashable?, nextID: AnyHashable?) -> Bool {
        guard let nextID else {
            return true
        }
        return currentID != nextID
    }
}
