import AppKit
import SwiftUI

struct PaperCodexToolbarButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var systemImage: String
    var tint: Color = .blue
    var disabled = false
    var action: () -> Void

    var body: some View {
        NativePaperCodexToolbarButton(
            title: title,
            systemImage: systemImage,
            tint: tint,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
        .fixedSize(horizontal: true, vertical: true)
        .help(title)
    }
}

struct PaperCodexIconButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var systemImage: String
    var tint: Color = .secondary
    var disabled = false
    var action: () -> Void

    var body: some View {
        NativePaperCodexIconButton(
            title: title,
            systemImage: systemImage,
            tint: tint,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
        .frame(width: PaperCodexHitTarget.toolbarIconSize, height: PaperCodexHitTarget.toolbarIconSize)
        .help(title)
        .accessibilityLabel(title)
    }
}

enum PaperCodexPanelButtonKind {
    case primary
    case secondary
    case destructive

    var tint: Color {
        switch self {
        case .primary:
            Color.accentColor
        case .secondary:
            Color.secondary
        case .destructive:
            Color.red
        }
    }
}

enum PaperCodexCardActionButtonKind {
    case primary
    case success

    var tint: Color {
        switch self {
        case .primary:
            Color(nsColor: .systemBlue)
        case .success:
            Color(nsColor: .systemGreen)
        }
    }
}

struct PaperCodexPanelButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var systemImage: String?
    var kind: PaperCodexPanelButtonKind = .secondary
    var disabled = false
    var role: ButtonRole?
    var action: () -> Void

    var body: some View {
        NativePaperCodexPanelButton(
            title: title,
            systemImage: systemImage,
            kind: kind,
            disabled: disabled,
            role: role,
            reduceMotion: reduceMotion,
            action: action
        )
        .fixedSize(horizontal: true, vertical: true)
        .help(title)
    }
}

struct PaperCodexCardActionButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var systemImage: String
    var kind: PaperCodexCardActionButtonKind
    var disabled = false
    var help: String?
    var action: () -> Void

    var body: some View {
        NativePaperCodexCardActionButton(
            title: title,
            systemImage: systemImage,
            kind: kind,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
        .fixedSize(horizontal: true, vertical: true)
        .help(help ?? title)
        .accessibilityLabel(help ?? title)
    }
}

struct PaperCodexResourceLinkButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var title: String
    var systemImage: String
    var compact = true
    var disabled = false
    var action: () -> Void

    var body: some View {
        NativePaperCodexResourceLinkButton(
            title: title,
            systemImage: systemImage,
            compact: compact,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
        .fixedSize(horizontal: true, vertical: true)
        .overlay(alignment: .top) {
            if compact && isHovering {
                Text(title)
                    .font(.paperCodexSystem(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .textBackgroundColor))
                            .shadow(color: Color.black.opacity(0.16), radius: 7, y: 3)
                    )
                    .offset(y: -28)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .zIndex(isHovering ? 10 : 0)
        .help("Open \(title)")
        .accessibilityLabel(title)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

struct PaperCodexPathChipButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var title: String
    var systemImage: String = "folder.fill"
    var tint: Color = .accentColor
    var disabled = false
    var action: () -> Void

    var body: some View {
        NativePaperCodexPathChipButton(
            title: title,
            systemImage: systemImage,
            tint: tint,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
        .fixedSize(horizontal: true, vertical: true)
        .help("Remove \(title)")
        .accessibilityLabel("Remove \(title)")
    }
}

private enum NativePaperCodexActionMetrics {
    static let toolbarHeight: CGFloat = max(
        PaperCodexHitTarget.toolbarButtonHeight,
        PaperCodexHitTarget.toolbarButtonFontSize + PaperCodexHitTarget.toolbarButtonVerticalPadding * 2
    )
    static let toolbarIconSize: CGFloat = PaperCodexHitTarget.toolbarButtonSymbolSize
    static let toolbarIconWidth: CGFloat = PaperCodexHitTarget.toolbarButtonSymbolWidth
    static let toolbarIconTextSpacing: CGFloat = PaperCodexHitTarget.toolbarButtonSymbolTextSpacing
    static let toolbarFontSize: CGFloat = PaperCodexHitTarget.toolbarButtonFontSize
    static let iconFontSize: CGFloat = PaperCodexHitTarget.toolbarIconSymbolSize
    static let iconSize: CGFloat = PaperCodexHitTarget.toolbarIconSize
    static let cornerRadius: CGFloat = PaperCodexCornerRadius.control
    static let pathChipHeight: CGFloat = 24
    static let pathChipHorizontalPadding: CGFloat = 8
    static let pathChipIconSize: CGFloat = 11
    static let pathChipRemoveIconSize: CGFloat = 9
    static let pathChipIconTextSpacing: CGFloat = 5
    static let pathChipTitleMaxWidth: CGFloat = 210
    static let pathChipCornerRadius: CGFloat = 7
    static let cardActionHeight: CGFloat = 26
    static let cardActionHorizontalPadding: CGFloat = 10
    static let cardActionIconSize: CGFloat = 13
    static let cardActionIconWidth: CGFloat = 15
    static let cardActionIconTextSpacing: CGFloat = 5
    static let cardActionFontSize: CGFloat = 13
    static let cardActionCornerRadius: CGFloat = 7
    static let resourceLinkCompactSize: CGFloat = 22
    static let resourceLinkExpandedHeight: CGFloat = 28
    static let resourceLinkHorizontalPadding: CGFloat = 9
    static let resourceLinkIconSize: CGFloat = 11.5
    static let resourceLinkIconWidth: CGFloat = 13
    static let resourceLinkIconTextSpacing: CGFloat = 5
    static let resourceLinkFontSize: CGFloat = 13
    static let resourceLinkCornerRadius: CGFloat = 6
}

private struct NativePaperCodexToolbarButton: NSViewRepresentable {
    var title: String
    var systemImage: String
    var tint: Color
    var disabled: Bool
    var reduceMotion: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NativePaperCodexToolbarButtonView {
        let view = NativePaperCodexToolbarButtonView()
        view.apply(
            title: title,
            systemImage: systemImage,
            tint: tint,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativePaperCodexToolbarButtonView, context: Context) {
        view.apply(
            title: title,
            systemImage: systemImage,
            tint: tint,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private struct NativePaperCodexPanelButton: NSViewRepresentable {
    var title: String
    var systemImage: String?
    var kind: PaperCodexPanelButtonKind
    var disabled: Bool
    var role: ButtonRole?
    var reduceMotion: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NativePaperCodexPanelButtonView {
        let view = NativePaperCodexPanelButtonView()
        view.apply(
            title: title,
            systemImage: systemImage,
            kind: kind,
            disabled: disabled,
            role: role,
            reduceMotion: reduceMotion,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativePaperCodexPanelButtonView, context: Context) {
        view.apply(
            title: title,
            systemImage: systemImage,
            kind: kind,
            disabled: disabled,
            role: role,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private struct NativePaperCodexIconButton: NSViewRepresentable {
    var title: String
    var systemImage: String
    var tint: Color
    var disabled: Bool
    var reduceMotion: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NativePaperCodexIconButtonView {
        let view = NativePaperCodexIconButtonView()
        view.apply(
            title: title,
            systemImage: systemImage,
            tint: tint,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativePaperCodexIconButtonView, context: Context) {
        view.apply(
            title: title,
            systemImage: systemImage,
            tint: tint,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private struct NativePaperCodexCardActionButton: NSViewRepresentable {
    var title: String
    var systemImage: String
    var kind: PaperCodexCardActionButtonKind
    var disabled: Bool
    var reduceMotion: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NativePaperCodexCardActionButtonView {
        let view = NativePaperCodexCardActionButtonView()
        view.apply(
            title: title,
            systemImage: systemImage,
            kind: kind,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativePaperCodexCardActionButtonView, context: Context) {
        view.apply(
            title: title,
            systemImage: systemImage,
            kind: kind,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private struct NativePaperCodexResourceLinkButton: NSViewRepresentable {
    var title: String
    var systemImage: String
    var compact: Bool
    var disabled: Bool
    var reduceMotion: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NativePaperCodexResourceLinkButtonView {
        let view = NativePaperCodexResourceLinkButtonView()
        view.apply(
            title: title,
            systemImage: systemImage,
            compact: compact,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativePaperCodexResourceLinkButtonView, context: Context) {
        view.apply(
            title: title,
            systemImage: systemImage,
            compact: compact,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private struct NativePaperCodexPathChipButton: NSViewRepresentable {
    var title: String
    var systemImage: String
    var tint: Color
    var disabled: Bool
    var reduceMotion: Bool
    var action: () -> Void

    func makeNSView(context: Context) -> NativePaperCodexPathChipButtonView {
        let view = NativePaperCodexPathChipButtonView()
        view.apply(
            title: title,
            systemImage: systemImage,
            tint: tint,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
        return view
    }

    func updateNSView(_ view: NativePaperCodexPathChipButtonView, context: Context) {
        view.apply(
            title: title,
            systemImage: systemImage,
            tint: tint,
            disabled: disabled,
            reduceMotion: reduceMotion,
            action: action
        )
    }
}

private final class NativePaperCodexCardActionButtonView: NSButton {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var pressHandler: () -> Void = {}
    private var kind = PaperCodexCardActionButtonKind.primary
    private var isHovering = false
    private var isPressed = false
    private var isDisabled = false
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
        let width = NativePaperCodexActionMetrics.cardActionHorizontalPadding * 2
            + NativePaperCodexActionMetrics.cardActionIconWidth
            + NativePaperCodexActionMetrics.cardActionIconTextSpacing
            + titleLabel.intrinsicContentSize.width
        return NSSize(width: ceil(width), height: NativePaperCodexActionMetrics.cardActionHeight)
    }

    func apply(
        title: String,
        systemImage: String,
        kind: PaperCodexCardActionButtonKind,
        disabled: Bool,
        reduceMotion: Bool,
        action: @escaping () -> Void
    ) {
        let localizedTitle = NSLocalizedString(title, comment: "")
        pressHandler = action
        self.kind = kind
        isDisabled = disabled
        self.reduceMotion = reduceMotion
        isEnabled = !disabled
        titleLabel.stringValue = localizedTitle
        iconView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: localizedTitle)
        toolTip = localizedTitle
        setAccessibilityLabel(localizedTitle)
        invalidateIntrinsicContentSize()
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
        guard !isDisabled else {
            return
        }
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        title = ""
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
        layer?.cornerRadius = NativePaperCodexActionMetrics.cardActionCornerRadius
        layer?.masksToBounds = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: NativePaperCodexActionMetrics.cardActionIconSize,
            weight: .semibold
        )
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(
            ofSize: NativePaperCodexActionMetrics.cardActionFontSize,
            weight: .semibold
        )
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        [iconView, titleLabel].forEach(addSubview(_:))
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.cardActionHeight),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: NativePaperCodexActionMetrics.cardActionHorizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.cardActionIconWidth),
            iconView.heightAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.cardActionIconWidth),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: NativePaperCodexActionMetrics.cardActionIconTextSpacing),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -NativePaperCodexActionMetrics.cardActionHorizontalPadding),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }

    @objc private func performPress() {
        guard !isDisabled else {
            return
        }
        pressHandler()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let tint = NSColor(kind.tint)
        let foreground: NSColor
        let background: NSColor
        let border: NSColor
        let shadowOpacity: Float

        if isDisabled {
            foreground = kind == .primary ? .white.withAlphaComponent(0.70) : .secondaryLabelColor.withAlphaComponent(0.60)
            background = kind == .primary ? .systemGray.withAlphaComponent(0.55) : .controlBackgroundColor.withAlphaComponent(0.56)
            border = .black.withAlphaComponent(0.07)
            shadowOpacity = 0
        } else {
            switch kind {
            case .primary:
                foreground = .white
                background = tint.withAlphaComponent(isPressed ? 0.78 : (isHovering ? 0.98 : 0.92))
                border = isPressed ? .white.withAlphaComponent(0.36) : .clear
                shadowOpacity = isPressed ? 0.12 : (isHovering ? 0.18 : 0)
            case .success:
                foreground = isPressed || isHovering ? tint : .labelColor.withAlphaComponent(0.86)
                background = isPressed ? tint.withAlphaComponent(0.20) : (isHovering ? tint.withAlphaComponent(0.13) : .controlBackgroundColor)
                border = isPressed ? tint.withAlphaComponent(0.58) : (isHovering ? tint.withAlphaComponent(0.44) : .black.withAlphaComponent(0.12))
                shadowOpacity = isPressed ? 0.12 : (isHovering ? 0.18 : 0)
            }
        }

        iconView.contentTintColor = foreground
        titleLabel.textColor = foreground
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = border == .clear ? 0 : 1
        layer?.borderColor = border.cgColor
        layer?.shadowColor = tint.cgColor
        layer?.shadowOpacity = shadowOpacity
        layer?.shadowRadius = isPressed ? 4 : 8
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? -1 : -3)

        let targetScale: CGFloat
        if reduceMotion || isDisabled {
            targetScale = 1
        } else if isPressed {
            targetScale = 0.965
        } else {
            targetScale = isHovering ? 1.025 : 1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
    }
}

private final class NativePaperCodexResourceLinkButtonView: NSButton {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var heightConstraint: NSLayoutConstraint?
    private var compactWidthConstraint: NSLayoutConstraint?
    private var compactIconCenterXConstraint: NSLayoutConstraint?
    private var expandedIconLeadingConstraint: NSLayoutConstraint?
    private var titleLeadingConstraint: NSLayoutConstraint?
    private var titleTrailingConstraint: NSLayoutConstraint?
    private var trackingArea: NSTrackingArea?
    private var pressHandler: () -> Void = {}
    private var isCompact = true
    private var isHovering = false
    private var isPressed = false
    private var isDisabled = false
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
        if isCompact {
            return NSSize(
                width: NativePaperCodexActionMetrics.resourceLinkCompactSize,
                height: NativePaperCodexActionMetrics.resourceLinkCompactSize
            )
        }

        let width = NativePaperCodexActionMetrics.resourceLinkHorizontalPadding * 2
            + NativePaperCodexActionMetrics.resourceLinkIconWidth
            + NativePaperCodexActionMetrics.resourceLinkIconTextSpacing
            + titleLabel.intrinsicContentSize.width
        return NSSize(width: ceil(width), height: NativePaperCodexActionMetrics.resourceLinkExpandedHeight)
    }

    func apply(
        title: String,
        systemImage: String,
        compact: Bool,
        disabled: Bool,
        reduceMotion: Bool,
        action: @escaping () -> Void
    ) {
        let localizedTitle = NSLocalizedString(title, comment: "")
        pressHandler = action
        isCompact = compact
        isDisabled = disabled
        self.reduceMotion = reduceMotion
        isEnabled = !disabled
        titleLabel.stringValue = localizedTitle
        titleLabel.font = .systemFont(
            ofSize: compact ? 11.5 : NativePaperCodexActionMetrics.resourceLinkFontSize,
            weight: .semibold
        )
        titleLabel.isHidden = compact
        iconView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: localizedTitle)
        toolTip = "Open \(localizedTitle)"
        setAccessibilityLabel(localizedTitle)
        updateLayoutMode()
        invalidateIntrinsicContentSize()
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
        guard !isDisabled else {
            return
        }
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        title = ""
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
        layer?.cornerRadius = NativePaperCodexActionMetrics.resourceLinkCornerRadius
        layer?.masksToBounds = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: NativePaperCodexActionMetrics.resourceLinkIconSize,
            weight: .semibold
        )
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(
            ofSize: NativePaperCodexActionMetrics.resourceLinkFontSize,
            weight: .semibold
        )
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        [iconView, titleLabel].forEach(addSubview(_:))

        let heightConstraint = heightAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.resourceLinkCompactSize)
        let compactWidthConstraint = widthAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.resourceLinkCompactSize)
        let compactIconCenterXConstraint = iconView.centerXAnchor.constraint(equalTo: centerXAnchor)
        let expandedIconLeadingConstraint = iconView.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: NativePaperCodexActionMetrics.resourceLinkHorizontalPadding
        )
        let titleLeadingConstraint = titleLabel.leadingAnchor.constraint(
            equalTo: iconView.trailingAnchor,
            constant: NativePaperCodexActionMetrics.resourceLinkIconTextSpacing
        )
        let titleTrailingConstraint = titleLabel.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -NativePaperCodexActionMetrics.resourceLinkHorizontalPadding
        )
        self.heightConstraint = heightConstraint
        self.compactWidthConstraint = compactWidthConstraint
        self.compactIconCenterXConstraint = compactIconCenterXConstraint
        self.expandedIconLeadingConstraint = expandedIconLeadingConstraint
        self.titleLeadingConstraint = titleLeadingConstraint
        self.titleTrailingConstraint = titleTrailingConstraint

        NSLayoutConstraint.activate([
            heightConstraint,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.resourceLinkIconWidth),
            iconView.heightAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.resourceLinkIconWidth),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateLayoutMode()
        updateAppearance()
    }

    @objc private func performPress() {
        guard !isDisabled else {
            return
        }
        pressHandler()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateLayoutMode() {
        heightConstraint?.constant = isCompact
            ? NativePaperCodexActionMetrics.resourceLinkCompactSize
            : NativePaperCodexActionMetrics.resourceLinkExpandedHeight
        compactWidthConstraint?.constant = NativePaperCodexActionMetrics.resourceLinkCompactSize
        compactWidthConstraint?.isActive = isCompact
        compactIconCenterXConstraint?.isActive = isCompact
        expandedIconLeadingConstraint?.isActive = !isCompact
        titleLeadingConstraint?.isActive = !isCompact
        titleTrailingConstraint?.isActive = !isCompact
        needsLayout = true
    }

    private func updateAppearance() {
        let tint = NSColor.controlAccentColor
        let foreground: NSColor
        let background: NSColor
        let border: NSColor
        let shadowOpacity: Float

        if isDisabled {
            foreground = .secondaryLabelColor.withAlphaComponent(0.45)
            background = .controlBackgroundColor.withAlphaComponent(0.50)
            border = .black.withAlphaComponent(0.06)
            shadowOpacity = 0
        } else if isPressed {
            foreground = tint
            background = tint.withAlphaComponent(0.20)
            border = tint.withAlphaComponent(0.58)
            shadowOpacity = 0.10
        } else if isHovering {
            foreground = tint
            background = tint.withAlphaComponent(0.13)
            border = tint.withAlphaComponent(0.45)
            shadowOpacity = 0.14
        } else {
            foreground = .labelColor.withAlphaComponent(0.82)
            background = .controlBackgroundColor
            border = .black.withAlphaComponent(0.10)
            shadowOpacity = 0
        }

        iconView.contentTintColor = foreground
        titleLabel.textColor = foreground
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = border.cgColor
        layer?.shadowColor = tint.cgColor
        layer?.shadowOpacity = shadowOpacity
        layer?.shadowRadius = isPressed ? 3 : 5
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? -1 : -2)

        let targetScale: CGFloat
        if reduceMotion || isDisabled {
            targetScale = 1
        } else if isPressed {
            targetScale = 0.94
        } else {
            targetScale = isHovering ? 1.06 : 1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
    }
}

private final class NativePaperCodexPanelButtonView: NSButton {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var titleLeadingIconConstraint: NSLayoutConstraint?
    private var titleLeadingButtonConstraint: NSLayoutConstraint?
    private var trackingArea: NSTrackingArea?
    private var pressHandler: () -> Void = {}
    private var kind = PaperCodexPanelButtonKind.secondary
    private var hasIcon = false
    private var isHovering = false
    private var isPressed = false
    private var isDisabled = false
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
        let iconWidth = hasIcon ? NativePaperCodexActionMetrics.toolbarIconWidth + NativePaperCodexActionMetrics.toolbarIconTextSpacing : 0
        let width = PaperCodexHitTarget.toolbarButtonHorizontalPadding * 2 + iconWidth + titleLabel.intrinsicContentSize.width
        return NSSize(width: ceil(width), height: NativePaperCodexActionMetrics.toolbarHeight)
    }

    func apply(
        title: String,
        systemImage: String?,
        kind: PaperCodexPanelButtonKind,
        disabled: Bool,
        role: ButtonRole?,
        reduceMotion: Bool,
        action: @escaping () -> Void
    ) {
        let localizedTitle = NSLocalizedString(title, comment: "")
        pressHandler = action
        self.kind = role == .destructive ? .destructive : kind
        isDisabled = disabled
        self.reduceMotion = reduceMotion
        isEnabled = !disabled
        hasIcon = systemImage != nil
        titleLabel.stringValue = localizedTitle
        iconView.image = systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: localizedTitle) }
        iconView.isHidden = systemImage == nil
        titleLeadingIconConstraint?.isActive = systemImage != nil
        titleLeadingButtonConstraint?.isActive = systemImage == nil
        toolTip = localizedTitle
        setAccessibilityLabel(localizedTitle)
        invalidateIntrinsicContentSize()
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
        guard !isDisabled else {
            return
        }
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        title = ""
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
        layer?.cornerRadius = NativePaperCodexActionMetrics.cornerRadius
        layer?.masksToBounds = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: NativePaperCodexActionMetrics.toolbarIconSize,
            weight: .semibold
        )
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: NativePaperCodexActionMetrics.toolbarFontSize, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        [iconView, titleLabel].forEach(addSubview(_:))
        let leadingIconConstraint = titleLabel.leadingAnchor.constraint(
            equalTo: iconView.trailingAnchor,
            constant: NativePaperCodexActionMetrics.toolbarIconTextSpacing
        )
        let leadingButtonConstraint = titleLabel.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: PaperCodexHitTarget.toolbarButtonHorizontalPadding
        )
        titleLeadingIconConstraint = leadingIconConstraint
        titleLeadingButtonConstraint = leadingButtonConstraint
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.toolbarHeight),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PaperCodexHitTarget.toolbarButtonHorizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.toolbarIconWidth),
            iconView.heightAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.toolbarIconWidth),
            leadingIconConstraint,
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PaperCodexHitTarget.toolbarButtonHorizontalPadding),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }

    @objc private func performPress() {
        guard !isDisabled else {
            return
        }
        pressHandler()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let tint = NSColor(kind.tint)
        let foreground: NSColor
        let background: NSColor
        let border: NSColor
        let shadowOpacity: Float

        if isDisabled {
            foreground = .secondaryLabelColor.withAlphaComponent(0.48)
            background = .controlBackgroundColor.withAlphaComponent(0.56)
            border = .black.withAlphaComponent(0.06)
            shadowOpacity = 0
        } else {
            switch kind {
            case .primary:
                foreground = .white
                background = tint.withAlphaComponent(isPressed ? 0.82 : (isHovering ? 0.96 : 0.90))
                border = tint.withAlphaComponent(isPressed ? 0.62 : (isHovering ? 0.48 : 0.34))
                shadowOpacity = isPressed ? 0.10 : (isHovering ? 0.16 : 0)
            case .secondary, .destructive:
                foreground = isPressed || isHovering ? tint : .labelColor.withAlphaComponent(0.82)
                background = isPressed ? tint.withAlphaComponent(0.18) : (isHovering ? tint.withAlphaComponent(0.12) : .controlBackgroundColor)
                border = isPressed ? tint.withAlphaComponent(0.54) : (isHovering ? tint.withAlphaComponent(0.38) : .black.withAlphaComponent(0.10))
                shadowOpacity = isPressed ? 0.10 : (isHovering ? 0.16 : 0)
            }
        }

        iconView.contentTintColor = foreground
        titleLabel.textColor = foreground
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = border.cgColor
        layer?.shadowColor = tint.cgColor
        layer?.shadowOpacity = shadowOpacity
        layer?.shadowRadius = isPressed ? 3 : 7
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? -1 : -3)

        let targetScale: CGFloat
        if reduceMotion || isDisabled {
            targetScale = 1
        } else if isPressed {
            targetScale = 0.97
        } else {
            targetScale = isHovering ? 1.02 : 1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
    }
}

private final class NativePaperCodexPathChipButtonView: NSButton {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let removeIconView = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var pressHandler: () -> Void = {}
    private var tintColor = NSColor.controlAccentColor
    private var isHovering = false
    private var isPressed = false
    private var isDisabled = false
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
        let titleWidth = min(
            titleLabel.intrinsicContentSize.width,
            NativePaperCodexActionMetrics.pathChipTitleMaxWidth
        )
        let width = NativePaperCodexActionMetrics.pathChipHorizontalPadding * 2
            + NativePaperCodexActionMetrics.pathChipIconSize
            + NativePaperCodexActionMetrics.pathChipIconTextSpacing
            + titleWidth
            + NativePaperCodexActionMetrics.pathChipIconTextSpacing
            + NativePaperCodexActionMetrics.pathChipRemoveIconSize
        return NSSize(width: ceil(width), height: NativePaperCodexActionMetrics.pathChipHeight)
    }

    func apply(title: String, systemImage: String, tint: Color, disabled: Bool, reduceMotion: Bool, action: @escaping () -> Void) {
        let accessibilityTitle = "Remove \(title)"
        pressHandler = action
        tintColor = NSColor(tint)
        isDisabled = disabled
        self.reduceMotion = reduceMotion
        isEnabled = !disabled
        titleLabel.stringValue = title
        iconView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        removeIconView.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: accessibilityTitle)
        toolTip = accessibilityTitle
        setAccessibilityLabel(accessibilityTitle)
        invalidateIntrinsicContentSize()
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
        guard !isDisabled else {
            return
        }
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        title = ""
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
        layer?.cornerRadius = NativePaperCodexActionMetrics.pathChipCornerRadius
        layer?.masksToBounds = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: NativePaperCodexActionMetrics.pathChipIconSize,
            weight: .semibold
        )
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        removeIconView.translatesAutoresizingMaskIntoConstraints = false
        removeIconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: NativePaperCodexActionMetrics.pathChipRemoveIconSize,
            weight: .bold
        )
        removeIconView.imageScaling = .scaleProportionallyDown

        [iconView, titleLabel, removeIconView].forEach(addSubview(_:))
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.pathChipHeight),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: NativePaperCodexActionMetrics.pathChipHorizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.pathChipIconSize),
            iconView.heightAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.pathChipIconSize),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: NativePaperCodexActionMetrics.pathChipIconTextSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: NativePaperCodexActionMetrics.pathChipTitleMaxWidth),
            removeIconView.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: NativePaperCodexActionMetrics.pathChipIconTextSpacing),
            removeIconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -NativePaperCodexActionMetrics.pathChipHorizontalPadding),
            removeIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeIconView.widthAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.pathChipRemoveIconSize),
            removeIconView.heightAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.pathChipRemoveIconSize)
        ])
        updateAppearance()
    }

    @objc private func performPress() {
        guard !isDisabled else {
            return
        }
        pressHandler()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let tint = tintColor
        let foreground: NSColor
        let background: NSColor
        let border: NSColor
        let shadowOpacity: Float

        if isDisabled {
            foreground = .secondaryLabelColor.withAlphaComponent(0.45)
            background = .controlBackgroundColor.withAlphaComponent(0.50)
            border = .black.withAlphaComponent(0.06)
            shadowOpacity = 0
        } else if isPressed {
            foreground = tint
            background = tint.withAlphaComponent(0.21)
            border = tint.withAlphaComponent(0.54)
            shadowOpacity = 0.10
        } else if isHovering {
            foreground = tint
            background = tint.withAlphaComponent(0.16)
            border = tint.withAlphaComponent(0.34)
            shadowOpacity = 0.14
        } else {
            foreground = .labelColor
            background = tint.withAlphaComponent(0.12)
            border = tint.withAlphaComponent(0.18)
            shadowOpacity = 0
        }

        iconView.contentTintColor = isDisabled ? foreground : tint.withAlphaComponent(isPressed || isHovering ? 0.92 : 0.72)
        titleLabel.textColor = foreground
        removeIconView.contentTintColor = foreground.withAlphaComponent(isPressed || isHovering ? 0.82 : 0.56)
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = border.cgColor
        layer?.shadowColor = tint.cgColor
        layer?.shadowOpacity = shadowOpacity
        layer?.shadowRadius = isPressed ? 3 : 6
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? -1 : -2)

        let targetScale: CGFloat
        if reduceMotion || isDisabled {
            targetScale = 1
        } else if isPressed {
            targetScale = 0.965
        } else {
            targetScale = isHovering ? 1.025 : 1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
    }
}

