import PaperCodexCore
import AppKit
import SwiftUI
import WebKit

private let chatComposerTextHeightDefaultsKey = "PaperCodexChatComposerTextHeight"

enum SessionPanelTab: Hashable {
    case chat
    case terminal
    case notes
}

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftsByComposerKey: [String: String] = [:]
    @State private var composerTextHeight = ChatComposerLayout.loadTextHeight()
    @State private var composerResizeStartHeight: CGFloat?
    @State private var sessionPendingRename: PaperSession?
    @State private var renameSessionTitle = ""
    @State private var selectedGeneratedImageURL: URL?
    @State private var composerFocusRequestID: UUID?
    @State private var chatScrollRequestToken = 0
    @State private var chatScrollRequestAnimated = false

    var body: some View {
        VStack(spacing: 0) {
            sessionBar
            Divider()
            selectedPanelContent
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .paperCodexNativeSheet(item: $sessionPendingRename, title: "Rename Session", minimumSize: CGSize(width: 380, height: 160)) { session in
            renameSessionSheet(session)
        }
        .task {
            await model.refreshAvailableCodexModels()
            await model.refreshAgentRuntimeDiagnostics()
        }
        .onChange(of: model.selectedSessionPanelTab) { _, tab in
            guard tab == .notes, let paper = model.selectedPaper else {
                return
            }
            model.loadPaperNotes(for: paper)
        }
        .onChange(of: model.selectedPaper?.id) { _, _ in
            guard model.selectedSessionPanelTab == .notes, let paper = model.selectedPaper else {
                return
            }
            model.loadPaperNotes(for: paper)
        }
        .onChange(of: model.selectedSession?.id) { _, _ in
            selectedGeneratedImageURL = nil
        }
        .onChange(of: model.chatComposerFocusRequestID) { _, requestID in
            composerFocusRequestID = requestID
        }
    }

    @ViewBuilder
    private var selectedPanelContent: some View {
        Group {
            switch model.selectedSessionPanelTab {
            case .chat:
                chatPanel
            case .terminal:
                AgentTerminalView()
            case .notes:
                SessionNotesPanel()
            }
        }
        .id(model.selectedSessionPanelTab)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
        .animation(PaperCodexMotion.selection, value: model.selectedSessionPanelTab)
    }

    private var chatPanel: some View {
        VStack(spacing: 0) {
            NativeChatTranscriptView(
                messages: model.messages,
                activeRun: visibleActiveCodexRun,
                runtimeName: model.selectedChatRuntimeDisplayName,
                isBusy: isCurrentSessionSending,
                messageFontSize: model.chatMessageFontSize,
                fontFamily: model.chatFontFamily,
                scrollRequestToken: chatScrollRequestToken,
                scrollRequestAnimated: chatScrollRequestAnimated,
                onCitation: { citationID in
                    model.jumpToCitation(citationID)
                },
                onRetryFailure: { messageID in
                    Task {
                        await model.retryCodexFailure(messageID: messageID)
                    }
                },
                onNewSession: {
                    model.startFreshSessionFromCurrentPaperSet()
                },
                onGeneratedImagePreview: { url in
                    selectedGeneratedImageURL = url
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: model.messages.count) { _, _ in
                requestChatScrollToBottom()
            }
            .onChange(of: visibleActiveCodexRun?.events.count ?? 0) { _, _ in
                requestChatScrollToBottom()
            }
            .onAppear {
                requestChatScrollToBottom(animated: false)
            }
            composer
        }
        .overlay {
            if let selectedGeneratedImageURL {
                GeneratedImagePreviewOverlay(imageURL: selectedGeneratedImageURL) {
                    self.selectedGeneratedImageURL = nil
                }
                .zIndex(10)
            }
        }
    }

    private var visibleActiveCodexRun: ActiveCodexRun? {
        model.activeCodexRun(for: model.selectedSession?.id)
    }

    private var isCurrentSessionSending: Bool {
        model.isSessionSending(model.selectedSession?.id)
    }

    private var canEditComposer: Bool {
        !isCurrentSessionSending
    }

    private var trimmedDraft: String {
        currentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentDraft: String {
        draftsByComposerKey[composerDraftKey, default: ""]
    }

    private var composerDraftKey: String {
        let sessionID = model.selectedSession?.id ?? "no-session"
        if let session = model.selectedSession, session.paperIDs.count > 1 {
            return "multi|\(sessionID)"
        }
        let paperID = model.selectedPaper?.id ?? "no-paper"
        return "\(paperID)|\(sessionID)"
    }

    private var composerDraftBinding: Binding<String> {
        Binding(
            get: {
                draftsByComposerKey[composerDraftKey, default: ""]
            },
            set: { value in
                draftsByComposerKey[composerDraftKey] = value
            }
        )
    }

    private var canUseSendButton: Bool {
        if isCurrentSessionSending {
            return true
        }
        return !trimmedDraft.isEmpty
    }

    private var sessionBar: some View {
        ReaderSessionToolbarView(
            selectedPanelTab: model.selectedSessionPanelTab,
            sessions: model.sessions,
            selectedSessionID: model.selectedSession?.id,
            onSelectPanelTab: { tab in
                model.selectedSessionPanelTab = tab
            },
            onSelectSession: { sessionID in
                model.selectSession(sessionID)
            },
            onNewSession: {
                model.newSessionButtonTapped()
            },
            onRenameSession: { session in
                renameSessionTitle = session.title
                sessionPendingRename = session
            }
        )
        .frame(maxWidth: .infinity, minHeight: 34, idealHeight: 34, maxHeight: 34)
    }

    private func requestChatScrollToBottom(animated: Bool = true) {
        chatScrollRequestAnimated = animated
        chatScrollRequestToken += 1
    }

    private func renameSessionSheet(_ session: PaperSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Rename Session", systemImage: "pencil")
                .font(.title3.weight(.semibold))
            PaperCodexNativeTextField(text: $renameSessionTitle, placeholder: "Session title")
                .frame(height: 30)
            HStack {
                Spacer()
                PaperCodexPanelButton(title: "Cancel") {
                    sessionPendingRename = nil
                }
                PaperCodexPanelButton(
                    title: "Save",
                    kind: .primary,
                    disabled: renameSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    model.renameSession(session, title: renameSessionTitle)
                    sessionPendingRename = nil
                }
            }
        }
        .padding(22)
        .frame(width: 380)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            composerTopDivider
            VStack(alignment: .leading, spacing: 8) {
                if let selection = model.currentSelection {
                    CurrentSelectionReplyCard(selection: selection) {
                        model.clearCurrentSelection()
                    }
                }

                ChatComposerNativePanelView(
                    text: composerDraftBinding,
                    isEditable: canEditComposer,
                    isSending: isCurrentSessionSending,
                    canSubmit: canUseSendButton,
                    textHeight: composerTextHeight,
                    fontSize: model.chatComposerFontSize,
                    fontFamily: model.chatFontFamily,
                    focusRequestID: composerFocusRequestID,
                    prompts: model.quickPrompts,
                    runtimeProfiles: model.agentRuntimeProfiles,
                    selectedRuntimeID: model.selectedChatRuntimeID,
                    runtimeName: model.selectedChatRuntimeDisplayName,
                    diagnostic: model.selectedChatRuntimeDiagnostic,
                    authSummary: model.selectedChatRuntimeAuthSummary,
                    modelOverride: model.codexModelOverride,
                    availableModelIDs: model.availableCodexModelIDs,
                    defaultModelID: model.codexDefaultModelID,
                    reasoningEffort: model.codexReasoningEffort,
                    onPrompt: { model.sendQuickPrompt($0) },
                    onRuntime: { model.setSelectedChatRuntimeID($0) },
                    onModelOverride: { model.setCodexModelOverride($0) },
                    onReasoningEffort: { model.setCodexReasoningEffort($0) },
                    onRefresh: {
                        Task {
                            await model.refreshCodexDiagnostic()
                            await model.refreshAvailableCodexModels()
                            await model.refreshAgentRuntimeDiagnostics()
                        }
                    },
                    onSubmit: sendDraft,
                    onCancel: {
                        model.cancelActiveCodexRun()
                    }
                )
                .frame(height: ChatComposerLayout.nativePanelHeight(for: composerTextHeight))
            }
            .padding(14)
        }
    }

    private var composerTopDivider: some View {
        WindowSafeComposerResizeHandle(
            onDragChanged: resizeComposerTextHeight,
            onDragEnded: finishComposerResize
        )
        .frame(maxWidth: .infinity)
        .frame(height: 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .help("Resize input")
    }

    private func resizeComposerTextHeight(translationY: CGFloat) {
        if composerResizeStartHeight == nil {
            composerResizeStartHeight = composerTextHeight
        }
        let nextHeight = (composerResizeStartHeight ?? composerTextHeight) + translationY
        composerTextHeight = ChatComposerLayout.clampedTextHeight(nextHeight)
    }

    private func finishComposerResize() {
        composerTextHeight = ChatComposerLayout.clampedTextHeight(composerTextHeight)
        ChatComposerLayout.saveTextHeight(composerTextHeight)
        composerResizeStartHeight = nil
    }

    private func sendDraft() {
        let message = trimmedDraft
        guard !isCurrentSessionSending, !message.isEmpty else {
            return
        }
        draftsByComposerKey[composerDraftKey] = ""
        Task {
            await model.sendMessage(message)
        }
    }
}

private struct SessionNotesPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var noteTitle = ""
    @State private var noteBody = ""
    @State private var editingNoteID: String?
    @State private var selectedNoteID: String?

    var body: some View {
        Group {
            if let paper = model.selectedPaper {
                SessionNotesNativePanelView(
                    paper: paper,
                    notes: model.paperNotesByID[paper.id, default: []],
                    selectedNoteID: $selectedNoteID,
                    noteTitle: $noteTitle,
                    noteBody: $noteBody,
                    editingNoteID: $editingNoteID,
                    onSelect: edit,
                    onNew: clearNoteDraft,
                    onSave: saveNote,
                    onDelete: deleteNote
                )
                .onAppear {
                    model.loadPaperNotes(for: paper)
                }
            } else {
                PaperCodexNativeEmptyState(title: "No Paper Selected", systemImage: "doc.text")
            }
        }
        .onChange(of: model.selectedPaper?.id) { _, _ in
            clearNoteDraft()
            if let paper = model.selectedPaper {
                model.loadPaperNotes(for: paper)
            }
        }
    }

    private func edit(_ note: PaperNote) {
        selectedNoteID = note.id
        editingNoteID = note.id
        noteTitle = note.title
        noteBody = note.bodyMarkdown
    }

    private func saveNote(_ paper: Paper) {
        model.saveNote(paperID: paper.id, noteID: editingNoteID, title: noteTitle, bodyMarkdown: noteBody)
        clearNoteDraft()
    }

    private func deleteNote(_ note: PaperNote) {
        model.deleteNote(note)
        if editingNoteID == note.id {
            clearNoteDraft()
        } else if selectedNoteID == note.id {
            selectedNoteID = nil
        }
    }

    private func clearNoteDraft() {
        selectedNoteID = nil
        editingNoteID = nil
        noteTitle = ""
        noteBody = ""
    }
}

