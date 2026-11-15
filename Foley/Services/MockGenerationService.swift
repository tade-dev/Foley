import Foundation

/// Fakes the proxy with bundled audio: simulated latency, optional failures, a naive parser.
/// Lets every screen and state be built with no network and no keys.
nonisolated final class MockGenerationService: GenerationService {
    private let cache: AudioCache
    private let bundle: Bundle
    private let latency: Duration
    private let failEvery: Int
    private let calls = Counter()

    init(cache: AudioCache, bundle: Bundle = .main, latency: Duration = .seconds(1.4), failEvery: Int = 0) {
        self.cache = cache
        self.bundle = bundle
        self.latency = latency
        self.failEvery = failEvery
    }

    private static let loopWords = ["rain", "wind", "hum", "chatter", "crowd", "waves", "fire", "engine",
                                    "traffic", "drone", "crickets", "storm", "river", "sea", "breeze"]

    func buildScene(prompt: String) async throws -> SceneResponse {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GenerationError.invalidResponse }
        try await sleep(fraction: 0.6)

        if trimmed.localizedCaseInsensitiveContains("pirate"), let pirate = try? DemoSeeder.load(from: bundle).scenes.first {
            return SceneResponse(title: pirate.title, mood: pirate.mood, sounds: pirate.sounds.map {
                .init(name: $0.name, keyword: $0.keyword, tint: $0.tint, kind: $0.kind, prompt: $0.prompt, duration: $0.duration)
            }).validated(for: trimmed)
        }

        let phrases = trimmed
            .replacingOccurrences(of: " and ", with: ",")
            .split(whereSeparator: { ",;.:".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
            .prefix(SceneResponse.maxSounds)

        let sounds = phrases.enumerated().map { i, phrase -> SceneResponse.Sound in
            let isLoop = Self.loopWords.contains { phrase.localizedCaseInsensitiveContains($0) }
            let words = phrase.split(separator: " ").filter { !["a", "an", "the", "with", "of", "in"].contains($0.lowercased()) }
            let name = words.prefix(3).joined(separator: " ")
            return .init(name: name.prefix(1).uppercased() + name.dropFirst(),
                         keyword: phrase,
                         tint: Tint.allCases[i % Tint.allCases.count],
                         kind: isLoop ? .loop : .oneShot,
                         prompt: phrase.prefix(1).uppercased() + phrase.dropFirst(),
                         duration: isLoop ? 12 : 3)
        }
        let titleWords = trimmed.split(separator: " ").prefix(5).joined(separator: " ")
        return SceneResponse(title: titleWords.prefix(1).uppercased() + titleWords.dropFirst(),
                             mood: sounds.first?.tint ?? .blue,
                             sounds: sounds).validated(for: trimmed)
    }

    func generateSound(_ spec: SoundSpec) async throws -> URL {
        if cache.contains(spec.cacheKey) { return cache.url(for: spec.cacheKey) }
        try await sleep(fraction: 1)
        let n = calls.next()
        if failEvery > 0, n % failEvery == 0 { throw GenerationError.server(500) }

        let sounds = (try? DemoSeeder.load(from: bundle).scenes.flatMap(\.sounds)) ?? []
        // Match the spec's kind so a 3-second one-shot never comes back as a 15-second bed.
        let files = sounds.filter { ($0.kind == .loop) == spec.loop }.map(\.file)
        guard !files.isEmpty else { throw GenerationError.invalidResponse }
        let pick = files[abs(spec.cacheKey.hashValue) % files.count]
        guard let source = DemoSeeder.audioURL(file: pick, bundle: bundle) else { throw GenerationError.invalidResponse }
        return try cache.store(try Data(contentsOf: source), key: spec.cacheKey)
    }

    private func sleep(fraction: Double) async throws {
        guard latency > .zero else { return }
        let base = Double(latency.components.seconds) + Double(latency.components.attoseconds) / 1e18
        let jitter = Double.random(in: 0.7...1.3)
        try await Task.sleep(for: .seconds(base * fraction * jitter))
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        func next() -> Int { lock.withLock { n += 1; return n } }
    }
}
