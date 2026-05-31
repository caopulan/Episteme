import AppKit
import SwiftUI

struct PaperCodexNativeEmptyState: NSViewRepresentable {
    var title: String
    var systemImage: String
    var message: String?
    var alignment: Alignment = .center

    func makeNSView(context: Context) -> NativePaperCodexEmptyStateView {
        NativePaperCodexEmptyStateView()
    }

    func updateNSView(_ view: NativePaperCodexEmptyStateView, context: Context) {
        view.apply(title: title, systemImage: systemImage, message: message, alignment: alignment)
    }
}

struct PaperCodexNativeSpinner: NSViewRepresentable {
    var controlSize: NSControl.ControlSize = .small
    var tintColor: NSColor?

    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.isIndeterminate = true
        indicator.controlSize = controlSize
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimation(nil)
        return indicator
    }

    func updateNSView(_ indicator: NSProgressIndicator, context: Context) {
        indicator.style = .spinning
        indicator.isIndeterminate = true
        indicator.controlSize = controlSize
        indicator.appearance = tintColor == nil ? nil : NSAppearance(named: .darkAqua)
        indicator.startAnimation(nil)
    }
}

struct PaperCodexNativeProgressBar: NSViewRepresentable {
    var value: Double?

    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .bar
        indicator.minValue = 0
        indicator.maxValue = 1
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }

    func updateNSView(_ indicator: NSProgressIndicator, context: Context) {
        indicator.style = .bar
        indicator.minValue = 0
        indicator.maxValue = 1
        if let value {
            indicator.isIndeterminate = false
            indicator.doubleValue = min(max(value, 0), 1)
            indicator.stopAnimation(nil)
        } else {
            indicator.isIndeterminate = true
            indicator.startAnimation(nil)
        }
    }
}

final class NativePaperCodexEmptyStateView: NSView {
    private let stackView = NSStackView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private var centerYConstraint: NSLayoutConstraint?
    private var topConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 260, height: 160)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func apply(title: String, systemImage: String, message: String?, alignment: Alignment) {
        iconView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        titleLabel.stringValue = NSLocalizedString(title, comment: "")
        messageLabel.stringValue = message.map { NSLocalizedString($0, comment: "") } ?? ""
        messageLabel.isHidden = (message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        setAccessibilityLabel(title)
        setAccessibilityValue(message)
        centerYConstraint?.isActive = alignment != .top
        topConstraint?.isActive = alignment == .top
        updateColors()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 7

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .systemFont(ofSize: 13, weight: .regular)
        messageLabel.alignment = .center
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 3

        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(messageLabel)
        addSubview(stackView)

        centerYConstraint = stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        topConstraint = stackView.topAnchor.constraint(equalTo: topAnchor, constant: 18)
        topConstraint?.isActive = false

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
        centerYConstraint?.isActive = true
        updateColors()
    }

    private func updateColors() {
        iconView.contentTintColor = .tertiaryLabelColor
        titleLabel.textColor = .secondaryLabelColor
        messageLabel.textColor = .tertiaryLabelColor
    }
}
