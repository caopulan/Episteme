import AppKit
import SwiftUI

struct LibraryNativeToolbarView: NSViewRepresentable {
    @Binding var searchText: String
    @Binding var sortRawValue: String
    @Binding var sortAscending: Bool
    @Binding var includeSubfolders: Bool

    var paperCount: Int
    var showsFolderScope: Bool
    var showsReadActions: Bool
    var canRead: Bool
    var hasActiveFilters: Bool
    var isLibraryActive: Bool
    var searchFocusRequestID: UUID
    var onRead: () -> Void
    var onChat: () -> Void
    var onClearFilters: () -> Void
    var onShowWatchedFolders: () -> Void
    var onShowArxivImport: () -> Void
    var onImportPDF: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LibraryToolbarContainerView {
        let toolbarView = LibraryToolbarContainerView()
        context.coordinator.parent = self
        context.coordinator.lastSearchFocusRequestID = searchFocusRequestID
        toolbarView.connectTargets(to: context.coordinator)
        toolbarView.apply(self)
        return toolbarView
    }

    func updateNSView(_ toolbarView: LibraryToolbarContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdatingFromSwiftUI = true
        toolbarView.apply(self)
        context.coordinator.isUpdatingFromSwiftUI = false
        context.coordinator.applyFocusIfNeeded(in: toolbarView)
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: LibraryNativeToolbarView?
        var isUpdatingFromSwiftUI = false
        var lastSearchFocusRequestID: UUID?

        func controlTextDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI,
                  let searchField = notification.object as? NSSearchField else {
                return
            }
            parent?.searchText = searchField.stringValue
        }

        @objc func scopeTogglePressed(_ sender: NSButton) {
            guard let includeSubfolders = parent?.includeSubfolders else {
                return
            }
            parent?.includeSubfolders = !includeSubfolders
        }

        @objc func clearFiltersPressed(_ sender: NSButton) {
            parent?.onClearFilters()
        }

        @objc func readPressed(_ sender: NSButton) {
            parent?.onRead()
        }

        @objc func chatPressed(_ sender: NSButton) {
            parent?.onChat()
        }

        @objc func watchedFoldersPressed(_ sender: NSButton) {
            parent?.onShowWatchedFolders()
        }

        @objc func arxivImportPressed(_ sender: NSButton) {
            parent?.onShowArxivImport()
        }

        @objc func sortSelectionChanged(_ sender: NSPopUpButton) {
            guard !isUpdatingFromSwiftUI,
                  let rawValue = sender.selectedItem?.representedObject as? String else {
                return
            }
            parent?.sortRawValue = rawValue
        }

        @objc func sortDirectionPressed(_ sender: NSButton) {
            guard let sortAscending = parent?.sortAscending else {
                return
            }
            parent?.sortAscending = !sortAscending
        }

        @objc func importPDFPressed(_ sender: NSButton) {
            parent?.onImportPDF()
        }

        func applyFocusIfNeeded(in toolbarView: LibraryToolbarContainerView) {
            guard let parent else {
                return
            }
            guard parent.searchFocusRequestID != lastSearchFocusRequestID else {
                return
            }
            lastSearchFocusRequestID = parent.searchFocusRequestID
            guard parent.isLibraryActive else {
                return
            }
            toolbarView.window?.makeFirstResponder(toolbarView.searchField)
        }
    }
}

final class LibraryToolbarContainerView: NSView {
    let searchField = NSSearchField()
    let sortDirectionButton = LibraryToolbarContainerView.makeIconButton(symbolName: "arrow.down", help: "Descending")
    let clearFiltersButton = LibraryToolbarContainerView.makeIconButton(
        symbolName: "line.3.horizontal.decrease.circle",
        help: LibraryToolbarContainerView.localized("Clear Filters")
    )

    private let titleLabel = NSTextField(labelWithString: LibraryToolbarContainerView.localized("Library"))
    private let countLabel = NSTextField(labelWithString: "0 papers")
    private let scopeToggleButton = NSButton(title: "All levels", target: nil, action: nil)
    private let readButton = NSButton(title: "Read", target: nil, action: nil)
    private let chatButton = NSButton(title: "Chat", target: nil, action: nil)
    private let watchedFoldersButton = LibraryToolbarContainerView.makeIconButton(symbolName: "folder.badge.plus", help: LibraryToolbarContainerView.localized("Folders"))
    private let arxivImportButton = LibraryToolbarContainerView.makeIconButton(symbolName: "number", help: LibraryToolbarContainerView.localized("arXiv"))
    private let sortPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let importPDFButton = NSButton(title: LibraryToolbarContainerView.localized("Import PDF"), target: nil, action: nil)
    private let flexibleSpacer = NSView()
    private let stackView = NSStackView()

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

