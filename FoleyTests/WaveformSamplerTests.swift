import Testing
import Foundation
@testable import Foley

@Suite struct WaveformSamplerTests {
    @Test func peaksAreNormalisedToCount() async throws {
        let url = try #require(Bundle.main.url(forResource: "thunder-crack", withExtension: "m4a"))
        let p = try await WaveformSampler.peaks(url: url, count: 56)
        #expect(p.count == 56); #expect(p.max() == 1); #expect(p.allSatisfy { (0...1).contains($0) })
    }
}
