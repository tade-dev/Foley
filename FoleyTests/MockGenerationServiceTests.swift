import Testing
import Foundation
@testable import Foley

@Suite struct MockGenerationServiceTests {
    @Test func buildSceneSplitsFreeText() async throws {
        let svc = MockGenerationService(cache: try AudioCacheTests.temp(), latency: .zero)
        let r = try await svc.buildScene(prompt: "campfire crackling, crickets and an owl hooting")
        #expect((1...6).contains(r.sounds.count))
        #expect(r.sounds.allSatisfy { !$0.name.isEmpty && !$0.prompt.isEmpty })
    }
    @Test func blankPromptIsInvalid() async throws {
        let svc = MockGenerationService(cache: try AudioCacheTests.temp(), latency: .zero)
        await #expect(throws: GenerationError.invalidResponse) { try await svc.buildScene(prompt: "   ") }
    }
    @Test func generateSoundCachesAndFailsEveryN() async throws {
        let cache = try AudioCacheTests.temp()
        let svc = MockGenerationService(cache: cache, latency: .zero, failEvery: 2)
        let a = SoundSpec(prompt: "a", duration: 2, loop: false)
        let b = SoundSpec(prompt: "b", duration: 2, loop: false)
        let u1 = try await svc.generateSound(a)
        #expect(cache.contains(a.cacheKey))
        await #expect(throws: GenerationError.server(500)) { try await svc.generateSound(b) }
        let u2 = try await svc.generateSound(a)   // cache hit, not counted as a call
        #expect(u1 == u2)
    }
}
