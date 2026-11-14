import SwiftUI

/// Bars from downsampled peaks. Played part in the tint, rest at rest colour.
/// `drawProgress` 0 → 1 reveals bars left to right for the "waveform draws itself" moment.
struct WaveformView: View {
    var samples: [Float]          // 0–1
    var progress: Double = 0      // 0–1 played
    var tint: Tint = .blue
    var tints: [Tint]? = nil      // optional per-bucket cycling (mix card)
    var drawProgress: Double = 1

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(samples.enumerated()), id: \.offset) { i, s in
                    let x = Double(i) / Double(max(samples.count - 1, 1))
                    let color = tints.map { $0[i * $0.count / max(samples.count, 1)].base } ?? tint.base
                    Capsule()
                        .fill(x <= progress ? color : (tints == nil ? Theme.Colors.waveformRest : color.opacity(0.45)))
                        .frame(height: max(3, geo.size.height * CGFloat(s)))
                        .opacity(x <= drawProgress ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}
