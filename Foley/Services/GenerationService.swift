import Foundation

nonisolated enum GenerationError: Error, Equatable, Sendable {
    case notConfigured
    case busy
    case quota
    case offline
    case invalidResponse
    case server(Int)

    /// Copy shown on a pad or inline. Says what happened; the UI offers the one action.
    var userMessage: String {
        switch self {
        case .quota: "Daily limit reached"
        case .busy: "Too many at once, retrying"
        case .offline: "You're offline"
        default: "Couldn't make this one"
        }
    }
}

/// The only way the app talks to sound generation. Phase A: `MockGenerationService`.
/// Phase B: `LiveGenerationService` through the Worker proxy.
nonisolated protocol GenerationService: Sendable {
    /// Split a scene description into named sounds with tints and kinds.
    func buildScene(prompt: String) async throws -> SceneResponse
    /// Return a cached audio file for the spec, generating it first if needed.
    /// Must return immediately on a cache hit.
    func generateSound(_ spec: SoundSpec) async throws -> URL
}
