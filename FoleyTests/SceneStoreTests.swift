import Testing
import Foundation
import SwiftData
@testable import Foley

@Suite(.serialized) @MainActor struct SceneStoreTests {
    final class CountingService: GenerationService, @unchecked Sendable {
        var active = 0, maxActive = 0, calls = 0
        var failing: Set<String> = []
        var busyOnce: Set<String> = []
        let cache: AudioCache
        init(cache: AudioCache) { self.cache = cache }
        func buildScene(prompt: String) async throws -> SceneResponse { fatalError("unused") }
        func generateSound(_ spec: SoundSpec) async throws -> URL {
            if cache.contains(spec.cacheKey) { return cache.url(for: spec.cacheKey) }
            calls += 1; active += 1; maxActive = max(maxActive, active)
            defer { active -= 1 }
            try await Task.sleep(for: .milliseconds(50))
            if busyOnce.remove(spec.cacheKey) != nil { throw GenerationError.busy }
            if failing.contains(spec.cacheKey) { throw GenerationError.server(500) }
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
        #expect(svc.maxActive == 3)
        #expect(scene.pads.allSatisfy { store.status(of: $0) == .ready })
        #expect(store.progress.done == 6 && store.progress.total == 6)
    }
    @Test func duplicateSpecsGenerateOnce() async throws {
        let (store, svc, scene, container) = try make(); defer { withExtendedLifetime(container) {} }
        await store.generateAll(for: scene)
        #expect(svc.calls == 5)
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
