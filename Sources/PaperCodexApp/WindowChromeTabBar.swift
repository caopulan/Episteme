import AppKit
import PaperCodexCore
import SwiftUI

struct PaperCodexWindowTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @State private var isWindowFullscreen = false

    var onShowSaveToLibrary: () -> Void

    var body: some View {
        NativeWindowChromeTabBarView(
            tabs: model.readerTabState.tabs,
            activePaperID: activeReaderPaperID,
            isHomeActive: navigation.route != .reader,
            homeHelpText: homeTabHelp,
            showsSaveToLibrary: model.selectedPaper.map { !$0.isSaved } ?? false,
            leadingInset: isWindowFullscreen ? PaperCodexWindowChrome.tabBarFullscreenLeadingInset : PaperCodexWindowChrome.tabBarTrafficLightLeadingInset,
            reduceMotion: reduceMotion,
            selectHome: selectHomeTab,
            selectTab: { tab in
                model.selectReaderTab(tab)
            },
            closeTab: { tab in
                model.closeReaderTab(tab)
            },
            showSaveToLibrary: {
                onShowSaveToLibrary()
            }
        )
        .frame(height: PaperCodexWindowChrome.tabBarHeight)
        .background(
            PaperCodexWindowFullscreenObserver { isFullscreen in
                isWindowFullscreen = isFullscreen
            }
        )
    }

    private var activeReaderPaperID: String? {
        guard navigation.route == .reader else {
            return nil
        }
        return model.selectedPaper?.id ?? model.readerTabState.activePaperID
    }

    private var homeTabHelp: String {
        switch navigation.route {
        case .library:
            return model.selectedLibrarySurface == .recentConversations ? "Home: Recent Conversations" : "Home: Library"
        case .discover:
            return "Home: 探索"
        case .search:
            return "Home: 搜索"
        case .settings:
            return "Home: Settings"
        case .reader:
            return "Home (Library, 探索, 搜索, Settings, Recent Conversations)"
        }
    }

    private func selectHomeTab() {
        if navigation.route == .reader {
            model.returnFromReader()
        } else {
            model.goToLibrary()
        }
    }
}

private struct NativeWindowChromeTabBarView: NSViewRepresentable {
    var tabs: [ReaderPaperTab]
    var activePaperID: String?
    var isHomeActive: Bool
    var homeHelpText: String
    var showsSaveToLibrary: Bool
    var leadingInset: CGFloat
    var reduceMotion: Bool
    var selectHome: () -> Void
    var selectTab: (ReaderPaperTab) -> Void
    var closeTab: (ReaderPaperTab) -> Void
    var showSaveToLibrary: () -> Void

    func makeNSView(context: Context) -> NativeWindowChromeTabBarContainerView {
        let view = NativeWindowChromeTabBarContainerView()
        view.apply(self)
        return view
    }

    func updateNSView(_ view: NativeWindowChromeTabBarContainerView, context: Context) {
        view.apply(self)
    }
}

private final class NativeWindowChromeTabBarContainerView: NSView {
    private let dividerView = NSView()
    private let contentStack = NSStackView()
    private let homeButton = NativeChromeHomeTabButton()
    private let scrollView = NSScrollView()
    private let tabStack = NSStackView()
    private let saveButton = NativeSaveToLibraryChromeButton()
    private var leadingConstraint: NSLayoutConstraint?
    private var lastRenderedTabIDs: [String] = []
    private var tabViewsByID: [String: NativeReaderChromeTabView] = [:]
    private var activePaperID: String?
    private var reduceMotion = false
    private var selectHomeHandler: () -> Void = {}
    private var selectTabHandler: (ReaderPaperTab) -> Void = { _ in }
    private var closeTabHandler: (ReaderPaperTab) -> Void = { _ in }
    private var saveToLibraryHandler: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func layout() {
        super.layout()
        updateTabDocumentFrame()
        scrollActiveTabToVisible()
    }

