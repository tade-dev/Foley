import AVFoundation
import Observation
import QuartzCore

/// A finished recording of the mix, plus the per-pad level envelope the share video animates to.
nonisolated struct MixRecording: Sendable {
    var url: URL                 // temporary .m4a
    var duration: TimeInterval
    var envelope: [UUID: [Float]]   // sampled at `envelopeRate` Hz for every loaded pad
    var padOrder: [UUID]
    static let envelopeRate: Double = 30
}

/// One player node per pad, mixed into the main mixer.
/// Publishes per-pad levels (~60 Hz) that drive the pad glow, 40 master bins for `MasterMeter`,
/// and records the mix to AAC with a per-pad envelope.
@Observable
@MainActor
final class AudioEngine {
    private(set) var levels: [UUID: Float] = [:]
    private(set) var masterLevels: [Float] = Array(repeating: 0, count: 40)
    private(set) var playing: Set<UUID> = []
    private(set) var isRecording = false
    private(set) var recordingElapsed: Duration = .zero

    var masterVolume: Double = 0.8 {
        didSet { engine.mainMixerNode.outputVolume = Float(max(0, min(1, masterVolume))) }
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var players: [UUID: AVAudioPlayerNode] = [:]
    @ObservationIgnored private var buffers: [UUID: AVAudioPCMBuffer] = [:]
    @ObservationIgnored private var kinds: [UUID: PadKind] = [:]
    @ObservationIgnored private var pans: [UUID: Double] = [:]
    @ObservationIgnored private var loadOrder: [UUID] = []
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private let meter = MeterStore()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Its own node so plucking the home-screen orb never interrupts a pad.
    @ObservationIgnored private lazy var voiceNode = AVAudioPlayerNode()
    @ObservationIgnored private var voiceAttached = false

    // Recording state (main actor only).
    @ObservationIgnored private var recordingStart: Date?
    @ObservationIgnored private var envelope: [UUID: [Float]] = [:]
    @ObservationIgnored private var lastEnvelopeSample: Date?
    /// Set the first time any pad is actually playing during a recording. A recording that never
    /// hears anything is silence, not a mix.
    @ObservationIgnored private var recordedSomething = false

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        installMasterTap()
        engine.prepare()
        try? engine.start()
        engine.mainMixerNode.outputVolume = Float(masterVolume)
        startLevelPump()
        observeSession()
    }

    // MARK: Loading

    func load(padID: UUID, kind: PadKind, url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else { return }
        try file.read(into: buffer)

        if let node = players[padID] {
            node.stop()
            playing.remove(padID)
        } else {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
            installTap(on: node, padID: padID)
            players[padID] = node
            loadOrder.append(padID)
        }
        buffers[padID] = buffer
        kinds[padID] = kind
        if !engine.isRunning { try? engine.start() }
    }

    /// Drops every loaded pad. Called when leaving a scene so nodes, taps and the recording
    /// envelope never carry another scene's pads.
    func unloadAll() {
        for id in players.keys { unload(padID: id) }
    }

    func unload(padID: UUID) {
        guard let node = players[padID] else { return }
        node.stop()
        node.removeTap(onBus: 0)
        engine.detach(node)
        players[padID] = nil
        buffers[padID] = nil
        kinds[padID] = nil
        pans[padID] = nil
        playing.remove(padID)
        levels[padID] = nil
        loadOrder.removeAll { $0 == padID }
        meter.remove(padID)
    }

    // MARK: Playback

    func isPlaying(_ padID: UUID) -> Bool { playing.contains(padID) }

    /// Loop: start/stop. One-shot: trigger from the start.
    func toggle(_ padID: UUID) {
        guard let node = players[padID], let buffer = buffers[padID] else { return }
        if !engine.isRunning { try? engine.start() }

        switch kinds[padID] ?? .loop {
        case .loop:
            if playing.contains(padID) {
                node.stop()
                playing.remove(padID)
            } else {
                node.scheduleBuffer(buffer, at: nil, options: .loops)
                node.play()
                playing.insert(padID)
            }
        case .oneShot:
            node.stop()
            node.scheduleBuffer(buffer, at: nil, options: .interrupts) { @Sendable [weak self] in
                Task { @MainActor in self?.playing.remove(padID) }
            }
            node.play()
            playing.insert(padID)
        }
    }

