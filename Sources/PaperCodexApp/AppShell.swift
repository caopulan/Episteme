import AppKit
import SwiftUI

struct PrimaryNavigationSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        NativePrimaryNavigationView(
            route: navigation.route,
            librarySurface: model.selectedLibrarySurface,
            reduceMotion: reduceMotion,
            goToLibrary: {
                model.goToLibrary()
            },
            showDiscover: {
                model.showDiscover()
            },
            showSearch: {
                model.showSearch()
            },
            showSettings: {
                model.showSettings()
            },
            showRecentConversations: {
                model.showRecentConversations()
            }
        )
        .frame(height: 5 * NativePrimaryNavigationMetrics.rowHeight + 4 * NativePrimaryNavigationMetrics.rowSpacing)
    }
}

private struct NativePrimaryNavigationView: NSViewRepresentable {
    var route: AppRoute
    var librarySurface: LibrarySurface
    var reduceMotion: Bool
    var goToLibrary: () -> Void
    var showDiscover: () -> Void
    var showSearch: () -> Void
    var showSettings: () -> Void
    var showRecentConversations: () -> Void

    func makeNSView(context: Context) -> NativePrimaryNavigationContainerView {
        let view = NativePrimaryNavigationContainerView()
        view.apply(self)
        return view
    }

    func updateNSView(_ view: NativePrimaryNavigationContainerView, context: Context) {
        view.apply(self)
    }
}

private enum NativePrimaryNavigationMetrics {
    static let rowHeight: CGFloat = 34
    static let rowSpacing: CGFloat = 8
    static let iconWidth: CGFloat = 18
    static let leadingInset: CGFloat = PaperCodexSpacing.sidebarRowLeading
    static let trailingInset: CGFloat = PaperCodexSpacing.sidebarRowTrailing
    static let cornerRadius: CGFloat = PaperCodexCornerRadius.control
}

private struct PrimaryNavigationItemDescriptor {
    var item: PrimaryNavigationItem
    var title: String
    var systemImageName: String
    var selectedSystemImageName: String?

    func systemImageName(isSelected: Bool) -> String {
        if isSelected, let selectedSystemImageName {
            return selectedSystemImageName
        }
        return systemImageName
    }
}

private let primaryNavigationItems: [PrimaryNavigationItemDescriptor] = [
    PrimaryNavigationItemDescriptor(
        item: .library,
        title: "Library",
        systemImageName: "books.vertical",
        selectedSystemImageName: "books.vertical.fill"
    ),
    PrimaryNavigationItemDescriptor(
        item: .discover,
        title: "探索",
        systemImageName: "sparkle.magnifyingglass",
        selectedSystemImageName: nil
    ),
    PrimaryNavigationItemDescriptor(
        item: .search,
        title: "搜索",
        systemImageName: "magnifyingglass",
        selectedSystemImageName: nil
    ),
    PrimaryNavigationItemDescriptor(
        item: .settings,
        title: "Settings",
        systemImageName: "gearshape",
        selectedSystemImageName: nil
    ),
    PrimaryNavigationItemDescriptor(
        item: .recentConversations,
        title: "Recent Conversations",
        systemImageName: "clock",
        selectedSystemImageName: nil
    )
]

private enum PrimaryNavigationItem {
    case library
    case discover
    case search
    case settings
    case recentConversations

    func isSelected(route: AppRoute, librarySurface: LibrarySurface) -> Bool {
        switch self {
        case .library:
            route == .library && librarySurface == .papers
        case .discover:
            route == .discover
        case .search:
            route == .search
        case .settings:
            route == .settings
        case .recentConversations:
            route == .library && librarySurface == .recentConversations
        }
    }
}

