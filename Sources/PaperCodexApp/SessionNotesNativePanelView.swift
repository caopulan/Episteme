import AppKit
import PaperCodexCore
import SwiftUI

struct SessionNotesNativePanelView: NSViewRepresentable {
    var paper: Paper
    var notes: [PaperNote]
    @Binding var selectedNoteID: String?
    @Binding var noteTitle: String
    @Binding var noteBody: String
    @Binding var editingNoteID: String?
    var onSelect: (PaperNote) -> Void
    var onNew: () -> Void
    var onSave: (Paper) -> Void
    var onDelete: (PaperNote) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SessionNotesContainerView {
        let notesView = SessionNotesContainerView()
        context.coordinator.parent = self
        notesView.connectTargets(to: context.coordinator)
        notesView.apply(self)
        return notesView
    }

    func updateNSView(_ notesView: SessionNotesContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdatingFromSwiftUI = true
        notesView.apply(self)
        context.coordinator.isUpdatingFromSwiftUI = false
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate {
        var parent: SessionNotesNativePanelView?
        var isUpdatingFromSwiftUI = false

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent?.notes.count ?? 0
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            76
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let note = parent?.notes[safe: row] else {
                return nil
            }
            let identifier = NSUserInterfaceItemIdentifier("SessionNoteCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? SessionNoteTableCellView
                ?? SessionNoteTableCellView(identifier: identifier)
            cell.apply(note)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI,
                  let tableView = notification.object as? NSTableView,
                  let note = parent?.notes[safe: tableView.selectedRow] else {
                return
            }
            parent?.selectedNoteID = note.id
            parent?.onSelect(note)
        }

        @objc func newNotePressed(_ sender: NSButton) {
            parent?.onNew()
        }

        @objc func deleteNotePressed(_ sender: NSButton) {
            guard let parent,
                  let noteID = parent.selectedNoteID ?? parent.editingNoteID,
                  let note = parent.notes.first(where: { $0.id == noteID }) else {
                return
            }
            parent.onDelete(note)
        }

        @objc func cancelEditPressed(_ sender: NSButton) {
            parent?.onNew()
        }

        @objc func saveNotePressed(_ sender: NSButton) {
            guard let parent else {
                return
            }
            parent.onSave(parent.paper)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }
            parent?.noteTitle = textField.stringValue
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            parent?.noteBody = textView.string
        }
    }
}

final class SessionNotesContainerView: NSView {
    let splitView = NSSplitView()
    let notesTableView = NSTableView()
    let titleField = NSTextField()
    let bodyTextView = NSTextView()
    let newNoteButton = NSButton(title: localized("New Note"), target: nil, action: nil)
    let deleteNoteButton = NSButton(title: "", target: nil, action: nil)
    let saveNoteButton = NSButton(title: localized("Add Note"), target: nil, action: nil)
    let cancelEditButton = NSButton(title: localized("Cancel"), target: nil, action: nil)

    private let toolbarContainer = NSView()
    private let toolbarStack = NSStackView()
    private let titleIconView = NSImageView()
    private let panelTitleLabel = NSTextField(labelWithString: localized("Paper Notes"))
    private let paperTitleLabel = NSTextField(labelWithString: "")
    private let noteCountLabel = NSTextField(labelWithString: "0")
    private let toolbarSeparator = NSBox()

    private let leftPane = NSView()
    private let leftHeader = NSView()
    private let leftHeaderStack = NSStackView()
    private let notesTitleLabel = NSTextField(labelWithString: localized("Notes"))
    private let listSeparator = NSBox()
    private let notesScrollView = NSScrollView()
    private let emptyNotesLabel = NSTextField(labelWithString: localized("No notes"))

