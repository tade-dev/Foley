import AVFoundation

/// Downsamples an audio file into peak buckets for `WaveformView`.
nonisolated enum WaveformSampler {
    /// `count` buckets of max-abs sample, normalised so the loudest bucket is 1 (all zeros stay 0).
    static func peaks(url: URL, count: Int) async throws -> [Float] {
        try await Task.detached(priority: .userInitiated) {
            let file = try AVAudioFile(forReading: url)
            let frames = AVAudioFrameCount(file.length)
            guard count > 0, frames > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
                return Array(repeating: 0, count: max(count, 0))
            }
            try file.read(into: buffer)
            guard let channels = buffer.floatChannelData else { return Array(repeating: 0, count: count) }
            let channelCount = Int(buffer.format.channelCount)
            let n = Int(buffer.frameLength)
            var out = [Float](repeating: 0, count: count)
            for b in 0..<count {
                let start = b * n / count
                let end = max(start + 1, (b + 1) * n / count)
                var peak: Float = 0
                for c in 0..<channelCount {
                    let data = channels[c]
                    for i in start..<min(end, n) { peak = max(peak, abs(data[i])) }
                }
                out[b] = peak
            }
            let maxPeak = out.max() ?? 0
            return maxPeak > 0 ? out.map { $0 / maxPeak } : out
        }.value
    }
}
