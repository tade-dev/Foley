#if DEBUG
import SwiftUI

/// Launch with `-gallery` to screenshot components against the handoff PNGs.
struct DebugGallery: View {
    @State private var level = 0.6

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionLabel("Orbs")
                HStack(spacing: 24) {
                    SoundOrb(tint: .amber, size: 72, mode: .idle)
                    SoundOrb(tint: .teal, size: 72, mode: .generating)
                    SoundOrb(tint: .blue, size: 72, mode: .ready)
                    SoundOrb(tint: .lavender, size: 72, mode: .playing, level: level)
                }
                SectionLabel("Master meter")
                MasterMeter(levels: (0..<40).map { _ in Float.random(in: 0.2...1) }, tints: [.amber, .teal, .lavender])
                SectionLabel("Pads")
                let states: [PadStatus] = [.ready, .playing, .generating, .queued, .failed("x"), .ready]
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(states.enumerated()), id: \.offset) { i, s in
                        PadView(pad: PadDisplay(name: ["Creaking hull", "Heavy rain", "Howling wind", "Waves on hull", "Grumpy cat", "Thunder crack"][i],
                                                meta: i == 5 ? "One-shot · 4s" : "Loop · 12s",
                                                tint: [.amber, .teal, .lavender, .sky, .pink, .blue][i],
                                                kind: i == 5 ? .oneShot : .loop,
                                                status: s),
                                level: level, loopProgress: 0.3)
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.Colors.sceneBg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
#endif