private final class NativePaperCodexToolbarButtonView: NSButton {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var pressHandler: () -> Void = {}
    private var tintColor = NSColor.controlAccentColor
    private var isHovering = false
    private var isPressed = false
    private var isDisabled = false
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
        let titleWidth = titleLabel.intrinsicContentSize.width
        let width = PaperCodexHitTarget.toolbarButtonHorizontalPadding * 2
            + NativePaperCodexActionMetrics.toolbarIconWidth
            + NativePaperCodexActionMetrics.toolbarIconTextSpacing
            + titleWidth
        return NSSize(width: ceil(width), height: NativePaperCodexActionMetrics.toolbarHeight)
    }

    func apply(title: String, systemImage: String, tint: Color, disabled: Bool, reduceMotion: Bool, action: @escaping () -> Void) {
        let localizedTitle = NSLocalizedString(title, comment: "")
        pressHandler = action
        tintColor = NSColor(tint)
        isDisabled = disabled
        self.reduceMotion = reduceMotion
        isEnabled = !disabled
        titleLabel.stringValue = localizedTitle
        iconView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: localizedTitle)
        toolTip = localizedTitle
        setAccessibilityLabel(localizedTitle)
        invalidateIntrinsicContentSize()
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
        guard !isDisabled else {
            return
        }
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        title = ""
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
        layer?.cornerRadius = NativePaperCodexActionMetrics.cornerRadius
        layer?.masksToBounds = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: NativePaperCodexActionMetrics.toolbarIconSize,
            weight: .semibold
        )
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: NativePaperCodexActionMetrics.toolbarFontSize, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        [iconView, titleLabel].forEach(addSubview(_:))
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.toolbarHeight),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PaperCodexHitTarget.toolbarButtonHorizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.toolbarIconWidth),
            iconView.heightAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.toolbarIconWidth),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: NativePaperCodexActionMetrics.toolbarIconTextSpacing),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PaperCodexHitTarget.toolbarButtonHorizontalPadding),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }

    @objc private func performPress() {
        guard !isDisabled else {
            return
        }
        pressHandler()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let tint = tintColor
        let foreground: NSColor
        let background: NSColor
        let border: NSColor
        let shadowOpacity: Float

        if isDisabled {
            foreground = .secondaryLabelColor.withAlphaComponent(0.55)
            background = .controlBackgroundColor.withAlphaComponent(0.55)
            border = .black.withAlphaComponent(0.06)
            shadowOpacity = 0
        } else if isPressed {
            foreground = tint
            background = tint.withAlphaComponent(0.18)
            border = tint.withAlphaComponent(0.58)
            shadowOpacity = 0.12
        } else if isHovering {
            foreground = tint
            background = tint.withAlphaComponent(0.12)
            border = tint.withAlphaComponent(0.45)
            shadowOpacity = 0.18
        } else {
            foreground = .labelColor.withAlphaComponent(0.82)
            background = .controlBackgroundColor
            border = .black.withAlphaComponent(0.10)
            shadowOpacity = 0
        }

        iconView.contentTintColor = foreground
        titleLabel.textColor = foreground
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = border.cgColor
        layer?.shadowColor = tint.cgColor
        layer?.shadowOpacity = shadowOpacity
        layer?.shadowRadius = isPressed ? 4 : 7
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? -1 : -3)

        let targetScale: CGFloat
        if reduceMotion || isDisabled {
            targetScale = 1
        } else if isPressed {
            targetScale = 0.97
        } else {
            targetScale = isHovering ? 1.025 : 1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
    }
}

