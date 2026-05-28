import SwiftUI

struct SidebarRowButton: View {
    @State private var isHovering = false

    var title: String
    var systemImage: String
    var selected: Bool
    var depth: Int = 0
    var trailingReserve: CGFloat = 0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.78))
                Text(LocalizedStringKey(title))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(depth * 14) + 9)
            .padding(.trailing, 9 + trailingReserve)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowButtonStyle(selected: selected, isHovering: isHovering, depth: depth))
        .onHover { hovering in
            withAnimation(PaperCodexMotion.hover) {
                isHovering = hovering
            }
        }
    }
}

private struct SidebarRowButtonStyle: ButtonStyle {
    var selected: Bool
    var isHovering: Bool
    var depth: Int

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(rowBackground(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: shadowColor(isPressed: configuration.isPressed), radius: 7, y: 3)
            .scaleEffect(configuration.isPressed ? 0.985 : (isHovering ? 1.015 : 1), anchor: .center)
            .overlay(alignment: .leading) {
                if selected || configuration.isPressed {
                    Capsule()
                        .fill(Color.accentColor.opacity(selected ? 0.72 : 0.52))
                        .frame(width: 3, height: 18)
                        .padding(.leading, CGFloat(depth * 14) + 3)
                        .transition(.opacity.combined(with: .scale(scale: 0.82)))
                }
            }
            .animation(PaperCodexMotion.press, value: configuration.isPressed)
            .animation(PaperCodexMotion.hover, value: isHovering)
            .animation(PaperCodexMotion.selection, value: selected)
    }

    private func rowBackground(isPressed: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(rowFill(isPressed: isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(rowStroke(isPressed: isPressed), lineWidth: 1)
            )
    }

    private func rowFill(isPressed: Bool) -> Color {
        if selected {
            return Color.accentColor.opacity(0.14)
        }
        if isPressed {
            return Color.accentColor.opacity(0.10)
        }
        return isHovering ? Color(nsColor: .textBackgroundColor) : Color.clear
    }

    private func rowStroke(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(0.38)
        }
        return isHovering ? Color.accentColor.opacity(0.25) : Color.clear
    }

    private func shadowColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(0.12)
        }
        return isHovering ? Color.black.opacity(0.08) : .clear
    }
}
