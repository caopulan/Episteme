import AppKit
import PaperCodexCore
import SwiftUI

struct ChatComposerNativePanelView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var isSending: Bool
    var canSubmit: Bool
    var textHeight: CGFloat
    var fontSize: Double
    var fontFamily: ChatFontFamily
    var focusRequestID: UUID?
    var prompts: [QuickPrompt]
    var runtimeProfiles: [AgentRuntimeProfile]
    var selectedRuntimeID: String
    var runtimeName: String
    var diagnostic: AgentRuntimeDiagnostic?
    var authSummary: String
    var modelOverride: String
    var availableModelIDs: [String]
    var defaultModelID: String
    var reasoningEffort: CodexReasoningEffort
    var onPrompt: (QuickPrompt) -> Void
    var onRuntime: (String) -> Void
    var onModelOverride: (String) -> Void
    var onReasoningEffort: (CodexReasoningEffort) -> Void
    var onRefresh: () -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ChatComposerContainerView {
        let composerView = ChatComposerContainerView()
        context.coordinator.parent = self
        composerView.connectTargets(to: context.coordinator)
        composerView.apply(self, coordinator: context.coordinator)
        return composerView
    }

    func updateNSView(_ composerView: ChatComposerContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdatingFromSwiftUI = true
        composerView.apply(self, coordinator: context.coordinator)
        context.coordinator.isUpdatingFromSwiftUI = false
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatComposerNativePanelView?
        var isUpdatingFromSwiftUI = false
        private var lastHandledFocusRequestID: UUID?

        @objc func quickPromptChanged(_ sender: NSPopUpButton) {
            guard !isUpdatingFromSwiftUI,
                  let parent,
                  let promptID = sender.selectedItem?.representedObject as? String,
                  let prompt = parent.prompts.first(where: { $0.id == promptID }) else {
                sender.selectItem(at: 0)
                return
            }
            parent.onPrompt(prompt)
            sender.selectItem(at: 0)
        }

        @objc func runtimeChanged(_ sender: NSPopUpButton) {
            guard !isUpdatingFromSwiftUI,
                  let runtimeID = sender.selectedItem?.representedObject as? String else {
                return
            }
            parent?.onRuntime(runtimeID)
        }

        @objc func modelChanged(_ sender: NSPopUpButton) {
            guard !isUpdatingFromSwiftUI,
                  let override = sender.selectedItem?.representedObject as? String else {
                return
            }
            parent?.onModelOverride(override)
        }

        @objc func reasoningChanged(_ sender: NSPopUpButton) {
            guard !isUpdatingFromSwiftUI,
                  let rawValue = sender.selectedItem?.representedObject as? String,
                  let effort = CodexReasoningEffort(rawValue: rawValue) else {
                return
            }
            parent?.onReasoningEffort(effort)
        }

        @objc func compatibleModelPressed(_ sender: NSButton) {
            parent?.onModelOverride("gpt-5.4-mini")
        }

        @objc func refreshPressed(_ sender: NSButton) {
            parent?.onRefresh()
        }

        @objc func sendPressed(_ sender: NSButton) {
            guard let parent else {
                return
            }
            if parent.isSending {
                parent.onCancel()
            } else {
                parent.onSubmit()
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            parent?.text = textView.string
        }

        func submit() {
            guard let parent else {
                return
            }
            if parent.isSending {
                parent.onCancel()
            } else {
                parent.onSubmit()
            }
        }

        func focusIfNeeded(_ textView: NativeChatInputTextView, focusRequestID: UUID?) {
            guard let focusRequestID, focusRequestID != lastHandledFocusRequestID else {
                return
            }
            lastHandledFocusRequestID = focusRequestID
            DispatchQueue.main.async { [weak textView] in
                guard let textView else {
                    return
                }
                textView.window?.makeFirstResponder(textView)
                let insertionPoint = NSRange(location: textView.string.utf16.count, length: 0)
                textView.setSelectedRange(insertionPoint)
                textView.scrollRangeToVisible(insertionPoint)
            }
        }
    }
}

final class ChatComposerContainerView: NSView {
    let quickPromptPopup = NSPopUpButton(frame: .zero, pullsDown: true)
    let runtimePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let reasoningPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let compatibleModelButton = NSButton(title: localized("Use gpt-5.4-mini"), target: nil, action: nil)
    let refreshButton = NSButton(title: "", target: nil, action: nil)
    let sendButton = NSButton(title: "", target: nil, action: nil)
    let inputScrollView = NSScrollView()
    let inputTextView = NativeChatInputTextView()