    func apply(_ view: NativeWindowChromeTabBarView) {
        activePaperID = view.activePaperID
        reduceMotion = view.reduceMotion
        selectHomeHandler = view.selectHome
        selectTabHandler = view.selectTab
        closeTabHandler = view.closeTab
        saveToLibraryHandler = view.showSaveToLibrary
        leadingConstraint?.constant = view.leadingInset

        homeButton.apply(isActive: view.isHomeActive, helpText: view.homeHelpText, reduceMotion: view.reduceMotion)
        saveButton.isHidden = !view.showsSaveToLibrary
        saveButton.apply(reduceMotion: view.reduceMotion)

        let tabIDs = view.tabs.map(\.paperID)
        if tabIDs != lastRenderedTabIDs {
            rebuildReaderTabs(view.tabs)
        } else {
            updateReaderTabs(view.tabs)
        }
        updateTabDocumentFrame()
        scrollActiveTabToVisible()
        needsLayout = true
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = PaperCodexChromeTabStyle.barBackground.cgColor

        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = PaperCodexChromeTabStyle.divider.cgColor
        addSubview(dividerView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .horizontal
        contentStack.alignment = .bottom
        contentStack.spacing = 0
        addSubview(contentStack)

        homeButton.target = self
        homeButton.action = #selector(homePressed(_:))
        contentStack.addArrangedSubview(homeButton)

        configureScrollView()
        contentStack.addArrangedSubview(scrollView)

        saveButton.target = self
        saveButton.action = #selector(saveToLibraryPressed(_:))
        contentStack.addArrangedSubview(saveButton)

        leadingConstraint = contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PaperCodexWindowChrome.tabBarTrafficLightLeadingInset)
        NSLayoutConstraint.activate([
            dividerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dividerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dividerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerView.heightAnchor.constraint(equalToConstant: 1),
            leadingConstraint!,
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentStack.heightAnchor.constraint(equalToConstant: PaperCodexWindowChrome.tabBarHeight),
            scrollView.heightAnchor.constraint(equalToConstant: PaperCodexWindowChrome.tabBarHeight)
        ])
    }

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.postsBoundsChangedNotifications = false
        scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        tabStack.orientation = .horizontal
        tabStack.alignment = .bottom
        tabStack.spacing = 0
        tabStack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        scrollView.documentView = tabStack
    }

    private func rebuildReaderTabs(_ tabs: [ReaderPaperTab]) {
        tabStack.arrangedSubviews.forEach { subview in
            tabStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        tabViewsByID.removeAll(keepingCapacity: true)
        lastRenderedTabIDs = tabs.map(\.paperID)

        for tab in tabs {
            let tabView = NativeReaderChromeTabView()
            tabView.onSelect = { [weak self] tab in
                self?.selectTab(tab)
            }
            tabView.onClose = { [weak self] tab in
                self?.closeTab(tab)
            }
            tabView.apply(tab: tab, isActive: tab.paperID == activePaperID, reduceMotion: reduceMotion)
            tabStack.addArrangedSubview(tabView)
            tabViewsByID[tab.paperID] = tabView
        }
    }

    private func updateReaderTabs(_ tabs: [ReaderPaperTab]) {
        for tab in tabs {
            tabViewsByID[tab.paperID]?.apply(tab: tab, isActive: tab.paperID == activePaperID, reduceMotion: reduceMotion)
        }
    }

    private func updateTabDocumentFrame() {
        let visibleSize = scrollView.contentView.bounds.size
        let fittingSize = tabStack.fittingSize
        let width = max(visibleSize.width, fittingSize.width)
        let height = max(PaperCodexWindowChrome.tabBarHeight, visibleSize.height)
        tabStack.setFrameSize(NSSize(width: width, height: height))
    }

    private func scrollActiveTabToVisible() {
        guard let activePaperID,
              let activeTabView = tabViewsByID[activePaperID],
              scrollView.contentView.bounds.width > 0 else {
            return
        }
        tabStack.layoutSubtreeIfNeeded()
        let clipView = scrollView.contentView
        let activeMidX = activeTabView.frame.midX
        let maximumX = max(0, tabStack.frame.width - clipView.bounds.width)
        let targetX = min(max(activeTabView.frame.midX - clipView.bounds.width / 2, 0), maximumX)
        guard abs(clipView.bounds.origin.x - targetX) > 0.5 || activeMidX < clipView.bounds.minX || activeMidX > clipView.bounds.maxX else {
            return
        }
        if reduceMotion {
            clipView.scroll(to: NSPoint(x: targetX, y: 0))
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clipView.animator().setBoundsOrigin(NSPoint(x: targetX, y: 0))
            }
        }
        scrollView.reflectScrolledClipView(clipView)
    }

    private func selectTab(_ tab: ReaderPaperTab) {
        selectTabHandler(tab)
    }

    private func closeTab(_ tab: ReaderPaperTab) {
        closeTabHandler(tab)
    }

    @objc private func homePressed(_ sender: NSButton) {
        selectHomeHandler()
    }

    @objc private func saveToLibraryPressed(_ sender: NSButton) {
        saveToLibraryHandler()
    }
}

