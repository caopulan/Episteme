import AppKit
import SwiftUI

private enum NativeSidebarRowMetrics {
    static let depthIndent: CGFloat = PaperCodexHitTarget.sidebarDepthIndent
    static let rowHeight: CGFloat = PaperCodexHitTarget.sidebarRowHeight
    static let iconWidth: CGFloat = PaperCodexHitTarget.sidebarIconWidth
    static let iconTextSpacing: CGFloat = PaperCodexHitTarget.sidebarIconTextSpacing
    static let selectionWidth: CGFloat = PaperCodexHitTarget.sidebarSelectionIndicatorWidth
    static let selectionHeight: CGFloat = PaperCodexHitTarget.sidebarSelectionIndicatorHeight
    static let selectionInset: CGFloat = PaperCodexHitTarget.sidebarSelectionIndicatorInset
    static let cornerRadius: CGFloat = PaperCodexCornerRadius.control
}

struct SidebarRowButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var systemImage: String
    var selected: Bool
    var depth: Int = 0
    var trailingReserve: CGFloat = 0
    var action: () -> Void

    var body: some View {
        NativeSidebarRowButton(
            title: title,
            systemImage: systemImage,
            selected: selected,
            depth: depth,
            trailingReserve: trailingReserve,
            reduceMotion: reduceMotion,
            action: action
        )
        .frame(maxWidth: .infinity, minHeight: NativeSidebarRowMetrics.rowHeight, maxHeight: NativeSidebarRowMetrics.rowHeight)
    }
}

private struct NativeSidebarRowButton: NSViewRepresentable {
    var title: String
    var systemImage: String
    var selected: Bool
    var depth: Int
    var trailingReserve: CGFloat
    var reduceMotion: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NativeSidebarRowButtonView {
        let view = NativeSidebarRowButtonView()
        view.apply(
            title: title,
            systemImage: systemImage,
            selected: selected,
            depth: depth,
            trailingReserve: trailingReserve,
            reduceMotion: reduceMotion,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativeSidebarRowButtonView, context: Context) {
        view.apply(
            title: title,
            systemImage: systemImage,
            selected: selected,
            depth: depth,
            trailingReserve: trailingReserve,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private final class NativeSidebarRowButtonView: NSButton {
    private let selectionIndicator = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var iconLeadingConstraint: NSLayoutConstraint?
    private var titleTrailingConstraint: NSLayoutConstraint?
    private var indicatorLeadingConstraint: NSLayoutConstraint?
    private var pressHandler: () -> Void = {}
    private var isHovering = false
    private var isPressed = false
    private var isSelectedRow = false
    private var reduceMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NativeSidebarRowMetrics.rowHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(
        title: String,
        systemImage: String,
        selected: Bool,
        depth: Int,
        trailingReserve: CGFloat,
        reduceMotion: Bool,
        action: @escaping () -> Void
    ) {
        let localizedTitle = NSLocalizedString(title, comment: "")
        pressHandler = action
        isSelectedRow = selected
        self.reduceMotion = reduceMotion
        self.title = ""
        toolTip = localizedTitle
        titleLabel.stringValue = localizedTitle
        iconView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: localizedTitle)
        setAccessibilityLabel(localizedTitle)
        setAccessibilityValue(selected ? NSLocalizedString("Selected", comment: "") : NSLocalizedString("Not selected", comment: ""))

        let leading = CGFloat(depth) * NativeSidebarRowMetrics.depthIndent + PaperCodexSpacing.sidebarRowLeading
        iconLeadingConstraint?.constant = leading
        indicatorLeadingConstraint?.constant = CGFloat(depth) * NativeSidebarRowMetrics.depthIndent + NativeSidebarRowMetrics.selectionInset
        titleTrailingConstraint?.constant = -(PaperCodexSpacing.sidebarRowTrailing + trailingReserve)
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        focusRingType = .none
        setButtonType(.momentaryChange)
        target = self
        action = #selector(performPress)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        wantsLayer = true
        layer?.cornerRadius = NativeSidebarRowMetrics.cornerRadius
        layer?.masksToBounds = false

        selectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        selectionIndicator.wantsLayer = true
        selectionIndicator.layer?.cornerRadius = NativeSidebarRowMetrics.selectionWidth / 2

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        [selectionIndicator, iconView, titleLabel].forEach(addSubview(_:))

        let iconLeading = iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PaperCodexSpacing.sidebarRowLeading)
        let titleTrailing = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -PaperCodexSpacing.sidebarRowTrailing)
        let indicatorLeading = selectionIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: NativeSidebarRowMetrics.selectionInset)
        iconLeadingConstraint = iconLeading
        titleTrailingConstraint = titleTrailing
        indicatorLeadingConstraint = indicatorLeading

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: NativeSidebarRowMetrics.rowHeight),
            indicatorLeading,
            selectionIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectionIndicator.widthAnchor.constraint(equalToConstant: NativeSidebarRowMetrics.selectionWidth),
            selectionIndicator.heightAnchor.constraint(equalToConstant: NativeSidebarRowMetrics.selectionHeight),
            iconLeading,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: NativeSidebarRowMetrics.iconWidth),
            iconView.heightAnchor.constraint(equalToConstant: NativeSidebarRowMetrics.iconWidth),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: NativeSidebarRowMetrics.iconTextSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleTrailing
        ])
        updateAppearance()
    }

    @objc private func performPress() {
        pressHandler()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let accent = NSColor.controlAccentColor
        iconView.contentTintColor = isSelectedRow ? accent : NSColor.labelColor.withAlphaComponent(0.78)
        titleLabel.textColor = isSelectedRow ? .labelColor : NSColor.labelColor.withAlphaComponent(0.92)
        selectionIndicator.isHidden = !(isSelectedRow || isPressed)
        selectionIndicator.layer?.backgroundColor = accent.withAlphaComponent(isSelectedRow ? 0.72 : 0.52).cgColor

        let background: NSColor
        let border: NSColor
        if isSelectedRow {
            background = accent.withAlphaComponent(isPressed ? 0.18 : 0.14)
            border = isPressed ? accent.withAlphaComponent(0.38) : .clear
        } else if isPressed {
            background = accent.withAlphaComponent(0.10)
            border = accent.withAlphaComponent(0.38)
        } else if isHovering {
            background = .textBackgroundColor
            border = accent.withAlphaComponent(0.25)
        } else {
            background = .clear
            border = .clear
        }

        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = border == .clear ? 0 : 1
        layer?.borderColor = border.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = isPressed ? 0.12 : (isHovering ? 0.08 : 0)
        layer?.shadowRadius = isPressed ? 3 : (isHovering ? 7 : 0)
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? 1 : -3)

        let targetScale: CGFloat
        if reduceMotion {
            targetScale = 1
        } else if isPressed {
            targetScale = 0.985
        } else {
            targetScale = isHovering ? 1.015 : 1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
    }
}
