import CryptoKit
import Foundation

/// Everything ElevenLabs needs to generate one sound. Hashed for the cache key.
nonisolated struct SoundSpec: Codable, Hashable, Sendable {
    var prompt: String
    var duration: Double?          // 0.5–22s, nil = let the API decide
    var loop: Bool
    var promptInfluence: Double = 0.3

    /// Stable identity of a generated file: the same spec never hits the API twice.
    var cacheKey: String {
        let d = duration.map { String(format: "%.2f", $0) } ?? "auto"
        let canonical = "\(prompt)|\(d)|\(loop)|\(String(format: "%.2f", promptInfluence))"
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
