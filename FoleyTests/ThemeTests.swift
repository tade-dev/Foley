import Testing
import SwiftUI
@testable import Foley

@Suite struct ThemeTests {
    @Test func everyTintHasDistinctBase() {
        let bases = Set(Tint.allCases.map(\.hexBase))
        #expect(bases.count == Tint.allCases.count)
    }
    @Test func tintDecodesFromRawValue() throws {
        #expect(try JSONDecoder().decode(Tint.self, from: Data("\"lavender\"".utf8)) == .lavender)
    }
    @Test func amberBaseMatchesTokens() { #expect(Tint.amber.hexBase == 0xFFB547) }
}
