import AVFoundation
import SwiftUI

/// Screen 08: the saved mix with playback and share options.
struct MixSavedView: View {
    var mix: Mix

    @Environment(Router.self) private var router
    @Environment(SceneStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var peaks: [Float] = []
    @State private var drawProgress: Double = 0
    @State private var appeared = false
    @State private var exporting = false
    @State private var exportProgress = 0.0
    @State private var exportFailed = false
    @State private var share: ShareItems?
    @State private var finishedTick = 0

    private var scene: SoundScene? { mix.scene }
    private var pads: [Pad] { scene?.orderedPads ?? [] }
    private var tints: [Tint] { pads.map(\.tint).isEmpty ? [.blue] : pads.map(\.tint) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CircleIconButton(symbol: "chevron.left", label: "Back", size: 52, glass: true) { stop(); router.pop() }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Tint.teal.base)
                    Text("Mix saved").font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.Colors.textPrimary)
                }
                Spacer()
                Color.clear.frame(width: 52, height: 52)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.xs)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    heroCard
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Share")
                        ShareRow(symbol: "video", title: "Share video", subtitle: "Pads animate to your mix · 9:16",
                                 isBusy: exporting, progress: exportProgress, prominent: true, action: exportVideo)
                        if exportFailed {
                            HStack {
                                Text("Couldn't export the video").font(.system(size: 15)).foregroundStyle(Theme.Colors.failedText)
                                Spacer()
                                Button("Retry", action: exportVideo).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                            }
                            .padding(.horizontal, 6)
                        }
                        ShareRow(symbol: "arrow.down.to.line", title: "Save audio", subtitle: ".m4a to Files") {
                            share = ShareItems(items: [store.mixURL(mix)])
                        }
                        ShareRow(symbol: "link", title: "Share scene", subtitle: "Friends can remix the board") {
                            share = ShareItems(items: [summary])
                        }
                    }
                    Text("Sounds generated with ElevenLabs")
                        .font(.system(size: 15)).foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Theme.Colors.bg.ignoresSafeArea())
        .sheet(item: $share) { ShareSheet(items: $0.items).presentationDetents([.medium, .large]) }
        .task { await load() }
        .onDisappear { stop() }
        .sensoryFeedback(.success, trigger: finishedTick)
        .animation(Motion.spring, value: exportFailed)
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ForEach(Array(pads.prefix(8).enumerated()), id: \.element.id) { i, pad in
                    Circle().fill(pad.tint.orbGradient(diameter: 44))
                        .frame(width: 44, height: 44)
                        .shadow(color: pad.tint.glow, radius: 8)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                        .opacity(appeared || reduceMotion ? 1 : 0)
                        .animation(Motion.spring.delay(Double(i) * 0.06), value: appeared)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(scene?.title ?? "Mix").font(Theme.Fonts.screenTitle).tracking(-0.8).foregroundStyle(Theme.Colors.textPrimary).lineLimit(2)
                Text("\(pads.count) layers · \(format(mix.duration)) · \(mix.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 16)).foregroundStyle(Theme.Colors.sceneSecondary)
            }
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { _ in
                WaveformView(samples: peaks.isEmpty ? Array(repeating: 0.1, count: 56) : peaks,
                             progress: progressFraction, tint: tints[0], tints: tints, drawProgress: drawProgress)
                    .frame(height: 64)
            }
            HStack {
                Button(action: togglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.Colors.bg)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 60, height: 60)
                        .background(Theme.Colors.textPrimary, in: .circle)
                }
                .buttonStyle(PressScaleStyle(scale: 0.9))
                .accessibilityLabel(isPlaying ? "Pause mix" : "Play mix")
                Spacer()
                TimelineView(.animation(minimumInterval: 0.25, paused: !isPlaying)) { _ in
                    Text("\(format(player?.currentTime ?? 0)) / \(format(mix.duration))")
                        .font(.system(size: 17)).monospacedDigit().foregroundStyle(Theme.Colors.sceneSecondary)
                }
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.cardLarge)
                .fill(LinearGradient(colors: [(scene?.mood ?? .blue).shadow.opacity(0.55), Theme.Colors.sceneBg],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge).strokeBorder(Theme.Colors.sceneBorder))
    }

    private var progressFraction: Double {
        guard let player, mix.duration > 0 else { return 0 }
        return min(1, player.currentTime / mix.duration)
    }

    private var summary: String {
        let title = scene?.title ?? "A Foley mix"
        return "\(title) — a Foley mix (\(format(mix.duration)))\n\n“\(scene?.sourcePrompt ?? "")”\n\n" +
            pads.map { "• \($0.name) (\($0.meta))" }.joined(separator: "\n") + "\n\nSounds generated with ElevenLabs."
    }

    // MARK: Actions

    private func load() async {
        let url = store.mixURL(mix)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        peaks = (try? await WaveformSampler.peaks(url: url, count: 56)) ?? []
        withAnimation(reduceMotion ? nil : .easeOut(duration: 1.1)) { drawProgress = 1 }
        appeared = true
        #if DEBUG
        if CommandLine.arguments.contains("-autoexport") { exportVideo() }
        #endif
    }

    private func togglePlay() {
        guard let player else { return }
        if isPlaying { player.pause(); isPlaying = false; return }
        if player.currentTime >= mix.duration - 0.05 { player.currentTime = 0 }
        player.play()
        isPlaying = true
        Task {
            while isPlaying, let p = self.player, p.isPlaying { try? await Task.sleep(for: .milliseconds(200)) }
            isPlaying = false
        }
    }

    private func stop() { player?.stop(); isPlaying = false }

    private func exportVideo() {
        guard !exporting, let scene else { return }
        exporting = true; exportFailed = false; exportProgress = 0
        let input = MixVideoInput(title: scene.title,
                                  pads: pads.map { MixVideoPad(id: $0.id, name: $0.name, tint: $0.tint) },
                                  envelope: store.envelope(for: mix), envelopeRate: MixRecording.envelopeRate,
                                  duration: mix.duration, audioURL: store.mixURL(mix))
        let output = FileManager.default.temporaryDirectory.appending(path: "Foley-\(scene.title.replacingOccurrences(of: " ", with: "-")).mp4")
        Task {
            do {
                let url = try await MixRenderer().render(input, to: output) { p in
                    Task { @MainActor in exportProgress = p }
                }
                exporting = false
                finishedTick += 1
                share = ShareItems(items: [url])
            } catch {
                exporting = false
                exportFailed = true
            }
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down)); return String(format: "%d:%02d", s / 60, s % 60)
    }
}