    /// Starts every loop in `ids` that is not already playing and triggers each one-shot once.
    func playAll(_ ids: [UUID]) {
        for id in ids where kinds[id] == .oneShot || !playing.contains(id) { toggle(id) }
    }

    func stopAll() {
        players.values.forEach { $0.stop() }
        playing.removeAll()
    }

    func setVolume(_ volume: Double, pan: Double, for padID: UUID) {
        let clampedPan = max(-1, min(1, pan))
        pans[padID] = clampedPan
        players[padID]?.volume = Float(max(0, min(1, volume)))
        players[padID]?.pan = Float(clampedPan)
    }

    func pan(for padID: UUID) -> Double { pans[padID] ?? 0 }

    func volume(for padID: UUID) -> Double { Double(players[padID]?.volume ?? 1) }

    /// 0–1 position inside the current loop, for `LoopRing`.
    func loopProgress(for padID: UUID) -> Double {
        guard let node = players[padID], let buffer = buffers[padID], buffer.frameLength > 0,
              let nodeTime = node.lastRenderTime, let t = node.playerTime(forNodeTime: nodeTime) else { return 0 }
        return Double(t.sampleTime % Int64(buffer.frameLength)) / Double(buffer.frameLength)
    }

    /// Route change or interruption: nothing is audible any more, so the UI must not glow.
    func handleInterruption() {
        stopAll()
        for id in levels.keys { levels[id] = 0 }
        masterLevels = Array(repeating: 0, count: 40)
        meter.reset()
        // The system deactivates the session during an interruption; without this the engine
        // never restarts and the app is silent until relaunch.
        try? AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning { try? engine.start() }
    }

    // MARK: The home-screen orb's voice

    /// Plays a short plucked note. Pitch and loudness come from how hard the orb was thrown.
    func pluck(speed: Double) {
        let frequency = OrbPhysics.note(forSpeed: speed)
        let amplitude = 0.25 + 0.75 * min(1, speed / 2200)
        play(OrbVoice.pluck(frequency: frequency, amplitude: amplitude, sampleRate: 44100))
    }

    private func play(_ samples: [Float]) {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        guard let format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channels = buffer.floatChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for channel in 0..<Int(format.channelCount) {
            samples.withUnsafeBufferPointer { channels[channel].update(from: $0.baseAddress!, count: samples.count) }
        }

        if !voiceAttached {
            engine.attach(voiceNode)
            engine.connect(voiceNode, to: engine.mainMixerNode, format: format)
            voiceAttached = true
        }
        if !engine.isRunning { try? engine.start() }
        voiceNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        voiceNode.play()
    }

    // MARK: Recording (.m4a)

