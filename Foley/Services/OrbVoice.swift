import Foundation

/// The sound the home-screen orb makes when you play with it: a short plucked tone.
/// Pure sample generation, so its pitch and decay can be tested without an audio device.
nonisolated enum OrbVoice {
    static let duration: Double = 0.75

    /// A fundamental with two quieter harmonics, an exponential decay, and a 6 ms fade in
    /// so the attack never clicks.
    static func pluck(frequency: Double, amplitude: Double, sampleRate: Double) -> [Float] {
        let count = Int(duration * sampleRate)
        let attack = Int(0.006 * sampleRate)
        var samples = [Float](repeating: 0, count: count)

        for i in 0..<count {
            let t = Double(i) / sampleRate
            let decay = exp(-t * 4.2)
            var value = sin(2 * .pi * frequency * t)
            value += 0.32 * sin(2 * .pi * frequency * 2 * t)
            value += 0.14 * sin(2 * .pi * frequency * 3 * t)
            // A touch of shimmer that fades faster than the body of the note.
            value += 0.08 * sin(2 * .pi * frequency * 4.02 * t) * exp(-t * 11)
            var gain = decay * amplitude * 0.42
            if i < attack { gain *= Double(i) / Double(attack) }
            samples[i] = Float(value * gain)
        }
        return samples
    }
}
