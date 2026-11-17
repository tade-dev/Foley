import Testing
import Foundation
import AVFoundation
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
    @Test func oneShotStopsShowingAsPlayingWhenItEnds() async throws {
        let e = AudioEngine(); let id = UUID()
        try e.load(padID: id, kind: .oneShot, url: try #require(Bundle.main.url(forResource: "grumpy-cat", withExtension: "m4a")))
        e.toggle(id); #expect(e.isPlaying(id))
        try await Task.sleep(for: .seconds(2.8))
        #expect(!e.isPlaying(id))
    }
    @Test func playAllReleasesOneShotsAmongLoops() async throws {
        let e = AudioEngine()
        var ids: [UUID] = []
        for (file, kind) in [("creaking-hull", PadKind.loop), ("thunder-crack", .oneShot), ("heavy-rain", .loop), ("grumpy-cat", .oneShot)] {
            let id = UUID(); ids.append(id)
            try e.load(padID: id, kind: kind, url: try #require(Bundle.main.url(forResource: file, withExtension: "m4a")))
        }
        e.playAll(ids)
        #expect(e.playing.count == 4)
        try await Task.sleep(for: .seconds(4.6))
        #expect(e.isPlaying(ids[0]) && e.isPlaying(ids[2]))
        #expect(!e.isPlaying(ids[1]) && !e.isPlaying(ids[3]))
    }
    @Test func recordingWithNothingPlayingIsDiscarded() async throws {
        let (e, _) = try engine()           // loaded but never toggled
        try e.startRecording()
        try await Task.sleep(for: .seconds(1.2))
        #expect(e.stopRecording() == nil, "a silent recording must not become a mix")
        #expect(!e.isRecording)
    }

    @Test func unloadAllClearsNodesSoEnvelopesStayScoped() async throws {
        let (e, id) = try engine()
        e.unloadAll()
        #expect(e.playing.isEmpty)
        let second = UUID()
        try e.load(padID: second, kind: .loop, url: try #require(Bundle.main.url(forResource: "heavy-rain", withExtension: "m4a")))
        e.toggle(second)
        try e.startRecording()
        try await Task.sleep(for: .seconds(0.8))
        let rec = try #require(e.stopRecording())
        #expect(rec.envelope[id] == nil, "a previous scene's pad leaked into the envelope")
        #expect(rec.envelope[second] != nil)
    }

    @Test func configurationChangeStopsTheGlow() async throws {
        let (e, id) = try engine()
        e.toggle(id)
        #expect(e.isPlaying(id))
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(e.playing.isEmpty, "pads would glow with no sound after the engine reconfigures")
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
