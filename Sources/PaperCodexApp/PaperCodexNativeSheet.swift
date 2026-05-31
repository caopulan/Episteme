import AppKit
import SwiftUI

struct PaperCodexNativeSheetConfiguration {
    var title: String
    var minimumSize: CGSize

    init(title: String = "", minimumSize: CGSize = CGSize(width: 360, height: 160)) {
        self.title = title
        self.minimumSize = minimumSize
    }
}

extension View {
    func paperCodexNativeSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        title: String = "",
        minimumSize: CGSize = CGSize(width: 360, height: 160),
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        background(
            PaperCodexNativeSheetPresenter(
                configuration: PaperCodexNativeSheetConfiguration(title: title, minimumSize: minimumSize),
                isPresented: isPresented,
                content: { AnyView(content()) }
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        )
    }

    func paperCodexNativeSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        title: String = "",
        minimumSize: CGSize = CGSize(width: 360, height: 160),
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        background(
            PaperCodexNativeItemSheetPresenter(
                configuration: PaperCodexNativeSheetConfiguration(title: title, minimumSize: minimumSize),
                item: item,
                content: { AnyView(content($0)) }
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        )
    }
}

struct PaperCodexNativeSheetPresenter: NSViewRepresentable {
    var configuration: PaperCodexNativeSheetConfiguration
    @Binding var isPresented: Bool
    var content: () -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(
            configuration: configuration,
            isPresented: $isPresented,
            content: content
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.configuration = configuration
        context.coordinator.isPresented = $isPresented
        context.coordinator.content = content
        context.coordinator.sync(from: view)
    }

    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        var configuration: PaperCodexNativeSheetConfiguration
        var isPresented: Binding<Bool>
        var content: () -> AnyView
        weak var anchorView: NSView?
        private var sheetWindow: NSWindow?
        private var isEndingSheet = false

        init(
            configuration: PaperCodexNativeSheetConfiguration,
            isPresented: Binding<Bool>,
            content: @escaping () -> AnyView
        ) {
            self.configuration = configuration
            self.isPresented = isPresented
            self.content = content
            super.init()
        }

        func sync(from view: NSView) {
            if isPresented.wrappedValue {
                if sheetWindow == nil {
                    present(from: view)
                } else {
                    updateSheetContent()
                }
            } else {
                endSheetIfNeeded()
            }
        }

        private func present(from view: NSView) {
            guard let window = view.window ?? NSApp.keyWindow ?? NSApp.mainWindow else {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else {
                        return
                    }
                    self.sync(from: view)
                }
                return
            }

            let rootView = content()
            let hostingController = NSHostingController(rootView: rootView)
            let sheetWindow = NSWindow(
                contentRect: NSRect(origin: .zero, size: configuration.minimumSize),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            sheetWindow.title = configuration.title
            sheetWindow.titleVisibility = .hidden
            sheetWindow.titlebarAppearsTransparent = true
            sheetWindow.isReleasedWhenClosed = false
            sheetWindow.delegate = self
            sheetWindow.contentViewController = hostingController
            sheetWindow.setContentSize(fittingSize(for: hostingController))
            self.sheetWindow = sheetWindow
            window.beginSheet(sheetWindow) { [weak self] _ in
                guard let self else {
                    return
                }
                self.sheetWindow = nil
                self.isEndingSheet = false
                if self.isPresented.wrappedValue {
                    self.isPresented.wrappedValue = false
                }
            }
        }

        private func updateSheetContent() {
            guard let hostingController = sheetWindow?.contentViewController as? NSHostingController<AnyView> else {
                return
            }
            hostingController.rootView = content()
            sheetWindow?.setContentSize(fittingSize(for: hostingController))
        }

        private func endSheetIfNeeded() {
            guard let sheetWindow, !isEndingSheet else {
                return
            }
            isEndingSheet = true
            if let window = sheetWindow.sheetParent {
                window.endSheet(sheetWindow)
            } else {
                sheetWindow.close()
                self.sheetWindow = nil
                isEndingSheet = false
            }
        }