    private let toolbarStack = NSStackView()
    private let inputStack = NSStackView()
    private let statusIconView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let rootStack = NSStackView()
    private var inputHeightConstraint: NSLayoutConstraint?

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

    func connectTargets(to coordinator: ChatComposerNativePanelView.Coordinator) {
        quickPromptPopup.target = coordinator
        quickPromptPopup.action = #selector(ChatComposerNativePanelView.Coordinator.quickPromptChanged(_:))
        runtimePopup.target = coordinator
        runtimePopup.action = #selector(ChatComposerNativePanelView.Coordinator.runtimeChanged(_:))
        modelPopup.target = coordinator
        modelPopup.action = #selector(ChatComposerNativePanelView.Coordinator.modelChanged(_:))
        reasoningPopup.target = coordinator
        reasoningPopup.action = #selector(ChatComposerNativePanelView.Coordinator.reasoningChanged(_:))
        compatibleModelButton.target = coordinator
        compatibleModelButton.action = #selector(ChatComposerNativePanelView.Coordinator.compatibleModelPressed(_:))
        refreshButton.target = coordinator
        refreshButton.action = #selector(ChatComposerNativePanelView.Coordinator.refreshPressed(_:))
        sendButton.target = coordinator
        sendButton.action = #selector(ChatComposerNativePanelView.Coordinator.sendPressed(_:))
        inputTextView.delegate = coordinator
        inputTextView.onSubmit = coordinator.submit
    }

