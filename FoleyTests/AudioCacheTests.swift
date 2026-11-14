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
