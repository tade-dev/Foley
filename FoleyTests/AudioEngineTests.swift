import Testing
import Foundation
@testable import Foley

@Suite(.serialized) @MainActor struct AudioEngineTests {
    func engine() throws -> (AudioEngine, UUID) {
        let e = AudioEngine(); let id = UUID()
        try e.load(padID: id, kind: .loop, url: try #require(Bundle.main.url(forResource: "heavy-rain", withExtension: "m4a")))
        return (e, id)
    }
    @Test func toggleStartsAndStopsLoop() throws {
        let (e, id) = try engine()
        e.toggle(id); #expect(e.isPlaying(id))
        e.toggle(id); #expect(!e.isPlaying(id))
    }
    @Test func stopAllAndInterruptionClearState() throws {
        let (e, id) = try engine()
        e.toggle(id); e.stopAll(); #expect(e.playing.isEmpty)
        e.toggle(id); e.handleInterruption(); #expect(e.playing.isEmpty); #expect(e.levels.values.allSatisfy { $0 == 0 })
    }
    @Test func panIsClamped() throws {
        let (e, id) = try engine()
        e.setVolume(0.5, pan: 4, for: id)
        #expect(e.pan(for: id) == 1)
    }
    @Test func shortRecordingIsDiscarded() async throws {
        let (e, _) = try engine()
        try e.startRecording(); try await Task.sleep(for: .milliseconds(100))
        #expect(e.stopRecording() == nil); #expect(!e.isRecording)
    }
    @Test func recordingProducesFileAndEnvelope() async throws {
        let (e, id) = try engine()
        e.toggle(id); try e.startRecording()
        try await Task.sleep(for: .milliseconds(800))
        let rec = try #require(e.stopRecording())
        #expect(rec.duration >= 0.5)
        #expect(FileManager.default.fileExists(atPath: rec.url.path))
        #expect((rec.envelope[id]?.count ?? 0) >= 15)
    }
}
