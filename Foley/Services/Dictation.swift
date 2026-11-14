import AVFoundation
import Observation
import Speech

/// Speech-to-text for the composer's mic button. Uses its own input engine so playback is untouched.
@Observable
@MainActor
final class Dictation {
    private(set) var transcript = ""
    private(set) var isListening = false
    private(set) var isAvailable = SFSpeechRecognizer()?.isAvailable ?? false
    private(set) var lastError: String?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    func start() async {
        guard !isListening else { return }
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard speechStatus == .authorized, micGranted, let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            isAvailable = false
            lastError = "Dictation isn't available"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            self.engine = engine
            self.request = request
            transcript = ""
            isListening = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                Task { @MainActor [weak self] in
                    if let text { self?.transcript = text }
                    if final || error != nil { self?.stop() }
                }
            }
        } catch {
            lastError = "Dictation isn't available"
            stop()
        }
    }

    func stop() {
        guard isListening || engine != nil else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        request?.endAudio()
        task?.cancel()
        engine = nil; request = nil; task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
