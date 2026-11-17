import SwiftData
import SwiftUI

/// Screens 04 (Board), 05 (Playing) and 06 (Orbit mixer) share this view; `mode` switches the layout.
struct BoardView: View {
    var scene: SoundScene

    @Environment(Router.self) private var router
    @Environment(SceneStore.self) private var store
    @Environment(AudioEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mode: TransportDock.Mode = .grid
    @Namespace private var orbNS
    @State private var editing: Pad?
    @State private var showMixes = false
    @State private var confirmDelete = false
    @State private var toast: String?
    @State private var prepared = false

    private var pads: [Pad] { scene.orderedPads }
    private var playingPads: [Pad] { pads.filter { engine.isPlaying($0.id) } }
    private var isPlaying: Bool { !playingPads.isEmpty }
    private var activeTints: [(tint: Tint, level: Double)] {
        playingPads.map { ($0.tint, Double(engine.levels[$0.id] ?? 0)) }
    }
    private var subtitle: String {
        if isPlaying { return "\(playingPads.count) of \(pads.count) playing · tap to toggle" }
        return "\(pads.count) sound\(pads.count == 1 ? "" : "s") · tap to play, hold to edit"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                if mode == .grid { gridHeader }
                content
            }
            if mode == .grid {
                TransportDock(mode: $mode, isPlaying: isPlaying, isRecording: engine.isRecording,
                              onPlayStop: playStop, onRecord: record)
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.bottom, Theme.Space.s)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let toast {
                Text(toast)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, 16).frame(height: 40)
                    .foleyGlass(Capsule())
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(SceneBackground(mood: scene.mood, active: activeTints))
        .animation(Motion.seg, value: mode)
        .animation(Motion.quick, value: toast)
        .onDisappear {
            // A recording must never follow the user into another scene.
            if router.path.last.map({ if case .mixSaved = $0 { false } else { true } }) ?? true {
                store.discardRecording()
            }
        }
        .task {
            guard !prepared else { return }
            prepared = true
            await store.prepare(scene)
            if router.autoPlaySceneID == scene.id || CommandLine.arguments.contains("-autoplay") {
                router.autoPlaySceneID = nil
                store.playAll(scene)
            }
            #if DEBUG
            await runDemoIfNeeded()
            if CommandLine.arguments.contains("-autorecord") {
                try? engine.startRecording()
                if CommandLine.arguments.contains("-autostop") {
                    try? await Task.sleep(for: .seconds(6))
                    record()
                }
            }
            if CommandLine.arguments.contains("-orbit") { mode = .orbit }
            if CommandLine.arguments.contains("-sheet"), pads.count > 1 { editing = pads[1] }
            #endif
        }
        .sheet(item: $editing) { pad in
            PadSheetView(pad: pad)
                .presentationDetents([.large])
                .presentationBackground(Theme.Colors.sheet)
                .presentationCornerRadius(Theme.Radius.sheet)
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showMixes) {
            MixesListView(scene: scene)
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.Colors.sheet)
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        .confirmationDialog("Delete this scene?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.deleteScene(scene); router.popToRoot() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Its sounds and mixes go with it.") }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            CircleIconButton(symbol: "chevron.left", label: "Back", size: 52, glass: true) {
                store.leave(scene)
                router.pop()
            }
            Spacer()
            if mode == .orbit {
                Text("Mixer").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
            } else if engine.isRecording {
                RecPill(elapsed: engine.recordingElapsed).transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            Spacer()
            if mode == .orbit {
                CircleIconButton(symbol: "arrow.counterclockwise", label: "Reset mix", size: 52, glass: true) {
                    resetMix()
                }
            } else {
                Menu {
                    Button("Mixes (\(scene.mixes.count))", systemImage: "waveform") { showMixes = true }
                    ShareLink(item: shareSummary) { Label("Share scene", systemImage: "square.and.arrow.up") }
                    Button("Delete scene", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(width: 52, height: 52)
                        .foleyGlass(Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .accessibilityLabel("More")
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.xs)
        .animation(Motion.quick, value: engine.isRecording)
    }

    private var gridHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(scene.title).font(Theme.Fonts.screenTitle).tracking(-0.8)
                    .foregroundStyle(Theme.Colors.textPrimary).lineLimit(2).minimumScaleFactor(0.8)
                if scene.isDemo {
                    Text("Demo").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.Colors.sceneSecondary)
                        .padding(.horizontal, 9).frame(height: 24)
                        .overlay(Capsule().strokeBorder(Theme.Colors.sceneBorder))
                        .accessibilityLabel("Demo scene")
                }
            }
            Text(subtitle).font(.system(size: 16)).foregroundStyle(Theme.Colors.sceneSecondary)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: subtitle)
            if isPlaying {
                MasterMeter(levels: engine.masterLevels, tints: playingPads.map(\.tint))
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, 18)
        .animation(Motion.spring, value: isPlaying)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch mode {
        case .grid:
            ScrollView {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { _ in
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(pads) { pad in
                            PadView(pad: PadDisplay(pad, status: store.status(of: pad)),
                                    level: Double(engine.levels[pad.id] ?? 0),
                                    loopProgress: pad.kind == .loop ? engine.loopProgress(for: pad.id) : 0,
                                    onTap: { tap(pad) },
                                    onEdit: { editing = pad },
                                    onRetry: { Task { await store.retry(pad) } })
                                .matchedGeometryEffect(id: pad.id, in: orbNS, isSource: mode == .grid)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, 22)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        case .orbit:
            OrbitMixerView(scene: scene, mode: $mode, namespace: orbNS)
        }
    }

    #if DEBUG
    /// Scripted sequences for recording demo clips.
    private func runDemoIfNeeded() async {
        guard let demo = DemoDirector.name else { return }
        switch demo {
        case "play":
            await DemoDirector.pause(1.4)
            for pad in pads where store.status(of: pad) == .ready {
                tap(pad)
                await DemoDirector.pause(1.1)
            }
            await DemoDirector.pause(3)
            for pad in pads.prefix(2) where engine.isPlaying(pad.id) {
                tap(pad)
                await DemoDirector.pause(0.9)
            }
        case "orbit":
            store.playAll(scene)
            await DemoDirector.pause(1.2)
            withAnimation(Motion.seg) { mode = .orbit }
        case "sheet":
            store.playAll(scene)
            await DemoDirector.pause(1.6)
            if pads.count > 1 { editing = pads[1] }
        case "record":
            await DemoDirector.pause(1)
            store.playAll(scene)
            await DemoDirector.pause(1.4)
            record()
            await DemoDirector.pause(9)
            record()
        default:
            break
        }
    }
    #endif

    // MARK: Actions

    @State private var tapTick = 0

    private func tap(_ pad: Pad) {
        store.toggle(pad)
        tapTick += 1
    }

    private func playStop() {
        if isPlaying { store.stopAll() } else { store.playAll(scene) }
    }

    private func record() {
        if engine.isRecording {
            guard let recording = engine.stopRecording() else { showToast("Recording too short"); return }
            do {
                let mix = try store.saveMix(recording, for: scene)
                store.stopAll()
                router.push(.mixSaved(mix))
            } catch {
                showToast("Couldn't save that mix")
            }
        } else {
            do { try engine.startRecording() } catch { showToast("Couldn't start recording") }
        }
    }

    private func resetMix() {
        withAnimation(Motion.spring) {
            for pad in pads {
                pad.volume = 0.8; pad.pan = 0
                engine.setVolume(0.8, pan: 0, for: pad.id)
            }
            engine.masterVolume = 0.8
        }
    }

    private func showToast(_ message: String) {
        toast = message
        Task { try? await Task.sleep(for: .seconds(1.6)); if toast == message { toast = nil } }
    }

    private var shareSummary: String {
        "\(scene.title) — a Foley scene\n\n“\(scene.sourcePrompt)”\n\n" +
        pads.map { "• \($0.name) (\($0.meta))" }.joined(separator: "\n") +
        "\n\nSounds generated with ElevenLabs."
    }
}
