import AppKit
import PaperCodexCore
import SwiftUI

struct NativeDiscoverCardLink: Equatable, Identifiable {
    var id: String
    var title: String
    var systemImage: String
    var urlString: String
}

struct NativeDiscoverCardModel: Equatable, Identifiable {
    var id: String
    var primaryCategory: String
    var arxivID: String
    var primaryTitle: String
    var secondaryTitle: String
    var summary: String
    var contribution: String?
    var error: String?
    var tags: [String]
    var links: [NativeDiscoverCardLink]
    var imageURL: URL?
    var thumbnailURLs: [URL]
    var inLibrary: Bool
    var isBusy: Bool
    var downloadProgress: Double?
    var interactionState: DiscoverPaperInteractionState?
}

struct NativeDiscoverCollectionView: NSViewRepresentable {
    var cards: [NativeDiscoverCardModel]
    var restorePaperID: String?
    var restoreToken: Int
    var onVisiblePaperChange: (String?) -> Void
    var onPreview: (String) -> Void
    var onSave: (String) -> Void
    var onOpen: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NativeDiscoverCollectionContainerView {
        let view = NativeDiscoverCollectionContainerView()
        view.collectionView.dataSource = context.coordinator
        view.collectionView.delegate = context.coordinator
        view.scrollView.onScroll = { [weak coordinator = context.coordinator] in
            coordinator?.reportVisiblePaper()
        }
        context.coordinator.containerView = view
        context.coordinator.update(from: self)
        view.collectionView.reloadData()
        view.updateLayoutMetrics()
        context.coordinator.scrollToPaper(restorePaperID, token: restoreToken)
        context.coordinator.reportVisiblePaper()
        return view
    }

    func updateNSView(_ view: NativeDiscoverCollectionContainerView, context: Context) {
        context.coordinator.containerView = view
        context.coordinator.update(from: self)
        view.collectionView.reloadData()
        view.updateLayoutMetrics()
        context.coordinator.scrollToPaper(restorePaperID, token: restoreToken)
        context.coordinator.reportVisiblePaper()
    }

    @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        private static let itemIdentifier = NSUserInterfaceItemIdentifier("NativeDiscoverPaperCardItem")

        weak var containerView: NativeDiscoverCollectionContainerView? {
            didSet {
                containerView?.collectionView.register(
                    NativeDiscoverPaperCardItem.self,
                    forItemWithIdentifier: Self.itemIdentifier
                )
            }
        }

        private var cards: [NativeDiscoverCardModel] = []
        private var restorePaperID: String?
        private var restoreToken = 0
        private var lastAppliedRestoreToken: Int?
        private var onVisiblePaperChange: (String?) -> Void = { _ in }
        private var onPreview: (String) -> Void = { _ in }
        private var onSave: (String) -> Void = { _ in }
        private var onOpen: (String) -> Void = { _ in }

        func update(from view: NativeDiscoverCollectionView) {
            cards = view.cards
            restorePaperID = view.restorePaperID
            restoreToken = view.restoreToken
            onVisiblePaperChange = view.onVisiblePaperChange
            onPreview = view.onPreview
            onSave = view.onSave
            onOpen = view.onOpen
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            cards.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: Self.itemIdentifier, for: indexPath)
            guard let cardItem = item as? NativeDiscoverPaperCardItem,
                  cards.indices.contains(indexPath.item) else {
                return item
            }
            cardItem.configure(
                with: cards[indexPath.item],
                onPreview: onPreview,
                onSave: onSave,
                onOpen: onOpen
            )
            return cardItem
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            layout collectionViewLayout: NSCollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> NSSize {
            guard let containerView else {
                return NSSize(width: 360, height: 590)
            }
            return containerView.currentItemSize
        }