enum ChatComposerLayout {
    static let minimumTextHeight: CGFloat = 72
    static let maximumTextHeight: CGFloat = 220
    static let defaultTextHeight: CGFloat = 96
    static let nativePanelVerticalChromeHeight: CGFloat = 34

    static func clampedTextHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minimumTextHeight), maximumTextHeight)
    }

    static func nativePanelHeight(for textHeight: CGFloat) -> CGFloat {
        clampedTextHeight(textHeight) + nativePanelVerticalChromeHeight
    }

    static func loadTextHeight() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: chatComposerTextHeightDefaultsKey)
        guard stored > 0 else {
            return defaultTextHeight
        }
        return clampedTextHeight(CGFloat(stored))
    }

    static func saveTextHeight(_ height: CGFloat) {
        UserDefaults.standard.set(Double(clampedTextHeight(height)), forKey: chatComposerTextHeightDefaultsKey)
    }
}

private struct WindowSafeComposerResizeHandle: NSViewRepresentable {
    var onDragChanged: (CGFloat) -> Void
    var onDragEnded: () -> Void

    func makeNSView(context: Context) -> ResizeHandleView {
        let view = ResizeHandleView()
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: ResizeHandleView, context: Context) {
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
    }

    final class ResizeHandleView: NSView {
        var onDragChanged: (CGFloat) -> Void = { _ in }
        var onDragEnded: () -> Void = {}
        private var dragStartWindowY: CGFloat?
        private var isHovering = false
        private var isDragging = false
        private var trackingArea: NSTrackingArea?

        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func mouseEntered(with event: NSEvent) {
            isHovering = true
            needsDisplay = true
            NSCursor.resizeUpDown.set()
        }

