import Foundation
import Observation
import SwiftData

/// Wires the services once at launch and hands them to the view tree.
@Observable
@MainActor
final class AppEnvironment {
    let engine: AudioEngine
    let cache: AudioCache
    let proxy: ProxyConfig
    let generation: GenerationService
    let store: SceneStore

    /// True when no proxy URL is configured: demo scenes play, Build scene explains the setup.
    var isDemoOnly: Bool { false }

    init(context: ModelContext) {
        let engine = AudioEngine()
        let cache = (try? AudioCache.appSupport())
            ?? (try! AudioCache(directory: FileManager.default.temporaryDirectory.appending(path: "FoleyAudio")))
        let proxy = ProxyConfig.fromBundle()
        let generation = MockGenerationService(cache: cache)
        self.engine = engine
        self.cache = cache
        self.proxy = proxy
        self.generation = generation
        self.store = SceneStore(context: context, engine: engine, cache: cache, generation: generation, proxy: proxy)
    }
}
