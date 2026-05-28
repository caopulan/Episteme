import SwiftUI

struct PaperCodexToolbarButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .padding(.horizontal, PaperCodexHitTarget.toolbarButtonHorizontalPadding)
            .padding(.vertical, PaperCodexHitTarget.toolbarButtonVerticalPadding)
        }
        .buttonStyle(PaperCodexToolbarButtonStyle(tint: tint, disabled: disabled, isHovering: isHovering, reduceMotion: reduceMotion))
        .disabled(disabled)
        .help(title)
        .onHover { hovering in
            PaperCodexMotion.perform(PaperCodexMotion.hover, reduceMotion: reduceMotion) {
                isHovering = hovering
            }
        }
    }
}

private struct PaperCodexToolbarButtonStyle: ButtonStyle {
    var tint: Color
    var disabled: Bool
    var isHovering: Bool
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && !disabled
        configuration.label
            .foregroundStyle(foregroundColor(isPressed: isPressed))
            .background(
                RoundedRectangle(cornerRadius: PaperCodexCornerRadius.control)
                    .fill(backgroundColor(isPressed: isPressed))
                    .overlay(
                        RoundedRectangle(cornerRadius: PaperCodexCornerRadius.control)
                            .stroke(borderColor(isPressed: isPressed), lineWidth: 1)
                    )
            )
            .shadow(color: shadowColor(isPressed: isPressed), radius: isPressed ? 4 : 7, y: isPressed ? 1 : 3)
            .scaleEffect(reduceMotion ? 1 : buttonScale(isPressed: isPressed), anchor: .center)
            .animation(PaperCodexMotion.accessible(PaperCodexMotion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(PaperCodexMotion.accessible(PaperCodexMotion.hover, reduceMotion: reduceMotion), value: isHovering)
            .animation(PaperCodexMotion.accessible(PaperCodexMotion.hover, reduceMotion: reduceMotion), value: disabled)
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        if disabled {
            return Color.secondary.opacity(0.55)
        }
        return isPressed || isHovering ? tint : Color.primary.opacity(0.82)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if disabled {
            return PaperCodexSurface.control.opacity(0.55)
        }
        if isPressed {
            return tint.opacity(0.18)
        }
        return isHovering ? tint.opacity(0.12) : PaperCodexSurface.control
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                .frame(width: PaperCodexHitTarget.toolbarIconSize, height: PaperCodexHitTarget.toolbarIconSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(PaperCodexIconButtonStyle(tint: tint, disabled: disabled, isHovering: isHovering, reduceMotion: reduceMotion))
        .disabled(disabled)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovering in
            PaperCodexMotion.perform(PaperCodexMotion.hover, reduceMotion: reduceMotion) {
                isHovering = hovering
            }
        }
    }
}

private struct PaperCodexIconButtonStyle: ButtonStyle {
    var tint: Color
    var disabled: Bool
    var isHovering: Bool
    var reduceMotion: Bool

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
            .scaleEffect(reduceMotion ? 1 : iconScale(isPressed: isPressed), anchor: .center)
            .contentShape(Rectangle())
            .animation(PaperCodexMotion.accessible(PaperCodexMotion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(PaperCodexMotion.accessible(PaperCodexMotion.hover, reduceMotion: reduceMotion), value: isHovering)
            .animation(PaperCodexMotion.accessible(PaperCodexMotion.hover, reduceMotion: reduceMotion), value: disabled)
    }

    private func iconColor(isPressed: Bool) -> Color {
        if disabled {
            return Color.secondary.opacity(0.45)
        }
        return isPressed || isHovering ? tint : tint.opacity(0.78)
    }

    private func iconBackground(isPressed: Bool) -> Color {
        if disabled {
            return PaperCodexSurface.control.opacity(0.40)
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