    func startRecording() throws {
        guard !isRecording else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foley-mix-\(UUID().uuidString).m4a")
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 160_000,
        ])
        envelope = Dictionary(uniqueKeysWithValues: loadOrder.map { ($0, [Float]()) })
        lastEnvelopeSample = nil
        recordedSomething = !playing.isEmpty
        recordingStart = .now
        recordingElapsed = .zero
        meter.recordFile = file
        isRecording = true
    }

    /// Returns nil (and discards the file) when the recording is shorter than half a second.
    func stopRecording() -> MixRecording? {
        guard isRecording, let start = recordingStart else { return nil }
        let file = meter.recordFile
        meter.recordFile = nil
        isRecording = false
        recordingStart = nil
        let duration = Date.now.timeIntervalSince(start)
        guard let file, duration >= 0.5, recordedSomething else {
            if let file { try? FileManager.default.removeItem(at: file.url) }
            return nil
        }
        return MixRecording(url: file.url, duration: duration, envelope: envelope, padOrder: loadOrder)
    }

    // MARK: Metering

    private func installTap(on node: AVAudioPlayerNode, padID: UUID) {
        let meter = self.meter
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { @Sendable buffer, _ in
            meter.setPad(padID, rms(buffer))
        }
    }

    private func installMasterTap() {
        let mixer = engine.mainMixerNode
        let meter = self.meter
        mixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { @Sendable buffer, _ in
            meter.pushMaster(rms(buffer))
            meter.write(buffer)
        }
    }

    private func startLevelPump() {
        let link = CADisplayLink(target: LinkTarget { [weak self] in self?.pumpLevels() }, selector: #selector(LinkTarget.tick))
        // 60 Hz is what the glow needs; ProMotion would otherwise pump at 120.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func pumpLevels() {
        let (pads, master) = meter.snapshot()
        // Fast attack, slower release, so the glow feels alive rather than jittery.
        for id in players.keys {
            let target = pads[id] ?? 0
            let current = levels[id] ?? 0
            let k: Float = target > current ? 0.6 : 0.15
            let next = playing.contains(id) ? current + (target - current) * k : 0
            if abs(next - current) > 0.001 || (next == 0 && current != 0) { levels[id] = next }
        }
        let nextMaster = playing.isEmpty ? Array(repeating: 0, count: 40) : master
        if nextMaster != masterLevels { masterLevels = nextMaster }
        sampleEnvelopeIfRecording()
    }

    private func sampleEnvelopeIfRecording() {
        guard isRecording, let start = recordingStart else { return }
        let now = Date.now
        recordingElapsed = .seconds(now.timeIntervalSince(start))
        let interval = 1 / MixRecording.envelopeRate
        if let last = lastEnvelopeSample, now.timeIntervalSince(last) < interval { return }
        lastEnvelopeSample = now
        if !playing.isEmpty { recordedSomething = true }
        for id in loadOrder {
            envelope[id, default: []].append(playing.contains(id) ? (levels[id] ?? 0) : 0)
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleInterruption() }
        })
        // Dictation flips the shared session to .playAndRecord, which reconfigures the engine and
        // stops every node: without this, pads keep glowing with no sound.
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleInterruption() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            guard reason == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.handleInterruption() }
        })
    }
}

/// Thread-safe store the audio taps write into; the display link reads it on main.
private nonisolated final class MeterStore: @unchecked Sendable {
    private let lock = NSLock()
    /// Separate from `lock`: encoding and writing a buffer must never block the display link's
    /// 60 Hz `snapshot()` on the main thread.
    private let fileLock = NSLock()
    private var pads: [UUID: Float] = [:]
    private var master: [Float] = Array(repeating: 0, count: 40)
    private var _recordFile: AVAudioFile?

    var recordFile: AVAudioFile? {
        get { fileLock.withLock { _recordFile } }
        set { fileLock.withLock { _recordFile = newValue } }
    }
    func setPad(_ id: UUID, _ v: Float) { lock.withLock { pads[id] = v } }
    func remove(_ id: UUID) { lock.withLock { pads[id] = nil } }
    func pushMaster(_ v: Float) { lock.withLock { master.removeFirst(); master.append(v) } }
    func reset() { lock.withLock { pads = [:]; master = Array(repeating: 0, count: 40) } }
    func write(_ buffer: AVAudioPCMBuffer) { fileLock.withLock { try? _recordFile?.write(from: buffer) } }
    func snapshot() -> ([UUID: Float], [Float]) { lock.withLock { (pads, master) } }
}

private nonisolated func rms(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let data = buffer.floatChannelData?[0] else { return 0 }
    let n = Int(buffer.frameLength)
    guard n > 0 else { return 0 }
    var sum: Float = 0
    for i in 0..<n { sum += data[i] * data[i] }
    return min(1, (sum / Float(n)).squareRoot() * 4)   // rough gain so normal SFX land in 0–1
}

private final class LinkTarget {
    let fire: () -> Void
    init(_ fire: @escaping () -> Void) { self.fire = fire }
    @objc func tick() { fire() }
}