        override func mouseExited(with event: NSEvent) {
            isHovering = false
            needsDisplay = true
            NSCursor.arrow.set()
        }

        override func mouseDown(with event: NSEvent) {
            dragStartWindowY = event.locationInWindow.y
            isDragging = true
            window?.makeFirstResponder(self)
            NSCursor.resizeUpDown.set()
            needsDisplay = true
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStartWindowY else {
                return
            }
            onDragChanged(event.locationInWindow.y - dragStartWindowY)
        }

        override func mouseUp(with event: NSEvent) {
            dragStartWindowY = nil
            isDragging = false
            onDragEnded()
            needsDisplay = true
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, isHovering {
                NSCursor.arrow.set()
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            let isActive = isHovering || isDragging
            let width: CGFloat = isDragging ? 70 : (isHovering ? 58 : 44)
            let height: CGFloat = isDragging ? 5 : 4
            let rect = NSRect(
                x: bounds.midX - width / 2,
                y: bounds.midY - height / 2,
                width: width,
                height: height
            )
            let color = isActive
                ? NSColor.controlAccentColor.withAlphaComponent(isDragging ? 0.86 : 0.68)
                : NSColor.secondaryLabelColor.withAlphaComponent(0.34)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }
}

private struct NativeChatTranscriptView: NSViewRepresentable {
    var messages: [ChatMessage]
    var activeRun: ActiveCodexRun?
    var runtimeName: String
    var isBusy: Bool
    var messageFontSize: Double
    var fontFamily: ChatFontFamily
    var scrollRequestToken: Int
    var scrollRequestAnimated: Bool
    var onCitation: (String) -> Void
    var onRetryFailure: (String) -> Void
    var onNewSession: () -> Void
    var onGeneratedImagePreview: (URL) -> Void

    private var htmlBaseURL: URL {
        Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCitation: onCitation,
            onRetryFailure: onRetryFailure,
            onNewSession: onNewSession,
            onGeneratedImagePreview: onGeneratedImagePreview
        )
    }

    func makeNSView(context: Context) -> NativeChatTranscriptWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let transcriptView = NativeChatTranscriptWebView(configuration: configuration)
        transcriptView.setNavigationDelegate(context.coordinator)
        context.coordinator.transcriptView = transcriptView
        transcriptView.apply(
            html: renderHTML(),
            htmlBaseURL: htmlBaseURL,
            scrollRequestToken: scrollRequestToken,
            scrollRequestAnimated: scrollRequestAnimated
        )
        return transcriptView
    }

    func updateNSView(_ transcriptView: NativeChatTranscriptWebView, context: Context) {
        context.coordinator.update(
            onCitation: onCitation,
            onRetryFailure: onRetryFailure,
            onNewSession: onNewSession,
            onGeneratedImagePreview: onGeneratedImagePreview
        )
        context.coordinator.transcriptView = transcriptView
        transcriptView.apply(
            html: renderHTML(),
            htmlBaseURL: htmlBaseURL,
            scrollRequestToken: scrollRequestToken,
            scrollRequestAnimated: scrollRequestAnimated
        )
    }

