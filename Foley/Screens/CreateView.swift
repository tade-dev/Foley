import SwiftData
import SwiftUI

/// Screens 02 (Typing) and 03 (Generating) in one view, so keywords can fly from the prompt to their pads.
struct CreateView: View {
    var initialText: String

    @Environment(Router.self) private var router
    @Environment(SceneStore.self) private var store
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Phase: Equatable { case typing, generating(SoundScene) }
    enum ClipLength: String, CaseIterable, Identifiable {
        case auto = "Auto", short = "Short · 5s", medium = "Medium · 10s", long = "Long · 15s"
        var id: String { rawValue }
        var seconds: Double? { switch self { case .auto: nil; case .short: 5; case .medium: 10; case .long: 15 } }
    }

    @State private var text: String
    @State private var phase: Phase = .typing
    @State private var parsed: SceneResponse?
    @State private var parsedFor = ""
    @State private var isParsing = false
    @State private var parseFailed = false
    @State private var ambientLoops = true
    @State private var clipLength: ClipLength = .auto
    @State private var soundIDs: [Int: UUID] = [:]
    @State private var newestChip: UUID?

    // Flight
    @State private var chipFrames: [Int: CGRect] = [:]
    @State private var slotFrames: [Int: CGRect] = [:]
    @State private var flight: [FlightItem] = []
    @State private var flying = false
    @State private var landed: Set<UUID> = []
    @State private var pendingScene: SoundScene?
    @State private var generationStarted = false
    @State private var landingTick = 0

    init(initialText: String) {
        self.initialText = initialText
        _text = State(initialValue: initialText)
    }

    private var sounds: [SceneResponse.Sound] { parsed?.sounds ?? [] }

