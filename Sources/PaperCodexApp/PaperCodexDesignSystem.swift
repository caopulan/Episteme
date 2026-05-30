import SwiftUI

enum PaperCodexSurface {
    static var window: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var control: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var text: Color {
        Color(nsColor: .textBackgroundColor)
    }

    static var separator: Color {
        Color.primary.opacity(0.13)
    }
}

enum PaperCodexSpacing {
    static let controlHorizontal: CGFloat = 10
    static let controlVertical: CGFloat = 7
    static let sidebarRowLeading: CGFloat = 9
    static let sidebarRowTrailing: CGFloat = 9
    static let sidebarRowVertical: CGFloat = 7
}

enum PaperCodexCornerRadius {
    static let control: CGFloat = 8
    static let chromeTab: CGFloat = 9
}

enum PaperCodexHitTarget {
    static let toolbarIconSize: CGFloat = 30
    static let toolbarButtonVerticalPadding: CGFloat = PaperCodexSpacing.controlVertical
    static let toolbarButtonHorizontalPadding: CGFloat = PaperCodexSpacing.controlHorizontal
    static let toolbarButtonHeight: CGFloat = 30
    static let toolbarButtonSymbolSize: CGFloat = 15
    static let toolbarButtonSymbolWidth: CGFloat = 16
    static let toolbarButtonSymbolTextSpacing: CGFloat = 6
    static let toolbarButtonFontSize: CGFloat = 12.5
    static let toolbarIconSymbolSize: CGFloat = 12
    static let chromeHomeTabWidth: CGFloat = 44
    static let chromeTabHeight: CGFloat = 34
    static let chromeCloseButtonSize: CGFloat = 22
}

enum PaperCodexMotion {
    static let hover = Animation.easeOut(duration: 0.12)
    static let press = Animation.easeOut(duration: 0.05)
    static let selection = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let pdfSplitOpen = Animation.easeInOut(duration: 0.24)
    static let pdfSplitContent = Animation.easeOut(duration: 0.16)

    static func accessible(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    static func perform(_ animation: Animation, reduceMotion: Bool, updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
}
