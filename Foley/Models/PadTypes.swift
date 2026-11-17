import Foundation

nonisolated enum PadKind: String, Codable, Sendable {
    case loop, oneShot

    var symbol: String { self == .loop ? "repeat" : "bolt.fill" }
    var label: String { self == .loop ? "Loop" : "One-shot" }
}

/// Transient UI state for a pad. Held in SceneStore, never persisted.
nonisolated enum PadStatus: Equatable, Sendable {
    case queued, generating, ready, playing
    case failed(String)
}
