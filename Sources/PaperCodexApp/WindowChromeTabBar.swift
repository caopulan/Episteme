import AppKit
import PaperCodexCore
import SwiftUI

struct PaperCodexWindowTabBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @State private var isWindowFullscreen = false

    var onShowSaveToLibrary: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)

            HStack(alignment: .bottom, spacing: 0) {
                PaperCodexHomeChromeTab(
                    isActive: navigation.route != .reader,
                    helpText: homeTabHelp
                ) {
                    selectHomeTab()
                }

                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(model.readerTabState.tabs) { tab in
                            PaperCodexReaderChromeTabItem(
                                tab: tab,
                                isActive: navigation.route == .reader
                                    && (model.selectedPaper?.id == tab.paperID
                                        || model.readerTabState.activePaperID == tab.paperID)
                            )
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
                .frame(height: PaperCodexWindowChrome.tabBarHeight)
                .layoutPriority(1)

                if let paper = model.selectedPaper, !paper.isSaved {
                    Button {
                        onShowSaveToLibrary()
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.paperCodexSystem(size: 12.5, weight: .semibold))
                            .frame(width: 28, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .help("Save to Library")
                    .padding(.bottom, 5)
                }
            }
            .padding(.leading, isWindowFullscreen ? PaperCodexWindowChrome.tabBarFullscreenLeadingInset : PaperCodexWindowChrome.tabBarTrafficLightLeadingInset)
            .padding(.trailing, 10)
            .frame(height: PaperCodexWindowChrome.tabBarHeight, alignment: .bottom)
        }
        .frame(height: PaperCodexWindowChrome.tabBarHeight)
        .background(Color(nsColor: .windowBackgroundColor))
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
            return "Home: Discover"
        case .settings:
            return "Home: Settings"
        case .reader:
            return "Home (Library, Discover, Settings, Recent Conversations)"
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

private struct PaperCodexHomeChromeTab: View {
    @State private var isHovering = false

    var isActive: Bool
    var helpText: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "house.fill" : "house")
                .font(.paperCodexSystem(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 44, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(tabBackground)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color(nsColor: .textBackgroundColor))
                    .frame(height: 2)
                    .offset(y: 1)
            }
        }
        .overlay(
            chromeTabShape
                .stroke(tabBorder, lineWidth: isActive ? 1 : 0.8)
        )
        .clipShape(chromeTabShape)
        .help(helpText)
        .accessibilityLabel("Home")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                isHovering = hovering
            }
        }
    }

    private var chromeTabShape: some InsettableShape {
        UnevenRoundedRectangle(
            topLeadingRadius: 10,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 10
        )
    }

    private var tabBackground: Color {
        if isActive {
            return Color(nsColor: .textBackgroundColor)
        }
        return isHovering ? Color(nsColor: .controlBackgroundColor).opacity(0.78) : Color(nsColor: .windowBackgroundColor)
    }

    private var tabBorder: Color {
        if isActive {
            return Color.primary.opacity(0.14)
        }
        return isHovering ? Color.primary.opacity(0.10) : Color.clear
    }
}

private struct PaperCodexReaderChromeTabItem: View {
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
            .buttonStyle(.plain)
            .help(tab.detail.isEmpty ? tab.title : "\(tab.title)\n\(tab.detail)")

            Button {
                model.closeReaderTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.paperCodexSystem(size: 10, weight: .bold))
                    .foregroundStyle(isActive ? Color.secondary : Color.secondary.opacity(0.58))
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close tab")
        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .frame(width: isActive ? 264 : 218, height: 34)
        .background(tabBackground)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color(nsColor: .textBackgroundColor))
                    .frame(height: 2)
                    .offset(y: 1)
            }
        }
        .overlay(
            chromeTabShape
                .stroke(tabBorder, lineWidth: isActive ? 1 : 0.8)
        )
        .clipShape(chromeTabShape)
        .shadow(
            color: isActive ? Color.black.opacity(0.10) : Color.clear,
            radius: isActive ? 5 : 0,
            x: 0,
            y: 1
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                isHovering = hovering
            }
        }
    }

    private var chromeTabShape: some InsettableShape {
        UnevenRoundedRectangle(
            topLeadingRadius: 10,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 10
        )
    }

    private var tabBackground: Color {
        if isActive {
            return Color(nsColor: .textBackgroundColor)
        }
        return isHovering ? Color(nsColor: .controlBackgroundColor).opacity(0.78) : Color(nsColor: .windowBackgroundColor)
    }

    private var tabBorder: Color {
        if isActive {
            return Color.primary.opacity(0.14)
        }
        return isHovering ? Color.primary.opacity(0.10) : Color.clear
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
