import AppKit
import PaperCodexCore
import SwiftUI

struct ReaderNativeToolbarView: NSViewRepresentable {
    var status: PDFDocumentStatus?
    var papers: [Paper]
    var activePaperID: String?
    var returnPoint: CitationReturnPoint?
    var isSplitVisible: Bool
    var onSelectPaper: (Paper) -> Void
    var onAddPaper: () -> Void
    var onRemoveActivePaper: () -> Void
    var onCommand: (PDFKitCommandKind) -> Void
    var onReturn: () -> Void
    var onToggleSplit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ReaderToolbarContainerView {
        let toolbarView = ReaderToolbarContainerView()
        context.coordinator.parent = self
        toolbarView.connectTargets(to: context.coordinator)
        toolbarView.apply(self)
        return toolbarView
    }

    func updateNSView(_ toolbarView: ReaderToolbarContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdatingFromSwiftUI = true
        toolbarView.apply(self)
        context.coordinator.isUpdatingFromSwiftUI = false
    }

    @MainActor final class Coordinator: NSObject {
        var parent: ReaderNativeToolbarView?
        var isUpdatingFromSwiftUI = false

        @objc func pageSegmentChanged(_ sender: NSSegmentedControl) {
            switch sender.selectedSegment {
            case 0:
                onCommand(.previousPage)
            case 1:
                onCommand(.nextPage)
            default:
                break
            }
            sender.selectedSegment = -1
        }

        @objc func zoomSegmentChanged(_ sender: NSSegmentedControl) {
            switch sender.selectedSegment {
            case 0:
                onCommand(.zoomOut)
            case 1:
                onCommand(.zoomIn)
            case 2:
                onCommand(.fitWidth)
            default:
                break
            }
            sender.selectedSegment = -1
        }

        @objc func paperSelectionChanged(_ sender: NSPopUpButton) {
            guard !isUpdatingFromSwiftUI,
                  let paperID = sender.selectedItem?.representedObject as? String,
                  let paper = parent?.papers.first(where: { $0.id == paperID }) else {
                return
            }
            parent?.onSelectPaper(paper)
        }

        @objc func addPaperPressed(_ sender: NSButton) {
            parent?.onAddPaper()
        }

        @objc func removePaperPressed(_ sender: NSButton) {
            parent?.onRemoveActivePaper()
        }

        @objc func toggleSplitPressed(_ sender: NSButton) {
            parent?.onToggleSplit()
        }

        @objc func returnPressed(_ sender: NSButton) {
            parent?.onReturn()
        }

        private func onCommand(_ command: PDFKitCommandKind) {
            parent?.onCommand(command)
        }
    }
}

