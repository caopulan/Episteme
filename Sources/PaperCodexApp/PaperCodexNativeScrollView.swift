import AppKit
import SwiftUI

struct PaperCodexNativeScrollRequest: Equatable {
    enum Target: Equatable {
        case top
        case bottom
        case verticalOffset(CGFloat)
        case verticalFraction(CGFloat)
    }

    var token: Int
    var target: Target
    var animated: Bool
}

struct PaperCodexNativeVisibleRange: Equatable {
    var minY: CGFloat
    var maxY: CGFloat
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
}

struct PaperCodexNativeScrollView<Content: View>: NSViewRepresentable {
    var axes: Axis.Set = .vertical
    var showsIndicators = true
    var drawsBackground = false
    var scrollRequest: PaperCodexNativeScrollRequest?
    var onVisibleRangeChange: ((PaperCodexNativeVisibleRange) -> Void)?
    var content: () -> Content

    init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        drawsBackground: Bool = false,
        scrollRequest: PaperCodexNativeScrollRequest? = nil,
        onVisibleRangeChange: ((PaperCodexNativeVisibleRange) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.drawsBackground = drawsBackground
        self.scrollRequest = scrollRequest
        self.onVisibleRangeChange = onVisibleRangeChange
        self.content = content
    }

    func makeNSView(context: Context) -> NativePaperCodexHostingScrollView {
        NativePaperCodexHostingScrollView()
    }

    func updateNSView(_ scrollView: NativePaperCodexHostingScrollView, context: Context) {
        scrollView.apply(
            axes: axes,
            showsIndicators: showsIndicators,
            drawsBackground: drawsBackground,
            scrollRequest: scrollRequest,
            onVisibleRangeChange: onVisibleRangeChange,
            rootView: AnyView(content())
        )
    }
}

final class NativePaperCodexHostingScrollView: NSScrollView {
    private let documentContainer = NativePaperCodexFlippedDocumentView()
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var axes: Axis.Set = .vertical
    private var hasLaidOutInitialDocument = false
    private var scrollRequest: PaperCodexNativeScrollRequest?
    private var lastHandledScrollRequestToken: Int?
    private var onVisibleRangeChange: ((PaperCodexNativeVisibleRange) -> Void)?
    private var lastVisibleRange: PaperCodexNativeVisibleRange?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layoutHostedContent()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        notifyVisibleRangeChange()
    }

    func apply(
        axes: Axis.Set,
        showsIndicators: Bool,
        drawsBackground: Bool,
        scrollRequest: PaperCodexNativeScrollRequest?,
        onVisibleRangeChange: ((PaperCodexNativeVisibleRange) -> Void)?,
        rootView: AnyView
    ) {
        self.axes = axes
        self.scrollRequest = scrollRequest
        self.onVisibleRangeChange = onVisibleRangeChange
        hasVerticalScroller = showsIndicators && axes.contains(.vertical)
        hasHorizontalScroller = showsIndicators && axes.contains(.horizontal)
        self.drawsBackground = drawsBackground
        backgroundColor = drawsBackground ? .textBackgroundColor : .clear
        hostingView.rootView = rootView
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func setup() {
        borderType = .noBorder
        drawsBackground = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        hasVerticalScroller = true
        hasHorizontalScroller = false
        documentView = documentContainer
        documentContainer.addSubview(hostingView)
    }

    private func layoutHostedContent() {
        let clipSize = contentView.bounds.size
        guard clipSize.width > 0, clipSize.height > 0 else {
            return
        }

        let fittingBeforeWidth = hostingView.fittingSize
        let targetWidth = axes.contains(.horizontal)
            ? max(clipSize.width, fittingBeforeWidth.width)
            : clipSize.width
        let targetHeight = axes.contains(.vertical)
            ? max(clipSize.height, fittingHeight(forWidth: targetWidth))
            : max(clipSize.height, fittingBeforeWidth.height)

        let documentSize = NSSize(width: max(1, targetWidth), height: max(1, targetHeight))
        documentContainer.setFrameSize(documentSize)
        hostingView.frame = NSRect(origin: .zero, size: documentSize)
        if !hasLaidOutInitialDocument {
            scroll(to: .zero, animated: false)
            hasLaidOutInitialDocument = true
        }
        clampCurrentScrollPosition()
        handlePendingScrollRequest()
        notifyVisibleRangeChange()
    }

    private func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        let currentHeight = max(1, hostingView.frame.height)
        hostingView.setFrameSize(NSSize(width: max(1, width), height: currentHeight))
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }

    private func handlePendingScrollRequest() {
        guard let scrollRequest,
              lastHandledScrollRequestToken != scrollRequest.token else {
            return
        }
        lastHandledScrollRequestToken = scrollRequest.token

        let clipHeight = contentView.bounds.height
        let documentHeight = documentContainer.bounds.height
        let maxY = max(0, documentHeight - clipHeight)
        let targetY: CGFloat
        switch scrollRequest.target {
        case .top:
            targetY = 0
        case .bottom:
            targetY = maxY
        case .verticalOffset(let offset):
            targetY = offset
        case .verticalFraction(let fraction):
            targetY = maxY * min(max(0, fraction), 1)
        }
        scroll(to: NSPoint(x: contentView.bounds.origin.x, y: targetY), animated: scrollRequest.animated)
    }

    private func clampCurrentScrollPosition() {
        let currentOrigin = contentView.bounds.origin
        let clampedOrigin = boundedVisibleOrigin(currentOrigin)
        if currentOrigin != clampedOrigin {
            scroll(to: clampedOrigin, animated: false)
        }
    }

    private func scroll(to origin: NSPoint, animated: Bool) {
        let boundedOrigin = boundedVisibleOrigin(origin)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                contentView.animator().setBoundsOrigin(boundedOrigin)
            }
        } else {
            contentView.setBoundsOrigin(boundedOrigin)
        }
        reflectScrolledClipView(contentView)
    }

    private func boundedVisibleOrigin(_ origin: NSPoint) -> NSPoint {
        let clipSize = contentView.bounds.size
        let documentSize = documentContainer.bounds.size
        let maxX = axes.contains(.horizontal) ? max(0, documentSize.width - clipSize.width) : 0
        let maxY = axes.contains(.vertical) ? max(0, documentSize.height - clipSize.height) : 0
        return NSPoint(
            x: min(max(0, origin.x), maxX),
            y: min(max(0, origin.y), maxY)
        )
    }

    private func notifyVisibleRangeChange() {
        guard let onVisibleRangeChange else {
            return
        }
        let visibleRect = documentVisibleRect
        let range = PaperCodexNativeVisibleRange(
            minY: visibleRect.minY,
            maxY: visibleRect.maxY,
            contentHeight: documentContainer.bounds.height,
            viewportHeight: visibleRect.height
        )
        guard range != lastVisibleRange else {
            return
        }
        lastVisibleRange = range
        DispatchQueue.main.async {
            onVisibleRangeChange(range)
        }
    }
}

private final class NativePaperCodexFlippedDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}
