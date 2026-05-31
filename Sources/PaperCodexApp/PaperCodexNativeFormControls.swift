import AppKit
import SwiftUI

struct PaperCodexNativePopupItem: Hashable, Identifiable {
    var id: String { value }
    var title: String
    var value: String

    init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}

struct PaperCodexNativeTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat = 13
    var focusRequestID: UUID?
    var isActiveForFocus = false
    var onSubmit: () -> Void = {}

    func makeCoordinator() -> PaperCodexNativeTextFieldCoordinator {
        PaperCodexNativeTextFieldCoordinator(self)
    }

    func makeNSView(context: Context) -> PaperCodexNativeTextFieldView {
        let textField = PaperCodexNativeTextFieldView()
        context.coordinator.parent = self
        context.coordinator.lastFocusRequestID = focusRequestID
        textField.delegate = context.coordinator
        textField.apply(text: text, placeholder: placeholder, fontSize: fontSize)
        return textField
    }

    func updateNSView(_ textField: PaperCodexNativeTextFieldView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdatingFromSwiftUI = true
        textField.apply(text: text, placeholder: placeholder, fontSize: fontSize)
        context.coordinator.isUpdatingFromSwiftUI = false
        context.coordinator.applyFocusIfNeeded(to: textField)
    }
}

@MainActor final class PaperCodexNativeTextFieldCoordinator: NSObject, NSTextFieldDelegate {
    var parent: PaperCodexNativeTextField
    var isUpdatingFromSwiftUI = false
    var lastFocusRequestID: UUID?

    init(_ parent: PaperCodexNativeTextField) {
        self.parent = parent
        super.init()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !isUpdatingFromSwiftUI,
              let textField = notification.object as? NSTextField else {
            return
        }
        parent.text = textField.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
            return false
        }
        parent.onSubmit()
        return true
    }

    func applyFocusIfNeeded(to textField: PaperCodexNativeTextFieldView) {
        guard let focusRequestID = parent.focusRequestID,
              focusRequestID != lastFocusRequestID else {
            return
        }
        lastFocusRequestID = focusRequestID
        guard parent.isActiveForFocus else {
            return
        }
        textField.window?.makeFirstResponder(textField)
    }
}

final class PaperCodexNativeTextFieldView: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 30)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(text: String, placeholder: String, fontSize: CGFloat) {
        let fieldEditorHasMarkedText = (currentEditor() as? NSTextView)?.hasMarkedText() == true
        if stringValue != text && !fieldEditorHasMarkedText {
            stringValue = text
        }
        placeholderString = placeholder
        toolTip = placeholder
        setAccessibilityLabel(placeholder)
        font = .systemFont(ofSize: fontSize)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        controlSize = .regular
        isBordered = true
        isBezeled = true
        bezelStyle = .roundedBezel
        focusRingType = .default
        usesSingleLineMode = true
        lineBreakMode = .byTruncatingTail
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}

struct PaperCodexNativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var accessibilityLabel: String
    var font: NSFont = .systemFont(ofSize: 13)
    var minHeight: CGFloat = 96
    var focusRequestID: UUID?
    var isActiveForFocus = false

    func makeCoordinator() -> PaperCodexNativeTextEditorCoordinator {
        PaperCodexNativeTextEditorCoordinator(self)
    }

    func makeNSView(context: Context) -> PaperCodexNativeTextEditorContainerView {
        let container = PaperCodexNativeTextEditorContainerView()
        context.coordinator.parent = self
        context.coordinator.lastFocusRequestID = focusRequestID
        container.textView.delegate = context.coordinator
        container.apply(text: text, accessibilityLabel: accessibilityLabel, font: font, minHeight: minHeight)
        return container
    }

    func updateNSView(_ container: PaperCodexNativeTextEditorContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdatingFromSwiftUI = true
        container.apply(text: text, accessibilityLabel: accessibilityLabel, font: font, minHeight: minHeight)
        context.coordinator.isUpdatingFromSwiftUI = false
        context.coordinator.applyFocusIfNeeded(to: container)
    }
}

@MainActor final class PaperCodexNativeTextEditorCoordinator: NSObject, NSTextViewDelegate {
    var parent: PaperCodexNativeTextEditor
    var isUpdatingFromSwiftUI = false
    var lastFocusRequestID: UUID?

    init(_ parent: PaperCodexNativeTextEditor) {
        self.parent = parent
        super.init()
    }

    func textDidChange(_ notification: Notification) {
        guard !isUpdatingFromSwiftUI,
              let textView = notification.object as? NSTextView else {
            return
        }
        parent.text = textView.string
    }

    func applyFocusIfNeeded(to container: PaperCodexNativeTextEditorContainerView) {
        guard let focusRequestID = parent.focusRequestID,
              focusRequestID != lastFocusRequestID else {
            return
        }
        lastFocusRequestID = focusRequestID
        guard parent.isActiveForFocus else {
            return
        }
        container.window?.makeFirstResponder(container.textView)
    }
}

