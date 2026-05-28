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
            .foregroundStyle(disabled ? Color.secondary.opacity(0.55) : (isHovering ? tint : Color.primary.opacity(0.82)))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(disabled ? Color(nsColor: .controlBackgroundColor).opacity(0.55) : (isHovering ? tint.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(disabled ? Color.black.opacity(0.06) : (isHovering ? tint.opacity(0.45) : Color.black.opacity(0.10)), lineWidth: 1)
                    )
            )
            .shadow(color: isHovering && !disabled ? tint.opacity(0.18) : .clear, radius: 7, y: 3)
            .scaleEffect(isHovering && !disabled ? 1.025 : 1)
            .animation(PaperCodexMotion.hover, value: isHovering)
            .animation(PaperCodexMotion.hover, value: disabled)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(title)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
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
                .foregroundStyle(iconColor)
                .background(
                    Circle()
                        .fill(iconBackground)
                )
                .overlay(
                    Circle()
                        .stroke(iconBorder, lineWidth: 1)
                )
                .shadow(color: isHovering && !disabled ? tint.opacity(0.14) : .clear, radius: 6, y: 2)
                .scaleEffect(isHovering && !disabled ? 1.07 : 1)
                .contentShape(Circle())
                .animation(PaperCodexMotion.hover, value: isHovering)
                .animation(PaperCodexMotion.hover, value: disabled)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var iconColor: Color {
        if disabled {
            return Color.secondary.opacity(0.45)
        }
        return isHovering ? tint : tint.opacity(0.78)
    }

    private var iconBackground: Color {
        if disabled {
            return Color(nsColor: .controlBackgroundColor).opacity(0.40)
        }
        return isHovering ? tint.opacity(0.13) : Color.clear
    }

    private var iconBorder: Color {
        if disabled {
            return Color.clear
        }
        return isHovering ? tint.opacity(0.38) : Color.clear
    }
}
