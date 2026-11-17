import SwiftUI

/// The scene field pinned to the bottom of Home: text, dictate, send.
struct Composer: View {
    @Binding var text: String
    var isListening = false
    var onDictate: () -> Void
    var onSubmit: () -> Void

    @FocusState private var focused: Bool
    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Your scene")
            HStack(alignment: .bottom, spacing: 8) {
                TextField("A pirate ship in a thunderstorm…", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .font(Theme.Fonts.bodyLarge)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tint(Theme.Colors.textPrimary)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { if !isEmpty { onSubmit() } }
                    .padding(.vertical, 10)
                CircleIconButton(symbol: isListening ? "waveform" : "mic", label: isListening ? "Stop dictation" : "Dictate",
                                 fill: isListening ? Theme.Colors.record.opacity(0.25) : Theme.Colors.surfaceRaised,
                                 tint: isListening ? Theme.Colors.record : Theme.Colors.textPrimary,
                                 action: onDictate)
                    .symbolEffect(.variableColor.iterative, isActive: isListening)
                CircleIconButton(symbol: "arrow.up", label: "Build scene",
                                 fill: isEmpty ? Theme.Colors.border : Theme.Colors.textPrimary,
                                 tint: isEmpty ? Theme.Colors.disabledIcon : Theme.Colors.bg,
                                 action: onSubmit)
                    .disabled(isEmpty)
                    .animation(Motion.quick, value: isEmpty)
            }
            .padding(.leading, 16).padding(8)
            .background(Theme.Colors.surface, in: .rect(cornerRadius: Theme.Radius.input))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.input)
                .strokeBorder(focused ? Theme.Colors.textTertiary : Theme.Colors.border))
            .animation(Motion.quick, value: focused)
        }
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
