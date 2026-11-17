import SwiftUI

/// 40 bars across the screen, coloured by the tints that are playing. Silent = 4 pt flat bars.
struct MasterMeter: View {
    var levels: [Float]          // 40 bins, 0–1
    var tints: [Tint]            // tints of playing pads; empty = silent

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { i, l in
                Capsule()
                    .fill(tints.isEmpty ? Theme.Colors.sceneBorder : tints[i % tints.count].base)
                    .frame(height: tints.isEmpty ? 4 : max(4, CGFloat(l) * 44))
            }
        }
        .frame(height: 44)
        .animation(.interactiveSpring(response: 0.1), value: levels)
        .accessibilityHidden(true)
    }
}
