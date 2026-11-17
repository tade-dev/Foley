import SwiftUI

/// Floating glass bar: Grid/Orbit toggle, 64 pt play/stop, Rec/Done pill.
struct TransportDock: View {
    enum Mode: Hashable { case grid, orbit }
    @Binding var mode: Mode
    var isPlaying: Bool
    var isRecording: Bool
    var onPlayStop: () -> Void
    var onRecord: () -> Void

    @Namespace private var seg
    @State private var playTaps = 0

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    segment(.grid, symbol: "square.grid.2x2", label: "Grid view")
                    segment(.orbit, symbol: "circle.circle", label: "Orbit mixer")
                }
                .padding(4)
                .background(Theme.Colors.sceneBg.opacity(0.7), in: .capsule)

                Spacer(minLength: 0)

                Button {
                    playTaps += 1
                    onPlayStop()
                } label: {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.Colors.bg)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: Theme.Size.transport, height: Theme.Size.transport)
                        .background(Theme.Colors.textPrimary, in: .circle)
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.9))
                .accessibilityLabel(isPlaying ? "Stop all" : "Play all")
                .sensoryFeedback(.impact(weight: .light), trigger: playTaps)

                Spacer(minLength: 0)

                Button(action: onRecord) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: isRecording ? 2 : 5)
                            .fill(Theme.Colors.record)
                            .frame(width: 10, height: 10)
                        Text(isRecording ? "Done" : "Rec").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 92, height: 44)
                    .background(isRecording ? Theme.Colors.record.opacity(0.14) : .clear, in: .capsule)
                    .overlay(Capsule().strokeBorder(isRecording ? Theme.Colors.record.opacity(0.6) : Theme.Colors.queuedBorder))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(isRecording ? "Stop recording" : "Record mix")
                .animation(Motion.quick, value: isRecording)
            }
            .padding(10)
            .foleyGlass(RoundedRectangle(cornerRadius: Theme.Radius.dock), tint: Theme.Colors.dockFill)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.dock).strokeBorder(Theme.Colors.dockBorder))
        }
        .sensoryFeedback(.impact(weight: .light), trigger: mode)
    }

    private func segment(_ m: Mode, symbol: String, label: String) -> some View {
        Button { withAnimation(Motion.seg) { mode = m } } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(mode == m ? Theme.Colors.textPrimary : Theme.Colors.sceneSecondary)
                .frame(width: 44, height: 36)
                .background {
                    if mode == m { Capsule().fill(Theme.Colors.dockBorder).matchedGeometryEffect(id: "seg", in: seg) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(mode == m ? .isSelected : [])
    }
}
