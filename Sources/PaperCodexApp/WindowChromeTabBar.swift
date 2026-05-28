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
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(PaperCodexChromeTabStyle.divider)
                .frame(height: 1)

            HStack(alignment: .bottom, spacing: 0) {
                PaperCodexHomeChromeTab(
                    isActive: navigation.route != .reader,
                    helpText: homeTabHelp
                ) {
                    selectHomeTab()
                }

                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(model.readerTabState.tabs) { tab in
                                PaperCodexReaderChromeTabItem(
                                    tab: tab,
                                    isActive: navigation.route == .reader
                                        && (model.selectedPaper?.id == tab.paperID
                                            || model.readerTabState.activePaperID == tab.paperID)
                                )
                                .id(tab.paperID)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity)
                                ))
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.top, 8)
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: PaperCodexWindowChrome.tabBarHeight)
                    .onChange(of: model.readerTabState.activePaperID) { _, activePaperID in
                        guard let activePaperID else {
                            return
                        }
                        PaperCodexMotion.perform(PaperCodexMotion.selection, reduceMotion: reduceMotion) {
                            scrollProxy.scrollTo(activePaperID, anchor: .center)
                        }
                    }
                    .animation(PaperCodexMotion.accessible(PaperCodexMotion.selection, reduceMotion: reduceMotion), value: model.readerTabState.activePaperID)
                    .animation(PaperCodexMotion.accessible(PaperCodexMotion.selection, reduceMotion: reduceMotion), value: readerTabIDs)
                }
                .layoutPriority(1)

                if let paper = model.selectedPaper, !paper.isSaved {
                    PaperCodexIconButton(title: "Save to Library", systemImage: "tray.and.arrow.down", tint: .accentColor) {
                        onShowSaveToLibrary()
                    }
                    .padding(.bottom, 5)
                }
            }
            .padding(.leading, isWindowFullscreen ? PaperCodexWindowChrome.tabBarFullscreenLeadingInset : PaperCodexWindowChrome.tabBarTrafficLightLeadingInset)
            .padding(.trailing, 10)
            .frame(height: PaperCodexWindowChrome.tabBarHeight, alignment: .bottom)
        }
        .frame(height: PaperCodexWindowChrome.tabBarHeight)
        .background(PaperCodexChromeTabStyle.barBackground)
        .background(
            PaperCodexWindowFullscreenObserver { isFullscreen in
                isWindowFullscreen = isFullscreen
            }
        )
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

    private var readerTabIDs: [String] {
        model.readerTabState.tabs.map(\.paperID)
    }

    private func selectHomeTab() {
        if navigation.route == .reader {
            model.returnFromReader()
        } else {
            model.goToLibrary()
        }
    }
}

private struct PaperCodexHomeChromeTab: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var isActive: Bool
    var helpText: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "house.fill" : "house")
                .font(.paperCodexSystem(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: PaperCodexHitTarget.chromeHomeTabWidth, height: PaperCodexHitTarget.chromeTabHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PaperCodexChromeTabButtonStyle(isActive: isActive, isHovering: isHovering, reduceMotion: reduceMotion))
        .background(tabBackground)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(PaperCodexChromeTabStyle.activeBackground)
                    .frame(height: 3)
                    .offset(y: 1)
            }
        }
        .overlay(
            chromeTabOutline
                .stroke(tabBorder, lineWidth: isActive ? 1 : 0.8)
        )
        .clipShape(chromeTabShape)
        .scaleEffect(reduceMotion ? 1 : tabScale, anchor: .bottom)
        .animation(PaperCodexMotion.accessible(PaperCodexMotion.hover, reduceMotion: reduceMotion), value: isHovering)
        .animation(PaperCodexMotion.accessible(PaperCodexMotion.selection, reduceMotion: reduceMotion), value: isActive)
        .help(helpText)
        .accessibilityLabel("Home")
        .onHover { hovering in
            PaperCodexMotion.perform(PaperCodexMotion.hover, reduceMotion: reduceMotion) {
                isHovering = hovering
            }
        }
    }

    private var chromeTabShape: some InsettableShape {
        UnevenRoundedRectangle(
            topLeadingRadius: PaperCodexChromeTabStyle.cornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: PaperCodexChromeTabStyle.cornerRadius
        )
    }

    private var chromeTabOutline: some Shape {
        PaperCodexChromeTabTopOutline(radius: PaperCodexChromeTabStyle.cornerRadius)
    }

    private var tabBackground: Color {
        if isActive {
            return PaperCodexChromeTabStyle.activeBackground
        }
        return isHovering ? PaperCodexChromeTabStyle.inactiveHoverBackground : PaperCodexChromeTabStyle.inactiveBackground
    }

    private var tabBorder: Color {
        if isActive {
            return PaperCodexChromeTabStyle.activeBorder
        }
        return isHovering ? PaperCodexChromeTabStyle.inactiveBorder : Color.clear
    }

    private var tabScale: CGFloat {
        isHovering && !isActive ? 1.018 : 1
    }
}