    /// Pads whose generation has finished; their hovering chip fades out.
    private var settledPadIDs: Set<UUID> {
        guard case .generating(let scene) = phase else { return [] }
        return Set(scene.pads.filter { pad in
            switch store.status(of: pad) { case .ready, .playing, .failed: true; default: false }
        }.map(\.id))
    }
    private var matches: [KeywordMatch] {
        zip(KeywordMatcher.ranges(of: sounds.map(\.keyword), in: text), sounds.indices).compactMap { range, i in
            range.map { KeywordMatch(id: id(for: i), range: $0, tint: sounds[i].resolvedTint) }
        }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .typing:
                typingLayout.transition(.opacity)
            case .generating(let scene):
                generatingLayout(scene).transition(.opacity)
            }
        }
        .coordinateSpace(name: "create")
        .resolveFrames { frames in
            if case .typing = phase { if frames != chipFrames { chipFrames = frames } }
            else if frames != slotFrames { slotFrames = frames }
        }
        .overlay { if !flight.isEmpty { FlightOverlay(items: flight, flying: flying, hidden: settledPadIDs) } }
        .background(background.ignoresSafeArea())
        .animation(Motion.spring, value: phase)
        .task(id: text) { await parseAfterPause() }
        .onChange(of: slotFrames) { _, _ in startFlightIfReady() }
        .onChange(of: store.progress) { _, p in finishIfDone(p) }
        .sensoryFeedback(.selection, trigger: sounds.count)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: landingTick)
    }

    @ViewBuilder private var background: some View {
        if case .generating(let scene) = phase { SceneBackground(mood: scene.mood) } else { Theme.Colors.bg }
    }

    // MARK: - Typing (02)

    private var typingLayout: some View {
        VStack(spacing: 0) {
            HStack {
                CircleIconButton(symbol: "xmark", label: "Close", size: 52, glass: true) { router.pop() }
                Spacer()
                if !env.isDemoOnly { statusPill }
                Spacer()
                Color.clear.frame(width: 52, height: 52)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.xs)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Your scene")
                        PromptEditor(text: $text, matches: matches, autoFocus: initialText.isEmpty)
                            .padding(22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.surface, in: .rect(cornerRadius: Theme.Radius.card))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Colors.border))
                    }
                    if env.isDemoOnly {
                        ProxySetupCard { router.push(.library) }
                    } else {
                        detectedSection
                        settingsCard
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 8) {
                if !env.isDemoOnly, parsed != nil, sounds.isEmpty, !isParsing {
                    Text("Describe at least one sound").font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textTertiary)
                }
                PrimaryButton(title: "Build scene", symbol: "sparkles", isEnabled: !sounds.isEmpty && !env.isDemoOnly, action: build)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.s)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle().fill(Tint.teal.base).frame(width: 8, height: 8)
                .shadow(color: Tint.teal.base.opacity(0.8), radius: isParsing ? 6 : 0)
                .phaseAnimator(isParsing && !reduceMotion ? [1.0, 0.35] : [1.0]) { v, o in v.opacity(o) } animation: { _ in .easeInOut(duration: 0.6) }
            Text(parseFailed ? "Couldn't read that, keep typing" : "Listening for sounds")
                .font(.system(size: 15)).foregroundStyle(Theme.Colors.textSecondary)
        }
        .animation(Motion.quick, value: isParsing)
    }

    private var detectedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(sounds.isEmpty ? "Sounds detected" : "\(sounds.count) sound\(sounds.count == 1 ? "" : "s") detected")
                Spacer()
                Text("Max \(SceneResponse.maxSounds)").font(.system(size: 14)).foregroundStyle(Theme.Colors.textTertiary)
            }
            FlowLayout(spacing: 10) {
                ForEach(Array(sounds.enumerated()), id: \.offset) { i, sound in
                    SoundChip(name: sound.name, tint: sound.resolvedTint, isNew: newestChip == id(for: i))
                        .anchorPreference(key: FramesKey.self, value: .bounds) { [i: $0] }
                        .opacity(flight.isEmpty ? 1 : 0)
                }
            }
            .animation(Motion.spring, value: sounds.count)
            if sounds.isEmpty, parsed == nil {
                Text(isParsing ? "Reading your scene…" : "Sounds appear here as you type.")
                    .font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $ambientLoops) {
                Text("Ambient sounds loop").font(.system(size: 17)).foregroundStyle(Theme.Colors.textPrimary)
            }
            .tint(Theme.Colors.textPrimary)
            .padding(.horizontal, 20).frame(height: 60)
            Divider().overlay(Theme.Colors.border)
            Menu {
                Picker("Clip length", selection: $clipLength) {
                    ForEach(ClipLength.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                HStack {
                    Text("Clip length").font(.system(size: 17)).foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Text(clipLength == .auto ? "Auto" : clipLength.rawValue).font(.system(size: 17)).foregroundStyle(Theme.Colors.textSecondary)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.horizontal, 20).frame(height: 60)
                .contentShape(Rectangle())
            }
        }
        .background(Theme.Colors.surface, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Colors.border))
    }

    // MARK: - Generating (03)

    private func generatingLayout(_ scene: SoundScene) -> some View {
        let pads = scene.orderedPads
        let promptMatches = zip(KeywordMatcher.ranges(of: pads.map(\.keyword), in: scene.sourcePrompt), pads).compactMap { range, pad in
            range.map { KeywordMatch(id: pad.id, range: $0, tint: pad.tint) }
        }
        let allFailed = store.progress.done == store.progress.total && store.progress.total > 0
            && pads.allSatisfy { if case .failed = store.status(of: $0) { true } else { false } }
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                CircleIconButton(symbol: "chevron.left", label: "Back", size: 52, glass: true) {
                    store.stopAll(); router.pop()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(scene.title).font(.system(size: 26, weight: .semibold)).tracking(-0.5).foregroundStyle(Theme.Colors.textPrimary).lineLimit(1)
                    Text(progressCopy(scene)).font(.system(size: 16)).foregroundStyle(Theme.Colors.sceneSecondary).contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.xs)

            GeometryReader { geo in
                Capsule().fill(Theme.Colors.sceneBorder)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.Colors.textPrimary)
                            .frame(width: geo.size.width * store.progress.fraction)
                            .animation(Motion.spring, value: store.progress.fraction)
                    }
            }
            .frame(height: 4)
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, 22)

            ScrollView {
                VStack(spacing: 24) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Array(pads.enumerated()), id: \.element.id) { i, pad in
                            PadView(pad: PadDisplay(pad, status: store.status(of: pad)),
                                    level: Double(store.engine.levels[pad.id] ?? 0),
                                    loopProgress: store.engine.loopProgress(for: pad.id),
                                    onTap: { store.toggle(pad) },
                                    onRetry: { Task { await store.retry(pad) } })
                                .anchorPreference(key: FramesKey.self, value: .bounds) { [i: $0] }
                        }
                    }
                    if allFailed {
                        VStack(spacing: 12) {
                            Text("Couldn't build this scene").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                            Text("Check your connection and try again.").font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.sceneSecondary)
                            PrimaryButton(title: "Retry", symbol: "arrow.clockwise") {
                                Task { for pad in pads { await store.retry(pad) } }
                            }
                        }
                        .padding(.top, 8)
                    }
                    KeywordText(text: scene.sourcePrompt, matches: promptMatches, gapped: landed,
                                font: .system(size: 17), color: Theme.Colors.sceneSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(Theme.Colors.padSurface.opacity(0.5), in: .rect(cornerRadius: Theme.Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Colors.sceneBorder))
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private func progressCopy(_ scene: SoundScene) -> String {
        let p = store.progress
        if p.total == 0 { return "Getting ready…" }
        if p.done >= p.total { return "\(p.total) sounds ready" }
        return "Building \(min(p.done + 1, p.total)) of \(p.total) sounds…"
    }

    // MARK: - Parsing

    private func parseAfterPause() async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .typing = phase, !env.isDemoOnly else { return }
        if prompt.isEmpty { parsed = nil; parsedFor = ""; return }
        if prompt == parsedFor { return }
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }
        await parse(prompt)
    }

    private func parse(_ prompt: String) async {
        isParsing = true
        parseFailed = false
        defer { isParsing = false }
        do {
            let response = try await store.generation.buildScene(prompt: prompt).validated(for: prompt)
            guard !Task.isCancelled else { return }
            let previous = Set(parsed?.sounds.map(\.name) ?? [])
            withAnimation(Motion.spring) {
                parsed = response
                parsedFor = prompt
                for (i, s) in response.sounds.enumerated() where !previous.contains(s.name) { newestChip = id(for: i) }
            }
            #if DEBUG
            if CommandLine.arguments.contains("-autobuild"), case .typing = phase {
                try? await Task.sleep(for: .seconds(1.2))
                build()
            }
            #endif
        } catch is CancellationError {
        } catch {
            parseFailed = true
        }
    }

    private func id(for index: Int) -> UUID {
        if let id = soundIDs[index] { return id }
        let id = UUID()
        DispatchQueue.main.async { soundIDs[index] = id }
        return id
    }

    // MARK: - Build + flight

    private func build() {
        Task {
            let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if parsedFor != prompt { await parse(prompt) }
            guard var response = parsed, !response.sounds.isEmpty else { return }
            response.sounds = response.sounds.map { s in
                var s = s
                if s.kind == .loop {
                    if !ambientLoops { s.kind = .oneShot; s.duration = min(s.duration ?? 5, 6) }
                    else if let fixed = clipLength.seconds { s.duration = fixed }
                }
                return s
            }
            let scene = store.createScene(from: response, sourcePrompt: prompt)
            let pads = scene.orderedPads
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

            if reduceMotion || chipFrames.isEmpty {
                pendingScene = nil
                phase = .generating(scene)
                startGeneration(scene)
                return
            }
            flight = pads.enumerated().compactMap { i, pad in
                chipFrames[i].map { FlightItem(id: pad.id, name: pad.name, tint: pad.tint, from: $0, to: $0) }
            }
            pendingScene = scene
            slotFrames = [:]
            phase = .generating(scene)
            // The flight is decorative: generation starts either way, so a grid that never
            // materialises its anchors (a short screen, a lazy row offscreen) cannot strand the user.
            startGeneration(scene)
        }
    }

    /// Once the generating grid has laid out, aim each chip at its slot and let go.
    private func startFlightIfReady() {
        guard let scene = pendingScene, !flying, !slotFrames.isEmpty else { return }
        let pads = scene.orderedPads
        guard slotFrames.count >= pads.count else { return }
        flight = flight.enumerated().map { i, item in
            var item = item
            if let slot = slotFrames[i] {
                item.to = CGRect(x: slot.minX + 14, y: slot.minY + 14, width: item.from.width, height: item.from.height)
            }
            return item
        }
        pendingScene = nil
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            flying = true
            for (i, item) in flight.enumerated() {
                try? await Task.sleep(for: .seconds(i == 0 ? 0.45 : Motion.stagger))
                landed.insert(item.id)
                landingTick += 1
            }
        }
    }

    private func startGeneration(_ scene: SoundScene) {
        guard !generationStarted else { return }
        generationStarted = true
        if reduceMotion || flight.isEmpty { landed = Set(scene.pads.map(\.id)) }
        Task {
            await store.generateAll(for: scene)
            finishIfDone(store.progress)
        }
    }

    private func finishIfDone(_ p: GenerationProgress) {
        guard case .generating(let scene) = phase, generationStarted, p.total > 0, p.done >= p.total else { return }
        let pads = scene.orderedPads
        let allFailed = pads.allSatisfy { if case .failed = store.status(of: $0) { true } else { false } }
        guard !allFailed else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard case .generating = phase else { return }
            router.replaceTop(with: .board(scene))
        }
    }
}
