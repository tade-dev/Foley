#if DEBUG
import SwiftUI

/// Launch with `-gallery` to screenshot components against the handoff PNGs.
struct DebugGallery: View {
    @State private var level = 0.6
    @State private var mode = TransportDock.Mode.grid
    @State private var text = ""
    @FocusState private var galleryFocus: Bool
    @State private var gapped: Set<UUID> = []
    private let controls = CommandLine.arguments.contains("-gallery-controls")
    private let prompt = "A creaky pirate ship in a thunderstorm, heavy rain, howling wind, waves smashing the hull and a grumpy cat below deck"

    var body: some View {
        ScrollView {
            if controls { controlsSection } else { padsSection }
        }
        .background(Theme.Colors.sceneBg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var controlsSection: some View {
        let keywords = ["creaky pirate ship", "thunderstorm", "heavy rain", "howling wind", "waves", "grumpy cat"]
        let tints: [Tint] = [.amber, .blue, .teal, .lavender, .sky, .pink]
        let ids = (0..<6).map { _ in UUID() }
        let matches = zip(KeywordMatcher.ranges(of: keywords, in: prompt), zip(tints, ids)).compactMap { r, ti in
            r.map { KeywordMatch(id: ti.1, range: $0, tint: ti.0) }
        }
        return VStack(alignment: .leading, spacing: 24) {
            TransportDock(mode: $mode, isPlaying: true, isRecording: true, onPlayStop: {}, onRecord: {})
            TransportDock(mode: $mode, isPlaying: false, isRecording: false, onPlayStop: {}, onRecord: {})
            SectionLabel("Keyword text")
            KeywordText(text: prompt, matches: matches, gapped: Set(ids.prefix(2)))
                .padding(20)
                .background(Theme.Colors.surface, in: .rect(cornerRadius: Theme.Radius.card))
            SectionLabel("Chips")
            HStack { SoundChip(name: "Thunder crack", tint: .blue); SoundChip(name: "Grumpy cat", tint: .pink, isNew: true); SoundChip(name: "Extra", tint: .sky, isDimmed: true) }
            HStack { SuggestionChip(title: "Rainy café in Tokyo", tint: .teal) {}; SuggestionChip(title: "Haunted house", tint: .lavender) {} }
            Composer(text: $text, focused: $galleryFocus, onDictate: {}, onSubmit: {})
            PrimaryButton(title: "Build scene", symbol: "sparkles") {}
            PrimaryButton(title: "Build scene", symbol: "sparkles", isEnabled: false) {}
            HStack { RecPill(elapsed: .seconds(12)); CircleIconButton(symbol: "chevron.left", label: "Back", glass: true) {}; CircleIconButton(symbol: "ellipsis", label: "More", glass: true) {} }
            WaveformView(samples: (0..<56).map { i in Float(abs(sin(Double(i) * 0.7))) }, progress: 0.35).frame(height: 48)
            WaveformView(samples: (0..<56).map { i in Float(abs(sin(Double(i) * 0.5)) * 0.8 + 0.1) }, progress: 0.6, tints: tints).frame(height: 56)
        }
        .padding(20)
    }

    private var padsSection: some View {
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
}
#endif
