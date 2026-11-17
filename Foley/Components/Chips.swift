import SwiftUI

/// A detected sound on the Typing screen. Just-added chips pop in with a tinted border.
struct SoundChip: View {
    var name: String
    var tint: Tint
    var isNew = false
    var isDimmed = false

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(tint.base).frame(width: 10, height: 10)
            Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, 12).frame(height: Theme.Size.chip)
        .background(Theme.Colors.chipFill, in: .capsule)
        .overlay(Capsule().strokeBorder(isNew ? tint.base : Theme.Colors.chipBorder))
        .opacity(isDimmed ? 0.4 : 1)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

/// "Try one" prompt on Home. Tap types the title into the composer.
struct SuggestionChip: View {
    var title: String
    var tint: Tint
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(tint.base).frame(width: 8, height: 8)
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Theme.Colors.chipText)
            .padding(.horizontal, 14).frame(height: Theme.Size.suggestionChip)
            .background(Theme.Colors.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.Colors.border))
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Generic press feedback for capsules and rows.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}