private final class NativeChromeHomeTabButton: NSButton {
    private var isActive = false
    private var isHovering = false
    private var isPressed = false
    private var reduceMotion = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: PaperCodexHitTarget.chromeHomeTabWidth, height: PaperCodexHitTarget.chromeTabHeight)
    }

    func apply(isActive: Bool, helpText: String, reduceMotion: Bool) {
        self.isActive = isActive
        self.reduceMotion = reduceMotion
        toolTip = helpText
        image = NSImage(systemSymbolName: isActive ? "house.fill" : "house", accessibilityDescription: "Home")
        contentTintColor = isActive ? .controlAccentColor : .secondaryLabelColor
        setAccessibilityLabel("Home")
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        imagePosition = .imageOnly
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = PaperCodexChromeTabStyle.cornerRadius
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer?.masksToBounds = true
        widthAnchor.constraint(equalToConstant: PaperCodexHitTarget.chromeHomeTabWidth).isActive = true
        heightAnchor.constraint(equalToConstant: PaperCodexHitTarget.chromeTabHeight).isActive = true
        updateAppearance()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let fill: NSColor
        if isPressed {
            fill = isActive ? .controlAccentColor.withAlphaComponent(0.14) : .labelColor.withAlphaComponent(0.08)
        } else if isActive {
            fill = PaperCodexChromeTabStyle.activeBackground
        } else if isHovering {
            fill = PaperCodexChromeTabStyle.inactiveHoverBackground
        } else {
            fill = PaperCodexChromeTabStyle.inactiveBackground
        }
        layer?.backgroundColor = fill.cgColor
        layer?.borderWidth = isActive || isHovering ? 1 : 0
        layer?.borderColor = (isActive ? PaperCodexChromeTabStyle.activeBorder : PaperCodexChromeTabStyle.inactiveBorder).cgColor
        alphaValue = isPressed ? 0.88 : 1
        if !reduceMotion {
            animator().setFrameSize(intrinsicContentSize)
        }
    }
}