        func scrollToPaper(_ paperID: String?, token: Int) {
            guard let paperID,
                  lastAppliedRestoreToken != token,
                  let collectionView = containerView?.collectionView,
                  let index = cards.firstIndex(where: { $0.id == paperID }) else {
                return
            }
            lastAppliedRestoreToken = token
            let indexPath = IndexPath(item: index, section: 0)
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .top)
        }

        func reportVisiblePaper() {
            guard let collectionView = containerView?.collectionView else {
                onVisiblePaperChange(nil)
                return
            }
            let visible = collectionView.indexPathsForVisibleItems()
                .sorted { $0.item < $1.item }
            guard let index = visible.first?.item,
                  cards.indices.contains(index) else {
                onVisiblePaperChange(nil)
                return
            }
            onVisiblePaperChange(cards[index].id)
        }
    }
}

final class NativeDiscoverCollectionContainerView: NSView {
    let scrollView = NativeDiscoverCollectionScrollView()
    let collectionView = NSCollectionView()

    private let flowLayout = NSCollectionViewFlowLayout()
    private let contentInsets = NSEdgeInsets(
        top: NativeDiscoverCollectionMetrics.verticalInset,
        left: NativeDiscoverCollectionMetrics.horizontalInset,
        bottom: NativeDiscoverCollectionMetrics.verticalInset,
        right: NativeDiscoverCollectionMetrics.horizontalInset
    )

    var currentItemSize = NSSize(width: 360, height: 590)

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

    override func layout() {
        super.layout()
        updateLayoutMetrics()
    }

    func updateLayoutMetrics() {
        let width = scrollView.contentView.bounds.width > 0 ? scrollView.contentView.bounds.width : bounds.width
        let columnCount = NativeDiscoverCollectionMetrics.columnCount(for: width)
        let totalSpacing = NativeDiscoverCollectionMetrics.columnSpacing * CGFloat(columnCount - 1)
        let availableWidth = max(
            1,
            width - contentInsets.left - contentInsets.right - totalSpacing
        )
        let itemWidth = floor(availableWidth / CGFloat(columnCount))
        let itemHeight = NativeDiscoverCollectionMetrics.itemHeight(for: itemWidth)
        let nextSize = NSSize(width: itemWidth, height: itemHeight)
        guard abs(nextSize.width - currentItemSize.width) > 0.5
                || abs(nextSize.height - currentItemSize.height) > 0.5 else {
            return
        }
        currentItemSize = nextSize
        flowLayout.itemSize = nextSize
        collectionView.collectionViewLayout?.invalidateLayout()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        flowLayout.minimumInteritemSpacing = NativeDiscoverCollectionMetrics.columnSpacing
        flowLayout.minimumLineSpacing = NativeDiscoverCollectionMetrics.rowSpacing
        flowLayout.sectionInset = contentInsets
        flowLayout.itemSize = currentItemSize

        collectionView.collectionViewLayout = flowLayout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.allowsMultipleSelection = false
        collectionView.postsFrameChangedNotifications = false

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = collectionView

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

final class NativeDiscoverCollectionScrollView: NSScrollView {
    var onScroll: () -> Void = {}

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        onScroll()
    }
}

private enum NativeDiscoverCollectionMetrics {
    static let horizontalInset: CGFloat = 10
    static let verticalInset: CGFloat = 8
    static let columnSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 14

    static func columnCount(for width: CGFloat) -> Int {
        if width >= 1120 {
            return 3
        }
        if width >= 760 {
            return 2
        }
        return 1
    }

    static func itemHeight(for width: CGFloat) -> CGFloat {
        if width < 320 {
            return 650
        }
        if width < 440 {
            return 590
        }
        return 540
    }
}

final class NativeDiscoverPaperCardItem: NSCollectionViewItem {
    private let cardView = NativeDiscoverPaperCardView()

    override func loadView() {
        view = cardView
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cardView.prepareForReuse()
    }