final class ReaderToolbarContainerView: NSView {
    let pageStatusLabel = NSTextField(labelWithString: "")
    let zoomStatusLabel = NSTextField(labelWithString: "")
    let paperPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private let pageSegmentedControl = NSSegmentedControl(labels: ["", ""], trackingMode: .momentary, target: nil, action: nil)
    private let zoomSegmentedControl = NSSegmentedControl(labels: ["", "", ""], trackingMode: .momentary, target: nil, action: nil)
    private let paperIconView = NSImageView()
    private let paperCountLabel = NSTextField(labelWithString: "0")
    private let addPaperButton = ReaderToolbarContainerView.makeIconButton(symbolName: "plus", help: localized("Add Paper"))
    private let removePaperButton = ReaderToolbarContainerView.makeIconButton(symbolName: "xmark", help: localized("Remove Current Paper"))
    private let splitButton = ReaderToolbarContainerView.makeIconButton(symbolName: "rectangle.split.2x1", help: localized("Open PDF Split"))
    private let returnButton = NSButton(title: localized("Back to source"), target: nil, action: nil)
    private let flexibleSpacer = NSView()
    private let stackView = NSStackView()
    private let firstSeparator = NSBox()
    private let secondSeparator = NSBox()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 36)
    }

    func connectTargets(to coordinator: ReaderNativeToolbarView.Coordinator) {
        pageSegmentedControl.target = coordinator
        pageSegmentedControl.action = #selector(ReaderNativeToolbarView.Coordinator.pageSegmentChanged(_:))
        zoomSegmentedControl.target = coordinator
        zoomSegmentedControl.action = #selector(ReaderNativeToolbarView.Coordinator.zoomSegmentChanged(_:))
        paperPopup.target = coordinator
        paperPopup.action = #selector(ReaderNativeToolbarView.Coordinator.paperSelectionChanged(_:))
        addPaperButton.target = coordinator
        addPaperButton.action = #selector(ReaderNativeToolbarView.Coordinator.addPaperPressed(_:))
        removePaperButton.target = coordinator
        removePaperButton.action = #selector(ReaderNativeToolbarView.Coordinator.removePaperPressed(_:))
        splitButton.target = coordinator
        splitButton.action = #selector(ReaderNativeToolbarView.Coordinator.toggleSplitPressed(_:))
        returnButton.target = coordinator
        returnButton.action = #selector(ReaderNativeToolbarView.Coordinator.returnPressed(_:))
    }

    func apply(_ view: ReaderNativeToolbarView) {
        pageStatusLabel.stringValue = Self.pageText(for: view.status)
        zoomStatusLabel.stringValue = Self.zoomText(for: view.status)
        paperCountLabel.stringValue = "\(view.papers.count)"
        paperIconView.image = Self.symbolImage(named: view.papers.count > 1 ? "square.stack.3d.up.fill" : "doc.text")
        rebuildPaperItems(papers: view.papers, activePaperID: view.activePaperID)
        removePaperButton.isEnabled = view.papers.count > 1
        applySplitButton(isSplitVisible: view.isSplitVisible)
        applyReturnButton(returnPoint: view.returnPoint)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        configureSegmentedControl(pageSegmentedControl, symbols: [
            ("chevron.up", Self.localized("Previous Page")),
            ("chevron.down", Self.localized("Next Page"))
        ])
        configureSegmentedControl(zoomSegmentedControl, symbols: [
            ("minus.magnifyingglass", Self.localized("Zoom Out")),
            ("plus.magnifyingglass", Self.localized("Zoom In")),
            ("arrow.left.and.right", Self.localized("Fit Width"))
        ])

        pageStatusLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        pageStatusLabel.textColor = .secondaryLabelColor
        pageStatusLabel.alignment = .left
        pageStatusLabel.setContentHuggingPriority(.required, for: .horizontal)
        pageStatusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        zoomStatusLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        zoomStatusLabel.textColor = .secondaryLabelColor
        zoomStatusLabel.alignment = .left
        zoomStatusLabel.setContentHuggingPriority(.required, for: .horizontal)
        zoomStatusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        paperIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        paperIconView.contentTintColor = .secondaryLabelColor
        paperIconView.setContentHuggingPriority(.required, for: .horizontal)

        paperCountLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        paperCountLabel.textColor = .secondaryLabelColor
        paperCountLabel.alignment = .left
        paperCountLabel.setContentHuggingPriority(.required, for: .horizontal)
        paperCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        paperPopup.controlSize = .small
        paperPopup.bezelStyle = .rounded
        paperPopup.toolTip = Self.localized("Select Paper")
        paperPopup.setAccessibilityLabel(Self.localized("Paper"))
        paperPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        paperPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        splitButton.keyEquivalent = "\\"
        splitButton.keyEquivalentModifierMask = [.command, .shift]

        configureTextButton(returnButton, symbolName: "arrow.uturn.backward", help: Self.localized("Back to source"))

        flexibleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        flexibleSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureSeparator(firstSeparator)
        configureSeparator(secondSeparator)

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        [
            pageSegmentedControl,
            pageStatusLabel,
            firstSeparator,
            zoomSegmentedControl,
            zoomStatusLabel,
            secondSeparator,
            paperIconView,
            paperCountLabel,
            paperPopup,
            addPaperButton,
            removePaperButton,
            splitButton,
            flexibleSpacer,
            returnButton
        ].forEach(stackView.addArrangedSubview(_:))

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            pageStatusLabel.widthAnchor.constraint(equalToConstant: 82),
            zoomStatusLabel.widthAnchor.constraint(equalToConstant: 48),
            paperIconView.widthAnchor.constraint(equalToConstant: 16),
            paperIconView.heightAnchor.constraint(equalToConstant: 18),
            paperCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            paperPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            paperPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            firstSeparator.widthAnchor.constraint(equalToConstant: 1),
            secondSeparator.widthAnchor.constraint(equalToConstant: 1)
        ])
    }

    private func configureSegmentedControl(_ control: NSSegmentedControl, symbols: [(String, String)]) {
        control.controlSize = .small
        control.segmentStyle = .rounded
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        for (index, symbol) in symbols.enumerated() {
            control.setImage(Self.symbolImage(named: symbol.0), forSegment: index)
            control.setToolTip(symbol.1, forSegment: index)
            control.setWidth(31, forSegment: index)
        }
        control.selectedSegment = -1
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
        button.setAccessibilityLabel(button.title)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func rebuildPaperItems(papers: [Paper], activePaperID: String?) {
        let previousSelection = paperPopup.selectedItem?.representedObject as? String
        let existingIDs = paperPopup.itemArray.compactMap { $0.representedObject as? String }
        let nextIDs = papers.map(\.id)
        let needsRebuild = existingIDs != nextIDs || paperPopup.numberOfItems != papers.count
        if needsRebuild {
            paperPopup.removeAllItems()
            for paper in papers {
                let item = NSMenuItem(title: paper.title, action: nil, keyEquivalent: "")
                item.representedObject = paper.id
                item.image = Self.symbolImage(named: "doc.text")
                paperPopup.menu?.addItem(item)
            }
        }

        let selectedID = activePaperID ?? previousSelection
        if let selectedID,
           let item = paperPopup.itemArray.first(where: { ($0.representedObject as? String) == selectedID }) {
            paperPopup.select(item)
            paperPopup.toolTip = item.title
        } else {
            paperPopup.select(nil)
            paperPopup.toolTip = Self.localized("Select Paper")
        }
        paperPopup.isEnabled = !papers.isEmpty
    }

    private func applySplitButton(isSplitVisible: Bool) {
        splitButton.image = Self.symbolImage(named: isSplitVisible ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
        splitButton.toolTip = Self.localized(isSplitVisible ? "Close PDF Split" : "Open PDF Split")
        splitButton.setAccessibilityLabel(Self.localized(isSplitVisible ? "Close PDF Split" : "Open PDF Split"))
        splitButton.contentTintColor = isSplitVisible ? .controlAccentColor : nil
    }

    private func applyReturnButton(returnPoint: CitationReturnPoint?) {
        returnButton.isHidden = returnPoint == nil
        returnButton.toolTip = returnPoint?.paperTitle ?? Self.localized("Back to source")
    }

    private static func makeIconButton(symbolName: String, help: String) -> NSButton {
        let button = NSButton(title: "", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.image = symbolImage(named: symbolName)
        button.imagePosition = .imageOnly
        button.toolTip = help
        button.setAccessibilityLabel(help)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])
        return button
    }

    private static func pageText(for status: PDFDocumentStatus?) -> String {
        guard let status, status.pageCount > 0 else {
            return "\(localized("Page")) --"
        }
        return "\(localized("Page")) \(status.pageIndex + 1)/\(status.pageCount)"
    }

    private static func zoomText(for status: PDFDocumentStatus?) -> String {
        guard let status else {
            return "--%"
        }
        return "\(Int((status.scaleFactor * 100).rounded()))%"
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
