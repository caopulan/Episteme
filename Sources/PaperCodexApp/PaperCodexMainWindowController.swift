import AppKit
import SwiftUI

@MainActor
final class PaperCodexMainWindowController: NSWindowController, NSWindowDelegate {
    private var titlebarDoubleClickMonitor: Any?

    init(model: AppModel) {
        let rootView = RootView()
            .environmentObject(model)
            .environmentObject(model.navigation)
            .frame(minWidth: 1100, minHeight: 720)

        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Episteme"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 1100, height: 720)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()

        super.init(window: window)
        window.delegate = self
        installTitlebarDoubleClickZoomMonitor(for: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        removeTitlebarDoubleClickZoomMonitor()
    }

    private func installTitlebarDoubleClickZoomMonitor(for window: NSWindow) {
        removeTitlebarDoubleClickZoomMonitor()
        titlebarDoubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak window] event in
            guard let window,
                  event.window === window,
                  event.clickCount == 2,
                  Self.isInTitlebarDoubleClickZoomArea(event.locationInWindow, window: window) else {
                return event
            }
            DispatchQueue.main.async { [weak window] in
                window?.performZoom(nil)
            }
            return nil
        }
    }

    private func removeTitlebarDoubleClickZoomMonitor() {
        if let titlebarDoubleClickMonitor {
            NSEvent.removeMonitor(titlebarDoubleClickMonitor)
        }
        titlebarDoubleClickMonitor = nil
    }

    private static func isInTitlebarDoubleClickZoomArea(_ location: NSPoint, window: NSWindow) -> Bool {
        location.y >= window.frame.height - PaperCodexWindowChrome.titlebarDoubleClickZoomHeight
    }
}
