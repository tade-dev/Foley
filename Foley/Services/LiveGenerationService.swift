import Foundation

/// The seam the tests replace: everything network in one method.
nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GenerationError.invalidResponse }
        return (data, http)
    }
}

/// Talks to the Cloudflare Worker. Never sees an API key; the proxy holds them.
nonisolated final class LiveGenerationService: GenerationService {
    private let baseURL: URL
    private let cache: AudioCache
    private let transport: HTTPTransport
    private let deviceID: String

    /// Smaller than any real sound file: anything under this is an error page, not audio.
    private static let minimumAudioBytes = 1024

    init(baseURL: URL, cache: AudioCache, transport: HTTPTransport = URLSessionTransport(),
         deviceID: String = DeviceID.current) {
        self.baseURL = baseURL
        self.cache = cache
        self.transport = transport
        self.deviceID = deviceID
    }

    func buildScene(prompt: String) async throws -> SceneResponse {
        let (data, response) = try await send("/scene", body: ["prompt": prompt])
        try check(response, data)
        do {
            return try JSONDecoder().decode(SceneResponse.self, from: data).validated(for: prompt)
        } catch {
            throw GenerationError.invalidResponse
        }
    }

    func generateSound(_ spec: SoundSpec) async throws -> URL {
        if cache.contains(spec.cacheKey) { return cache.url(for: spec.cacheKey) }

        let (data, response) = try await send("/sound", encodable: SoundRequest(spec))
        try check(response, data)

        let type = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard type.hasPrefix("audio/"), data.count >= Self.minimumAudioBytes else {
            throw GenerationError.invalidResponse
        }
        return try cache.store(data, key: spec.cacheKey)
    }

    // MARK: Transport

    private func send(_ path: String, body: [String: String]) async throws -> (Data, HTTPURLResponse) {
        try await send(path, payload: try JSONEncoder().encode(body))
    }

    private func send(_ path: String, encodable: some Encodable) async throws -> (Data, HTTPURLResponse) {
        try await send(path, payload: try JSONEncoder().encode(encodable))
    }

    private func send(_ path: String, payload: Data) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
        request.httpBody = payload
        do {
            return try await transport.send(request)
        } catch let error as GenerationError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw GenerationError.offline
        }
    }

    /// Maps the Worker's `{"error": code}` bodies onto the app's errors.
    private func check(_ response: HTTPURLResponse, _ data: Data) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        let code = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
        switch code {
        // A burst limit clears in a minute, so it retries; only the daily caps end the session.
        case "busy", "rate_limited": throw GenerationError.busy
        case "quota": throw GenerationError.quota
        case "bad_prompt", "invalid_scene": throw GenerationError.invalidResponse
        default: throw GenerationError.server(response.statusCode)
        }
    }
}