    func connectTargets(to coordinator: LibraryNativeToolbarView.Coordinator) {
        searchField.delegate = coordinator
        scopeToggleButton.target = coordinator
        scopeToggleButton.action = #selector(LibraryNativeToolbarView.Coordinator.scopeTogglePressed(_:))
        clearFiltersButton.target = coordinator
        clearFiltersButton.action = #selector(LibraryNativeToolbarView.Coordinator.clearFiltersPressed(_:))
        readButton.target = coordinator
        readButton.action = #selector(LibraryNativeToolbarView.Coordinator.readPressed(_:))
        chatButton.target = coordinator
        chatButton.action = #selector(LibraryNativeToolbarView.Coordinator.chatPressed(_:))
        watchedFoldersButton.target = coordinator
        watchedFoldersButton.action = #selector(LibraryNativeToolbarView.Coordinator.watchedFoldersPressed(_:))
        arxivImportButton.target = coordinator
        arxivImportButton.action = #selector(LibraryNativeToolbarView.Coordinator.arxivImportPressed(_:))
        sortPopup.target = coordinator
        sortPopup.action = #selector(LibraryNativeToolbarView.Coordinator.sortSelectionChanged(_:))
        sortDirectionButton.target = coordinator
        sortDirectionButton.action = #selector(LibraryNativeToolbarView.Coordinator.sortDirectionPressed(_:))
        importPDFButton.target = coordinator
        importPDFButton.action = #selector(LibraryNativeToolbarView.Coordinator.importPDFPressed(_:))
    }

    func apply(_ view: LibraryNativeToolbarView) {
        if searchField.stringValue != view.searchText {
            searchField.stringValue = view.searchText
        }
        countLabel.stringValue = "\(view.paperCount) papers"
        applyScopeState(includeSubfolders: view.includeSubfolders, isVisible: view.showsFolderScope)
        clearFiltersButton.isHidden = !view.hasActiveFilters
        readButton.isHidden = !view.showsReadActions
        chatButton.isHidden = !view.showsReadActions
        readButton.isEnabled = view.canRead
        chatButton.isEnabled = view.canRead
        applySortSelection(rawValue: view.sortRawValue)
        applySortDirection(ascending: view.sortAscending)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        searchField.placeholderString = Self.localized("Search title, author, tag, category, year, or source")
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: 14)
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        configureTextButton(scopeToggleButton, symbolName: "folder.badge.gearshape", help: Self.localized("Showing current folder and subfolders"))
        configureTextButton(readButton, symbolName: "book", help: Self.localized("Read visible papers"))
        configureTextButton(chatButton, symbolName: "text.bubble", help: Self.localized("Chat with visible papers"))
        configureTextButton(importPDFButton, symbolName: "plus", help: Self.localized("Import PDF"))

        sortPopup.controlSize = .small
        sortPopup.bezelStyle = .rounded
        sortPopup.toolTip = Self.localized("Sort Library")
        sortPopup.setContentHuggingPriority(.required, for: .horizontal)
        sortPopup.setContentCompressionResistancePriority(.required, for: .horizontal)
        rebuildSortItems()

        flexibleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        flexibleSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        [
            titleLabel,
            searchField,
            countLabel,
            scopeToggleButton,
            flexibleSpacer,
            clearFiltersButton,
            readButton,
            chatButton,
            watchedFoldersButton,
            arxivImportButton,
            sortPopup,
            sortDirectionButton,
            importPDFButton
        ].forEach(stackView.addArrangedSubview(_:))

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 210),
            sortPopup.widthAnchor.constraint(equalToConstant: 116)
        ])
    }

    private func rebuildSortItems() {
        sortPopup.removeAllItems()
        for option in LibrarySortOption.allCases {
            let item = NSMenuItem(title: Self.localized(option.title), action: nil, keyEquivalent: "")
            item.representedObject = option.rawValue
            item.image = Self.symbolImage(named: option.systemImage)
            sortPopup.menu?.addItem(item)
        }
    }

    private func applyScopeState(includeSubfolders: Bool, isVisible: Bool) {
        scopeToggleButton.isHidden = !isVisible
        if includeSubfolders {
            scopeToggleButton.title = Self.localized("All levels")
            scopeToggleButton.image = Self.symbolImage(named: "folder.badge.gearshape")
            scopeToggleButton.toolTip = Self.localized("Showing current folder and subfolders")
            scopeToggleButton.setAccessibilityLabel(Self.localized("Show Current Folder Only"))
        } else {
            scopeToggleButton.title = Self.localized("This folder")
            scopeToggleButton.image = Self.symbolImage(named: "folder")
            scopeToggleButton.toolTip = Self.localized("Showing current folder only")
            scopeToggleButton.setAccessibilityLabel(Self.localized("Show Current Folder And Subfolders"))
        }
    }

    private func applySortSelection(rawValue: String) {
        guard let item = sortPopup.itemArray.first(where: { ($0.representedObject as? String) == rawValue }) else {
            return
        }
        sortPopup.select(item)
    }

    private func applySortDirection(ascending: Bool) {
        let symbolName = ascending ? "arrow.up" : "arrow.down"
        sortDirectionButton.image = Self.symbolImage(named: symbolName)
        sortDirectionButton.toolTip = ascending ? Self.localized("Ascending") : Self.localized("Descending")
        sortDirectionButton.setAccessibilityLabel(ascending ? Self.localized("Sort Ascending") : Self.localized("Sort Descending"))
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
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        return button
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

    private static func symbolImage(named name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        return image?.withSymbolConfiguration(configuration)
    }

    private static func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