private final class NativeReaderChromeTabView: NSControl {
    var onSelect: (ReaderPaperTab) -> Void = { _ in }
    var onClose: (ReaderPaperTab) -> Void = { _ in }

    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let unsavedDot = NSView()
    private let selectButton = NativeReaderChromeSelectButton()
    private let closeButton = NativeChromeCloseButton()
    private var tab: ReaderPaperTab?
    private var isActive = false
    private var isHovering = false
    private var isPressed = false
    private var reduceMotion = false
    private var trackingArea: NSTrackingArea?
    private var widthConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: isActive ? 264 : 218, height: PaperCodexHitTarget.chromeTabHeight)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else {
            return nil
        }
        let closePoint = convert(point, to: closeButton)
        if closeButton.bounds.contains(closePoint) {
            return closeButton.hitTest(closePoint) ?? closeButton
        }
        return self
    }

    func apply(tab: ReaderPaperTab, isActive: Bool, reduceMotion: Bool) {
        self.tab = tab
        self.isActive = isActive
        self.reduceMotion = reduceMotion
        widthConstraint?.constant = isActive ? 264 : 218
        iconView.image = NSImage(systemSymbolName: isActive ? "doc.text.fill" : "doc.text", accessibilityDescription: "Paper")
        iconView.contentTintColor = isActive ? .controlAccentColor : .secondaryLabelColor
        titleField.stringValue = tab.title
        titleField.font = .systemFont(ofSize: 13, weight: isActive ? .semibold : .medium)
        titleField.textColor = isActive ? .labelColor : .secondaryLabelColor
        unsavedDot.isHidden = tab.isSaved
        closeButton.contentTintColor = isActive ? .secondaryLabelColor : .tertiaryLabelColor
        toolTip = tab.detail.isEmpty ? tab.title : "\(tab.title)\n\(tab.detail)"
        setAccessibilityLabel(tab.title)
        selectButton.setAccessibilityLabel(tab.title)
        selectButton.setAccessibilityHelp(toolTip)
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
    }

    override func mouseUp(with event: NSEvent) {
        let shouldSelect = isPressed && bounds.contains(convert(event.locationInWindow, from: nil))
        setPressed(false)
        if shouldSelect, let tab {
            onSelect(tab)
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = PaperCodexChromeTabStyle.cornerRadius
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        selectButton.target = self
        selectButton.action = #selector(selectPressed(_:))
        selectButton.onPressedChanged = { [weak self] pressed in
            self?.setPressed(pressed)
        }

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        unsavedDot.translatesAutoresizingMaskIntoConstraints = false
        unsavedDot.wantsLayer = true
        unsavedDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        unsavedDot.layer?.cornerRadius = 3
        unsavedDot.toolTip = "Cached paper"

        closeButton.target = self
        closeButton.action = #selector(closePressed(_:))
        closeButton.toolTip = "Close tab"
        closeButton.setAccessibilityLabel("Close tab")

        [iconView, titleField, unsavedDot, selectButton, closeButton].forEach(addSubview(_:))
        setAccessibilityChildren([selectButton, closeButton])
        widthConstraint = widthAnchor.constraint(equalToConstant: 218)
        widthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: PaperCodexHitTarget.chromeTabHeight),
            selectButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectButton.topAnchor.constraint(equalTo: topAnchor),
            selectButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            selectButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            unsavedDot.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: 7),
            unsavedDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            unsavedDot.widthAnchor.constraint(equalToConstant: 6),
            unsavedDot.heightAnchor.constraint(equalToConstant: 6),
            closeButton.leadingAnchor.constraint(equalTo: unsavedDot.trailingAnchor, constant: 7),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: PaperCodexHitTarget.chromeCloseButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: PaperCodexHitTarget.chromeCloseButtonSize)
        ])
        updateAppearance()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let fill: NSColor
        if isPressed {
            fill = isActive ? .controlAccentColor.withAlphaComponent(0.14) : .labelColor.withAlphaComponent(0.08)
        } else if isActive {
            fill = PaperCodexChromeTabStyle.activeBackground
        } else if isHovering {
            fill = PaperCodexChromeTabStyle.inactiveHoverBackground
        } else {
            fill = PaperCodexChromeTabStyle.inactiveBackground
        }
        layer?.backgroundColor = fill.cgColor
        layer?.borderWidth = isActive || isHovering ? 1 : 0
        layer?.borderColor = (isActive ? PaperCodexChromeTabStyle.activeBorder : PaperCodexChromeTabStyle.inactiveBorder).cgColor
        alphaValue = isPressed ? 0.90 : 1
        closeButton.isHoveringParent = isHovering || isActive
        if !reduceMotion {
            animator().alphaValue = alphaValue
        }
    }

    @objc private func closePressed(_ sender: NSButton) {
        if let tab {
            onClose(tab)
        }
    }

    @objc private func selectPressed(_ sender: NSButton) {
        if let tab {
            onSelect(tab)
        }
    }
}

