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

    static let extensions = ["mp3", "m4a", "wav"]

    /// The stored file for a key (whatever container it was written as), or the default .mp3 path.
    func url(for key: String) -> URL {
        for ext in Self.extensions {
            let candidate = directory.appending(path: "\(key).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appending(path: "\(key).mp3")
    }

    func contains(_ key: String) -> Bool { FileManager.default.fileExists(atPath: url(for: key).path) }

    /// Writes the bytes under an extension that matches their container, because CoreAudio
    /// refuses an MPEG-4 file named .mp3 but opens any correctly named one.
    @discardableResult
    func store(_ data: Data, key: String) throws -> URL {
        remove(key)
        let target = directory.appending(path: "\(key).\(Self.sniffExtension(data))")
        try data.write(to: target, options: .atomic)
        return target
    }

    func remove(_ key: String) {
        for ext in Self.extensions { try? FileManager.default.removeItem(at: directory.appending(path: "\(key).\(ext)")) }
    }

    static func sniffExtension(_ data: Data) -> String {
        guard data.count >= 12 else { return "mp3" }
        if data[4..<8] == Data("ftyp".utf8) { return "m4a" }
        if data[0..<4] == Data("RIFF".utf8) { return "wav" }
        return "mp3"
    }
}
