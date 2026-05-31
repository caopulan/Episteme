import AppKit

enum PaperCodexNativeConfirmation {
    @MainActor
    static func present(
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String = "Cancel",
        style: NSAlert.Style = .warning,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString(title, comment: "")
        alert.informativeText = NSLocalizedString(message, comment: "")
        alert.alertStyle = style
        alert.addButton(withTitle: NSLocalizedString(confirmTitle, comment: ""))
        alert.addButton(withTitle: NSLocalizedString(cancelTitle, comment: ""))

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                onConfirm()
            } else {
                onCancel?()
            }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window) { response in
                handleResponse(response)
            }
        } else {
            handleResponse(alert.runModal())
        }
    }
}
