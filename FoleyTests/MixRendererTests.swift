import Testing
import Foundation
import AVFoundation
@testable import Foley

@Suite struct MixRendererTests {
    @Test func rendersPortraitVideoWithAudio() async throws {
        let audio = try #require(Bundle.main.url(forResource: "thunder-crack", withExtension: "m4a"))
        let id = UUID()
        let input = MixVideoInput(title: "Test", pads: [MixVideoPad(id: id, name: "Thunder", tint: .blue)],
                                  envelope: [id: (0..<60).map { Float($0 % 10) / 10 }], envelopeRate: 30,
                                  duration: 2, audioURL: audio)
        let out = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).mp4")
        _ = try await MixRenderer(fps: 15).render(input, to: out) { _ in }
        let asset = AVURLAsset(url: out)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await video.load(.naturalSize) == CGSize(width: 1080, height: 1920))
        #expect(abs(try await asset.load(.duration).seconds - 2) < 0.3)
    }
}
