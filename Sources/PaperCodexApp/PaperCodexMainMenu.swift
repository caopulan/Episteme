import AppKit

@MainActor
final class PaperCodexMainMenuController: NSObject, NSMenuItemValidation {
    private static let returnKey = "\r"
    private static let upArrowKey = "\u{F700}"
    private static let downArrowKey = "\u{F701}"

    private let model: AppModel
    private let navigation: AppNavigation

    init(model: AppModel, navigation: AppNavigation) {
        self.model = model
        self.navigation = navigation
    }

    func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu(title: "Main Menu")
        mainMenu.addItem(applicationMenuItem())
        mainMenu.addItem(navigationMenuItem())
        mainMenu.addItem(sessionMenuItem())
        mainMenu.addItem(readerMenuItem())
        mainMenu.addItem(windowMenuItem())
        return mainMenu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showReader):
            return model.selectedPaper != nil
        case #selector(newSession):
            return navigation.route == .reader && model.selectedPaper != nil
        case #selector(stopAgent):
            return model.isSessionSending(model.selectedSession?.id)
        case #selector(focusChatComposer), #selector(showReaderChat), #selector(showReaderTerminal), #selector(showReaderNotes):
            return navigation.route == .reader && model.selectedPaper != nil
        case #selector(selectPreviousReaderTab), #selector(selectNextReaderTab):
            return navigation.route == .reader && model.selectedPaper != nil && model.readerTabState.tabs.count > 1
        case #selector(readSelectedPaper), #selector(chatWithSelectedPaper):
            return navigation.route == .library
                && model.selectedLibrarySurface == .papers
                && model.canOpenSelectedLibraryPaper
        case #selector(previousPDFPage), #selector(nextPDFPage), #selector(zoomPDFIn), #selector(zoomPDFOut), #selector(fitPDFWidth):
            return navigation.route == .reader && model.selectedPaper != nil
        default:
            return true
        }
    }

    private func applicationMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Episteme")
        menu.addItem(systemItem("About Episteme", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Settings...", action: #selector(showSettings), key: ","))
        menu.addItem(NSMenuItem.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        menu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        menu.addItem(NSMenuItem.separator())
        menu.addItem(systemItem("Hide Episteme", action: #selector(NSApplication.hide(_:)), key: "h"))
        menu.addItem(systemItem("Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]))
        menu.addItem(systemItem("Show All", action: #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(systemItem("Quit Episteme", action: #selector(NSApplication.terminate(_:)), key: "q"))

        let item = NSMenuItem(title: "Episteme", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func navigationMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Navigate")
        menu.addItem(item("Library", action: #selector(goToLibrary), key: "1"))
        menu.addItem(item("探索", action: #selector(showDiscover), key: "2"))
        menu.addItem(item("搜索", action: #selector(showSearch), key: "3"))
        menu.addItem(item("Reader", action: #selector(showReader), key: "4"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Focus Search", action: #selector(focusSearch), key: "f"))

        let item = NSMenuItem(title: "Navigate", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func sessionMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Session")
        menu.addItem(item("New Session", action: #selector(newSession), key: "n"))
        menu.addItem(item("Stop Agent", action: #selector(stopAgent), key: "."))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Focus Chat Composer", action: #selector(focusChatComposer), key: "l"))
        menu.addItem(item("Show Reader Chat", action: #selector(showReaderChat), key: "1", modifiers: [.command, .option]))
        menu.addItem(item("Show Reader Terminal", action: #selector(showReaderTerminal), key: "2", modifiers: [.command, .option]))
        menu.addItem(item("Show Reader Notes", action: #selector(showReaderNotes), key: "3", modifiers: [.command, .option]))

        let item = NSMenuItem(title: "Session", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func readerMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Reader")
        menu.addItem(item("Select Previous Reader Tab", action: #selector(selectPreviousReaderTab), key: "[", modifiers: [.command, .shift]))
        menu.addItem(item("Select Next Reader Tab", action: #selector(selectNextReaderTab), key: "]", modifiers: [.command, .shift]))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Read Selected Paper", action: #selector(readSelectedPaper), key: Self.returnKey))
        menu.addItem(item("Chat With Selected Paper", action: #selector(chatWithSelectedPaper), key: Self.returnKey, modifiers: [.command, .shift]))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Previous PDF Page", action: #selector(previousPDFPage), key: Self.upArrowKey))
        menu.addItem(item("Next PDF Page", action: #selector(nextPDFPage), key: Self.downArrowKey))
        menu.addItem(item("Zoom PDF In", action: #selector(zoomPDFIn), key: "="))
        menu.addItem(item("Zoom PDF Out", action: #selector(zoomPDFOut), key: "-"))
        menu.addItem(item("Fit PDF Width", action: #selector(fitPDFWidth), key: "0"))

        let item = NSMenuItem(title: "Reader", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(systemItem("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m", target: nil))
        menu.addItem(systemItem("Zoom", action: #selector(NSWindow.performZoom(_:)), target: nil))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(systemItem("Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = menu

        let item = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func item(
        _ title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func systemItem(
        _ title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = NSApp
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    @objc private func goToLibrary() {
        model.goToLibrary()
    }

    @objc private func showDiscover() {
        model.showDiscover()
    }

    @objc private func showSearch() {
        model.showSearch()
    }

    @objc private func showReader() {
        if model.selectedPaper != nil {
            model.route = .reader
        }
    }

    @objc private func showSettings() {
        model.showSettings()
    }

    @objc private func newSession() {
        model.newSessionButtonTapped()
    }

    @objc private func stopAgent() {
        model.cancelActiveCodexRun()
    }

    @objc private func focusSearch() {
        model.requestSearchFocus()
    }

    @objc private func focusChatComposer() {
        model.requestChatComposerFocus()
    }

    @objc private func showReaderChat() {
        model.showReaderSessionPanel(.chat)
    }

    @objc private func showReaderTerminal() {
        model.showReaderSessionPanel(.terminal)
    }

    @objc private func showReaderNotes() {
        model.showReaderSessionPanel(.notes)
    }

    @objc private func selectPreviousReaderTab() {
        model.selectPreviousReaderTab()
    }

    @objc private func selectNextReaderTab() {
        model.selectNextReaderTab()
    }

    @objc private func readSelectedPaper() {
        model.openSelectedLibraryPaperForReading()
    }

    @objc private func chatWithSelectedPaper() {
        model.openSelectedLibraryPaperForChat()
    }

    @objc private func previousPDFPage() {
        model.sendPDFKitCommand(.previousPage)
    }

    @objc private func nextPDFPage() {
        model.sendPDFKitCommand(.nextPage)
    }

    @objc private func zoomPDFIn() {
        model.sendPDFKitCommand(.zoomIn)
    }

    @objc private func zoomPDFOut() {
        model.sendPDFKitCommand(.zoomOut)
    }

    @objc private func fitPDFWidth() {
        model.sendPDFKitCommand(.fitWidth)
    }
}