private final class NativeReaderChromeSelectButton: NSButton {
    var onPressedChanged: (Bool) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        onPressedChanged(true)
        super.mouseDown(with: event)
        onPressedChanged(false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        focusRingType = .none
        setButtonType(.momentaryChange)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
}

private final class NativeChromeCloseButton: NSButton {
    var isHoveringParent = false {
        didSet {
            updateAppearance()
        }
    }

    private var isHovering = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        imagePosition = .imageOnly
        contentTintColor = .secondaryLabelColor
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        wantsLayer = true
        layer?.cornerRadius = PaperCodexHitTarget.chromeCloseButtonSize / 2
        updateAppearance()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        if isPressed {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.34).cgColor
        } else if isHovering || isHoveringParent {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            layer?.borderWidth = isHovering ? 1 : 0
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
        }
    }
}

private final class NativeSaveToLibraryChromeButton: NSButton {
    private var isHovering = false
    private var isPressed = false
    private var reduceMotion = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 34, height: 30)
    }

    func apply(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Save to Library")
        imagePosition = .imageOnly
        contentTintColor = .controlAccentColor
        toolTip = "Save to Library"
        setAccessibilityLabel("Save to Library")
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = PaperCodexChromeTabStyle.controlCornerRadius
        layer?.masksToBounds = true
        widthAnchor.constraint(equalToConstant: 34).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        updateAppearance()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let fill: NSColor
        if isPressed {
            fill = .controlAccentColor.withAlphaComponent(0.16)
        } else if isHovering {
            fill = .controlAccentColor.withAlphaComponent(0.10)
        } else {
            fill = .clear
        }
        layer?.backgroundColor = fill.cgColor
        alphaValue = isPressed ? 0.88 : 1
        if !reduceMotion {
            animator().alphaValue = alphaValue
        }
    }
}

private enum PaperCodexChromeTabStyle {
    static let cornerRadius: CGFloat = PaperCodexCornerRadius.chromeTab
    static let controlCornerRadius: CGFloat = PaperCodexCornerRadius.control
    static var barBackground: NSColor { .windowBackgroundColor }
    static var activeBackground: NSColor { .textBackgroundColor }
    static var inactiveBackground: NSColor { .controlBackgroundColor.withAlphaComponent(0.36) }
    static var inactiveHoverBackground: NSColor { .controlBackgroundColor.withAlphaComponent(0.70) }
    static var divider: NSColor { .separatorColor }
    static var activeBorder: NSColor { .labelColor.withAlphaComponent(0.16) }
    static var inactiveBorder: NSColor { .labelColor.withAlphaComponent(0.10) }
}

private struct PaperCodexWindowFullscreenObserver: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> PaperCodexWindowFullscreenProbeView {
        let view = PaperCodexWindowFullscreenProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: PaperCodexWindowFullscreenProbeView, context: Context) {
        nsView.onChange = onChange
        nsView.publishFullscreenState()
    }
}

private final class PaperCodexWindowFullscreenProbeView: NSView {
    var onChange: ((Bool) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowFullscreenStateChanged),
                name: NSWindow.didEnterFullScreenNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowFullscreenStateChanged),
                name: NSWindow.didExitFullScreenNotification,
                object: window
            )
        }
        publishFullscreenState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowFullscreenStateChanged() {
        publishFullscreenState()
    }

    func publishFullscreenState() {
        let isFullscreen = window?.styleMask.contains(.fullScreen) ?? false
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(isFullscreen)
        }
    }
}
