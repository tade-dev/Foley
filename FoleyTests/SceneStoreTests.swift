import Testing
import Foundation
import SwiftData
@testable import Foley

@Suite(.serialized) @MainActor struct SceneStoreTests {
    /// Counts upstream calls and the real concurrency. Every counter is behind a lock: the task
    /// group calls this from several threads at once, and racy counters under-report.
    final class CountingService: GenerationService, @unchecked Sendable {
        private let lock = NSLock()
        private var _active = 0, _maxActive = 0, _calls = 0
        private var _failing: Set<String> = [], _busyOnce: Set<String> = []

        var maxActive: Int { lock.withLock { _maxActive } }
        var calls: Int { lock.withLock { _calls } }
        var failing: Set<String> {
            get { lock.withLock { _failing } }
            set { lock.withLock { _failing = newValue } }
        }
        var busyOnce: Set<String> {
            get { lock.withLock { _busyOnce } }
            set { lock.withLock { _busyOnce = newValue } }
        }

        let cache: AudioCache
        init(cache: AudioCache) { self.cache = cache }

        func buildScene(prompt: String) async throws -> SceneResponse { fatalError("unused") }

        func generateSound(_ spec: SoundSpec) async throws -> URL {
            if cache.contains(spec.cacheKey) { return cache.url(for: spec.cacheKey) }
            let active = lock.withLock { () -> Int in
                _calls += 1; _active += 1; _maxActive = max(_maxActive, _active)
                return _active
            }
            defer { lock.withLock { _active -= 1 } }
            _ = active
            // Hold until the store has filled its concurrency window, so the assertion on
            // maxActive measures the cap rather than the machine's scheduling luck.
            let deadline = Date.now.addingTimeInterval(0.3)
            while lock.withLock({ _active }) < 3, Date.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            try await Task.sleep(for: .milliseconds(20))
            if lock.withLock({ _busyOnce.remove(spec.cacheKey) }) != nil { throw GenerationError.busy }
            if lock.withLock({ _failing.contains(spec.cacheKey) }) { throw GenerationError.server(500) }
            let demo = Bundle.main.url(forResource: "thunder-crack", withExtension: "m4a")!
            return try cache.store(try Data(contentsOf: demo), key: spec.cacheKey)
        }
    }