    private let editorPane = NSView()
    private let editorHeader = NSView()
    private let editorHeaderStack = NSStackView()
    private let editorTitleIconView = NSImageView()
    private let editorTitleLabel = NSTextField(labelWithString: localized("New Note"))
    private let editorSeparator = NSBox()
    private let bodyScrollView = NSScrollView()
    private let footerStack = NSStackView()
    private let footerPaperLabel = NSTextField(labelWithString: "")

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

    override func layout() {
        super.layout()
        if let noteColumn = notesTableView.tableColumns.first {
            noteColumn.width = max(notesScrollView.contentSize.width, 120)
        }
    }

    func connectTargets(to coordinator: SessionNotesNativePanelView.Coordinator) {
        notesTableView.dataSource = coordinator
        notesTableView.delegate = coordinator
        titleField.delegate = coordinator
        bodyTextView.delegate = coordinator
        newNoteButton.target = coordinator
        newNoteButton.action = #selector(SessionNotesNativePanelView.Coordinator.newNotePressed(_:))
        deleteNoteButton.target = coordinator
        deleteNoteButton.action = #selector(SessionNotesNativePanelView.Coordinator.deleteNotePressed(_:))
        cancelEditButton.target = coordinator
        cancelEditButton.action = #selector(SessionNotesNativePanelView.Coordinator.cancelEditPressed(_:))
        saveNoteButton.target = coordinator
        saveNoteButton.action = #selector(SessionNotesNativePanelView.Coordinator.saveNotePressed(_:))
    }

    func apply(_ view: SessionNotesNativePanelView) {
        paperTitleLabel.stringValue = view.paper.title
        paperTitleLabel.toolTip = view.paper.title
        footerPaperLabel.stringValue = view.paper.title
        footerPaperLabel.toolTip = view.paper.title
        noteCountLabel.stringValue = "\(view.notes.count)"
        notesTableView.reloadData()
        selectNote(view.selectedNoteID, notes: view.notes)
        emptyNotesLabel.isHidden = !view.notes.isEmpty
        let deleteCandidateID = view.selectedNoteID ?? view.editingNoteID
        deleteNoteButton.isEnabled = deleteCandidateID.map { noteID in
            view.notes.contains { $0.id == noteID }
        } ?? false
        applyDraft(title: view.noteTitle, body: view.noteBody, editingNoteID: view.editingNoteID)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        configureToolbar()
        configureSplitView()
        configureLeftPane()
        configureEditorPane()
        configureSeparator(toolbarSeparator)

        [toolbarContainer, toolbarSeparator, splitView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            toolbarContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbarContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbarContainer.topAnchor.constraint(equalTo: topAnchor),
            toolbarContainer.heightAnchor.constraint(equalToConstant: 40),

            toolbarSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbarSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbarSeparator.topAnchor.constraint(equalTo: toolbarContainer.bottomAnchor),
            toolbarSeparator.heightAnchor.constraint(equalToConstant: 1),

            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: toolbarSeparator.bottomAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func configureToolbar() {
        toolbarContainer.wantsLayer = true
        toolbarContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        titleIconView.image = Self.symbolImage(named: "note.text")
        titleIconView.imageScaling = .scaleProportionallyDown
        titleIconView.widthAnchor.constraint(equalToConstant: 18).isActive = true

        panelTitleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        panelTitleLabel.setContentHuggingPriority(.required, for: .horizontal)
        paperTitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        paperTitleLabel.textColor = .secondaryLabelColor
        paperTitleLabel.lineBreakMode = .byTruncatingTail

        noteCountLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        noteCountLabel.textColor = .secondaryLabelColor
        noteCountLabel.alignment = .right
        noteCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true

        configureTextButton(newNoteButton, symbolName: "plus", help: Self.localized("New Note"))

        toolbarStack.orientation = .horizontal
        toolbarStack.alignment = .centerY
        toolbarStack.distribution = .fill
        toolbarStack.spacing = 8
        toolbarStack.edgeInsets = NSEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false
        [
            titleIconView,
            panelTitleLabel,
            paperTitleLabel,
            noteCountLabel,
            newNoteButton
        ].forEach(toolbarStack.addArrangedSubview(_:))

        toolbarContainer.addSubview(toolbarStack)
        NSLayoutConstraint.activate([
            toolbarStack.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor),
            toolbarStack.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor),
            toolbarStack.topAnchor.constraint(equalTo: toolbarContainer.topAnchor),
            toolbarStack.bottomAnchor.constraint(equalTo: toolbarContainer.bottomAnchor)
        ])
    }

