import Testing
import Foundation
@testable import Foley

@Suite struct LiveGenerationServiceTests {
    final class FakeTransport: HTTPTransport, @unchecked Sendable {
        var responses: [String: (Int, [String: String], Data)] = [:]
        var requests: [URLRequest] = []
        var thrown: Error?
        func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(r)
            if let thrown { throw thrown }
            guard let (code, headers, body) = responses[r.url!.path] else { throw URLError(.badURL) }
            return (body, HTTPURLResponse(url: r.url!, statusCode: code, httpVersion: nil, headerFields: headers)!)
        }
    }

    func make() throws -> (LiveGenerationService, FakeTransport, AudioCache) {
        let cache = try AudioCacheTests.temp()
        let t = FakeTransport()
        let svc = LiveGenerationService(baseURL: URL(string: "https://example.test")!, cache: cache,
                                        transport: t, deviceID: "test-device")
        return (svc, t, cache)
    }

    @Test func sendsDeviceHeaderAndDecodesScene() async throws {
        let (svc, t, _) = try make()
        t.responses["/scene"] = (200, ["Content-Type": "application/json"], Data(#"{"title":"T","mood":"blue","sounds":[{"name":"Rain","keyword":"rain","tint":"teal","kind":"loop","prompt":"p","duration":10}]}"#.utf8))
        let r = try await svc.buildScene(prompt: "soft rain")
        #expect(r.sounds.first?.name == "Rain")
        #expect(t.requests[0].value(forHTTPHeaderField: "X-Device-ID") == "test-device")
        #expect(t.requests[0].httpMethod == "POST")
    }

    @Test func mapsErrorCodes() async throws {
        let (svc, t, _) = try make()
        let spec = SoundSpec(prompt: "x", duration: 2, loop: false)
        t.responses["/sound"] = (429, [:], Data(#"{"error":"busy"}"#.utf8))
        await #expect(throws: GenerationError.busy) { try await svc.generateSound(spec) }
        t.responses["/sound"] = (429, [:], Data(#"{"error":"quota"}"#.utf8))
        await #expect(throws: GenerationError.quota) { try await svc.generateSound(spec) }
        // A 60-second burst is transient: it must retry, not end the session with "Daily limit reached".
        t.responses["/sound"] = (429, [:], Data(#"{"error":"rate_limited"}"#.utf8))
        await #expect(throws: GenerationError.busy) { try await svc.generateSound(spec) }
        t.responses["/sound"] = (502, [:], Data(#"{"error":"elevenlabs_error"}"#.utf8))
        await #expect(throws: GenerationError.server(502)) { try await svc.generateSound(spec) }
    }

    @Test func networkFailureIsOffline() async throws {
        let (svc, t, _) = try make()
        t.thrown = URLError(.notConnectedToInternet)
        await #expect(throws: GenerationError.offline) { try await svc.buildScene(prompt: "rain") }
    }

    @Test func rejectsNonAudioAndCachesAudio() async throws {
        let (svc, t, cache) = try make()
        let spec = SoundSpec(prompt: "y", duration: 2, loop: false)
        t.responses["/sound"] = (200, ["Content-Type": "text/html"], Data(repeating: 0, count: 5000))
        await #expect(throws: GenerationError.invalidResponse) { try await svc.generateSound(spec) }
        #expect(!cache.contains(spec.cacheKey))

        t.responses["/sound"] = (200, ["Content-Type": "audio/mpeg"], Data(repeating: 0, count: 100))
        await #expect(throws: GenerationError.invalidResponse) { try await svc.generateSound(spec) }

        t.responses["/sound"] = (200, ["Content-Type": "audio/mpeg"], Data(repeating: 1, count: 5000))
        _ = try await svc.generateSound(spec)
        #expect(cache.contains(spec.cacheKey))
        _ = try await svc.generateSound(spec)
        #expect(t.requests.filter { $0.url!.path == "/sound" }.count == 3, "a cache hit must not call the proxy")
    }
}