    func configure(
        with model: NativeDiscoverCardModel,
        onPreview: @escaping (String) -> Void,
        onSave: @escaping (String) -> Void,
        onOpen: @escaping (String) -> Void
    ) {
        cardView.configure(
            with: model,
            onPreview: onPreview,
            onSave: onSave,
            onOpen: onOpen
        )
    }
}

final class NativeDiscoverPaperCardView: NSView {
    private let mediaButton = NSButton()
    private let imageView = NSImageView()
    private let metadataStack = NSStackView()
    private let categoryLabel = NSTextField(labelWithString: "")
    private let arxivIDLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let secondaryTitleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let contributionLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let tagsStack = NSStackView()
    private let linksStack = NSStackView()
    private let progressIndicator = NSProgressIndicator()
    private let savedBadge = NSTextField(labelWithString: "Saved")
    private let saveButton = NSButton()
    private let openButton = NSButton()
    private var representedModel: NativeDiscoverCardModel?
    private var representedImageURL: URL?
    private var imageRequestID = UUID()
    private var onPreview: (String) -> Void = { _ in }
    private var onSave: (String) -> Void = { _ in }
    private var onOpen: (String) -> Void = { _ in }
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

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

    override func prepareForReuse() {
        super.prepareForReuse()
        representedModel = nil
        representedImageURL = nil
        imageRequestID = UUID()
        imageView.image = nil
    }

    func configure(
        with model: NativeDiscoverCardModel,
        onPreview: @escaping (String) -> Void,
        onSave: @escaping (String) -> Void,
        onOpen: @escaping (String) -> Void
    ) {
        representedModel = model
        self.onPreview = onPreview
        self.onSave = onSave
        self.onOpen = onOpen

        categoryLabel.stringValue = model.primaryCategory
        arxivIDLabel.stringValue = model.arxivID
        statusLabel.stringValue = nativeDiscoverStatusTitle(for: model.interactionState)
        statusLabel.isHidden = model.interactionState == nil
        titleLabel.stringValue = model.primaryTitle
        secondaryTitleLabel.stringValue = model.secondaryTitle
        secondaryTitleLabel.isHidden = model.secondaryTitle.isEmpty || model.secondaryTitle == model.primaryTitle
        summaryLabel.stringValue = model.summary
        contributionLabel.stringValue = model.contribution ?? ""
        contributionLabel.isHidden = (model.contribution ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        errorLabel.stringValue = model.error ?? ""
        errorLabel.isHidden = (model.error ?? "").isEmpty

        configureTags(model.tags)
        configureLinks(model.links)
        configureActions(model)
        configureImage(model)
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

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = false

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 0
        addSubview(root)

        mediaButton.translatesAutoresizingMaskIntoConstraints = false
        mediaButton.isBordered = false
        mediaButton.title = ""
        mediaButton.imagePosition = .imageOnly
        mediaButton.target = self
        mediaButton.action = #selector(performMediaAction)
        mediaButton.wantsLayer = true
        mediaButton.layer?.cornerRadius = 6

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        mediaButton.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: mediaButton.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: mediaButton.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: mediaButton.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: mediaButton.bottomAnchor),
            mediaButton.heightAnchor.constraint(equalToConstant: 150)
        ])