    private func configureSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(leftPane)
        splitView.addArrangedSubview(editorPane)

        leftPane.translatesAutoresizingMaskIntoConstraints = false
        editorPane.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leftPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
            leftPane.widthAnchor.constraint(lessThanOrEqualToConstant: 330),
            editorPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
    }

    private func configureLeftPane() {
        leftPane.wantsLayer = true
        leftPane.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        configureSeparator(listSeparator)

        notesTitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        notesTitleLabel.textColor = .secondaryLabelColor
        configureIconButton(deleteNoteButton, symbolName: "trash", help: Self.localized("Delete Note"))
        deleteNoteButton.contentTintColor = .systemRed

        leftHeaderStack.orientation = .horizontal
        leftHeaderStack.alignment = .centerY
        leftHeaderStack.distribution = .fill
        leftHeaderStack.spacing = 8
        leftHeaderStack.edgeInsets = NSEdgeInsets(top: 7, left: 12, bottom: 7, right: 10)
        leftHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        [notesTitleLabel, NSView(), deleteNoteButton].forEach(leftHeaderStack.addArrangedSubview(_:))
        leftHeader.addSubview(leftHeaderStack)

        notesScrollView.borderType = .noBorder
        notesScrollView.hasVerticalScroller = true
        notesScrollView.drawsBackground = false
        notesScrollView.autohidesScrollers = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Note"))
        column.resizingMask = .autoresizingMask
        notesTableView.addTableColumn(column)
        notesTableView.headerView = nil
        notesTableView.rowHeight = 76
        notesTableView.intercellSpacing = NSSize(width: 0, height: 1)
        notesTableView.usesAlternatingRowBackgroundColors = false
        notesTableView.selectionHighlightStyle = .regular
        notesTableView.backgroundColor = .controlBackgroundColor
        notesTableView.setAccessibilityLabel(Self.localized("Notes"))
        notesScrollView.documentView = notesTableView

        emptyNotesLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        emptyNotesLabel.textColor = .secondaryLabelColor
        emptyNotesLabel.alignment = .center

        [leftHeader, listSeparator, notesScrollView, emptyNotesLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            leftPane.addSubview($0)
        }

        NSLayoutConstraint.activate([
            leftHeader.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            leftHeader.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            leftHeader.topAnchor.constraint(equalTo: leftPane.topAnchor),
            leftHeader.heightAnchor.constraint(equalToConstant: 36),
            leftHeaderStack.leadingAnchor.constraint(equalTo: leftHeader.leadingAnchor),
            leftHeaderStack.trailingAnchor.constraint(equalTo: leftHeader.trailingAnchor),
            leftHeaderStack.topAnchor.constraint(equalTo: leftHeader.topAnchor),
            leftHeaderStack.bottomAnchor.constraint(equalTo: leftHeader.bottomAnchor),

            listSeparator.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            listSeparator.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            listSeparator.topAnchor.constraint(equalTo: leftHeader.bottomAnchor),
            listSeparator.heightAnchor.constraint(equalToConstant: 1),

            notesScrollView.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            notesScrollView.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            notesScrollView.topAnchor.constraint(equalTo: listSeparator.bottomAnchor),
            notesScrollView.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),

            emptyNotesLabel.centerXAnchor.constraint(equalTo: notesScrollView.centerXAnchor),
            emptyNotesLabel.centerYAnchor.constraint(equalTo: notesScrollView.centerYAnchor)
        ])
    }

    private func configureEditorPane() {
        editorPane.wantsLayer = true
        editorPane.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        configureSeparator(editorSeparator)

        editorTitleIconView.image = Self.symbolImage(named: "square.and.pencil")
        editorTitleIconView.imageScaling = .scaleProportionallyDown
        editorTitleIconView.widthAnchor.constraint(equalToConstant: 18).isActive = true

        editorTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        configureTextButton(cancelEditButton, help: Self.localized("Cancel"))

        editorHeaderStack.orientation = .horizontal
        editorHeaderStack.alignment = .centerY
        editorHeaderStack.distribution = .fill
        editorHeaderStack.spacing = 8
        editorHeaderStack.edgeInsets = NSEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
        editorHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        [editorTitleIconView, editorTitleLabel, NSView(), cancelEditButton].forEach(editorHeaderStack.addArrangedSubview(_:))
        editorHeader.addSubview(editorHeaderStack)

        titleField.placeholderString = Self.localized("Note title")
        titleField.bezelStyle = .roundedBezel
        titleField.font = .systemFont(ofSize: NSFont.systemFontSize)
        titleField.setAccessibilityLabel(Self.localized("Note title"))

        bodyScrollView.borderType = .lineBorder
        bodyScrollView.hasVerticalScroller = true
        bodyScrollView.drawsBackground = true
        bodyScrollView.backgroundColor = .textBackgroundColor
        bodyScrollView.autohidesScrollers = true

        bodyTextView.isRichText = false
        bodyTextView.isAutomaticQuoteSubstitutionEnabled = false
        bodyTextView.isAutomaticDashSubstitutionEnabled = false
        bodyTextView.isAutomaticTextReplacementEnabled = false
        bodyTextView.font = .systemFont(ofSize: 13)
        bodyTextView.drawsBackground = false
        bodyTextView.textContainerInset = NSSize(width: 8, height: 8)
        bodyTextView.minSize = NSSize(width: 0, height: 0)
        bodyTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        bodyTextView.isVerticallyResizable = true
        bodyTextView.isHorizontallyResizable = false
        bodyTextView.autoresizingMask = [.width]
        bodyTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        bodyTextView.textContainer?.widthTracksTextView = true
        bodyTextView.setAccessibilityLabel(Self.localized("Note body"))
        bodyScrollView.documentView = bodyTextView

        configureTextButton(saveNoteButton, symbolName: "checkmark", help: Self.localized("Add Note"))
        footerPaperLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        footerPaperLabel.textColor = .tertiaryLabelColor
        footerPaperLabel.lineBreakMode = .byTruncatingTail

        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.distribution = .fill
        footerStack.spacing = 8
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        [saveNoteButton, footerPaperLabel].forEach(footerStack.addArrangedSubview(_:))

        [editorHeader, editorSeparator, titleField, bodyScrollView, footerStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            editorPane.addSubview($0)
        }

        NSLayoutConstraint.activate([
            editorHeader.leadingAnchor.constraint(equalTo: editorPane.leadingAnchor),
            editorHeader.trailingAnchor.constraint(equalTo: editorPane.trailingAnchor),
            editorHeader.topAnchor.constraint(equalTo: editorPane.topAnchor),
            editorHeader.heightAnchor.constraint(equalToConstant: 40),
            editorHeaderStack.leadingAnchor.constraint(equalTo: editorHeader.leadingAnchor),
            editorHeaderStack.trailingAnchor.constraint(equalTo: editorHeader.trailingAnchor),
            editorHeaderStack.topAnchor.constraint(equalTo: editorHeader.topAnchor),
            editorHeaderStack.bottomAnchor.constraint(equalTo: editorHeader.bottomAnchor),

            editorSeparator.leadingAnchor.constraint(equalTo: editorPane.leadingAnchor),
            editorSeparator.trailingAnchor.constraint(equalTo: editorPane.trailingAnchor),
            editorSeparator.topAnchor.constraint(equalTo: editorHeader.bottomAnchor),
            editorSeparator.heightAnchor.constraint(equalToConstant: 1),

            titleField.leadingAnchor.constraint(equalTo: editorPane.leadingAnchor, constant: 14),
            titleField.trailingAnchor.constraint(equalTo: editorPane.trailingAnchor, constant: -14),
            titleField.topAnchor.constraint(equalTo: editorSeparator.bottomAnchor, constant: 14),

            bodyScrollView.leadingAnchor.constraint(equalTo: editorPane.leadingAnchor, constant: 14),
            bodyScrollView.trailingAnchor.constraint(equalTo: editorPane.trailingAnchor, constant: -14),
            bodyScrollView.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 10),
            bodyScrollView.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -10),

            footerStack.leadingAnchor.constraint(equalTo: editorPane.leadingAnchor, constant: 14),
            footerStack.trailingAnchor.constraint(equalTo: editorPane.trailingAnchor, constant: -14),
            footerStack.bottomAnchor.constraint(equalTo: editorPane.bottomAnchor, constant: -14),
            saveNoteButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92)
        ])
    }

    private func applyDraft(title: String, body: String, editingNoteID: String?) {
        if titleField.stringValue != title {
            titleField.stringValue = title
        }
        if bodyTextView.string != body {
            bodyTextView.string = body
        }
        let isEditing = editingNoteID != nil
        editorTitleLabel.stringValue = Self.localized(isEditing ? "Edit Note" : "New Note")
        cancelEditButton.isHidden = !isEditing
        saveNoteButton.title = Self.localized(isEditing ? "Save Note" : "Add Note")
        saveNoteButton.toolTip = saveNoteButton.title
        saveNoteButton.setAccessibilityLabel(saveNoteButton.title)
        let titleIsEmpty = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let bodyIsEmpty = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        saveNoteButton.isEnabled = !(titleIsEmpty && bodyIsEmpty)
    }

    private func selectNote(_ selectedNoteID: String?, notes: [PaperNote]) {
        guard let selectedNoteID,
              let row = notes.firstIndex(where: { $0.id == selectedNoteID }) else {
            notesTableView.deselectAll(nil)
            return
        }
        let rowIndexes = IndexSet(integer: row)
        if notesTableView.selectedRowIndexes != rowIndexes {
            notesTableView.selectRowIndexes(rowIndexes, byExtendingSelection: false)
            notesTableView.scrollRowToVisible(row)
        }
    }

    private func configureSeparator(_ separator: NSBox) {
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
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

    private func configureTextButton(_ button: NSButton, symbolName: String? = nil, help: String) {
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.image = symbolName.flatMap { Self.symbolImage(named: $0) }
        button.imagePosition = symbolName == nil ? .noImage : .imageLeading
        button.toolTip = help
        button.setAccessibilityLabel(help)
        button.setContentHuggingPriority(.required, for: .horizontal)
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

private final class SessionNoteTableCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let stackView = NSStackView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func apply(_ note: PaperNote) {
        titleLabel.stringValue = note.title
        bodyLabel.stringValue = note.bodyMarkdown.isEmpty ? SessionNotesContainerView.localized("No body") : note.bodyMarkdown
        bodyLabel.isHidden = note.bodyMarkdown.isEmpty
        dateLabel.stringValue = Self.dateFormatter.string(from: note.updatedAt)
        toolTip = note.title
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        titleLabel.font = .systemFont(ofSize: 12.8, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        bodyLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.maximumNumberOfLines = 2

        dateLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .regular)
        dateLabel.textColor = .tertiaryLabelColor
        dateLabel.lineBreakMode = .byTruncatingTail

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .gravityAreas
        stackView.spacing = 4
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        [titleLabel, bodyLabel, dateLabel].forEach(stackView.addArrangedSubview(_:))
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