private final class NativePaperCodexIconButtonView: NSButton {
    private let iconView = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var pressHandler: () -> Void = {}
    private var tintColor = NSColor.secondaryLabelColor
    private var isHovering = false
    private var isPressed = false
    private var isDisabled = false
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
        NSSize(width: NativePaperCodexActionMetrics.iconSize, height: NativePaperCodexActionMetrics.iconSize)
    }

    func apply(title: String, systemImage: String, tint: Color, disabled: Bool, reduceMotion: Bool, action: @escaping () -> Void) {
        let localizedTitle = NSLocalizedString(title, comment: "")
        pressHandler = action
        tintColor = NSColor(tint)
        isDisabled = disabled
        self.reduceMotion = reduceMotion
        isEnabled = !disabled
        iconView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: localizedTitle)
        toolTip = localizedTitle
        setAccessibilityLabel(localizedTitle)
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
        guard !isDisabled else {
            return
        }
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        title = ""
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
        layer?.cornerRadius = NativePaperCodexActionMetrics.iconSize / 2
        layer?.masksToBounds = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: NativePaperCodexActionMetrics.iconFontSize,
            weight: .semibold
        )
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.iconSize),
            heightAnchor.constraint(equalToConstant: NativePaperCodexActionMetrics.iconSize),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16)
        ])
        updateAppearance()
    }

    @objc private func performPress() {
        guard !isDisabled else {
            return
        }
        pressHandler()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let tint = tintColor
        let foreground: NSColor
        let background: NSColor
        let border: NSColor
        let shadowOpacity: Float

        if isDisabled {
            foreground = .secondaryLabelColor.withAlphaComponent(0.45)
            background = .controlBackgroundColor.withAlphaComponent(0.40)
            border = .clear
            shadowOpacity = 0
        } else if isPressed {
            foreground = tint
            background = tint.withAlphaComponent(0.20)
            border = tint.withAlphaComponent(0.52)
            shadowOpacity = 0.10
        } else if isHovering {
            foreground = tint
            background = tint.withAlphaComponent(0.13)
            border = tint.withAlphaComponent(0.38)
            shadowOpacity = 0.14
        } else {
            foreground = tint.withAlphaComponent(0.78)
            background = .clear
            border = .clear
            shadowOpacity = 0
        }

        iconView.contentTintColor = foreground
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = border == .clear ? 0 : 1
        layer?.borderColor = border.cgColor
        layer?.shadowColor = tint.cgColor
        layer?.shadowOpacity = shadowOpacity
        layer?.shadowRadius = isPressed ? 3 : 6
        layer?.shadowOffset = CGSize(width: 0, height: isPressed ? -1 : -2)

        let targetScale: CGFloat
        if reduceMotion || isDisabled {
            targetScale = 1
        } else if isPressed {
            targetScale = 0.965
        } else {
            targetScale = isHovering ? 1.025 : 1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
    }
}
