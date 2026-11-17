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
    let isDemoOnly: Bool

    init(context: ModelContext) {
        let engine = AudioEngine()
        let cache = (try? AudioCache.appSupport())
            ?? (try! AudioCache(directory: FileManager.default.temporaryDirectory.appending(path: "FoleyAudio")))
        let proxy = ProxyConfig.fromBundle()
        var failEvery = 0
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "-failEvery"), i + 1 < CommandLine.arguments.count {
            failEvery = Int(CommandLine.arguments[i + 1]) ?? 0
        }
        #endif
        var useMockOverride = false
        #if DEBUG
        useMockOverride = CommandLine.arguments.contains("-FoleyUseMock")
        #endif
        let useMock = useMockOverride || !proxy.isConfigured
        let generation: GenerationService = if let baseURL = proxy.baseURL, !useMock {
            LiveGenerationService(baseURL: baseURL, cache: cache)
        } else {
            MockGenerationService(cache: cache, failEvery: failEvery)
        }
        // Demo-only mode is about the proxy, not the stand-in: with -FoleyUseMock the create flow still works.
        self.isDemoOnly = !proxy.isConfigured && !useMockOverride
        self.engine = engine
        self.cache = cache
        self.proxy = proxy
        self.generation = generation
        self.store = SceneStore(context: context, engine: engine, cache: cache, generation: generation, proxy: proxy)
    }
}
