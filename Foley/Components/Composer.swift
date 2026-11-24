import SwiftUI

/// The scene field pinned to the bottom of Home.
///
/// Two shapes, like the input in a chat app: a slim capsule at rest, and when you focus it the
/// text takes its own line and the controls drop below, so long prompts have room to breathe.
struct Composer: View {
    @Binding var text: String
    var isListening = false
    var onDictate: () -> Void
    var onSubmit: () -> Void

    @FocusState private var focused: Bool

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isExpanded: Bool { focused || !isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isExpanded {
                field
                HStack(spacing: 10) {
                    micButton
                    Spacer(minLength: 0)
                    sendButton
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 10) {
                    field
                    micButton
                    sendButton
                }
            }
        }
        .padding(.horizontal, isExpanded ? 18 : 8)
        .padding(.vertical, isExpanded ? 16 : 8)
        .background {
            let shape = RoundedRectangle(cornerRadius: isExpanded ? 30 : 34, style: .continuous)
            shape.fill(Theme.Colors.surface.opacity(0.55))
                .foleyGlass(shape)
                .overlay(shape.strokeBorder(Theme.Colors.border.opacity(0.9)))
        }
        .animation(Motion.seg, value: isExpanded)
    }

    private var field: some View {
        TextField("A pirate ship in a thunderstorm…", text: $text, axis: .vertical)
            .lineLimit(isExpanded ? 1...6 : 1...1)
            .font(Theme.Fonts.bodyLarge)
            .foregroundStyle(Theme.Colors.textPrimary)
            .tint(Theme.Colors.textPrimary)
            .focused($focused)
            .submitLabel(.go)
            .onSubmit { if !isEmpty { onSubmit() } }
            .padding(.leading, isExpanded ? 2 : 12)
            .padding(.vertical, isExpanded ? 2 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var micButton: some View {
        CircleIconButton(symbol: isListening ? "waveform" : "mic",
                         label: isListening ? "Stop dictation" : "Dictate",
                         fill: isListening ? Theme.Colors.record.opacity(0.25) : Theme.Colors.surfaceRaised,
                         tint: isListening ? Theme.Colors.record : Theme.Colors.textSecondary,
                         size: 42,
                         action: onDictate)
            .symbolEffect(.variableColor.iterative, isActive: isListening)
    }

    private var sendButton: some View {
        CircleIconButton(symbol: "arrow.up", label: "Build scene",
                         fill: isEmpty ? Theme.Colors.surfaceRaised : Theme.Colors.textPrimary,
                         tint: isEmpty ? Theme.Colors.disabledIcon : Theme.Colors.bg,
                         size: 46,
                         action: onSubmit)
            .disabled(isEmpty)
            .animation(Motion.quick, value: isEmpty)
    }
}

/// 44 pt (default) circular icon button. `glass: true` renders it in Liquid Glass for floating chrome.
struct CircleIconButton: View {
    var symbol: String
    var label: String
    var fill: Color = Theme.Colors.surface
    var tint: Color = Theme.Colors.textPrimary
    var size: CGFloat = Theme.Size.touch
    var glass = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background {
                    if glass {
                        Circle().fill(.clear).foleyGlass(Circle(), interactive: true)
                    } else {
                        Circle().fill(fill)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .accessibilityLabel(label)
    }
}
