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