final class PaperCodexNativeTextEditorContainerView: NSView {
    let textView = NSTextView()
    private let scrollView = NSScrollView()
    private var heightConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: heightConstraint?.constant ?? 96)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(text: String, accessibilityLabel: String, font: NSFont, minHeight: CGFloat) {
        if textView.string != text && !textView.hasMarkedText() {
            textView.string = text
        }
        textView.font = font
        textView.setAccessibilityLabel(accessibilityLabel)
        scrollView.setAccessibilityLabel(accessibilityLabel)
        heightConstraint?.constant = minHeight
        invalidateIntrinsicContentSize()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 7)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        addSubview(scrollView)
        let heightConstraint = heightAnchor.constraint(equalToConstant: 96)
        self.heightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            heightConstraint,
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}

struct PaperCodexNativePopupButton: NSViewRepresentable {
    @Binding var selection: String
    var items: [PaperCodexNativePopupItem]
    var accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> PaperCodexNativePopupButtonView {
        let popup = PaperCodexNativePopupButtonView()
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        popup.apply(items: items, selection: selection, accessibilityLabel: accessibilityLabel)
        return popup
    }

    func updateNSView(_ popup: PaperCodexNativePopupButtonView, context: Context) {
        context.coordinator.selection = $selection
        popup.apply(items: items, selection: selection, accessibilityLabel: accessibilityLabel)
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<String>

        init(selection: Binding<String>) {
            self.selection = selection
            super.init()
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let value = sender.selectedItem?.representedObject as? String else {
                return
            }
            selection.wrappedValue = value
        }
    }
}

final class PaperCodexNativePopupButtonView: NSPopUpButton {
    private var itemValues: [String] = []

    init() {
        super.init(frame: .zero, pullsDown: false)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 30)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(items: [PaperCodexNativePopupItem], selection: String, accessibilityLabel: String) {
        let values = items.map(\.value)
        if values != itemValues || numberOfItems != items.count {
            removeAllItems()
            for item in items {
                addItem(withTitle: item.title)
                lastItem?.representedObject = item.value
            }
            itemValues = values
        }

        if let index = values.firstIndex(of: selection) {
            selectItem(at: index)
        } else if !items.isEmpty {
            selectItem(at: 0)
        }
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityValue(selectedItem?.title ?? "")
        toolTip = selectedItem?.title
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        controlSize = .regular
        font = .systemFont(ofSize: 13)
        focusRingType = .default
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}

struct PaperCodexNativeCheckboxRow: NSViewRepresentable {
    @Binding var isOn: Bool
    var title: String
    var indentation: CGFloat = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(isOn: $isOn)
    }

    func makeNSView(context: Context) -> PaperCodexNativeCheckboxRowView {
        let row = PaperCodexNativeCheckboxRowView()
        row.apply(title: title, isOn: isOn, indentation: indentation) { value in
            context.coordinator.selectionChanged(value)
        }
        return row
    }

    func updateNSView(_ row: PaperCodexNativeCheckboxRowView, context: Context) {
        context.coordinator.isOn = $isOn
        row.apply(title: title, isOn: isOn, indentation: indentation) { value in
            context.coordinator.selectionChanged(value)
        }
    }

    @MainActor final class Coordinator: NSObject {
        var isOn: Binding<Bool>

        init(isOn: Binding<Bool>) {
            self.isOn = isOn
            super.init()
        }

        func selectionChanged(_ value: Bool) {
            isOn.wrappedValue = value
        }
    }
}

final class PaperCodexNativeCheckboxRowView: NSView {
    private let checkbox = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private var titleLeadingConstraint: NSLayoutConstraint?
    private var currentIsOn = false
    private var toggleHandler: (Bool) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 26)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        setSelected(!currentIsOn, notify: true)
    }

    func apply(title: String, isOn: Bool, indentation: CGFloat, onToggle: @escaping (Bool) -> Void) {
        currentIsOn = isOn
        toggleHandler = onToggle
        checkbox.state = isOn ? .on : .off
        checkbox.setAccessibilityLabel(title)
        checkbox.setAccessibilityValue(isOn ? "Selected" : "Not selected")
        titleLabel.stringValue = title
        titleLeadingConstraint?.constant = 6 + indentation
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.title = ""
        checkbox.isBordered = false
        checkbox.controlSize = .regular
        checkbox.focusRingType = .default
        checkbox.setButtonType(.switch)
        checkbox.setAccessibilityElement(true)
        checkbox.setAccessibilityRole(.checkBox)
        checkbox.target = self
        checkbox.action = #selector(checkBoxChanged(_:))

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1

        addSubview(checkbox)
        addSubview(titleLabel)
        let titleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 6)
        self.titleLeadingConstraint = titleLeadingConstraint
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkbox.widthAnchor.constraint(equalToConstant: 18),
            checkbox.heightAnchor.constraint(equalToConstant: 18),
            titleLeadingConstraint,
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @objc private func checkBoxChanged(_ sender: NSButton) {
        setSelected(sender.state == .on, notify: true)
    }

    private func setSelected(_ selected: Bool, notify: Bool) {
        currentIsOn = selected
        checkbox.state = selected ? .on : .off
        checkbox.setAccessibilityValue(selected ? "Selected" : "Not selected")
        if notify {
            toggleHandler(selected)
        }
    }
}