private struct PaperCodexReaderChromeTabItem: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: AppModel
    var tab: ReaderPaperTab
    var isActive: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.selectReaderTab(tab)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isActive ? "doc.text.fill" : "doc.text")
                        .font(.paperCodexSystem(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

                    Text(tab.title)
                        .font(.paperCodexSystem(size: 13, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if !tab.isSaved {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .help("Cached paper")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PaperCodexChromeTabButtonStyle(isActive: isActive, isHovering: isHovering, reduceMotion: reduceMotion))
            .help(tab.detail.isEmpty ? tab.title : "\(tab.title)\n\(tab.detail)")

            Button {
                model.closeReaderTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.paperCodexSystem(size: 10, weight: .bold))
                    .foregroundStyle(isActive ? Color.secondary : Color.secondary.opacity(0.58))
                    .frame(width: PaperCodexHitTarget.chromeCloseButtonSize, height: PaperCodexHitTarget.chromeCloseButtonSize)
                    .contentShape(Circle())
            }
            .buttonStyle(PaperCodexChromeTabCloseButtonStyle(isActive: isActive, isHovering: isHovering, reduceMotion: reduceMotion))
            .help("Close tab")
        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .frame(width: isActive ? 264 : 218, height: 34)
        .background(tabBackground)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(PaperCodexChromeTabStyle.activeBackground)
                    .frame(height: 3)
                    .offset(y: 1)
            }
        }
        .overlay(
            chromeTabOutline
                .stroke(tabBorder, lineWidth: isActive ? 1 : 0.8)
        )
        .clipShape(chromeTabShape)
        .shadow(
            color: isActive && !reduceMotion ? Color.black.opacity(0.10) : Color.clear,
            radius: isActive ? 5 : 0,
            x: 0,
            y: 1
        )
        .scaleEffect(reduceMotion ? 1 : tabScale, anchor: .bottom)
        .animation(PaperCodexMotion.accessible(PaperCodexMotion.hover, reduceMotion: reduceMotion), value: isHovering)
        .animation(PaperCodexMotion.accessible(PaperCodexMotion.selection, reduceMotion: reduceMotion), value: isActive)
        .onHover { hovering in
            PaperCodexMotion.perform(PaperCodexMotion.hover, reduceMotion: reduceMotion) {
                isHovering = hovering
            }
        }
    }

    private var chromeTabShape: some InsettableShape {
        UnevenRoundedRectangle(
            topLeadingRadius: PaperCodexChromeTabStyle.cornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: PaperCodexChromeTabStyle.cornerRadius
        )
    }

    private var chromeTabOutline: some Shape {
        PaperCodexChromeTabTopOutline(radius: PaperCodexChromeTabStyle.cornerRadius)
    }

    private var tabBackground: Color {
        if isActive {
            return PaperCodexChromeTabStyle.activeBackground
        }
        return isHovering ? PaperCodexChromeTabStyle.inactiveHoverBackground : PaperCodexChromeTabStyle.inactiveBackground
    }

    private var tabBorder: Color {
        if isActive {
            return PaperCodexChromeTabStyle.activeBorder
        }
        return isHovering ? PaperCodexChromeTabStyle.inactiveBorder : Color.clear
    }

    private var tabScale: CGFloat {
        isHovering && !isActive ? 1.012 : 1
    }
}

private struct PaperCodexChromeTabButtonStyle: ButtonStyle {
    var isActive: Bool
    var isHovering: Bool
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        configuration.label
            .opacity(isPressed ? 0.84 : 1)
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.972 : 1), anchor: .bottom)
            .background(
                RoundedRectangle(cornerRadius: PaperCodexCornerRadius.control)
                    .fill(pressFill(isPressed: isPressed))
            )
            .animation(PaperCodexMotion.accessible(PaperCodexMotion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(PaperCodexMotion.accessible(PaperCodexMotion.hover, reduceMotion: reduceMotion), value: isHovering)
            .animation(PaperCodexMotion.accessible(PaperCodexMotion.selection, reduceMotion: reduceMotion), value: isActive)
    }

    private func pressFill(isPressed: Bool) -> Color {
        if !isPressed {
            return .clear
        }
        return isActive ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.06)
    }
}

private struct PaperCodexChromeTabCloseButtonStyle: ButtonStyle {
    var isActive: Bool
    var isHovering: Bool
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        configuration.label
            .background(
                Circle()
                    .fill(backgroundFill(isPressed: isPressed))
            )
            .overlay(
                Circle()
                    .stroke(borderColor(isPressed: isPressed), lineWidth: isPressed || isHovering ? 1 : 0)
            )
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.88 : (isHovering ? 1.06 : 1)), anchor: .center)
            .animation(PaperCodexMotion.accessible(PaperCodexMotion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(PaperCodexMotion.accessible(PaperCodexMotion.hover, reduceMotion: reduceMotion), value: isHovering)
            .animation(PaperCodexMotion.accessible(PaperCodexMotion.selection, reduceMotion: reduceMotion), value: isActive)
    }

    private func backgroundFill(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(isActive ? 0.18 : 0.14)
        }
        return isHovering ? Color.primary.opacity(isActive ? 0.06 : 0.05) : .clear
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(0.34)
        }
        return isHovering ? Color.primary.opacity(0.10) : .clear
    }
}

private enum PaperCodexChromeTabStyle {
    static let cornerRadius: CGFloat = PaperCodexCornerRadius.chromeTab
    static let barBackground = PaperCodexSurface.window
    static let activeBackground = PaperCodexSurface.text
    static let inactiveBackground = PaperCodexSurface.control.opacity(0.36)
    static let inactiveHoverBackground = PaperCodexSurface.control.opacity(0.70)
    static let divider = PaperCodexSurface.separator
    static let activeBorder = Color.primary.opacity(0.16)
    static let inactiveBorder = Color.primary.opacity(0.10)
}

private struct PaperCodexChromeTabTopOutline: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
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