    /// Pirate scene with pads 4 and 5 sharing one spec, so 6 pads need 5 generations.
    func make() throws -> (SceneStore, CountingService, SoundScene, ModelContainer) {
        let container = try ModelContainer(for: SoundScene.self, Pad.self, Mix.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let cache = try AudioCacheTests.temp()
        let svc = CountingService(cache: cache)
        let store = SceneStore(context: container.mainContext, engine: AudioEngine(), cache: cache,
                               generation: svc, proxy: ProxyConfig(string: ""), busyDelays: [.zero])
        let pirate = try DemoSeeder.load().scenes[0]
        var sounds = pirate.sounds.map { SceneResponse.Sound(name: $0.name, keyword: $0.keyword, tint: $0.tint, kind: $0.kind, prompt: $0.prompt, duration: $0.duration) }
        sounds[5].prompt = sounds[4].prompt; sounds[5].duration = sounds[4].duration; sounds[5].kind = sounds[4].kind
        let scene = store.createScene(from: SceneResponse(title: pirate.title, mood: pirate.mood, sounds: sounds), sourcePrompt: pirate.sourcePrompt)
        return (store, svc, scene, container)
    }

    @Test func generatesWithConcurrencyThreeAndMarksReady() async throws {
        let (store, svc, scene, container) = try make(); defer { withExtendedLifetime(container) {} }
        await store.generateAll(for: scene)
        #expect(svc.maxActive == 3, "concurrency was \(svc.maxActive), expected the store's cap of 3")
        #expect(scene.pads.allSatisfy { store.status(of: $0) == .ready })
        #expect(store.progress.done == 6 && store.progress.total == 6)
    }
    @Test func duplicateSpecsGenerateOnce() async throws {
        let (store, svc, scene, container) = try make(); defer { withExtendedLifetime(container) {} }
        await store.generateAll(for: scene)
        #expect(svc.calls == 5, "upstream calls were \(svc.calls); statuses \(scene.orderedPads.map { store.status(of: $0) })")
    }
    @Test func failedPadRetriesInPlace() async throws {
        let (store, svc, scene, container) = try make(); defer { withExtendedLifetime(container) {} }; let pad = scene.orderedPads[2]
        svc.failing = [pad.spec.cacheKey]
        await store.generateAll(for: scene)
        #expect(store.status(of: pad) == .failed("Couldn't make this one"))
        svc.failing = []; await store.retry(pad)
        #expect(store.status(of: pad) == .ready)
    }
    @Test func busyIsRetriedAutomatically() async throws {
        let (store, svc, scene, container) = try make(); defer { withExtendedLifetime(container) {} }; let pad = scene.orderedPads[0]
        svc.busyOnce = [pad.spec.cacheKey]
        await store.generateAll(for: scene)
        #expect(store.status(of: pad) == .ready)
    }
    @Test func cancellationMarksFailedNotStuck() async throws {
        let (store, _, scene, container) = try make(); defer { withExtendedLifetime(container) {} }
        let t = Task { await store.generateAll(for: scene) }
        try await Task.sleep(for: .milliseconds(20)); t.cancel(); await t.value
        #expect(scene.pads.allSatisfy { store.status(of: $0) != .generating && store.status(of: $0) != .queued })
    }
    @Test func demoSceneOneShotsFinishAfterPlayAll() async throws {
        let container = try ModelContainer(for: SoundScene.self, Pad.self, Mix.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(container) {} }
        _ = try DemoSeeder.seedIfNeeded(context: container.mainContext)
        let cache = try AudioCacheTests.temp()
        let engine = AudioEngine()
        let store = SceneStore(context: container.mainContext, engine: engine, cache: cache,
                               generation: MockGenerationService(cache: cache, latency: .zero), proxy: ProxyConfig(string: ""))
        let scene = try #require(try container.mainContext.fetch(FetchDescriptor<SoundScene>()).first { $0.title == "Pirate ship in a storm" })
        await store.prepare(scene)
        store.playAll(scene)
        #expect(store.playingCount(in: scene) == 6)
        try await Task.sleep(for: .seconds(4.6))
        let oneShots = scene.pads.filter { $0.kind == .oneShot }
        #expect(oneShots.count == 2)
        #expect(oneShots.allSatisfy { store.status(of: $0) == .ready }, "one-shots still playing: \(oneShots.map { store.status(of: $0) })")
        store.stopAll()
    }
    @Test func retryDuringActiveRunStillCompletes() async throws {
        let (store, svc, scene, container) = try make(); defer { withExtendedLifetime(container) {} }
        let pad = scene.orderedPads[0]
        svc.failing = [pad.spec.cacheKey]
        let run = Task { await store.generateAll(for: scene) }
        try await Task.sleep(for: .milliseconds(30))
        svc.failing = []
        await store.retry(pad)           // arrives while the first run is still in flight
        await run.value
        #expect(store.status(of: pad) == .ready, "retry during an active run was dropped")
        #expect(store.progress.done == store.progress.total)
    }

    @Test func storedVolumeAndPanAreAppliedOnPrepare() async throws {
        let (store, _, scene, container) = try make(); defer { withExtendedLifetime(container) {} }
        await store.generateAll(for: scene)
        let pad = scene.orderedPads[0]
        pad.volume = 0.3
        pad.pan = -0.7
        store.engine.unload(padID: pad.id)
        await store.prepare(scene)
        #expect(abs(store.engine.volume(for: pad.id) - 0.3) < 0.01)
        #expect(abs(store.engine.pan(for: pad.id) + 0.7) < 0.01)
    }

    @Test func saveMixRejectsShortRecordings() throws {
        let (store, _, scene, container) = try make(); defer { withExtendedLifetime(container) {} }
        let rec = MixRecording(url: URL(fileURLWithPath: "/dev/null"), duration: 0.2, envelope: [:], padOrder: [])
        #expect(throws: MixError.tooShort) { try store.saveMix(rec, for: scene) }
    }
    @Test func deletingOneOfTwoPadsWithSameSpecKeepsAudio() async throws {
        let (store, _, scene, container) = try make(); defer { withExtendedLifetime(container) {} }
        await store.generateAll(for: scene)
        let a = scene.orderedPads[4], b = scene.orderedPads[5]
        store.delete(b)
        #expect(store.audioURL(for: a) != nil)
        #expect(scene.pads.count == 5)
    }
}
