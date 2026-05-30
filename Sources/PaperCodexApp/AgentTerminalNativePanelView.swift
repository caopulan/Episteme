import AppKit
import PaperCodexCore
import SwiftUI

struct AgentTerminalNativePanelView: NSViewRepresentable {
    var state: AgentTerminalState?
    var runtimeProfiles: [AgentRuntimeProfile]
    var selectedRuntimeID: String
    var selectedRuntimeDisplayName: String
    var canLaunch: Bool
    @Binding var inputDraft: String
    @Binding var requestedColumns: Int
    @Binding var requestedRows: Int
    var onSelectRuntime: (String) -> Void
    var onStart: (Int, Int) -> Void
    var onStop: () -> Void
    var onResize: (Int, Int) -> Void
    var onSend: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AgentTerminalContainerView {
        let panelView = AgentTerminalContainerView()
        context.coordinator.parent = self
        panelView.connectTargets(to: context.coordinator)
        panelView.apply(self)
        return panelView
    }

    func updateNSView(_ panelView: AgentTerminalContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdatingFromSwiftUI = true
        panelView.apply(self)
        context.coordinator.isUpdatingFromSwiftUI = false
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AgentTerminalNativePanelView?
        var isUpdatingFromSwiftUI = false

        @objc func runtimeSelectionChanged(_ sender: NSPopUpButton) {
            guard !isUpdatingFromSwiftUI,
                  let runtimeID = sender.selectedItem?.representedObject as? String else {
                return
            }
            parent?.onSelectRuntime(runtimeID)
        }

        @objc func columnsChanged(_ sender: NSStepper) {
            guard !isUpdatingFromSwiftUI else {
                return
            }
            parent?.requestedColumns = sender.integerValue
            resizeIfRunning()
        }

        @objc func rowsChanged(_ sender: NSStepper) {
            guard !isUpdatingFromSwiftUI else {
                return
            }
            parent?.requestedRows = sender.integerValue
            resizeIfRunning()
        }

        @objc func resizePressed(_ sender: NSButton) {
            guard let parent else {
                return
            }
            parent.onResize(parent.requestedColumns, parent.requestedRows)
        }

        @objc func startStopPressed(_ sender: NSButton) {
            guard let parent else {
                return
            }
            if parent.state?.isRunning == true {
                parent.onStop()
            } else {
                parent.onStart(parent.requestedColumns, parent.requestedRows)
            }
        }

        @objc func sendPressed(_ sender: NSButton) {
            sendCurrentInput()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            parent?.inputDraft = textView.string
        }

        func sendCurrentInput() {
            guard let parent else {
                return
            }
            let trimmed = parent.inputDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }
            parent.onSend(parent.inputDraft)
            parent.inputDraft = ""
        }

        private func resizeIfRunning() {
            guard let parent, parent.state?.isRunning == true else {
                return
            }
            parent.onResize(parent.requestedColumns, parent.requestedRows)
        }
    }
}

final class AgentTerminalContainerView: NSView {
    let runtimePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let columnsStepper = NSStepper()
    let rowsStepper = NSStepper()
    let outputTextView = NSTextView()
    let inputTextView = TerminalInputTextView()
    let sendButton = NSButton(title: "", target: nil, action: nil)
    let startStopButton = NSButton(title: "", target: nil, action: nil)

    private let toolbarContainer = NSView()
    private let toolbarStack = NSStackView()
    private let statusImageView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let logLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let resizeButton = NSButton(title: "", target: nil, action: nil)
    private let outputScrollView = NSScrollView()
    private let inputContainer = NSView()
    private let inputStack = NSStackView()
    private let inputScrollView = NSScrollView()
    private let topSeparator = NSBox()
    private let bottomSeparator = NSBox()

    private var lastRenderedOutput = ""

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