        private func fittingSize(for hostingController: NSHostingController<AnyView>) -> NSSize {
            hostingController.view.layoutSubtreeIfNeeded()
            let fittingSize = hostingController.view.fittingSize
            return NSSize(
                width: max(configuration.minimumSize.width, fittingSize.width),
                height: max(configuration.minimumSize.height, fittingSize.height)
            )
        }

        func windowWillClose(_ notification: Notification) {
            guard !isEndingSheet else {
                return
            }
            if isPresented.wrappedValue {
                isPresented.wrappedValue = false
            }
            sheetWindow = nil
        }
    }
}

private struct PaperCodexNativeItemSheetPresenter<Item: Identifiable>: NSViewRepresentable {
    var configuration: PaperCodexNativeSheetConfiguration
    @Binding var item: Item?
    var content: (Item) -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(
            configuration: configuration,
            item: $item,
            content: content
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.configuration = configuration
        context.coordinator.item = $item
        context.coordinator.content = content
        context.coordinator.sync(from: view)
    }

    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        var configuration: PaperCodexNativeSheetConfiguration
        var item: Binding<Item?>
        var content: (Item) -> AnyView
        weak var anchorView: NSView?
        private var sheetWindow: NSWindow?
        private var isEndingSheet = false

        init(
            configuration: PaperCodexNativeSheetConfiguration,
            item: Binding<Item?>,
            content: @escaping (Item) -> AnyView
        ) {
            self.configuration = configuration
            self.item = item
            self.content = content
            super.init()
        }

        func sync(from view: NSView) {
            if item.wrappedValue != nil {
                if sheetWindow == nil {
                    present(from: view)
                } else {
                    updateSheetContent()
                }
            } else {
                endSheetIfNeeded()
            }
        }

        private func present(from view: NSView) {
            guard let item = item.wrappedValue else {
                return
            }
            guard let window = view.window ?? NSApp.keyWindow ?? NSApp.mainWindow else {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else {
                        return
                    }
                    self.sync(from: view)
                }
                return
            }

            let rootView = content(item)
            let hostingController = NSHostingController(rootView: rootView)
            let sheetWindow = NSWindow(
                contentRect: NSRect(origin: .zero, size: configuration.minimumSize),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            sheetWindow.title = configuration.title
            sheetWindow.titleVisibility = .hidden
            sheetWindow.titlebarAppearsTransparent = true
            sheetWindow.isReleasedWhenClosed = false
            sheetWindow.delegate = self
            sheetWindow.contentViewController = hostingController
            sheetWindow.setContentSize(fittingSize(for: hostingController))
            self.sheetWindow = sheetWindow
            window.beginSheet(sheetWindow) { [weak self] _ in
                guard let self else {
                    return
                }
                self.sheetWindow = nil
                self.isEndingSheet = false
                if self.item.wrappedValue != nil {
                    self.item.wrappedValue = nil
                }
            }
        }

        private func updateSheetContent() {
            guard let item = item.wrappedValue,
                  let hostingController = sheetWindow?.contentViewController as? NSHostingController<AnyView> else {
                return
            }
            hostingController.rootView = content(item)
            sheetWindow?.setContentSize(fittingSize(for: hostingController))
        }

        private func endSheetIfNeeded() {
            guard let sheetWindow, !isEndingSheet else {
                return
            }
            isEndingSheet = true
            if let window = sheetWindow.sheetParent {
                window.endSheet(sheetWindow)
            } else {
                sheetWindow.close()
                self.sheetWindow = nil
                isEndingSheet = false
            }
        }

        private func fittingSize(for hostingController: NSHostingController<AnyView>) -> NSSize {
            hostingController.view.layoutSubtreeIfNeeded()
            let fittingSize = hostingController.view.fittingSize
            return NSSize(
                width: max(configuration.minimumSize.width, fittingSize.width),
                height: max(configuration.minimumSize.height, fittingSize.height)
            )
        }

        func windowWillClose(_ notification: Notification) {
            guard !isEndingSheet else {
                return
            }
            if item.wrappedValue != nil {
                item.wrappedValue = nil
            }
            sheetWindow = nil
        }
    }
}
