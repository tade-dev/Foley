import SwiftUI

/// "REC 0:12" with a pulsing dot. Shown in the Board header while recording.
struct RecPill: View {
    var elapsed: Duration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.Colors.record).frame(width: 8, height: 8)
                .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.3]) { v, o in v.opacity(o) } animation: { _ in .easeInOut(duration: 0.5) }
            Text("REC \(elapsed.formatted(.time(pattern: .minuteSecond)))")
                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, 12).frame(height: 32)
        .foleyGlass(Capsule(), tint: Theme.Colors.record.opacity(0.35))
        .overlay(Capsule().strokeBorder(Theme.Colors.record.opacity(0.5)))
        .accessibilityLabel("Recording, \(elapsed.formatted(.time(pattern: .minuteSecond)))")
    }
}