    static func dismantleNSView(_ transcriptView: NativeChatTranscriptWebView, coordinator: Coordinator) {
        transcriptView.setNavigationDelegate(nil)
        transcriptView.stopLoading()
        coordinator.transcriptView = nil
    }

    private func renderHTML() -> String {
        NativeChatTranscriptHTMLBuilder.render(
            messages: messages.map(NativeChatTranscriptRenderableMessage.init(message:)),
            activeRun: activeRun,
            runtimeName: runtimeName,
            isBusy: isBusy,
            messageFontSize: messageFontSize,
            fontFamily: fontFamily
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var transcriptView: NativeChatTranscriptWebView?
        private var onCitation: (String) -> Void
        private var onRetryFailure: (String) -> Void
        private var onNewSession: () -> Void
        private var onGeneratedImagePreview: (URL) -> Void

        init(
            onCitation: @escaping (String) -> Void,
            onRetryFailure: @escaping (String) -> Void,
            onNewSession: @escaping () -> Void,
            onGeneratedImagePreview: @escaping (URL) -> Void
        ) {
            self.onCitation = onCitation
            self.onRetryFailure = onRetryFailure
            self.onNewSession = onNewSession
            self.onGeneratedImagePreview = onGeneratedImagePreview
            super.init()
        }

        func update(
            onCitation: @escaping (String) -> Void,
            onRetryFailure: @escaping (String) -> Void,
            onNewSession: @escaping () -> Void,
            onGeneratedImagePreview: @escaping (URL) -> Void
        ) {
            self.onCitation = onCitation
            self.onRetryFailure = onRetryFailure
            self.onNewSession = onNewSession
            self.onGeneratedImagePreview = onGeneratedImagePreview
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            transcriptView?.finishHTMLLoad()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if handlePaperCodexURL(url) {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated,
               ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private func handlePaperCodexURL(_ url: URL) -> Bool {
            if let citationID = CitationParser.citationID(from: url) {
                onCitation(citationID)
                return true
            }

            guard url.scheme == "papercodex-chat" else {
                return false
            }
            let action = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            switch action {
            case "retry":
                if let messageID = queryItems.first(where: { $0.name == "message_id" })?.value {
                    onRetryFailure(messageID)
                }
                return true
            case "new-session":
                onNewSession()
                return true
            case "image":
                if let path = queryItems.first(where: { $0.name == "path" })?.value {
                    onGeneratedImagePreview(URL(fileURLWithPath: path))
                }
                return true
            default:
                return false
            }
        }
    }
}

private final class NativeChatTranscriptWebView: NSView {
    private let webView: WKWebView
    private var currentHTML: String?
    private var lastScrollRequestToken = 0
    private var pendingScrollRequest: (token: Int, animated: Bool)?
    private var isHTMLLoaded = false

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func setNavigationDelegate(_ delegate: WKNavigationDelegate?) {
        webView.navigationDelegate = delegate
    }

    func apply(
        html: String,
        htmlBaseURL: URL,
        scrollRequestToken: Int,
        scrollRequestAnimated: Bool
    ) {
        if currentHTML != html {
            currentHTML = html
            isHTMLLoaded = false
            if scrollRequestToken > lastScrollRequestToken {
                pendingScrollRequest = (scrollRequestToken, scrollRequestAnimated)
            }
            webView.loadHTMLString(html, baseURL: htmlBaseURL)
            return
        }
        if scrollRequestToken > lastScrollRequestToken {
            scrollToBottom(token: scrollRequestToken, animated: scrollRequestAnimated)
        }
    }

    func finishHTMLLoad() {
        isHTMLLoaded = true
        if let pendingScrollRequest {
            scrollToBottom(token: pendingScrollRequest.token, animated: pendingScrollRequest.animated)
            self.pendingScrollRequest = nil
        }
    }

    func stopLoading() {
        webView.stopLoading()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        webView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        webView.setContentHuggingPriority(.defaultLow, for: .vertical)
        webView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func scrollToBottom(token: Int, animated: Bool) {
        guard isHTMLLoaded else {
            pendingScrollRequest = (token, animated)
            return
        }
        lastScrollRequestToken = max(lastScrollRequestToken, token)
        let behavior = animated ? "smooth" : "auto"
        let script = "window.paperCodexScrollToBottom && window.paperCodexScrollToBottom('\(behavior)');"
        webView.evaluateJavaScript(script)
    }
}

private struct NativeChatTranscriptRenderableMessage: Equatable {
    var id: String
    var role: ChatRole
    var content: String
    var createdAt: Date
    var renderedMarkdown: String
    var userSourceAttachment: UserSourceAttachment?
    var failureNotice: CodexFailureNotice?
    var generatedImages: [URL]

    var isUser: Bool {
        role == .user
    }

    init(message: ChatMessage) {
        id = message.id
        role = message.role
        content = message.content
        createdAt = message.createdAt

        let parsedUserSource = UserSourceAttachmentParser.parse(message.content)
        let parsedCitations = CitationParser.parse(message.content, maxVisibleCitations: message.role == .user ? nil : 3)
        let failureNotice = CodexFailureNotice.parse(message.content)
        self.failureNotice = failureNotice
        userSourceAttachment = message.role == .user ? parsedUserSource.attachment : nil
        generatedImages = generatedImageURLs(in: message.content)

        if let failureNotice {
            renderedMarkdown = failureNotice.messageContent
        } else if message.role == .user {
            renderedMarkdown = parsedUserSource.visibleContent
        } else {
            renderedMarkdown = parsedCitations.displayMarkdown
        }
    }
}

private enum NativeChatTranscriptHTMLBuilder {
    static func render(
        messages: [NativeChatTranscriptRenderableMessage],
        activeRun: ActiveCodexRun?,
        runtimeName: String,
        isBusy: Bool,
        messageFontSize: Double,
        fontFamily: ChatFontFamily
    ) -> String {
        let style = ChatMarkdownRenderStyle(
            fontSize: messageFontSize,
            fontFamily: fontFamily.cssFontFamily
        )
        let content: String
        if messages.isEmpty, activeRun == nil {
            content = renderEmptyState(runtimeName: runtimeName)
        } else {
            let messageHTML = messages
                .map { renderMessage($0, style: style, isBusy: isBusy) }
                .joined(separator: "\n")
            let activeRunHTML = activeRun.map(renderActiveRun) ?? ""
            content = [messageHTML, activeRunHTML]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(stylesheet(messageFontSize: style.fontSize, fontFamily: style.fontFamily))
        </style>
        <link rel="stylesheet" href="KaTeX/katex.min.css">
        <script defer src="KaTeX/katex.min.js"></script>
        <script defer src="KaTeX/contrib/auto-render.min.js"></script>
        </head>
        <body>
        <main class="transcript">
        \(content)
        </main>
        <script>
        window.paperCodexScrollToBottom = function(behavior) {
          window.scrollTo({ top: document.documentElement.scrollHeight, behavior: behavior || 'auto' });
        };
        let didRenderMath = false;
        function renderMath() {
          if (didRenderMath || !window.renderMathInElement) {
            return;
          }
          didRenderMath = true;
          renderMathInElement(document.querySelector('.transcript'), {
            delimiters: [
              {left: '$$', right: '$$', display: true},
              {left: '\\\\[', right: '\\\\]', display: true},
              {left: '\\\\(', right: '\\\\)', display: false},
              {left: '$', right: '$', display: false}
            ],
            ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'],
            throwOnError: false,
            strict: 'ignore'
          });
        }
        document.addEventListener('DOMContentLoaded', renderMath);
        window.addEventListener('load', renderMath);
        setTimeout(renderMath, 50);
        setTimeout(renderMath, 250);
        </script>
        </body>
        </html>
        """
    }

    private static func renderMessage(
        _ message: NativeChatTranscriptRenderableMessage,
        style: ChatMarkdownRenderStyle,
        isBusy: Bool
    ) -> String {
        let roleName = message.isUser ? "You" : (message.role == .system ? "System" : "Agent")
        let roleInitial = message.isUser ? "Y" : (message.role == .system ? "S" : "A")
        let timestamp = formattedTimestamp(message.createdAt)
        let markdown = message.renderedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let markdownHTML = markdown.isEmpty
            ? ""
            : #"<div class="markdown">\#(ChatMarkdownRenderer.renderFragment(markdown: markdown))</div>"#
        let sourceHTML = message.userSourceAttachment.map(renderQuotedSource) ?? ""
        let galleryHTML = renderGeneratedImageGallery(urls: message.generatedImages)
        let failureActionsHTML = renderFailureActions(for: message, isBusy: isBusy)
        let bodyHTML = [sourceHTML, markdownHTML, galleryHTML, failureActionsHTML]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        if message.isUser {
            return """
            <article class="message-row message-row-user" data-message-id="\(escapeAttribute(message.id))">
              <div class="message-shell message-user">
                <header class="message-header"><strong>\(escapeText(roleName))</strong><time>\(escapeText(timestamp))</time></header>
                <div class="message-user-bubble">\(bodyHTML)</div>
              </div>
              <div class="role-badge role-badge-user" aria-hidden="true">\(roleInitial)</div>
            </article>
            """
        }

        return """
        <article class="message-row message-row-agent" data-message-id="\(escapeAttribute(message.id))">
          <div class="role-badge role-badge-agent" aria-hidden="true">\(roleInitial)</div>
          <div class="message-shell message-agent">
            <header class="message-header"><strong>\(escapeText(roleName))</strong><time>\(escapeText(timestamp))</time></header>
            \(bodyHTML)
          </div>
        </article>
        """
    }

    private static func renderEmptyState(runtimeName: String) -> String {
        """
        <section class="empty-state">
          <div class="empty-state-icon">PC</div>
          <h1>No Messages</h1>
          <p>Select text in the PDF, then ask \(escapeText(runtimeName)) in this session. The selected source appears as a quoted reply.</p>
        </section>
        """
    }

    private static func renderQuotedSource(_ attachment: UserSourceAttachment) -> String {
        let href = CitationParser.linkURL(for: attachment.anchorID)
        return """
        <a class="quoted-source" href="\(escapeAttribute(href))" title="Open quoted source" aria-label="Open quoted source">
          <span class="quoted-source-mark">Quote</span>
          <span class="quoted-source-body">
            <strong>Quoted source - p\(attachment.page)</strong>
            <span>\(escapeText(attachment.selectedText))</span>
          </span>
          <span class="quoted-source-open">Open</span>
        </a>
        """
    }

    private static func renderFailureActions(
        for message: NativeChatTranscriptRenderableMessage,
        isBusy: Bool
    ) -> String {
        guard message.failureNotice != nil else {
            return ""
        }
        if isBusy {
            return """
            <div class="failure-actions">
              <span class="transcript-action is-disabled" aria-disabled="true">Retry</span>
              <span class="transcript-action is-disabled" aria-disabled="true">New Session</span>
            </div>
            """
        }
        let retryURL = "papercodex-chat://retry?message_id=\(percentEncode(message.id))"
        return """
        <div class="failure-actions">
          <a class="transcript-action" href="\(escapeAttribute(retryURL))">Retry</a>
          <a class="transcript-action" href="papercodex-chat://new-session">New Session</a>
        </div>
        """
    }

    private static func renderGeneratedImageGallery(urls: [URL]) -> String {
        guard !urls.isEmpty else {
            return ""
        }
        let cards = urls.map { url in
            let previewURL = "papercodex-chat://image?path=\(percentEncode(url.path))"
            let imageSource = url.absoluteString
            let filename = url.lastPathComponent
            return """
            <a class="generated-image-card" href="\(escapeAttribute(previewURL))" title="Preview generated image" aria-label="Preview generated image">
              <img src="\(escapeAttribute(imageSource))" alt="\(escapeAttribute(filename))">
              <span>\(escapeText(filename))</span>
            </a>
            """
        }.joined(separator: "\n")
        return #"<div class="generated-image-gallery">\#(cards)</div>"#
    }

    private static func renderActiveRun(_ run: ActiveCodexRun) -> String {
        let visibleEvents = visibleCodexRunEvents(from: run)
        let status = tokenUsageSummary(for: run) ?? (visibleEvents.isEmpty ? "Working" : "\(visibleEvents.count) updates")
        let eventsHTML = visibleEvents
            .map(renderRunEvent)
            .joined(separator: "\n")
        return """
        <section class="active-run" aria-label="Agent running">
          <div class="active-run-header">
            <span class="run-spinner" aria-hidden="true"></span>
            <strong>Agent</strong>
            <span>Running</span>
            <span class="run-status">\(escapeText(status))</span>
          </div>
          <div class="run-events">\(eventsHTML)</div>
        </section>
        """
    }

    private static func visibleCodexRunEvents(from run: ActiveCodexRun) -> [CodexRunEvent] {
        Array(run.events.filter { event in
            switch event.kind {
            case .thinking, .tool, .terminal, .answer, .usage, .warning, .error:
                true
            case .status, .raw:
                false
            }
        }.suffix(8))
    }

    private static func tokenUsageSummary(for run: ActiveCodexRun) -> String? {
        var aggregate = CodexTokenUsage()
        for event in run.events {
            if let tokenUsage = event.tokenUsage {
                aggregate.add(tokenUsage)
            }
        }
        return aggregate.isEmpty ? nil : aggregate.compactSummary
    }

    private static func renderRunEvent(_ event: CodexRunEvent) -> String {
        let eventClass = "run-event-\(event.kind.rawValue)"
        let title = event.displayTitle.isEmpty ? event.kind.rawValue.capitalized : event.displayTitle
        if event.kind == .terminal {
            return """
            <details class="run-event \(eventClass)">
              <summary><span class="run-event-icon">\(escapeText(eventIconName(for: event.kind)))</span><strong>\(escapeText(title))</strong><span>\(escapeText(event.previewDetail))</span></summary>
              <pre>\(escapeText(event.detail))</pre>
            </details>
            """
        }
        return """
        <div class="run-event \(eventClass)">
          <div class="run-event-title"><span class="run-event-icon">\(escapeText(eventIconName(for: event.kind)))</span><strong>\(escapeText(title))</strong></div>
          <p>\(escapeText(event.detail))</p>
        </div>
        """
    }

    private static func eventIconName(for kind: CodexRunEventKind) -> String {
        switch kind {
        case .status:
            "Status"
        case .thinking:
            "Think"
        case .tool:
            "Tool"
        case .terminal:
            "Term"
        case .answer:
            "Answer"
        case .usage:
            "Usage"
        case .warning:
            "Warn"
        case .error:
            "Error"
        case .raw:
            "Raw"
        }
    }

    private static func stylesheet(messageFontSize: Double, fontFamily: String) -> String {
        """
        :root {
          color-scheme: light dark;
          font: -apple-system-body;
        }
        html, body {
          width: 100%;
          min-height: 100%;
          margin: 0;
          background: transparent;
          color: CanvasText;
        }
        body {
          overflow-y: auto;
          overflow-x: hidden;
        }
        .transcript {
          box-sizing: border-box;
          min-height: 100vh;
          width: 100%;
          padding: 16px;
          display: flex;
          flex-direction: column;
          gap: 14px;
          font-family: \(fontFamily);
          font-size: \(formattedFontSize(messageFontSize))px;
          line-height: 1.55;
          overflow-wrap: anywhere;
        }
        .message-row {
          display: grid;
          align-items: flex-start;
          gap: 10px;
          width: 100%;
          box-sizing: border-box;
        }
        .message-row-agent {
          grid-template-columns: 28px minmax(0, 1fr);
        }
        .message-row-user {
          grid-template-columns: minmax(0, 1fr) 28px;
        }
        .message-shell {
          min-width: 0;
        }
        .message-agent {
          width: 100%;
        }
        .message-user {
          justify-self: end;
          max-width: min(70%, 680px);
        }
        .message-user-bubble {
          padding: 10px 13px 8px;
          background: color-mix(in srgb, LinkText 9%, transparent);
          border: 1px solid color-mix(in srgb, LinkText 18%, transparent);
          border-radius: 8px;
          box-shadow: 0 3px 9px color-mix(in srgb, LinkText 8%, transparent);
        }
        .message-header {
          display: flex;
          align-items: baseline;
          gap: 6px;
          margin-bottom: 7px;
          color: color-mix(in srgb, CanvasText 68%, transparent);
          font-size: 0.78em;
        }
        .message-row-user .message-header {
          justify-content: flex-end;
          color: LinkText;
        }
        .message-header time {
          color: color-mix(in srgb, CanvasText 52%, transparent);
          font-variant-numeric: tabular-nums;
        }
        .role-badge {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 28px;
          height: 28px;
          border-radius: 50%;
          font-size: 11px;
          font-weight: 750;
          user-select: none;
        }
        .role-badge-user {
          color: LinkText;
          background: color-mix(in srgb, LinkText 12%, transparent);
          border: 1px solid color-mix(in srgb, LinkText 22%, transparent);
        }
        .role-badge-agent {
          color: color-mix(in srgb, CanvasText 72%, #c76f00 55%);
          background: color-mix(in srgb, #ff9500 12%, transparent);
          border: 1px solid color-mix(in srgb, #ff9500 22%, transparent);
        }
        .markdown p, .markdown ul, .markdown ol, .markdown blockquote, .markdown pre, .markdown table {
          margin: 0 0 0.72em;
        }
        .markdown p:last-child,
        .markdown ul:last-child,
        .markdown ol:last-child,
        .markdown blockquote:last-child,
        .markdown pre:last-child {
          margin-bottom: 0;
        }
        .markdown h1, .markdown h2, .markdown h3 {
          margin: 0.25em 0 0.45em;
          line-height: 1.2;
        }
        .markdown h1 { font-size: 1.35em; }
        .markdown h2 { font-size: 1.18em; }
        .markdown h3 { font-size: 1.05em; }
        a {
          color: LinkText;
        }
        a.citation {
          display: inline-flex;
          align-items: center;
          min-width: 1.6em;
          height: 1.45em;
          padding: 0 0.35em;
          border-radius: 0.72em;
          background: color-mix(in srgb, LinkText 16%, transparent);
          color: LinkText;
          font-size: 0.86em;
          font-weight: 650;
          text-decoration: none;
          vertical-align: 0.08em;
        }
        code {
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
          font-size: 0.92em;
          background: color-mix(in srgb, CanvasText 8%, transparent);
          border-radius: 4px;
          padding: 0.08em 0.28em;
        }
        pre {
          overflow-x: auto;
          padding: 0.7em;
          border-radius: 6px;
          background: color-mix(in srgb, CanvasText 8%, transparent);
        }
        pre code {
          background: transparent;
          padding: 0;
        }
        blockquote {
          padding-left: 0.8em;
          border-left: 3px solid color-mix(in srgb, CanvasText 24%, transparent);
          color: color-mix(in srgb, CanvasText 78%, transparent);
        }
        table {
          border-collapse: collapse;
          width: 100%;
        }
        th, td {
          border: 1px solid color-mix(in srgb, CanvasText 18%, transparent);
          padding: 0.35em 0.5em;
          text-align: left;
        }
        img {
          max-width: 100%;
          height: auto;
          border-radius: 6px;
        }
        .quoted-source {
          display: grid;
          grid-template-columns: auto minmax(0, 1fr) auto;
          gap: 9px;
          align-items: flex-start;
          margin-bottom: 9px;
          padding: 9px;
          border-radius: 7px;
          text-decoration: none;
          color: CanvasText;
          background: color-mix(in srgb, CanvasText 5%, transparent);
          border-left: 3px solid color-mix(in srgb, LinkText 55%, transparent);
          box-shadow: inset 0 0 0 1px color-mix(in srgb, LinkText 16%, transparent);
        }
        .quoted-source-mark,
        .quoted-source-open {
          color: LinkText;
          font-size: 0.76em;
          font-weight: 700;
        }
        .quoted-source-body {
          display: grid;
          gap: 3px;
          min-width: 0;
        }
        .quoted-source-body span {
          color: color-mix(in srgb, CanvasText 68%, transparent);
          display: -webkit-box;
          -webkit-line-clamp: 3;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .generated-image-gallery {
          display: flex;
          gap: 8px;
          overflow-x: auto;
          padding: 2px 0 4px;
          margin-top: 9px;
        }
        .generated-image-card {
          flex: 0 0 138px;
          display: grid;
          gap: 5px;
          padding: 6px;
          border-radius: 8px;
          text-decoration: none;
          color: color-mix(in srgb, CanvasText 72%, transparent);
          background: color-mix(in srgb, CanvasText 5%, transparent);
          box-shadow: inset 0 0 0 1px color-mix(in srgb, CanvasText 12%, transparent);
        }
        .generated-image-card img {
          width: 126px;
          height: 86px;
          object-fit: cover;
          background: color-mix(in srgb, CanvasText 7%, transparent);
        }
        .generated-image-card span {
          font-size: 0.75em;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .failure-actions {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
          margin-top: 9px;
        }
        .transcript-action {
          display: inline-flex;
          align-items: center;
          min-height: 26px;
          padding: 0 10px;
          border-radius: 7px;
          text-decoration: none;
          color: CanvasText;
          background: color-mix(in srgb, CanvasText 7%, transparent);
          box-shadow: inset 0 0 0 1px color-mix(in srgb, CanvasText 16%, transparent);
        }
        .transcript-action.is-disabled {
          opacity: 0.48;
        }
        .active-run {
          width: min(720px, calc(100% - 38px));
          margin-left: 38px;
          padding: 12px;
          border-radius: 8px;
          background: color-mix(in srgb, CanvasText 5%, transparent);
          box-shadow: inset 0 0 0 1px color-mix(in srgb, LinkText 20%, transparent);
        }
        .active-run-header {
          display: flex;
          align-items: center;
          gap: 8px;
          color: color-mix(in srgb, CanvasText 70%, transparent);
          font-size: 0.82em;
        }
        .run-spinner {
          width: 14px;
          height: 14px;
          border-radius: 50%;
          border: 2px solid color-mix(in srgb, LinkText 18%, transparent);
          border-top-color: LinkText;
          animation: spin 0.9s linear infinite;
        }
        .run-status {
          margin-left: auto;
          color: color-mix(in srgb, CanvasText 52%, transparent);
          font-size: 0.86em;
        }
        .run-events {
          display: grid;
          gap: 8px;
          margin-top: 10px;
        }
        .run-event {
          min-width: 0;
          color: color-mix(in srgb, CanvasText 72%, transparent);
          font-size: 0.82em;
        }
        .run-event-title,
        .run-event summary {
          display: flex;
          align-items: center;
          gap: 7px;
        }
        .run-event summary {
          cursor: default;
        }
        .run-event summary span:last-child {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          color: color-mix(in srgb, CanvasText 55%, transparent);
        }
        .run-event p {
          margin: 3px 0 0 31px;
          display: -webkit-box;
          -webkit-line-clamp: 3;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .run-event pre {
          max-height: 160px;
          margin: 8px 0 0 31px;
          overflow: auto;
          white-space: pre-wrap;
        }
        .run-event-icon {
          display: inline-flex;
          justify-content: center;
          width: 24px;
          color: LinkText;
          font-size: 0.78em;
          font-weight: 700;
        }
        .empty-state {
          min-height: calc(100vh - 32px);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 8px;
          color: color-mix(in srgb, CanvasText 64%, transparent);
          text-align: center;
        }
        .empty-state-icon {
          width: 38px;
          height: 38px;
          border-radius: 50%;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          color: LinkText;
          background: color-mix(in srgb, LinkText 12%, transparent);
          font-size: 0.78em;
          font-weight: 800;
        }
        .empty-state h1 {
          margin: 0;
          color: CanvasText;
          font-size: 1.1em;
        }
        .empty-state p {
          margin: 0;
          max-width: 420px;
          line-height: 1.45;
        }
        .math-display {
          margin: 0 0 0.72em;
          overflow-x: auto;
        }
        .katex {
          font-size: 1.03em;
        }
        .katex-display {
          margin: 0.2em 0;
          overflow-x: auto;
          overflow-y: hidden;
          max-width: 100%;
        }
        @keyframes spin {
          to { transform: rotate(360deg); }
        }
        @media (max-width: 620px) {
          .message-user {
            max-width: min(88%, 680px);
          }
          .active-run {
            width: auto;
            margin-left: 38px;
          }
        }
        """
    }

    private static func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func formattedFontSize(_ size: Double) -> String {
        if size.rounded() == size {
            return String(Int(size))
        }
        return String(format: "%.1f", size)
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escapeText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private func generatedImageURLs(in markdown: String) -> [URL] {
    let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif"]
    var urls: [URL] = []
    var seen: Set<String> = []
    for line in markdown.components(separatedBy: .newlines) {
        guard line.trimmingCharacters(in: .whitespaces).hasPrefix("!") else {
            continue
        }
        guard let open = line.range(of: "]("),
              let close = line[open.upperBound...].firstIndex(of: ")") else {
            continue
        }
        var raw = String(line[open.upperBound..<close])
        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            raw = url.path
        }
        let url = URL(fileURLWithPath: raw)
        let path = url.standardizedFileURL.path
        guard supportedExtensions.contains(url.pathExtension.lowercased()),
              FileManager.default.fileExists(atPath: path),
              !seen.contains(path) else {
            continue
        }
        seen.insert(path)
        urls.append(url.standardizedFileURL)
    }
    return urls
}

private struct GeneratedImagePreviewOverlay: View {
    var imageURL: URL
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.56)
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
                }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "photo")
                        .foregroundStyle(.white.opacity(0.76))
                    Text(imageURL.lastPathComponent)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    PaperCodexIconButton(title: "Close Preview", systemImage: "xmark", tint: .white) {
                        onDismiss()
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.black.opacity(0.88))

                ZoomableImageScrollView(imageURL: imageURL) {
                    onDismiss()
                }
            }
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 16)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .onExitCommand {
            onDismiss()
        }
    }
}

private struct CurrentSelectionReplyCard: View {
    var selection: PDFSelectionInfo
    var onClear: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.opening")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text("Replying to source · p\(selection.page)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(selection.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            PaperCodexIconButton(title: "Remove Source", systemImage: "xmark.circle.fill", tint: .secondary) {
                onClear()
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.65))
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
