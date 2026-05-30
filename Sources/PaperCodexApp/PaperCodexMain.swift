import AppKit

@main
enum PaperCodexMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = PaperCodexApplicationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