    func connectTargets(to coordinator: AgentTerminalNativePanelView.Coordinator) {
        runtimePopup.target = coordinator
        runtimePopup.action = #selector(AgentTerminalNativePanelView.Coordinator.runtimeSelectionChanged(_:))
        columnsStepper.target = coordinator
        columnsStepper.action = #selector(AgentTerminalNativePanelView.Coordinator.columnsChanged(_:))
        rowsStepper.target = coordinator
        rowsStepper.action = #selector(AgentTerminalNativePanelView.Coordinator.rowsChanged(_:))
        resizeButton.target = coordinator
        resizeButton.action = #selector(AgentTerminalNativePanelView.Coordinator.resizePressed(_:))
        startStopButton.target = coordinator
        startStopButton.action = #selector(AgentTerminalNativePanelView.Coordinator.startStopPressed(_:))
        sendButton.target = coordinator
        sendButton.action = #selector(AgentTerminalNativePanelView.Coordinator.sendPressed(_:))
        inputTextView.delegate = coordinator
        inputTextView.onSubmit = coordinator.sendCurrentInput
    }

    func apply(_ view: AgentTerminalNativePanelView) {
        rebuildRuntimeItems(
            profiles: view.runtimeProfiles.filter(\.supportsPTY),
            selectedRuntimeID: view.selectedRuntimeID,
            fallbackTitle: view.selectedRuntimeDisplayName
        )
        applyTerminalState(view.state, canLaunch: view.canLaunch)
        applySize(columns: view.requestedColumns, rows: view.requestedRows)
        applyOutput(view.state?.output ?? "")
        applyInput(view.inputDraft, isEnabled: view.state?.isRunning == true)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        configureToolbar()
        configureOutput()
        configureInputBar()
        configureSeparator(topSeparator)
        configureSeparator(bottomSeparator)

        [toolbarContainer, topSeparator, outputScrollView, bottomSeparator, inputContainer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            toolbarContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbarContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbarContainer.topAnchor.constraint(equalTo: topAnchor),
            toolbarContainer.heightAnchor.constraint(equalToConstant: 40),

            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparator.topAnchor.constraint(equalTo: toolbarContainer.bottomAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 1),

            outputScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            outputScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            outputScrollView.topAnchor.constraint(equalTo: topSeparator.bottomAnchor),
            outputScrollView.bottomAnchor.constraint(equalTo: bottomSeparator.topAnchor),

            bottomSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomSeparator.bottomAnchor.constraint(equalTo: inputContainer.topAnchor),
            bottomSeparator.heightAnchor.constraint(equalToConstant: 1),

            inputContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            inputContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 70)
        ])
    }

    private func configureToolbar() {
        toolbarContainer.wantsLayer = true
        toolbarContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        toolbarStack.orientation = .horizontal
        toolbarStack.alignment = .centerY
        toolbarStack.distribution = .fill
        toolbarStack.spacing = 8
        toolbarStack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        toolbarStack.detachesHiddenViews = true
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false

        statusImageView.imageScaling = .scaleProportionallyDown
        statusImageView.setContentHuggingPriority(.required, for: .horizontal)
        statusImageView.widthAnchor.constraint(equalToConstant: 18).isActive = true

        runtimePopup.controlSize = .small
        runtimePopup.bezelStyle = .rounded
        runtimePopup.toolTip = Self.localized("Agent Runtime")
        runtimePopup.setAccessibilityLabel(Self.localized("Agent Runtime"))
        runtimePopup.setContentHuggingPriority(.required, for: .horizontal)

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)

        logLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        logLabel.textColor = .tertiaryLabelColor
        logLabel.lineBreakMode = .byTruncatingMiddle
        logLabel.maximumNumberOfLines = 1
        logLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureStepper(columnsStepper, minimum: 80, maximum: 220, increment: 10, label: Self.localized("Columns"))
        configureStepper(rowsStepper, minimum: 20, maximum: 80, increment: 4, label: Self.localized("Rows"))

        sizeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.alignment = .right
        sizeLabel.widthAnchor.constraint(equalToConstant: 58).isActive = true

        configureIconButton(resizeButton, symbolName: "arrow.up.left.and.arrow.down.right", help: Self.localized("Resize Terminal"))
        configureTextButton(startStopButton, help: Self.localized("Start Terminal"))

        toolbarContainer.addSubview(toolbarStack)
        [
            statusImageView,
            runtimePopup,
            statusLabel,
            logLabel,
            NSView(),
            columnsStepper,
            sizeLabel,
            rowsStepper,
            resizeButton,
            startStopButton
        ].forEach(toolbarStack.addArrangedSubview(_:))

        NSLayoutConstraint.activate([
            toolbarStack.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor),
            toolbarStack.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor),
            toolbarStack.topAnchor.constraint(equalTo: toolbarContainer.topAnchor),
            toolbarStack.bottomAnchor.constraint(equalTo: toolbarContainer.bottomAnchor),
            runtimePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 112)
        ])
    }

    private func configureOutput() {
        outputScrollView.borderType = .noBorder
        outputScrollView.hasVerticalScroller = true
        outputScrollView.drawsBackground = true
        outputScrollView.backgroundColor = .textBackgroundColor
        outputScrollView.autohidesScrollers = true

        outputTextView.isEditable = false
        outputTextView.isSelectable = true
        outputTextView.isRichText = false
        outputTextView.drawsBackground = false
        outputTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        outputTextView.textColor = .labelColor
        outputTextView.textContainerInset = NSSize(width: 12, height: 12)
        outputTextView.minSize = NSSize(width: 0, height: 0)
        outputTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        outputTextView.isVerticallyResizable = true
        outputTextView.isHorizontallyResizable = false
        outputTextView.autoresizingMask = [.width]
        outputTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        outputTextView.textContainer?.widthTracksTextView = true
        outputTextView.setAccessibilityLabel(Self.localized("Terminal output"))

        outputScrollView.documentView = outputTextView
    }

    private func configureInputBar() {
        inputContainer.wantsLayer = true
        inputContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        inputStack.orientation = .horizontal
        inputStack.alignment = .centerY
        inputStack.distribution = .fill
        inputStack.spacing = 8
        inputStack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        inputStack.translatesAutoresizingMaskIntoConstraints = false

        inputScrollView.borderType = .noBorder
        inputScrollView.hasVerticalScroller = true
        inputScrollView.drawsBackground = true
        inputScrollView.backgroundColor = .textBackgroundColor
        inputScrollView.autohidesScrollers = true
        inputScrollView.wantsLayer = true
        inputScrollView.layer?.cornerRadius = 6
        inputScrollView.layer?.borderColor = NSColor.separatorColor.cgColor
        inputScrollView.layer?.borderWidth = 1

        inputTextView.isRichText = false
        inputTextView.isAutomaticQuoteSubstitutionEnabled = false
        inputTextView.isAutomaticDashSubstitutionEnabled = false
        inputTextView.isAutomaticTextReplacementEnabled = false
        inputTextView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        inputTextView.drawsBackground = false
        inputTextView.textContainerInset = NSSize(width: 8, height: 8)
        inputTextView.minSize = NSSize(width: 0, height: 48)
        inputTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.isVerticallyResizable = true
        inputTextView.isHorizontallyResizable = false
        inputTextView.autoresizingMask = [.width]
        inputTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.textContainer?.widthTracksTextView = true
        inputTextView.placeholder = Self.localized("Terminal input")
        inputTextView.setAccessibilityLabel(Self.localized("Terminal input"))

        inputScrollView.documentView = inputTextView

        configureIconButton(sendButton, symbolName: "arrow.turn.down.left", help: Self.localized("Send Input"))
        sendButton.keyEquivalent = "\r"
        sendButton.keyEquivalentModifierMask = [.command]
        sendButton.setContentHuggingPriority(.required, for: .horizontal)

        inputContainer.addSubview(inputStack)
        [inputScrollView, sendButton].forEach(inputStack.addArrangedSubview(_:))

        NSLayoutConstraint.activate([
            inputStack.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            inputStack.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            inputStack.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            inputStack.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),
            inputScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            sendButton.widthAnchor.constraint(equalToConstant: 34),
            sendButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func configureSeparator(_ separator: NSBox) {
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
    }

    private func rebuildRuntimeItems(profiles: [AgentRuntimeProfile], selectedRuntimeID: String, fallbackTitle: String) {
        let existingIDs = runtimePopup.itemArray.compactMap { $0.representedObject as? String }
        let nextIDs = profiles.map(\.id)
        if existingIDs != nextIDs || runtimePopup.numberOfItems != profiles.count {
            runtimePopup.removeAllItems()
            for profile in profiles {
                let item = NSMenuItem(title: profile.displayName, action: nil, keyEquivalent: "")
                item.representedObject = profile.id
                item.image = Self.symbolImage(named: "terminal")
                runtimePopup.menu?.addItem(item)
            }
        }

        if let item = runtimePopup.itemArray.first(where: { ($0.representedObject as? String) == selectedRuntimeID }) {
            runtimePopup.select(item)
            runtimePopup.toolTip = "\(Self.localized("Agent Runtime")): \(item.title)"
        } else if runtimePopup.numberOfItems == 0 {
            runtimePopup.addItem(withTitle: fallbackTitle)
            runtimePopup.lastItem?.representedObject = selectedRuntimeID
            runtimePopup.select(runtimePopup.lastItem)
        }
    }

    private func applyTerminalState(_ state: AgentTerminalState?, canLaunch: Bool) {
        let isRunning = state?.isRunning == true
        runtimePopup.isEnabled = !isRunning
        columnsStepper.isEnabled = true
        rowsStepper.isEnabled = true
        resizeButton.isEnabled = isRunning
        startStopButton.isEnabled = isRunning || canLaunch
        sendButton.isEnabled = isRunning && !inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if isRunning {
            statusImageView.image = Self.symbolImage(named: "terminal.fill", pointSize: 14)
            statusLabel.stringValue = Self.localized("Running")
            statusLabel.textColor = .systemGreen
            configureTextButton(startStopButton, symbolName: "stop.fill", title: Self.localized("Stop"), help: Self.localized("Stop Terminal"))
        } else {
            statusImageView.image = Self.symbolImage(named: "terminal", pointSize: 14)
            statusLabel.stringValue = canLaunch ? Self.localized("Stopped") : Self.localized("Terminal unavailable")
            statusLabel.textColor = canLaunch ? .secondaryLabelColor : .systemOrange
            configureTextButton(startStopButton, symbolName: "play.fill", title: Self.localized("Start"), help: Self.localized("Start Terminal"))
        }

        if let state {
            logLabel.stringValue = state.logPath
            logLabel.toolTip = state.logPath
            logLabel.isHidden = false
        } else {
            logLabel.stringValue = ""
            logLabel.toolTip = nil
            logLabel.isHidden = true
        }
    }

    private func applySize(columns: Int, rows: Int) {
        columnsStepper.integerValue = columns
        rowsStepper.integerValue = rows
        sizeLabel.stringValue = "\(columns)x\(rows)"
        sizeLabel.setAccessibilityValue(sizeLabel.stringValue)
    }

    private func applyOutput(_ output: String) {
        let renderedOutput = output.isEmpty ? " " : output
        guard renderedOutput != lastRenderedOutput else {
            return
        }
        lastRenderedOutput = renderedOutput
        outputTextView.string = renderedOutput
        let endRange = NSRange(location: outputTextView.string.utf16.count, length: 0)
        outputTextView.scrollRangeToVisible(endRange)
    }

    private func applyInput(_ input: String, isEnabled: Bool) {
        inputTextView.isEditable = isEnabled
        inputTextView.textColor = isEnabled ? .labelColor : .secondaryLabelColor
        if inputTextView.string != input {
            inputTextView.string = input
            inputTextView.needsDisplay = true
        }
        sendButton.isEnabled = isEnabled && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func configureStepper(_ stepper: NSStepper, minimum: Double, maximum: Double, increment: Double, label: String) {
        stepper.minValue = minimum
        stepper.maxValue = maximum
        stepper.increment = increment
        stepper.controlSize = .small
        stepper.setAccessibilityLabel(label)
        stepper.toolTip = label
        stepper.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, help: String) {
        button.title = ""
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.image = Self.symbolImage(named: symbolName)
        button.toolTip = help
        button.setAccessibilityLabel(help)
    }

    private func configureTextButton(_ button: NSButton, symbolName: String? = nil, title: String = "", help: String) {
        button.title = title
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.image = symbolName.flatMap { Self.symbolImage(named: $0) }
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.toolTip = help
        button.setAccessibilityLabel(help)
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private static func symbolImage(named name: String, pointSize: CGFloat = 13) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        return image?.withSymbolConfiguration(configuration)
    }

    static func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

final class TerminalInputTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var placeholder = "" {
        didSet {
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, !event.modifierFlags.contains(.shift) {
            if hasMarkedText() {
                super.keyDown(with: event)
                return
            }
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else {
            return
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        let origin = NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height + 1)
        placeholder.draw(at: origin, withAttributes: attributes)
    }
}
