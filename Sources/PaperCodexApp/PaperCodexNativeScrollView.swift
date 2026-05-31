import AppKit
import SwiftUI

struct PaperCodexNativeScrollView<Content: View>: NSViewRepresentable {
    var axes: Axis.Set = .vertical
    var showsIndicators = true
    var drawsBackground = false
    var content: () -> Content

    init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        drawsBackground: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.drawsBackground = drawsBackground
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
            rootView: AnyView(content())
        )
    }
}

final class NativePaperCodexHostingScrollView: NSScrollView {
    private let documentContainer = NativePaperCodexFlippedDocumentView()
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var axes: Axis.Set = .vertical
    private var hasLaidOutInitialDocument = false

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

    func apply(
        axes: Axis.Set,
        showsIndicators: Bool,
        drawsBackground: Bool,
        rootView: AnyView
    ) {
        self.axes = axes
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
            documentContainer.scroll(.zero)
            hasLaidOutInitialDocument = true
        }
    }

    private func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        let currentHeight = max(1, hostingView.frame.height)
        hostingView.setFrameSize(NSSize(width: max(1, width), height: currentHeight))
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }
}

private final class NativePaperCodexFlippedDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}
