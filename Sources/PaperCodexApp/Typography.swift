import SwiftUI

enum PaperCodexTypography {
    static let defaultBodySize: CGFloat = 13
    static let fixedFontNoBoostThreshold: CGFloat = 24
    static let fixedFontSingleBoostThreshold: CGFloat = 20
    static let readableLineWidth: CGFloat = 720

    static func scaledFixedSize(_ size: CGFloat) -> CGFloat {
        if size >= fixedFontNoBoostThreshold {
            return size
        }
        if size >= fixedFontSingleBoostThreshold {
            return size + 1
        }
        return size + 2
    }
}

extension Font {
    static func paperCodexSystem(
        size: CGFloat,
        weight: Font.Weight? = nil,
        design: Font.Design? = nil
    ) -> Font {
        .system(size: PaperCodexTypography.scaledFixedSize(size), weight: weight, design: design)
    }
}

private struct PaperCodexTypographyScale: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.paperCodexSystem(size: PaperCodexTypography.defaultBodySize))
            .dynamicTypeSize(.medium ... .accessibility2)
    }
}

private struct PaperCodexReadableLineLimit: ViewModifier {
    var maxWidth: CGFloat
    var alignment: Alignment

    func body(content: Content) -> some View {
        content.frame(maxWidth: maxWidth, alignment: alignment)
    }
}

extension View {
    func paperCodexTypographyScale() -> some View {
        modifier(PaperCodexTypographyScale())
    }

    func paperCodexReadableLineLimit(
        _ maxWidth: CGFloat = PaperCodexTypography.readableLineWidth,
        alignment: Alignment = .leading
    ) -> some View {
        modifier(PaperCodexReadableLineLimit(maxWidth: maxWidth, alignment: alignment))
    }
}
