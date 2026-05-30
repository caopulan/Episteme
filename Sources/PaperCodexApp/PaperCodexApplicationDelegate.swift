import AppKit

@MainActor
final class PaperCodexApplicationDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var mainWindowController: PaperCodexMainWindowController?
    private var mainMenuController: PaperCodexMainMenuController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let menuController = PaperCodexMainMenuController(model: model, navigation: model.navigation)
        mainMenuController = menuController
        NSApp.mainMenu = menuController.makeMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func showMainWindow() {
        if mainWindowController == nil {
            mainWindowController = PaperCodexMainWindowController(model: model)
        }
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}
