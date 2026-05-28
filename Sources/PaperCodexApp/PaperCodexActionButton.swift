import SwiftUI

enum PaperCodexMotion {
    static let hover = Animation.easeOut(duration: 0.12)
    static let press = Animation.easeOut(duration: 0.05)
    static let selection = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let route = Animation.easeOut(duration: 0.08)
}

struct PaperCodexToolbarButton: View {
    @State private var isHovering = false

    var title: String
    var systemImage: String
    var tint: Color = .blue
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(LocalizedStringKey(title))
                    .lineLimit(1)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.paperCodexSystem(size: 12.5, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(PaperCodexToolbarButtonStyle(tint: tint, disabled: disabled, isHovering: isHovering))
        .disabled(disabled)
        .help(title)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct PaperCodexToolbarButtonStyle: ButtonStyle {
    var tint: Color
    var disabled: Bool
    var isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && !disabled
        configuration.label
            .foregroundStyle(foregroundColor(isPressed: isPressed))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor(isPressed: isPressed))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor(isPressed: isPressed), lineWidth: 1)
                    )
            )
            .shadow(color: shadowColor(isPressed: isPressed), radius: isPressed ? 4 : 7, y: isPressed ? 1 : 3)
            .scaleEffect(buttonScale(isPressed: isPressed), anchor: .center)
            .animation(PaperCodexMotion.press, value: configuration.isPressed)
            .animation(PaperCodexMotion.hover, value: isHovering)
            .animation(PaperCodexMotion.hover, value: disabled)
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        if disabled {
            return Color.secondary.opacity(0.55)
        }
        return isPressed || isHovering ? tint : Color.primary.opacity(0.82)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if disabled {
            return Color(nsColor: .controlBackgroundColor).opacity(0.55)
        }
        if isPressed {
            return tint.opacity(0.18)
        }
        return isHovering ? tint.opacity(0.12) : Color(nsColor: .controlBackgroundColor)
    }

    private func borderColor(isPressed: Bool) -> Color {
        if disabled {
            return Color.black.opacity(0.06)
        }
        if isPressed {
            return tint.opacity(0.58)
        }
        return isHovering ? tint.opacity(0.45) : Color.black.opacity(0.10)
    }

    private func shadowColor(isPressed: Bool) -> Color {
        if disabled {
            return .clear
        }
        return isPressed || isHovering ? tint.opacity(isPressed ? 0.12 : 0.18) : .clear
    }

    private func buttonScale(isPressed: Bool) -> CGFloat {
        if disabled {
            return 1
        }
        return isPressed ? 0.97 : (isHovering ? 1.025 : 1)
    }
}

struct PaperCodexIconButton: View {
    @State private var isHovering = false

    var title: String
    var systemImage: String
    var tint: Color = .secondary
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.paperCodexSystem(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(PaperCodexIconButtonStyle(tint: tint, disabled: disabled, isHovering: isHovering))
        .disabled(disabled)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct PaperCodexIconButtonStyle: ButtonStyle {
    var tint: Color
    var disabled: Bool
    var isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && !disabled
        configuration.label
            .foregroundStyle(iconColor(isPressed: isPressed))
            .background(
                Circle()
                    .fill(iconBackground(isPressed: isPressed))
            )
            .overlay(
                Circle()
                    .stroke(iconBorder(isPressed: isPressed), lineWidth: 1)
            )
            .shadow(color: iconShadow(isPressed: isPressed), radius: isPressed ? 3 : 6, y: isPressed ? 1 : 2)
            .scaleEffect(iconScale(isPressed: isPressed), anchor: .center)
            .contentShape(Circle())
            .animation(PaperCodexMotion.press, value: configuration.isPressed)
            .animation(PaperCodexMotion.hover, value: isHovering)
            .animation(PaperCodexMotion.hover, value: disabled)
    }

    private func iconColor(isPressed: Bool) -> Color {
        if disabled {
            return Color.secondary.opacity(0.45)
        }
        return isPressed || isHovering ? tint : tint.opacity(0.78)
    }

    private func iconBackground(isPressed: Bool) -> Color {
        if disabled {
            return Color(nsColor: .controlBackgroundColor).opacity(0.40)
        }
        if isPressed {
            return tint.opacity(0.20)
        }
        return isHovering ? tint.opacity(0.13) : Color.clear
    }

    private func iconBorder(isPressed: Bool) -> Color {
        if disabled {
            return Color.clear
        }
        if isPressed {
            return tint.opacity(0.52)
        }
        return isHovering ? tint.opacity(0.38) : Color.clear
    }

    private func iconShadow(isPressed: Bool) -> Color {
        if disabled {
            return .clear
        }
        return isPressed || isHovering ? tint.opacity(isPressed ? 0.10 : 0.14) : .clear
    }

    private func iconScale(isPressed: Bool) -> CGFloat {
        if disabled {
            return 1
        }
        return isPressed ? 0.92 : (isHovering ? 1.07 : 1)
    }
}
