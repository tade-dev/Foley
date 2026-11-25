import SwiftUI

/// The scene field pinned to the bottom of Home.
///
/// Two shapes, like the input in a chat app: a slim capsule at rest, and when you focus it the
/// text takes its own line and the controls drop below, so long prompts have room to breathe.
struct Composer: View {
    @Binding var text: String
    /// Owned by the screen, so it can make room when the keyboard arrives.
    @FocusState.Binding var focused: Bool
    var isListening = false
    var onDictate: () -> Void
    var onSubmit: () -> Void

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isExpanded: Bool { focused || !isEmpty }

    var body: some View {
        // One container, three children, always the same three. Swapping between `if` branches
        // would build a second text field and destroy the first, so focus died the instant a tap
        // granted it: the keyboard opened and shut again and the field looked dead.
        ComposerLayout(expanded: isExpanded) {
            field
            micButton
            sendButton
        }
        .padding(.horizontal, isExpanded ? 18 : 8)
        .padding(.vertical, isExpanded ? 16 : 8)
        .background {
            let shape = RoundedRectangle(cornerRadius: isExpanded ? 30 : 34, style: .continuous)
            shape.fill(Theme.Colors.surface.opacity(0.55))
                .foleyGlass(shape)
                .overlay(shape.strokeBorder(Theme.Colors.border.opacity(0.9)))
                .allowsHitTesting(false)      // decoration only; never swallow a tap meant for the field
        }
        .animation(Motion.keyboard, value: isExpanded)
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
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
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


/// Lays the composer out as one row when collapsed and two when expanded.
///
/// This exists so the shape can change without the views changing: a `Layout` re-places the
/// same subviews, where an `if`/`else` would create new ones and drop the text field's focus.
private struct ComposerLayout: Layout {
    var expanded: Bool
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let (field, mic, send) = (subviews[0], subviews[1], subviews[2])
        let micSize = mic.sizeThatFits(.unspecified)
        let sendSize = send.sizeThatFits(.unspecified)

        if expanded {
            let fieldSize = field.sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: width,
                          height: fieldSize.height + spacing + max(micSize.height, sendSize.height))
        }
        let room = max(0, width - micSize.width - sendSize.width - spacing * 2)
        let fieldSize = field.sizeThatFits(ProposedViewSize(width: room, height: nil))
        return CGSize(width: width,
                      height: max(fieldSize.height, max(micSize.height, sendSize.height)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (field, mic, send) = (subviews[0], subviews[1], subviews[2])
        let micSize = mic.sizeThatFits(.unspecified)
        let sendSize = send.sizeThatFits(.unspecified)

        if expanded {
            let fieldSize = field.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            field.place(at: CGPoint(x: bounds.minX, y: bounds.minY),
                        proposal: ProposedViewSize(width: bounds.width, height: fieldSize.height))
            let controlsY = bounds.minY + fieldSize.height + spacing
            mic.place(at: CGPoint(x: bounds.minX, y: controlsY), proposal: .unspecified)
            send.place(at: CGPoint(x: bounds.maxX - sendSize.width, y: controlsY), proposal: .unspecified)
            return
        }

        let room = max(0, bounds.width - micSize.width - sendSize.width - spacing * 2)
        let fieldSize = field.sizeThatFits(ProposedViewSize(width: room, height: nil))
        let rowHeight = max(fieldSize.height, max(micSize.height, sendSize.height))
        func centred(_ height: CGFloat) -> CGFloat { bounds.minY + (rowHeight - height) / 2 }

        field.place(at: CGPoint(x: bounds.minX, y: centred(fieldSize.height)),
                    proposal: ProposedViewSize(width: room, height: fieldSize.height))
        mic.place(at: CGPoint(x: bounds.minX + room + spacing, y: centred(micSize.height)),
                  proposal: .unspecified)
        send.place(at: CGPoint(x: bounds.maxX - sendSize.width, y: centred(sendSize.height)),
                   proposal: .unspecified)
    }
}
