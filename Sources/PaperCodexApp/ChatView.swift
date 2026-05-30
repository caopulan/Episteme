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

    var body: some View {
        VStack(spacing: 0) {
            sessionBar
            Divider()
            selectedPanelContent
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(item: $sessionPendingRename) { session in
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.messages.isEmpty && visibleActiveCodexRun == nil {
                            ContentUnavailableView(
                                "No Messages",
                                systemImage: "text.bubble",
                                description: Text("Select text in the PDF, then ask \(model.selectedChatRuntimeDisplayName) in this session. The selected source appears as a quoted reply.")
                            )
                            .padding(.top, 80)
                        } else {
                            ForEach(model.messages) { message in
                                MessageBubble(
                                    message: message,
                                    isBusy: isCurrentSessionSending,
                                    messageFontSize: model.chatMessageFontSize,
                                    fontFamily: model.chatFontFamily,
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
                                .id(message.id)
                            }
                            if let activeCodexRun = visibleActiveCodexRun {
                                CodexRunBubble(run: activeCodexRun)
                                    .id("active-run")
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("chat-bottom")
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: visibleActiveCodexRun?.events.count ?? 0) { _, _ in
                    scrollToBottom(proxy)
                }
                .onAppear {
                    scrollToBottom(proxy)
                }
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }

    private func renameSessionSheet(_ session: PaperSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Rename Session", systemImage: "pencil")
                .font(.title3.weight(.semibold))
            TextField("Session title", text: $renameSessionTitle)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                ChatPanelActionButton {
                    sessionPendingRename = nil
                } label: {
                    Text("Cancel")
                }
                ChatPanelActionButton(kind: .primary, disabled: renameSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    model.renameSession(session, title: renameSessionTitle)
                    sessionPendingRename = nil
                } label: {
                    Text("Save")
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
                ContentUnavailableView("No Paper Selected", systemImage: "doc.text")
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

private enum ChatPanelActionButtonKind {
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

private struct ChatPanelActionButton<Label: View>: View {
    @State private var isHovering = false

    var kind: ChatPanelActionButtonKind = .secondary
    var disabled = false
    var role: ButtonRole?
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(role: role, action: action) {
            label()
        }
        .buttonStyle(ChatPanelActionButtonStyle(kind: kind, disabled: disabled, isHovering: isHovering))
        .disabled(disabled)
        .onHover { hovering in
            withAnimation(PaperCodexMotion.hover) {
                isHovering = hovering
            }
        }
    }
}

private struct ChatPanelActionButtonStyle: ButtonStyle {
    var kind: ChatPanelActionButtonKind
    var disabled: Bool
    var isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && !disabled
        configuration.label
            .font(.paperCodexSystem(size: 12.5, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(foregroundColor(isPressed: isPressed))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor(isPressed: isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor(isPressed: isPressed), lineWidth: 1)
            )
            .shadow(color: shadowColor(isPressed: isPressed), radius: isPressed ? 3 : 7, y: isPressed ? 1 : 3)
            .scaleEffect(buttonScale(isPressed: isPressed), anchor: .center)
            .animation(PaperCodexMotion.press, value: configuration.isPressed)
            .animation(PaperCodexMotion.hover, value: isHovering)
            .animation(PaperCodexMotion.hover, value: disabled)
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        if disabled {
            return Color.secondary.opacity(0.48)
        }
        switch kind {
        case .primary:
            return .white
        case .secondary, .destructive:
            return isPressed || isHovering ? kind.tint : Color.primary.opacity(0.82)
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if disabled {
            return Color(nsColor: .controlBackgroundColor).opacity(0.55)
        }
        switch kind {
        case .primary:
            return Color.accentColor.opacity(isPressed ? 0.82 : (isHovering ? 0.96 : 0.90))
        case .secondary, .destructive:
            if isPressed {
                return kind.tint.opacity(0.18)
            }
            return isHovering ? kind.tint.opacity(0.12) : Color(nsColor: .controlBackgroundColor)
        }
    }

    private func borderColor(isPressed: Bool) -> Color {
        if disabled {
            return Color.black.opacity(0.06)
        }
        switch kind {
        case .primary:
            return Color.accentColor.opacity(isPressed ? 0.62 : (isHovering ? 0.48 : 0.34))
        case .secondary, .destructive:
            if isPressed {
                return kind.tint.opacity(0.54)
            }
            return isHovering ? kind.tint.opacity(0.38) : Color.black.opacity(0.10)
        }
    }

    private func shadowColor(isPressed: Bool) -> Color {
        if disabled {
            return .clear
        }
        return kind.tint.opacity(isPressed ? 0.10 : (isHovering ? 0.16 : 0))
    }

    private func buttonScale(isPressed: Bool) -> CGFloat {
        if disabled {
            return 1
        }
        return isPressed ? 0.97 : (isHovering ? 1.02 : 1)
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

private struct CodexRunBubble: View {
    var run: ActiveCodexRun

    private var visibleEvents: [CodexRunEvent] {
        Array(run.events.filter { $0.kind == .thinking || $0.kind == .tool || $0.kind == .answer || $0.kind == .usage }.suffix(8))
    }

    private var tokenUsageSummary: String? {
        var aggregate = CodexTokenUsage()
        for event in run.events {
            if let tokenUsage = event.tokenUsage {
                aggregate.add(tokenUsage)
            }
        }
        return aggregate.isEmpty ? nil : aggregate.compactSummary
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Agent")
                        .font(.caption.weight(.semibold))
                    Text("Running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !visibleEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visibleEvents) { event in
                            CodexRunEventRow(event: event)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 32)
        }
    }

    private var statusText: String {
        if let tokenUsageSummary {
            return tokenUsageSummary
        }
        return visibleEvents.isEmpty ? "Working" : "\(visibleEvents.count) update\(visibleEvents.count == 1 ? "" : "s")"
    }
}

private struct CodexRunEventRow: View {
    var event: CodexRunEvent
    @State private var isExpanded = false

    var body: some View {
        if event.kind == .terminal {
            DisclosureGroup(isExpanded: $isExpanded) {
                Text(event.detail)
                    .font(.paperCodexSystem(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } label: {
                eventHeader
            }
            .font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                eventHeader
                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(event.kind == .tool ? 3 : 2)
            }
        }
    }

    private var eventHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(event.displayTitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if event.kind == .terminal, !isExpanded {
                Text(event.previewDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var iconName: String {
        switch event.kind {
        case .status:
            "circle.dotted"
        case .thinking:
            "brain.head.profile"
        case .tool:
            "wrench.and.screwdriver"
        case .terminal:
            "terminal"
        case .answer:
            "text.bubble"
        case .usage:
            "chart.bar"
        case .warning:
            "exclamationmark.triangle"
        case .error:
            "xmark.octagon"
        case .raw:
            "doc.plaintext"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .status:
            .blue
        case .thinking:
            .purple
        case .tool:
            .indigo
        case .terminal:
            .gray
        case .answer:
            .green
        case .usage:
            .indigo
        case .warning:
            .orange
        case .error:
            .red
        case .raw:
            .secondary
        }
    }
}

private struct MessageBubble: View {
    var message: ChatMessage
    var isBusy: Bool
    var messageFontSize: Double
    var fontFamily: ChatFontFamily
    var onCitation: (String) -> Void
    var onRetryFailure: (String) -> Void
    var onNewSession: () -> Void
    var onGeneratedImagePreview: (URL) -> Void

    private var isUser: Bool {
        message.role == .user
    }

    private var parsed: ParsedCitationText {
        CitationParser.parse(message.content, maxVisibleCitations: isUser ? nil : 3)
    }

    private var parsedUserSource: ParsedUserSourceMessage {
        UserSourceAttachmentParser.parse(message.content)
    }

    private var userSourceAttachment: UserSourceAttachment? {
        isUser ? parsedUserSource.attachment : nil
    }

    private var failureNotice: CodexFailureNotice? {
        CodexFailureNotice.parse(message.content)
    }

    private var renderedMarkdown: String {
        if let failureNotice {
            return failureNotice.messageContent
        }
        if isUser {
            return parsedUserSource.visibleContent
        }
        return parsed.displayMarkdown
    }

    private var chatBubbleContentWidth: CGFloat? {
        guard isUser else {
            return nil
        }
        let trimmedMarkdown = renderedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMarkdown.isEmpty else {
            return nil
        }
        if userSourceAttachment != nil || failureNotice != nil || trimmedMarkdown.contains("\n") || trimmedMarkdown.count > 120 {
            return chatBubbleMaximumContentWidth
        }

        let displayText = chatBubbleWidthText(from: trimmedMarkdown)
        guard !displayText.isEmpty else {
            return nil
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: fontFamily.nsFont(size: messageFontSize)
        ]
        let measured = (displayText as NSString).boundingRect(
            with: CGSize(width: chatBubbleMaximumContentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return min(max(ceil(measured.width) + 2, 44), chatBubbleMaximumContentWidth)
    }

    private var chatBubbleMaximumContentWidth: CGFloat {
        PaperCodexTypography.readableLineWidth - 26
    }

    var body: some View {
        if isUser {
            userMessageRow
        } else {
            agentMessageRow
        }
    }

    private var userMessageRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Spacer(minLength: 44)

            VStack(alignment: .trailing, spacing: 7) {
                messageHeader
                messageContent
                    .padding(.horizontal, 13)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(UserMessageBubbleBackground())
            }
            .paperCodexReadableLineLimit(alignment: .trailing)

            ChatRoleBadge(isUser: true)
        }
    }

    private var agentMessageRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ChatRoleBadge(isUser: false)

            VStack(alignment: .leading, spacing: 7) {
                messageHeader
                messageContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var messageHeader: some View {
        HStack(spacing: 6) {
            Text(isUser ? "You" : "Agent")
                .font(fontFamily.swiftUIFont(size: max(11, messageFontSize - 4), weight: .semibold))
            Text(message.createdAt, style: .time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary.opacity(0.82))
        }
        .foregroundStyle(isUser ? Color.accentColor : Color.secondary)
    }

    private var messageContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let userSourceAttachment {
                UserSourceReplyView(attachment: userSourceAttachment, onOpen: onCitation)
            }
            if !renderedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                markdownMessage
            }
            let imageURLs = generatedImageURLs(in: message.content)
            if !imageURLs.isEmpty {
                GeneratedImageGallery(urls: imageURLs, onPreview: onGeneratedImagePreview)
            }
            if failureNotice != nil {
                HStack(spacing: 8) {
                    ChatPanelActionButton(disabled: isBusy) {
                        onRetryFailure(message.id)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }

                    ChatPanelActionButton(disabled: isBusy) {
                        onNewSession()
                    } label: {
                        Label("New Session", systemImage: "plus.bubble")
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var markdownMessage: some View {
        if isUser {
            MarkdownMessageView(
                messageID: message.id,
                markdown: renderedMarkdown,
                fontSize: messageFontSize,
                fontFamily: fontFamily,
                onCitation: onCitation
            )
            .frame(width: chatBubbleContentWidth, alignment: .leading)
        } else {
            MarkdownMessageView(
                messageID: message.id,
                markdown: renderedMarkdown,
                fontSize: messageFontSize,
                fontFamily: fontFamily,
                expandsHorizontally: true,
                onCitation: onCitation
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
    }
}

private struct ChatRoleBadge: View {
    var isUser: Bool

    var body: some View {
        Image(systemName: isUser ? "person.fill" : "sparkles")
            .font(.paperCodexSystem(size: 12, weight: .bold))
            .frame(width: 28, height: 28)
            .foregroundStyle(isUser ? Color.accentColor : Color.orange)
            .background(
                Circle()
                    .fill((isUser ? Color.accentColor : Color.orange).opacity(0.12))
            )
            .overlay(
                Circle()
                    .stroke((isUser ? Color.accentColor : Color.orange).opacity(0.22), lineWidth: 1)
            )
            .shadow(color: (isUser ? Color.accentColor : Color.orange).opacity(0.10), radius: 5, y: 2)
            .accessibilityHidden(true)
    }
}

private struct UserMessageBubbleBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: PaperCodexCornerRadius.control)
            .fill(Color.accentColor.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: PaperCodexCornerRadius.control)
                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.accentColor.opacity(0.10), radius: 7, y: 3)
    }
}

private func chatBubbleWidthText(from markdown: String) -> String {
    var text = markdown
    text = text.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]+\)"#, with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
    text = text.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
    text = text.replacingOccurrences(of: #"[*_#>~-]+"#, with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

private struct GeneratedImageGallery: View {
    var urls: [URL]
    var onPreview: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(urls, id: \.path) { url in
                    Button {
                        onPreview(url)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            ZStack(alignment: .topTrailing) {
                                LocalThumbnailImage(url: url, maxPixelSize: 260, contentMode: .fill) {
                                    Image(systemName: "photo")
                                        .frame(width: 126, height: 86)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                }
                                .frame(width: 126, height: 86)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 7))

                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(5)
                                    .background(.black.opacity(0.46), in: Circle())
                                    .padding(5)
                            }
                            Text(url.lastPathComponent)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help("Preview generated image")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.callout.weight(.semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.82))
                    .help("Close preview")
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
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove source")
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

private struct UserSourceReplyView: View {
    var attachment: UserSourceAttachment
    var onOpen: (String) -> Void

    var body: some View {
        Button {
            onOpen(attachment.anchorID)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "quote.opening")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quoted source · p\(attachment.page)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(attachment.selectedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.75))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Open quoted source")
    }
}

private struct MarkdownMessageView: View {
    var messageID: String
    var markdown: String
    var fontSize: Double
    var fontFamily: ChatFontFamily
    var expandsHorizontally = false
    var onCitation: (String) -> Void
    @State private var height: CGFloat = 24

    var body: some View {
        MarkdownWebView(
            html: ChatMarkdownRenderer.renderDocument(
                markdown: markdown,
                style: ChatMarkdownRenderStyle(
                    fontSize: fontSize,
                    fontFamily: fontFamily.cssFontFamily
                )
            ),
            height: $height,
            expandsHorizontally: expandsHorizontally,
            onCitation: onCitation
        )
        .id("\(messageID)-\(markdown.hashValue)-\(fontSize)-\(fontFamily.rawValue)")
        .frame(minHeight: 24)
        .frame(minWidth: expandsHorizontally ? 0 : nil, maxWidth: expandsHorizontally ? .infinity : nil, alignment: .leading)
        .frame(height: max(24, height))
        .onChange(of: markdown) {
            height = 24
        }
        .onChange(of: fontSize) {
            height = 24
        }
        .onChange(of: fontFamily) {
            height = 24
        }
    }
}

private struct MarkdownWebView: NSViewRepresentable {
    var html: String
    @Binding var height: CGFloat
    var expandsHorizontally: Bool
    var onCitation: (String) -> Void

    private var htmlBaseURL: URL {
        Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height, onCitation: onCitation)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "height")
        let webView = ScrollForwardingWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        webView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.currentHTML = html
        webView.loadHTMLString(html, baseURL: htmlBaseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onCitation = onCitation
        webView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        webView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if context.coordinator.currentHTML != html {
            context.coordinator.currentHTML = html
            webView.loadHTMLString(html, baseURL: htmlBaseURL)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat
        var onCitation: (String) -> Void
        var currentHTML: String?

        init(height: Binding<CGFloat>, onCitation: @escaping (String) -> Void) {
            _height = height
            self.onCitation = onCitation
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "height" else {
                return
            }
            let value: CGFloat?
            if let number = message.body as? NSNumber {
                value = CGFloat(truncating: number)
            } else if let double = message.body as? Double {
                value = CGFloat(double)
            } else {
                value = nil
            }
            if let value, value > 0, abs(value - height) > 1 {
                DispatchQueue.main.async {
                    self.height = value
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.ceil(document.documentElement.scrollHeight)") { [weak self] result, _ in
                guard let self else {
                    return
                }
                let value: CGFloat?
                if let number = result as? NSNumber {
                    value = CGFloat(truncating: number)
                } else if let double = result as? Double {
                    value = CGFloat(double)
                } else {
                    value = nil
                }
                if let value, value > 0 {
                    DispatchQueue.main.async {
                        self.height = value
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               let citationID = CitationParser.citationID(from: url) {
                onCitation(citationID)
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "height")
        webView.navigationDelegate = nil
    }

    final class ScrollForwardingWebView: WKWebView {
        override func scrollWheel(with event: NSEvent) {
            if let outerScrollView = findOuterScrollView() {
                outerScrollView.scrollWheel(with: event)
                return
            }
            super.scrollWheel(with: event)
        }

        private func findOuterScrollView() -> NSScrollView? {
            var view = superview
            while let current = view {
                if let scrollView = current.enclosingScrollView {
                    return scrollView
                }
                view = current.superview
            }
            return nil
        }
    }
}