        let mediaWrap = NSView()
        mediaWrap.translatesAutoresizingMaskIntoConstraints = false
        mediaWrap.addSubview(mediaButton)
        root.addArrangedSubview(mediaWrap)
        NSLayoutConstraint.activate([
            mediaButton.leadingAnchor.constraint(equalTo: mediaWrap.leadingAnchor, constant: 14),
            mediaButton.trailingAnchor.constraint(equalTo: mediaWrap.trailingAnchor, constant: -14),
            mediaButton.topAnchor.constraint(equalTo: mediaWrap.topAnchor, constant: 14),
            mediaButton.bottomAnchor.constraint(equalTo: mediaWrap.bottomAnchor, constant: -8),
            mediaWrap.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        let content = NSStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 9
        root.addArrangedSubview(content)

        metadataStack.orientation = .horizontal
        metadataStack.alignment = .centerY
        metadataStack.spacing = 6
        metadataStack.addArrangedSubview(categoryLabel)
        metadataStack.addArrangedSubview(arxivIDLabel)
        metadataStack.addArrangedSubview(statusLabel)
        content.addArrangedSubview(metadataStack)

        configurePill(categoryLabel, foreground: .systemTeal, background: NSColor.systemTeal.withAlphaComponent(0.12))
        configurePill(arxivIDLabel, foreground: .secondaryLabelColor, background: NSColor.controlBackgroundColor.withAlphaComponent(0.72))
        configurePill(statusLabel, foreground: .systemGreen, background: NSColor.systemGreen.withAlphaComponent(0.12))
        configureText(titleLabel, font: .systemFont(ofSize: 16, weight: .semibold), color: .labelColor, lines: 2)
        configureText(secondaryTitleLabel, font: .systemFont(ofSize: 13), color: .secondaryLabelColor, lines: 2)
        configureText(summaryLabel, font: .systemFont(ofSize: 13.5), color: .secondaryLabelColor, lines: 5)
        configureText(contributionLabel, font: .systemFont(ofSize: 13.5, weight: .medium), color: .controlAccentColor, lines: 3)
        configureText(errorLabel, font: .systemFont(ofSize: 12), color: .systemRed, lines: 3)

        content.addArrangedSubview(titleLabel)
        content.addArrangedSubview(secondaryTitleLabel)
        content.addArrangedSubview(summaryLabel)
        content.addArrangedSubview(contributionLabel)
        content.addArrangedSubview(errorLabel)

        tagsStack.orientation = .horizontal
        tagsStack.alignment = .centerY
        tagsStack.spacing = 6
        content.addArrangedSubview(tagsStack)

        let spacer = NSView()
        root.addArrangedSubview(spacer)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .bottom
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(footer)

        linksStack.orientation = .horizontal
        linksStack.alignment = .centerY
        linksStack.spacing = 5
        footer.addArrangedSubview(linksStack)

        let footerSpacer = NSView()
        footer.addArrangedSubview(footerSpacer)

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.controlSize = .small
        progressIndicator.style = .bar
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        footer.addArrangedSubview(progressIndicator)
        progressIndicator.widthAnchor.constraint(equalToConstant: 78).isActive = true

        configurePill(savedBadge, foreground: .systemGreen, background: NSColor.systemGreen.withAlphaComponent(0.12))
        footer.addArrangedSubview(savedBadge)

        configureActionButton(saveButton, title: "Add", systemImage: "tray.and.arrow.down", action: #selector(performSave))
        configureActionButton(openButton, title: "Open", systemImage: "book", action: #selector(performOpen))
        footer.addArrangedSubview(saveButton)
        footer.addArrangedSubview(openButton)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
    }

    private func configureImage(_ model: NativeDiscoverCardModel) {
        guard let imageURL = model.imageURL ?? model.thumbnailURLs.first else {
            mediaButton.isHidden = true
            imageView.image = nil
            representedImageURL = nil
            return
        }
        mediaButton.isHidden = false
        mediaButton.toolTip = model.imageURL == nil ? "Open cached PDF" : "Open image preview"
        if representedImageURL == imageURL, imageView.image != nil {
            return
        }
        representedImageURL = imageURL
        imageView.image = nil
        let requestID = UUID()
        imageRequestID = requestID
        Task { @MainActor [weak self] in
            let image = await NativeDiscoverImageCache.shared.loadImage(at: imageURL)
            guard let self,
                  self.imageRequestID == requestID,
                  self.representedImageURL == imageURL else {
                return
            }
            self.imageView.image = image
        }
    }

    private func configureTags(_ tags: [String]) {
        clearStack(tagsStack)
        for tag in tags.prefix(7) {
            let label = NSTextField(labelWithString: tag)
            configurePill(label, foreground: .systemOrange, background: NSColor.systemOrange.withAlphaComponent(0.12))
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            tagsStack.addArrangedSubview(label)
        }
    }

    private func configureLinks(_ links: [NativeDiscoverCardLink]) {
        clearStack(linksStack)
        for link in links.prefix(5) {
            let button = NSButton(title: "", target: self, action: #selector(openResourceLink(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(link.urlString)
            button.image = NSImage(systemSymbolName: link.systemImage, accessibilityDescription: link.title)
            button.toolTip = link.title
            button.bezelStyle = .rounded
            button.isBordered = true
            button.setAccessibilityLabel(link.title)
            linksStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 26).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
    }

    private func configureActions(_ model: NativeDiscoverCardModel) {
        saveButton.isHidden = model.inLibrary
        savedBadge.isHidden = !model.inLibrary
        saveButton.isEnabled = !model.isBusy
        openButton.isEnabled = !model.isBusy
        progressIndicator.isHidden = !model.isBusy
        if let progress = model.downloadProgress {
            progressIndicator.doubleValue = min(max(progress, 0), 1)
        } else {
            progressIndicator.doubleValue = 0
        }
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderWidth = isHovering ? 1.3 : 1
        layer?.borderColor = (isHovering ? NSColor.controlAccentColor.withAlphaComponent(0.36) : NSColor.black.withAlphaComponent(0.08)).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = isHovering ? 0.15 : 0.035
        layer?.shadowRadius = isHovering ? 14 : 2
        layer?.shadowOffset = CGSize(width: 0, height: isHovering ? -7 : -1)
    }

    @objc private func performMediaAction() {
        guard let model = representedModel else {
            return
        }
        if model.imageURL != nil {
            onPreview(model.id)
        } else {
            onOpen(model.id)
        }
    }

    @objc private func performSave() {
        guard let model = representedModel else {
            return
        }
        onSave(model.id)
    }

    @objc private func performOpen() {
        guard let model = representedModel else {
            return
        }
        onOpen(model.id)
    }

    @objc private func openResourceLink(_ sender: NSButton) {
        guard let urlString = sender.identifier?.rawValue,
              let url = URL(string: urlString),
              NSWorkspace.shared.open(url) else {
            NSSound.beep()
            return
        }
    }

    private func clearStack(_ stack: NSStackView) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func configureText(_ label: NSTextField, font: NSFont, color: NSColor, lines: Int) {
        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = lines
        label.lineBreakMode = .byTruncatingTail
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configurePill(_ label: NSTextField, foreground: NSColor, background: NSColor) {
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = foreground
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.drawsBackground = true
        label.backgroundColor = background
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.heightAnchor.constraint(equalToConstant: 23).isActive = true
    }

    private func configureActionButton(_ button: NSButton, title: String, systemImage: String, action: Selector) {
        button.title = title
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = self
        button.action = action
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }
}

@MainActor
private final class NativeDiscoverImageCache {
    static let shared = NativeDiscoverImageCache()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 320
    }

    func loadImage(at url: URL) async -> NSImage? {
        if let image = cache.object(forKey: url as NSURL) {
            return image
        }
        let data = await Task.detached(priority: .userInitiated) {
            let data = try? Data(contentsOf: url)
            return data
        }.value
        let image = data.flatMap(NSImage.init(data:))
        if let image {
            cache.setObject(image, forKey: url as NSURL)
        }
        return image
    }
}

private func nativeDiscoverStatusTitle(for state: DiscoverPaperInteractionState?) -> String {
    switch state {
    case nil:
        ""
    case .queued:
        "Queued"
    case .processing:
        "Processing"
    case .processed:
        "Processed"
    case .cached:
        "Cached"
    case .failed:
        "Failed"
    case .cancelled:
        "Stopped"
    case .downloading:
        "Caching PDF"
    case .pdfCached:
        "PDF Cached"
    }
}
