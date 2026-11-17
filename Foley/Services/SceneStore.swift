import Foundation
import Observation
import SwiftData

nonisolated enum MixError: Error, Equatable {
    case tooShort
}

nonisolated struct GenerationProgress: Equatable, Sendable {
    var done: Int = 0
    var total: Int = 0
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

/// Transient pad state and generation orchestration. The only thing views talk to besides `AudioEngine`.
@Observable
@MainActor
final class SceneStore {
    private(set) var statuses: [UUID: PadStatus] = [:]
    private(set) var progress = GenerationProgress()

    let engine: AudioEngine
    let cache: AudioCache
    let generation: GenerationService
    let proxy: ProxyConfig

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let busyDelays: [Duration]
    @ObservationIgnored private var activeRuns: Set<UUID> = []
    /// Pads the current run has already tried. A Retry arriving mid-run removes its pad from here,
    /// which is how the run picks the request up instead of dropping it — and why a pad that simply
    /// failed is not tried again forever.
    @ObservationIgnored private var attemptedThisRun: Set<UUID> = []

    init(context: ModelContext, engine: AudioEngine, cache: AudioCache, generation: GenerationService,
         proxy: ProxyConfig, busyDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]) {
        self.context = context
        self.engine = engine
        self.cache = cache
        self.generation = generation
        self.proxy = proxy
        self.busyDelays = busyDelays
    }

    // MARK: Status

    func status(of pad: Pad) -> PadStatus {
        let s = statuses[pad.id] ?? .queued
        if s == .ready, engine.isPlaying(pad.id) { return .playing }
        return s
    }

    func audioURL(for pad: Pad) -> URL? {
        if let key = pad.cacheKey, cache.contains(key) { return cache.url(for: key) }
        if let file = pad.demoFile { return DemoSeeder.audioURL(file: file) }
        return nil
    }

    // MARK: Scenes

    func createScene(from response: SceneResponse, sourcePrompt: String) -> SoundScene {
        let scene = SoundScene(title: response.title, sourcePrompt: sourcePrompt, mood: response.mood)
        context.insert(scene)
        for (i, s) in response.sounds.enumerated() {
            let pad = Pad(name: s.name, keyword: s.keyword, tint: s.resolvedTint, kind: s.kind,
                          spec: SoundSpec(prompt: s.prompt, duration: s.duration, loop: s.kind == .loop),
                          sortIndex: i)
            pad.scene = scene
            context.insert(pad)
            statuses[pad.id] = .queued
        }
        try? context.save()
        progress = GenerationProgress(done: 0, total: response.sounds.count)
        return scene
    }

    /// Load everything that already has audio; generate the rest.
    func prepare(_ scene: SoundScene) async {
        var needsGeneration = false
        for pad in scene.orderedPads {
            if let url = audioURL(for: pad), (try? load(pad, from: url)) != nil {
                statuses[pad.id] = .ready
            } else if statuses[pad.id] != .generating {
                statuses[pad.id] = .queued
                needsGeneration = true
            }
        }
        if needsGeneration { await generateAll(for: scene) }
    }

    /// Everything that must happen when a scene's board goes away.
    func leave(_ scene: SoundScene) {
        discardRecording()
        engine.stopAll()
        engine.unloadAll()
        for pad in scene.pads { statuses[pad.id] = nil }
    }

    /// Drops an in-flight recording without saving it.
    func discardRecording() {
        guard engine.isRecording, let recording = engine.stopRecording() else { return }
        try? FileManager.default.removeItem(at: recording.url)
    }

    func deleteScene(_ scene: SoundScene) {
        discardRecording()
        engine.stopAll()
        for pad in scene.pads {
            engine.unload(padID: pad.id)
            statuses[pad.id] = nil
        }
        context.delete(scene)
        try? context.save()
    }

    // MARK: Generation

    /// Generates every queued or failed pad, at most three at a time, one call per distinct spec.
    /// Safe to cancel: pads that never finish are marked failed, never left generating.
    /// Re-reads the queue after each pass, so a Retry that lands mid-run is picked up rather than lost.
    func generateAll(for scene: SoundScene) async {
        guard !activeRuns.contains(scene.id) else { return }
        activeRuns.insert(scene.id)
        attemptedThisRun = []
        defer { activeRuns.remove(scene.id); attemptedThisRun = [] }

        while true {
            let pads = scene.orderedPads
            let pending = pads.filter { pad in
                guard !attemptedThisRun.contains(pad.id) else { return false }
                switch statuses[pad.id] ?? .queued {
                case .queued, .failed: return true
                default: return false
                }
            }
            guard !pending.isEmpty else { break }
            await runPass(pending, in: pads)
            if Task.isCancelled { break }
        }

        for pad in scene.orderedPads where statuses[pad.id] == .generating || statuses[pad.id] == .queued {
            statuses[pad.id] = .failed(GenerationError.server(0).userMessage)
        }
        refreshProgress(scene.orderedPads)
        try? context.save()
    }

    /// One wave: every distinct spec among `pending`, three in flight at a time.
    private func runPass(_ pending: [Pad], in pads: [Pad]) async {
        var byKey: [String: [Pad]] = [:]
        var keys: [String] = []
        for pad in pending {
            if byKey[pad.spec.cacheKey] == nil { keys.append(pad.spec.cacheKey) }
            byKey[pad.spec.cacheKey, default: []].append(pad)
        }
        refreshProgress(pads)

        let service = generation
        let delays = busyDelays
        await withTaskGroup(of: (String, Result<URL, Error>).self) { group in
            var iterator = keys.makeIterator()
            @MainActor func start(_ key: String) {
                guard let spec = byKey[key]?.first?.spec else { return }
                for pad in byKey[key] ?? [] { statuses[pad.id] = .generating }
                group.addTask {
                    do { return (key, .success(try await Self.generate(spec, with: service, busyDelays: delays))) }
                    catch { return (key, .failure(error)) }
                }
            }
            for _ in 0..<3 { if let k = iterator.next() { start(k) } }
            for await (key, result) in group {
                for pad in byKey[key] ?? [] {
                    attemptedThisRun.insert(pad.id)
                    settle(pad, result)
                }
                refreshProgress(pads)
                if let k = iterator.next() { start(k) }
            }
        }
    }

    func retry(_ pad: Pad) async {
        guard let scene = pad.scene else { return }
        statuses[pad.id] = .queued
        attemptedThisRun.remove(pad.id)   // an active run will pick this up on its next pass
        await generateAll(for: scene)
    }

    func regenerate(_ pad: Pad, with spec: SoundSpec) async {
        guard let scene = pad.scene else { return }
        engine.unload(padID: pad.id)
        pad.spec = spec
        pad.kindRaw = (spec.loop ? PadKind.loop : .oneShot).rawValue
        pad.cacheKey = nil
        pad.version += 1
        statuses[pad.id] = .queued
        attemptedThisRun.remove(pad.id)
        await generateAll(for: scene)
    }

    private nonisolated static func generate(_ spec: SoundSpec, with service: GenerationService,
                                             busyDelays: [Duration]) async throws -> URL {
        var attempt = 0
        while true {
            do {
                return try await service.generateSound(spec)
            } catch GenerationError.busy where attempt < busyDelays.count {
                try await Task.sleep(for: busyDelays[attempt])
                attempt += 1
            }
        }
    }

    private func settle(_ pad: Pad, _ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            pad.cacheKey = pad.spec.cacheKey
            do {
                try load(pad, from: url)
                pad.demoFile = nil          // the generated file has replaced the bundled one
                statuses[pad.id] = .ready
            } catch {
                statuses[pad.id] = .failed(GenerationError.invalidResponse.userMessage)
            }
        case .failure(let error):
            if error is CancellationError {
                statuses[pad.id] = .failed(GenerationError.server(0).userMessage)
            } else if let g = error as? GenerationError, g != .busy {
                statuses[pad.id] = .failed(g.userMessage)
            } else {
                statuses[pad.id] = .failed(GenerationError.server(0).userMessage)
            }
        }
    }

    /// Loads a pad's audio and restores the mix position the user left it at.
    private func load(_ pad: Pad, from url: URL) throws {
        try engine.load(padID: pad.id, kind: pad.kind, url: url)
        engine.setVolume(pad.volume, pan: pad.pan, for: pad.id)
    }

    private func refreshProgress(_ pads: [Pad]) {
        let done = pads.filter {
            switch statuses[$0.id] ?? .queued {
            case .ready, .playing, .failed: true
            default: false
            }
        }.count
        progress = GenerationProgress(done: done, total: pads.count)
    }

    // MARK: Playback

    func toggle(_ pad: Pad) { engine.toggle(pad.id) }

    func playAll(_ scene: SoundScene) {
        engine.playAll(scene.orderedPads.filter { statuses[$0.id] == .ready }.map(\.id))
    }

    func stopAll() { engine.stopAll() }

    func playingCount(in scene: SoundScene) -> Int {
        scene.pads.filter { engine.isPlaying($0.id) }.count
    }

    func delete(_ pad: Pad) {
        engine.unload(padID: pad.id)
        statuses[pad.id] = nil
        context.delete(pad)
        try? context.save()
    }

    // MARK: Mixes

    private var mixesDirectory: URL {
        get throws {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
            let dir = base.appending(path: "Foley/Mixes")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
    }

    @discardableResult
    func saveMix(_ recording: MixRecording, for scene: SoundScene) throws -> Mix {
        guard recording.duration >= 0.5 else { throw MixError.tooShort }
        let dir = try mixesDirectory
        let id = UUID()
        let audioName = "\(id.uuidString).m4a"
        let envelopeName = "\(id.uuidString).json"
        try FileManager.default.copyItem(at: recording.url, to: dir.appending(path: audioName))
        let encoded = try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: recording.envelope.map { ($0.key.uuidString, $0.value) }))
        try encoded.write(to: dir.appending(path: envelopeName), options: .atomic)
        let mix = Mix(fileName: audioName, envelopeFileName: envelopeName, duration: recording.duration)
        mix.scene = scene
        context.insert(mix)
        try context.save()
        try? FileManager.default.removeItem(at: recording.url)
        return mix
    }

    func mixURL(_ mix: Mix) -> URL {
        (try? mixesDirectory.appending(path: mix.fileName)) ?? URL(fileURLWithPath: "/dev/null")
    }

    func envelope(for mix: Mix) -> [UUID: [Float]] {
        guard let dir = try? mixesDirectory,
              let data = try? Data(contentsOf: dir.appending(path: mix.envelopeFileName)),
              let raw = try? JSONDecoder().decode([String: [Float]].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
    }

    func deleteMix(_ mix: Mix) {
        if let dir = try? mixesDirectory {
            try? FileManager.default.removeItem(at: dir.appending(path: mix.fileName))
            try? FileManager.default.removeItem(at: dir.appending(path: mix.envelopeFileName))
        }
        context.delete(mix)
        try? context.save()
    }
}
