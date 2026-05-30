import AppKit
import PaperCodexCore
import SwiftUI

struct ReaderSessionToolbarView: NSViewRepresentable {
    var selectedPanelTab: SessionPanelTab
    var sessions: [PaperSession]
    var selectedSessionID: String?
    var onSelectPanelTab: (SessionPanelTab) -> Void
    var onSelectSession: (String) -> Void
    var onNewSession: () -> Void
    var onRenameSession: (PaperSession) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ReaderSessionToolbarContainerView {
        let toolbarView = ReaderSessionToolbarContainerView()
        context.coordinator.parent = self
        toolbarView.connectTargets(to: context.coordinator)
        toolbarView.apply(self)
        return toolbarView
    }

    func updateNSView(_ toolbarView: ReaderSessionToolbarContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdatingFromSwiftUI = true
        toolbarView.apply(self)
        context.coordinator.isUpdatingFromSwiftUI = false
    }

    @MainActor final class Coordinator: NSObject {
        var parent: ReaderSessionToolbarView?
        var isUpdatingFromSwiftUI = false

        @objc func panelSelectionChanged(_ sender: NSSegmentedControl) {
            guard !isUpdatingFromSwiftUI else {
                return
            }
            switch sender.selectedSegment {
            case 0:
                parent?.onSelectPanelTab(.chat)
            case 1:
                parent?.onSelectPanelTab(.terminal)
            case 2:
                parent?.onSelectPanelTab(.notes)
            default:
                break
            }
        }

        @objc func sessionSelectionChanged(_ sender: NSPopUpButton) {
            guard !isUpdatingFromSwiftUI,
                  let sessionID = sender.selectedItem?.representedObject as? String else {
                return
            }
            parent?.onSelectSession(sessionID)
        }

        @objc func newSessionPressed(_ sender: NSButton) {
            parent?.onNewSession()
        }

        @objc func renameSessionPressed(_ sender: NSButton) {
            guard let parent,
                  let selectedSessionID = parent.selectedSessionID,
                  let session = parent.sessions.first(where: { $0.id == selectedSessionID }) else {
                return
            }
            parent.onRenameSession(session)
        }
    }
}

final class ReaderSessionToolbarContainerView: NSView {
    let panelSegmentedControl = NSSegmentedControl(labels: ["", "", ""], trackingMode: .selectOne, target: nil, action: nil)
    let sessionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let newSessionButton = NSButton(title: localized("New"), target: nil, action: nil)
    let renameButton = NSButton(title: localized("Rename"), target: nil, action: nil)

    private let firstSeparator = NSBox()
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 34)
    }

    func connectTargets(to coordinator: ReaderSessionToolbarView.Coordinator) {
        panelSegmentedControl.target = coordinator
        panelSegmentedControl.action = #selector(ReaderSessionToolbarView.Coordinator.panelSelectionChanged(_:))
        sessionPopup.target = coordinator
        sessionPopup.action = #selector(ReaderSessionToolbarView.Coordinator.sessionSelectionChanged(_:))
        newSessionButton.target = coordinator
        newSessionButton.action = #selector(ReaderSessionToolbarView.Coordinator.newSessionPressed(_:))
        renameButton.target = coordinator
        renameButton.action = #selector(ReaderSessionToolbarView.Coordinator.renameSessionPressed(_:))
    }

    func apply(_ view: ReaderSessionToolbarView) {
        panelSegmentedControl.selectedSegment = Self.segmentIndex(for: view.selectedPanelTab)
        rebuildSessionItems(sessions: view.sessions, selectedSessionID: view.selectedSessionID)
        renameButton.isEnabled = view.selectedSessionID != nil
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        configurePanelControl()
        configureSeparator(firstSeparator)

        sessionPopup.controlSize = .small
        sessionPopup.bezelStyle = .rounded
        sessionPopup.toolTip = Self.localized("Select Session")
        sessionPopup.setAccessibilityLabel(Self.localized("Session"))
        sessionPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sessionPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureTextButton(newSessionButton, symbolName: "plus", help: Self.localized("New"))
        configureTextButton(renameButton, symbolName: "pencil", help: Self.localized("Rename"))

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        [
            panelSegmentedControl,
            firstSeparator,
            sessionPopup,
            newSessionButton,
            renameButton
        ].forEach(stackView.addArrangedSubview(_:))

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            panelSegmentedControl.widthAnchor.constraint(equalToConstant: 222),
            firstSeparator.widthAnchor.constraint(equalToConstant: 1),
            sessionPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            sessionPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
    }

    private func configurePanelControl() {
        panelSegmentedControl.controlSize = .small
        panelSegmentedControl.segmentStyle = .rounded
        panelSegmentedControl.setContentHuggingPriority(.required, for: .horizontal)
        panelSegmentedControl.setContentCompressionResistancePriority(.required, for: .horizontal)
        let segments: [(String, String)] = [
            ("text.bubble", "Chat"),
            ("terminal", "Terminal"),
            ("note.text", "Notes")
        ]
        for (index, segment) in segments.enumerated() {
            panelSegmentedControl.setImage(Self.symbolImage(named: segment.0), forSegment: index)
            panelSegmentedControl.setLabel(Self.localized(segment.1), forSegment: index)
            panelSegmentedControl.setToolTip(Self.localized(segment.1), forSegment: index)
            panelSegmentedControl.setWidth(74, forSegment: index)
        }
        panelSegmentedControl.setAccessibilityLabel(Self.localized("Session Panel"))
    }

    private func configureSeparator(_ separator: NSBox) {
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 18).isActive = true
    }

    private func configureTextButton(_ button: NSButton, symbolName: String, help: String) {
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.image = Self.symbolImage(named: symbolName)
        button.imagePosition = .imageLeading
        button.toolTip = help
        button.setAccessibilityLabel(help)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func rebuildSessionItems(sessions: [PaperSession], selectedSessionID: String?) {
        let previousSelection = sessionPopup.selectedItem?.representedObject as? String
        let existingIDs = sessionPopup.itemArray.compactMap { $0.representedObject as? String }
        let nextIDs = sessions.map(\.id)
        let needsRebuild = existingIDs != nextIDs || sessionPopup.numberOfItems != sessions.count
        if needsRebuild {
            sessionPopup.removeAllItems()
            for session in sessions {
                let item = NSMenuItem(title: Self.sessionMenuTitle(session), action: nil, keyEquivalent: "")
                item.representedObject = session.id
                item.image = Self.symbolImage(named: session.paperIDs.count > 1 ? "square.stack.3d.up.fill" : "text.bubble")
                sessionPopup.menu?.addItem(item)
            }
        }

        let selectedID = selectedSessionID ?? previousSelection
        if let selectedID,
           let item = sessionPopup.itemArray.first(where: { ($0.representedObject as? String) == selectedID }) {
            sessionPopup.select(item)
            sessionPopup.toolTip = item.title
        } else {
            sessionPopup.select(nil)
            sessionPopup.toolTip = Self.localized("Select Session")
        }
        sessionPopup.isEnabled = !sessions.isEmpty
    }

    private static func segmentIndex(for tab: SessionPanelTab) -> Int {
        switch tab {
        case .chat:
            return 0
        case .terminal:
            return 1
        case .notes:
            return 2
        }
    }

    private static func sessionMenuTitle(_ session: PaperSession) -> String {
        guard session.paperIDs.count > 1 else {
            return session.title
        }
        return "\(session.title) \u{00B7} \(session.paperIDs.count) papers"
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
