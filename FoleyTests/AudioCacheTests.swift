import Testing
import Foundation
@testable import Foley

@Suite struct AudioCacheTests {
    static func temp() throws -> AudioCache {
        try AudioCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }
    @Test func storeThenContains() throws {
        let c = try Self.temp(); let key = String(repeating: "a", count: 64)
        #expect(!c.contains(key))
        let url = try c.store(Data([1, 2, 3]), key: key)
        #expect(c.contains(key)); #expect(url == c.url(for: key))
        c.remove(key); #expect(!c.contains(key))
    }
}

extension AudioCacheTests {
    @Test func extensionFollowsTheBytesNotTheSource() throws {
        let c = try Self.temp()
        let m4a = try Data(contentsOf: #require(Bundle.main.url(forResource: "thunder-crack", withExtension: "m4a")))
        let mp3Header = Data([0x49, 0x44, 0x33, 0x04, 0x00]) + Data(repeating: 0, count: 64)
        #expect(try c.store(m4a, key: "k1").pathExtension == "m4a")
        #expect(try c.store(mp3Header, key: "k2").pathExtension == "mp3")
        #expect(c.contains("k1") && c.url(for: "k1").pathExtension == "m4a")
    }
}