private final class NativePrimaryNavigationContainerView: NSView {
    private let stackView = NSStackView()
    private var rowButtons: [PrimaryNavigationItem: NativePrimaryNavigationRowButton] = [:]
    private var goToLibraryHandler: () -> Void = {}
    private var showDiscoverHandler: () -> Void = {}
    private var showSearchHandler: () -> Void = {}
    private var showSettingsHandler: () -> Void = {}
    private var showRecentConversationsHandler: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    func apply(_ view: NativePrimaryNavigationView) {
        goToLibraryHandler = view.goToLibrary
        showDiscoverHandler = view.showDiscover
        showSearchHandler = view.showSearch
        showSettingsHandler = view.showSettings
        showRecentConversationsHandler = view.showRecentConversations

        for descriptor in primaryNavigationItems {
            let selected = descriptor.item.isSelected(route: view.route, librarySurface: view.librarySurface)
            rowButtons[descriptor.item]?.apply(
                title: descriptor.title,
                systemImageName: descriptor.systemImageName(isSelected: selected),
                selected: selected,
                reduceMotion: view.reduceMotion
            )
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = NativePrimaryNavigationMetrics.rowSpacing
        addSubview(stackView)

        for descriptor in primaryNavigationItems {
            let row = NativePrimaryNavigationRowButton(item: descriptor.item)
            row.target = self
            row.action = #selector(rowPressed(_:))
            rowButtons[descriptor.item] = row
            stackView.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: NativePrimaryNavigationMetrics.rowHeight),
                row.widthAnchor.constraint(equalTo: stackView.widthAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    @objc private func rowPressed(_ sender: NativePrimaryNavigationRowButton) {
        switch sender.item {
        case .library:
            goToLibraryHandler()
        case .discover:
            showDiscoverHandler()
        case .search:
            showSearchHandler()
        case .settings:
            showSettingsHandler()
        case .recentConversations:
            showRecentConversationsHandler()
        }
    }
}

private final class NativePrimaryNavigationRowButton: NSButton {
    let item: PrimaryNavigationItem

    private let indicatorView = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isPressed = false
    private var isSelectedRow = false
    private var reduceMotion = false

    init(item: PrimaryNavigationItem) {
        self.item = item
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    func apply(title: String, systemImageName: String, selected: Bool, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        isSelectedRow = selected
        titleLabel.stringValue = NSLocalizedString(title, comment: "")
        iconView.image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: title)
        toolTip = titleLabel.stringValue
        setAccessibilityLabel(titleLabel.stringValue)
        setAccessibilityValue(selected ? NSLocalizedString("Selected", comment: "") : nil)
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
        wantsLayer = true
        layer?.cornerRadius = NativePrimaryNavigationMetrics.cornerRadius
        layer?.masksToBounds = false

        indicatorView.translatesAutoresizingMaskIntoConstraints = false
        indicatorView.wantsLayer = true
        indicatorView.layer?.cornerRadius = 1.5

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        [indicatorView, iconView, titleLabel].forEach(addSubview(_:))
        NSLayoutConstraint.activate([
            indicatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            indicatorView.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicatorView.widthAnchor.constraint(equalToConstant: 3),
            indicatorView.heightAnchor.constraint(equalToConstant: 18),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: NativePrimaryNavigationMetrics.leadingInset),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: NativePrimaryNavigationMetrics.iconWidth),
            iconView.heightAnchor.constraint(equalToConstant: NativePrimaryNavigationMetrics.iconWidth),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -NativePrimaryNavigationMetrics.trailingInset),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateAppearance()
    }

    private func updateAppearance() {
        let accent = NSColor.controlAccentColor
        let foreground: NSColor = isSelectedRow ? accent : .labelColor.withAlphaComponent(0.78)
        iconView.contentTintColor = foreground
        titleLabel.textColor = isSelectedRow ? .labelColor : .labelColor.withAlphaComponent(0.86)
        indicatorView.isHidden = !(isSelectedRow || isPressed)
        indicatorView.layer?.backgroundColor = accent.withAlphaComponent(isSelectedRow ? 0.72 : 0.52).cgColor

        let background: NSColor
        let border: NSColor
        if isSelectedRow {
            background = accent.withAlphaComponent(0.14)
            border = NSColor.clear
        } else if isPressed {
            background = accent.withAlphaComponent(0.10)
            border = accent.withAlphaComponent(0.38)
        } else if isHovering {
            background = NSColor.textBackgroundColor
            border = accent.withAlphaComponent(0.25)
        } else {
            background = .clear
            border = .clear
        }

        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = border == .clear ? 0 : 1
        layer?.borderColor = border.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = isPressed ? 0.12 : (isHovering ? 0.08 : 0)
        layer?.shadowRadius = isPressed || isHovering ? 7 : 0
        layer?.shadowOffset = CGSize(width: 0, height: -3)

        let targetScale: CGFloat
        if reduceMotion {
            targetScale = 1
        } else if isPressed {
            targetScale = 0.985
        } else {
            targetScale = isHovering ? 1.015 : 1
        }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (isPressed ? 0.05 : 0.12))
        layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
    }
}
