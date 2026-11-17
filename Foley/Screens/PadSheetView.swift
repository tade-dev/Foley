import SwiftUI

/// Screen 07: edit one pad's prompt, kind, length and prompt influence; regenerate or delete it.
struct PadSheetView: View {
    var pad: Pad

    @Environment(SceneStore.self) private var store
    @Environment(AppEnvironment.self) private var env
    @Environment(AudioEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SoundSpec
    @State private var peaks: [Float] = []
    @State private var regenerating = false
    @State private var failed = false
    @State private var confirmDelete = false

    init(pad: Pad) {
        self.pad = pad
        _draft = State(initialValue: pad.spec)
    }

    private var isPlaying: Bool { engine.isPlaying(pad.id) }
    private var isFailedPad: Bool { if case .failed = store.status(of: pad) { true } else { false } }
    private var canRegenerate: Bool {
        !env.isDemoOnly && !regenerating && (draft != pad.spec || isFailedPad)
            && !draft.prompt.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var meta: String {
        let kind = draft.loop ? "Loop" : "One-shot"
        let length = draft.duration.map { String(format: "%.1fs", $0) } ?? "auto"
        return "\(kind) · \(length) · version \(pad.version)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.Colors.sceneBorder).frame(width: 44, height: 5).padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    playerRow
                    promptField
                    kindSegment
                    slider(title: "Length", value: Binding(get: { draft.duration ?? 5 }, set: { draft.duration = $0 }),
                           range: 0.5...22, step: 0.5, label: String(format: "%.1fs", draft.duration ?? 5))
                    VStack(alignment: .leading, spacing: 8) {
                        slider(title: "Follow my prompt", value: $draft.promptInfluence, range: 0...1, step: 0.05,
                               label: String(format: "%.1f", draft.promptInfluence))
                        HStack {
                            Text("More creative"); Spacer(); Text("More literal")
                        }
                        .font(.system(size: 15)).foregroundStyle(Theme.Colors.sceneSecondary)
                    }
                    if env.isDemoOnly {
                        Text("Connect your proxy in Config/Local.xcconfig to regenerate this sound. The demo sounds play without it.")
                            .font(.system(size: 15)).foregroundStyle(Theme.Colors.sceneSecondary).lineSpacing(3)
                    }
                    if failed {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.Colors.error)
                            Text("Couldn't make this one").foregroundStyle(Theme.Colors.failedText)
                            Spacer()
                            Button("Retry") { regenerate() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                        }
                        .font(.system(size: 15))
                        .padding(16)
                        .background(Theme.Colors.failedFill, in: .rect(cornerRadius: Theme.Radius.row))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row).strokeBorder(Theme.Colors.failedBorder))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            actions
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.m)
        }
        .background(Theme.Colors.sheet.ignoresSafeArea())
        .disabled(false)
        .animation(Motion.spring, value: regenerating)
        .animation(Motion.spring, value: failed)
        .task(id: store.audioURL(for: pad)) { await loadPeaks() }
        #if DEBUG
        .task {
            guard DemoDirector.isRunning("sheet") else { return }
            await DemoDirector.pause(2.2)
            store.toggle(pad)                      // play the current sound
            await DemoDirector.pause(2.6)
            if engine.isPlaying(pad.id) { store.toggle(pad) }
            withAnimation(Motion.spring) { draft.duration = 8 }
            await DemoDirector.pause(1.3)
            withAnimation(Motion.spring) { draft.promptInfluence = 0.75 }
            await DemoDirector.pause(1.6)
            regenerate()
        }
        #endif
        .confirmationDialog("Delete \(pad.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.delete(pad); dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            SoundOrb(tint: pad.tint, size: 88, mode: regenerating ? .generating : (isPlaying ? .playing : .ready),
                     level: Double(engine.levels[pad.id] ?? 0))
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(pad.name).font(Theme.Fonts.sheetTitle).tracking(-0.5).foregroundStyle(Theme.Colors.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                Text(meta).font(.system(size: 15)).foregroundStyle(Theme.Colors.sceneSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8).contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            CircleIconButton(symbol: "xmark", label: "Close", size: 52, glass: true) { dismiss() }
        }
    }

    private var playerRow: some View {
        HStack(spacing: 14) {
            Button { store.toggle(pad) } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.bg)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 56, height: 56)
                    .background(pad.tint.base, in: .circle)
            }
            .buttonStyle(PressScaleStyle(scale: 0.9))
            .disabled(regenerating || store.audioURL(for: pad) == nil)
            .accessibilityLabel(isPlaying ? "Stop" : "Play")
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { _ in
                WaveformView(samples: peaks.isEmpty ? Array(repeating: 0.08, count: 56) : peaks,
                             progress: isPlaying ? engine.loopProgress(for: pad.id) : 0,
                             tint: pad.tint)
                    .frame(height: 56)
                    .opacity(regenerating ? 0.35 : 1)
            }
        }
    }

    private var promptField: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Sound prompt")
            TextField("Describe the sound", text: $draft.prompt, axis: .vertical)
                .lineLimit(2...5)
                .font(.system(size: 17))
                .foregroundStyle(Theme.Colors.textPrimary)
                .tint(Theme.Colors.textPrimary)
                .padding(18)
                .background(Theme.Colors.padSurface.opacity(0.7), in: .rect(cornerRadius: Theme.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Colors.sceneBorder))
                .disabled(regenerating)
        }
    }

    private var kindSegment: some View {
        HStack(spacing: 0) {
            kindButton("Loop", loop: true)
            kindButton("One-shot", loop: false)
        }
        .padding(5)
        .foleyGlass(Capsule(), tint: Theme.Colors.padSurface.opacity(0.8))
        .overlay(Capsule().strokeBorder(Theme.Colors.sceneBorder))
        .disabled(regenerating)
    }

    private func kindButton(_ title: String, loop: Bool) -> some View {
        Button { withAnimation(Motion.seg) { draft.loop = loop } } label: {
            Text(title).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(draft.loop == loop ? Theme.Colors.bg : Theme.Colors.sceneSecondary)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background { if draft.loop == loop { Capsule().fill(Theme.Colors.textPrimary) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(draft.loop == loop ? .isSelected : [])
    }

    private func slider(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 17)).foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(label).font(.system(size: 17)).monospacedDigit().foregroundStyle(Theme.Colors.sceneSecondary)
            }
            Slider(value: value, in: range, step: step)
                .tint(pad.tint.base)
                .accessibilityLabel(title)
        }
        .disabled(regenerating)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button { confirmDelete = true } label: {
                Text("Delete").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.error)
                    .padding(.horizontal, 22).frame(height: 56)
                    .overlay(Capsule().strokeBorder(Theme.Colors.error.opacity(0.5)))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(regenerating)
            PrimaryButton(title: regenerating ? "Regenerating…" : "Regenerate", symbol: "arrow.clockwise",
                          isEnabled: canRegenerate, action: regenerate)
        }
    }

    // MARK: Actions

    private func regenerate() {
        guard !regenerating else { return }
        failed = false
        regenerating = true
        var spec = draft
        spec.prompt = spec.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await store.regenerate(pad, with: spec)
            regenerating = false
            if case .failed = store.status(of: pad) { failed = true }
        }
    }

    private func loadPeaks() async {
        guard let url = store.audioURL(for: pad) else { peaks = []; return }
        peaks = (try? await WaveformSampler.peaks(url: url, count: 56)) ?? []
    }
}
