import Testing
@testable import Foley

@Suite struct KeywordMatcherTests {
    let text = "A creaky pirate ship in a thunderstorm, heavy rain, howling wind, waves smashing the hull"
    @Test func findsCaseInsensitiveAndStripsPunctuation() {
        let r = KeywordMatcher.ranges(of: ["Heavy Rain,", "WAVES"], in: text)
        #expect(r[0].map { String(text[$0]) } == "heavy rain")
        #expect(r[1].map { String(text[$0]) } == "waves")
    }
    @Test func unknownKeywordIsNilAndDoesNotShiftOthers() {
        let r = KeywordMatcher.ranges(of: ["grumpy cat", "howling wind"], in: text)
        #expect(r[0] == nil)
        #expect(r[1].map { String(text[$0]) } == "howling wind")
    }
    @Test func repeatedWordTakesNextOccurrence() {
        let t = "rain then more rain"
        let r = KeywordMatcher.ranges(of: ["rain", "rain"], in: t)
        #expect(r[0] != r[1]); #expect(r[1] != nil)
    }
}
