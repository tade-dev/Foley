import Foundation

/// Generated audio on disk, keyed by `SoundSpec.cacheKey`. A hit never touches the network.
nonisolated final class AudioCache: Sendable {
    let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Application Support/Foley/Audio
    static func appSupport() throws -> AudioCache {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return try AudioCache(directory: base.appending(path: "Foley/Audio"))
    }

    func url(for key: String) -> URL { directory.appending(path: "\(key).mp3") }

    func contains(_ key: String) -> Bool { FileManager.default.fileExists(atPath: url(for: key).path) }

    @discardableResult
    func store(_ data: Data, key: String) throws -> URL {
        let target = url(for: key)
        try data.write(to: target, options: .atomic)
        return target
    }

    func remove(_ key: String) { try? FileManager.default.removeItem(at: url(for: key)) }
}
