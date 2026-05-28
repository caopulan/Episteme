import AppKit
import SwiftUI

enum ChatAppearanceDefaults {
    static let defaultMessageFontSize: Double = 16
    static let defaultComposerFontSize: Double = 15
    static let messageFontSizeRange: ClosedRange<Double> = 13...22
    static let composerFontSizeRange: ClosedRange<Double> = 13...20

    static func clampedMessageFontSize(_ size: Double) -> Double {
        min(max(size, messageFontSizeRange.lowerBound), messageFontSizeRange.upperBound)
    }

    static func clampedComposerFontSize(_ size: Double) -> Double {
        min(max(size, composerFontSizeRange.lowerBound), composerFontSizeRange.upperBound)
    }
}

enum ChatFontFamily: String, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "System"
        case .rounded:
            "Rounded"
        case .serif:
            "Serif"
        case .monospaced:
            "Mono"
        }
    }

    var cssFontFamily: String {
        switch self {
        case .system:
            "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif"
        case .rounded:
            "'SF Pro Rounded', -apple-system, BlinkMacSystemFont, sans-serif"
        case .serif:
            "ui-serif, 'New York', Georgia, serif"
        case .monospaced:
            "ui-monospace, 'SF Mono', Menlo, monospace"
        }
    }

    var fontDesign: Font.Design? {
        switch self {
        case .system:
            nil
        case .rounded:
            .rounded
        case .serif:
            .serif
        case .monospaced:
            .monospaced
        }
    }

    func swiftUIFont(size: Double, weight: Font.Weight? = nil) -> Font {
        .system(size: CGFloat(size), weight: weight, design: fontDesign)
    }

    func nsFont(size: Double) -> NSFont {
        let pointSize = CGFloat(size)
        switch self {
        case .system:
            return .systemFont(ofSize: pointSize)
        case .monospaced:
            return .monospacedSystemFont(ofSize: pointSize, weight: .regular)
        case .rounded:
            return designedFont(size: pointSize, design: .rounded)
        case .serif:
            return designedFont(size: pointSize, design: .serif)
        }
    }

    private func designedFont(size: CGFloat, design: NSFontDescriptor.SystemDesign) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(design),
              let font = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return font
    }
}
