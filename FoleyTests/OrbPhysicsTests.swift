import Testing
import CoreGraphics
@testable import Foley

@Suite struct OrbPhysicsTests {
    @Test func flungOrbReturnsToCentreAndStops() {
        var p = OrbPhysics()
        p.release(velocity: CGVector(dx: 900, dy: -600))
        for _ in 0..<600 { p.step(dt: 1.0 / 60) }          // ten seconds
        #expect(abs(p.position.x) < 0.5 && abs(p.position.y) < 0.5, "orb never came home")
        #expect(p.speed < 1, "orb never settled")
    }

    @Test func itOvershootsAtLeastOnceSoItFeelsSpringy() {
        var p = OrbPhysics()
        p.release(velocity: CGVector(dx: 1200, dy: 0))
        var crossings = 0
        var previous = p.position.x
        for _ in 0..<240 {
            p.step(dt: 1.0 / 60)
            if previous > 0, p.position.x <= 0 { crossings += 1 }
            if previous < 0, p.position.x >= 0 { crossings += 1 }
            previous = p.position.x
        }
        #expect(crossings >= 1, "a spring that never crosses centre reads as a slide, not a bounce")
    }

    @Test func stretchFollowsSpeedAndIsBounded() {
        var p = OrbPhysics()
        #expect(p.stretch == 0)
        p.release(velocity: CGVector(dx: 2000, dy: 0))
        p.step(dt: 1.0 / 60)
        let fast = p.stretch
        #expect(fast > 0.1, "a hard fling should visibly deform the orb")
        #expect(fast <= 0.45, "deformation must stay inside the ring")
    }

    @Test func dragIsTrackedWithoutSpringForcesFightingTheFinger() {
        var p = OrbPhysics()
        p.beginDrag()
        p.drag(to: CGPoint(x: 60, y: 20))
        p.step(dt: 1.0 / 60)
        #expect(p.position.x == 60 && p.position.y == 20, "the orb must sit under the finger while held")
    }

    @Test func noteRisesWithSpeedAndStaysInThePentatonicScale() {
        let scale = OrbPhysics.pentatonic
        let slow = OrbPhysics.note(forSpeed: 50)
        let fast = OrbPhysics.note(forSpeed: 2500)
        #expect(scale.contains(slow) && scale.contains(fast))
        #expect(fast > slow, "a harder fling should sound brighter")
        #expect(OrbPhysics.note(forSpeed: 99999) <= scale.last!, "mapping must clamp, not run off the scale")
    }
}

@Suite struct OrbVoiceTests {
    @Test func pluckDecaysAndIsAudible() {
        let samples = OrbVoice.pluck(frequency: 440, amplitude: 1, sampleRate: 44100)
        #expect(samples.count > 20_000, "too short to hear")
        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(peak > 0.1 && peak <= 1, "peak was \(peak)")
        let half = samples.count / 2
        let early = samples[..<half].reduce(0) { $0 + abs($1) } / Float(half)
        let late = samples[half...].reduce(0) { $0 + abs($1) } / Float(samples.count - half)
        #expect(late < early * 0.5, "a pluck must ring out, not sustain")
        #expect(abs(samples[0]) < 0.05, "a hard start would click")
    }

    @Test func pitchMatchesTheRequestedNote() {
        let frequency = 440.0, rate = 44100.0
        let samples = OrbVoice.pluck(frequency: frequency, amplitude: 1, sampleRate: rate)
        // Count zero crossings over the first 0.2s, where the tone is strongest.
        let window = Array(samples[..<Int(rate * 0.2)])
        var crossings = 0
        for i in 1..<window.count where (window[i - 1] < 0) != (window[i] < 0) { crossings += 1 }
        let measured = Double(crossings) / 2 / 0.2
        #expect(abs(measured - frequency) < frequency * 0.15, "measured \(measured)Hz, wanted \(frequency)Hz")
    }

    @Test func amplitudeScalesTheOutput() {
        let quiet = OrbVoice.pluck(frequency: 440, amplitude: 0.2, sampleRate: 44100)
        let loud = OrbVoice.pluck(frequency: 440, amplitude: 1, sampleRate: 44100)
        let quietPeak = quiet.map { abs($0) }.max() ?? 0
        let loudPeak = loud.map { abs($0) }.max() ?? 0
        #expect(quietPeak < loudPeak * 0.5)
    }
}