    func apply(_ view: ChatComposerNativePanelView, coordinator: ChatComposerNativePanelView.Coordinator) {
        configureQuickPrompts(view.prompts)
        configureRuntimeProfiles(view.runtimeProfiles, selectedRuntimeID: view.selectedRuntimeID)
        configureModelChoices(
            selectedRuntimeID: view.selectedRuntimeID,
            modelOverride: view.modelOverride,
            availableModelIDs: view.availableModelIDs,
            defaultModelID: view.defaultModelID,
            diagnostic: view.diagnostic
        )
        configureReasoning(view.reasoningEffort, selectedRuntimeID: view.selectedRuntimeID)
        configureStatus(runtimeName: view.runtimeName, diagnostic: view.diagnostic, authSummary: view.authSummary)
        configureSendButton(isSending: view.isSending, canSubmit: view.canSubmit)
        inputHeightConstraint?.constant = view.textHeight

        inputTextView.isEditable = view.isEditable
        inputTextView.textColor = view.isEditable ? .labelColor : .secondaryLabelColor
        inputTextView.onSubmit = coordinator.submit
        let nsFont = view.fontFamily.nsFont(size: view.fontSize)
        inputTextView.font = nsFont
        inputTextView.typingAttributes[.font] = nsFont
        if inputTextView.string != view.text {
            inputTextView.string = view.text
        }
        coordinator.focusIfNeeded(inputTextView, focusRequestID: view.focusRequestID)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        configurePopup(quickPromptPopup, minWidth: 138)
        configurePopup(runtimePopup, minWidth: 86)
        configurePopup(modelPopup, minWidth: 102)
        configurePopup(reasoningPopup, minWidth: 96)
        configureTextButton(compatibleModelButton)
        configureIconButton(refreshButton, symbolName: "arrow.clockwise", help: Self.localized("Refresh Agent Status"))
        configureSendButtonBase()
        configureStatusViews()
        configureInputTextView()

        toolbarStack.orientation = .horizontal
        toolbarStack.alignment = .centerY
        toolbarStack.distribution = .fill
        toolbarStack.spacing = 8
        [quickPromptPopup, statusIconView, statusLabel, runtimePopup, compatibleModelButton, modelPopup, reasoningPopup, refreshButton]
            .forEach(toolbarStack.addArrangedSubview(_:))

        inputStack.orientation = .horizontal
        inputStack.alignment = .bottom
        inputStack.distribution = .fill
        inputStack.spacing = 8
        [inputScrollView, sendButton].forEach(inputStack.addArrangedSubview(_:))

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.distribution = .fill
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(toolbarStack)
        rootStack.addArrangedSubview(inputStack)
        addSubview(rootStack)

        inputHeightConstraint = inputScrollView.heightAnchor.constraint(equalToConstant: ChatComposerLayout.defaultTextHeight)
        inputHeightConstraint?.isActive = true
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            toolbarStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            inputStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 38),
            sendButton.heightAnchor.constraint(equalToConstant: 38)
        ])
    }

    private func configureQuickPrompts(_ prompts: [QuickPrompt]) {
        quickPromptPopup.removeAllItems()
        quickPromptPopup.addItem(withTitle: Self.localized("Quick Prompt"))
        quickPromptPopup.item(at: 0)?.image = Self.symbolImage(named: "text.bubble")
        for prompt in prompts {
            quickPromptPopup.addItem(withTitle: prompt.title)
            quickPromptPopup.lastItem?.representedObject = prompt.id
        }
        quickPromptPopup.selectItem(at: 0)
        quickPromptPopup.isEnabled = !prompts.isEmpty
        quickPromptPopup.toolTip = Self.localized("Quick Prompt")
        quickPromptPopup.setAccessibilityLabel(Self.localized("Quick Prompt"))
    }

    private func configureRuntimeProfiles(_ profiles: [AgentRuntimeProfile], selectedRuntimeID: String) {
        runtimePopup.removeAllItems()
        for profile in profiles {
            runtimePopup.addItem(withTitle: profile.displayName)
            runtimePopup.lastItem?.representedObject = profile.id
        }
        runtimePopup.selectItem(withRepresentedObject: selectedRuntimeID)
        runtimePopup.toolTip = selectedRuntimeID
    }

    private func configureModelChoices(
        selectedRuntimeID: String,
        modelOverride: String,
        availableModelIDs: [String],
        defaultModelID: String,
        diagnostic: AgentRuntimeDiagnostic?
    ) {
        let isCodex = selectedRuntimeID == "codex"
        modelPopup.isHidden = !isCodex
        compatibleModelButton.isHidden = !(isCodex && shouldOfferCompatibleModel(modelOverride: modelOverride, diagnostic: diagnostic))
        guard isCodex else {
            return
        }

        let trimmedOverride = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        modelPopup.removeAllItems()
        modelPopup.addItem(withTitle: defaultModelLabel(defaultModelID: defaultModelID))
        modelPopup.lastItem?.representedObject = ""
        for modelID in availableModelIDs {
            modelPopup.addItem(withTitle: modelID)
            modelPopup.lastItem?.representedObject = modelID
        }
        modelPopup.selectItem(withRepresentedObject: trimmedOverride)
        if modelPopup.selectedItem == nil {
            modelPopup.selectItem(at: 0)
        }
        modelPopup.toolTip = modelLabel(modelOverride: modelOverride, defaultModelID: defaultModelID)
    }

    private func configureReasoning(_ reasoningEffort: CodexReasoningEffort, selectedRuntimeID: String) {
        let isCodex = selectedRuntimeID == "codex"
        reasoningPopup.isHidden = !isCodex
        guard isCodex else {
            return
        }

        reasoningPopup.removeAllItems()
        for effort in CodexReasoningEffort.allCases {
            reasoningPopup.addItem(withTitle: reasoningLabel(effort))
            reasoningPopup.lastItem?.representedObject = effort.rawValue
        }
        reasoningPopup.selectItem(withRepresentedObject: reasoningEffort.rawValue)
    }

    private func configureStatus(runtimeName: String, diagnostic: AgentRuntimeDiagnostic?, authSummary: String) {
        statusIconView.image = Self.symbolImage(named: iconName(for: diagnostic))
        statusIconView.contentTintColor = tint(for: diagnostic)
        statusLabel.stringValue = title(runtimeName: runtimeName, diagnostic: diagnostic)
        let detail = "\(diagnostic?.detail ?? Self.localized("Checking local agent runtime."))\n\(authSummary)"
        [statusIconView, statusLabel, runtimePopup, modelPopup, reasoningPopup, refreshButton].forEach {
            $0.toolTip = detail
        }
    }

    private func configureSendButton(isSending: Bool, canSubmit: Bool) {
        sendButton.isEnabled = canSubmit
        sendButton.image = Self.symbolImage(named: isSending ? "xmark.circle.fill" : "arrow.up.circle.fill")
        sendButton.contentTintColor = canSubmit ? (isSending ? .systemRed : .controlAccentColor) : .secondaryLabelColor
        let help = Self.localized(isSending ? "Stop Agent" : "Send")
        sendButton.toolTip = help
        sendButton.setAccessibilityLabel(help)
    }

    private func configurePopup(_ popup: NSPopUpButton, minWidth: CGFloat) {
        popup.controlSize = .small
        popup.bezelStyle = .rounded
        popup.setContentHuggingPriority(.required, for: .horizontal)
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
    }

    private func configureTextButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.toolTip = button.title
        button.setAccessibilityLabel(button.title)
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, help: String) {
        button.title = ""
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.image = Self.symbolImage(named: symbolName)
        button.imagePosition = .imageOnly
        button.toolTip = help
        button.setAccessibilityLabel(help)
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureSendButtonBase() {
        sendButton.title = ""
        sendButton.bezelStyle = .circular
        sendButton.controlSize = .large
        sendButton.imagePosition = .imageOnly
        sendButton.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureStatusViews() {
        statusIconView.imageScaling = .scaleProportionallyDown
        statusIconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func configureInputTextView() {
        inputScrollView.borderType = .noBorder
        inputScrollView.hasVerticalScroller = true
        inputScrollView.drawsBackground = true
        inputScrollView.backgroundColor = .textBackgroundColor
        inputScrollView.autohidesScrollers = true
        inputScrollView.wantsLayer = true
        inputScrollView.layer?.cornerRadius = 8
        inputScrollView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        inputScrollView.layer?.borderWidth = 1

        inputTextView.isRichText = false
        inputTextView.isAutomaticQuoteSubstitutionEnabled = false
        inputTextView.isAutomaticDashSubstitutionEnabled = false
        inputTextView.isAutomaticTextReplacementEnabled = false
        inputTextView.textContainerInset = NSSize(width: 8, height: 8)
        inputTextView.drawsBackground = false
        inputTextView.minSize = NSSize(width: 0, height: ChatComposerLayout.minimumTextHeight)
        inputTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.isVerticallyResizable = true
        inputTextView.isHorizontallyResizable = false
        inputTextView.autoresizingMask = [.width]
        inputTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.textContainer?.widthTracksTextView = true
        inputTextView.setAccessibilityLabel(Self.localized("Chat input"))
        inputScrollView.documentView = inputTextView
    }

    private func title(runtimeName: String, diagnostic: AgentRuntimeDiagnostic?) -> String {
        guard let diagnostic else {
            return String(format: Self.localized("Checking %@"), runtimeName)
        }
        if let version = diagnostic.version {
            return "\(diagnostic.title) · \(version)"
        }
        return diagnostic.title
    }

    private func modelLabel(modelOverride: String, defaultModelID: String) -> String {
        let trimmed = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultModelLabel(defaultModelID: defaultModelID) : trimmed
    }

    private func defaultModelLabel(defaultModelID: String) -> String {
        let trimmed = defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.localized("Default") : "\(Self.localized("Default")) (\(trimmed))"
    }

    private func reasoningLabel(_ effort: CodexReasoningEffort) -> String {
        "\(Self.localized("Think")) \(effort.displayName)"
    }

    private func shouldOfferCompatibleModel(modelOverride: String, diagnostic: AgentRuntimeDiagnostic?) -> Bool {
        diagnostic?.title == "Codex model incompatible"
            && modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func iconName(for diagnostic: AgentRuntimeDiagnostic?) -> String {
        guard let diagnostic else {
            return "circle.dotted"
        }
        switch diagnostic.state {
        case .checking:
            return "clock"
        case .ready:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .blocked:
            return "xmark.circle.fill"
        }
    }

    private func tint(for diagnostic: AgentRuntimeDiagnostic?) -> NSColor {
        guard let diagnostic else {
            return .secondaryLabelColor
        }
        switch diagnostic.state {
        case .checking:
            return .secondaryLabelColor
        case .ready:
            return .systemGreen
        case .warning:
            return .systemOrange
        case .blocked:
            return .systemRed
        }
    }

    private static func symbolImage(named name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        return image?.withSymbolConfiguration(configuration)
    }

    static func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

final class NativeChatInputTextView: NSTextView {
    var onSubmit: (() -> Void)?

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
}

private extension NSPopUpButton {
    func selectItem(withRepresentedObject representedObject: String) {
        guard let item = itemArray.first(where: { ($0.representedObject as? String) == representedObject }) else {
            return
        }
        select(item)
    }
}
