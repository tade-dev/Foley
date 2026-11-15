import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import UIKit

nonisolated struct MixVideoPad: Sendable, Identifiable {
    var id: UUID
    var name: String
    var tint: Tint
}

nonisolated struct MixVideoInput: Sendable {
    var title: String
    var pads: [MixVideoPad]
    var envelope: [UUID: [Float]]
    var envelopeRate: Double
    var duration: TimeInterval
    var audioURL: URL
}

nonisolated enum MixRenderError: Error { case writerFailed(String), noAudioTrack }

/// Renders a recorded mix into a 9:16 H.264 video: the pads' orbs pulse with their envelopes
/// over the scene title, with a progress waveform, muxed with the recorded audio.
nonisolated final class MixRenderer: Sendable {
    let size: CGSize
    let fps: Int

    init(size: CGSize = CGSize(width: 1080, height: 1920), fps: Int = 30) {
        self.size = size
        self.fps = fps
    }

    func render(_ input: MixVideoInput, to outputURL: URL, progress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
        ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(videoInput)

        // Audio: decode the recording to PCM and re-encode as AAC inside the mp4.
        let asset = AVURLAsset(url: input.audioURL)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else { throw MixRenderError.noAudioTrack }
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        reader.add(readerOutput)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: input.duration, preferredTimescale: 600))
        let descriptions = try await audioTrack.load(.formatDescriptions)
        let asbd = descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: asbd?.mSampleRate ?? 44_100,
            AVNumberOfChannelsKey: Int(asbd?.mChannelsPerFrame ?? 2),
            AVEncoderBitRateKey: 160_000,
        ])
        audioInput.expectsMediaDataInRealTime = false
        writer.add(audioInput)

        guard writer.startWriting() else { throw MixRenderError.writerFailed(writer.error?.localizedDescription ?? "start") }
        writer.startSession(atSourceTime: .zero)
        reader.startReading()

        let frameCount = max(1, Int((input.duration * Double(fps)).rounded(.up)))
        let box = WriterBox(writer: writer, videoInput: videoInput, adaptor: adaptor, audioInput: audioInput,
                            reader: reader, readerOutput: readerOutput, painter: FramePainter(size: size, input: input))
        let fps = self.fps

        async let videoDone: Void = withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let frame = FrameCounter()
            let queue = DispatchQueue(label: "foley.render.video")
            box.videoInput.requestMediaDataWhenReady(on: queue) {
                while box.videoInput.isReadyForMoreMediaData {
                    let i = frame.value
                    if i >= frameCount {
                        box.videoInput.markAsFinished()
                        cont.resume()
                        return
                    }
                    guard let pool = box.adaptor.pixelBufferPool else {
                        cont.resume(throwing: MixRenderError.writerFailed("no pixel buffer pool")); return
                    }
                    var buffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                    guard let buffer else { cont.resume(throwing: MixRenderError.writerFailed("pixel buffer")); return }
                    box.painter.draw(frame: i, fps: fps, into: buffer)
                    box.adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
                    frame.value = i + 1
                    progress(Double(i + 1) / Double(frameCount) * 0.9)
                }
            }
        }
        async let audioDone: Void = withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "foley.render.audio")
            box.audioInput.requestMediaDataWhenReady(on: queue) {
                while box.audioInput.isReadyForMoreMediaData {
                    if let sample = box.readerOutput.copyNextSampleBuffer() {
                        box.audioInput.append(sample)
                    } else {
                        box.audioInput.markAsFinished()
                        if box.reader.status == .failed { cont.resume(throwing: box.reader.error ?? MixRenderError.writerFailed("audio read")) }
                        else { cont.resume() }
                        return
                    }
                }
            }
        }
        _ = try await (videoDone, audioDone)
        writer.endSession(atSourceTime: CMTime(seconds: input.duration, preferredTimescale: 600))
        await writer.finishWriting()
        if writer.status == .failed { throw MixRenderError.writerFailed(writer.error?.localizedDescription ?? "finish") }
        progress(1)
        return outputURL
    }
}

private nonisolated final class FrameCounter: @unchecked Sendable {
    var value = 0
}

/// AVFoundation writer objects are not Sendable; they are only touched from their own serial queues.
private nonisolated final class WriterBox: @unchecked Sendable {
    let writer: AVAssetWriter
    let videoInput: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let audioInput: AVAssetWriterInput
    let reader: AVAssetReader
    let readerOutput: AVAssetReaderTrackOutput
    let painter: FramePainter
    init(writer: AVAssetWriter, videoInput: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor,
         audioInput: AVAssetWriterInput, reader: AVAssetReader, readerOutput: AVAssetReaderTrackOutput, painter: FramePainter) {
        self.writer = writer; self.videoInput = videoInput; self.adaptor = adaptor
        self.audioInput = audioInput; self.reader = reader; self.readerOutput = readerOutput; self.painter = painter
    }
}

/// Core Graphics drawing of one frame. Pure function of (frame, input).
private nonisolated struct FramePainter: Sendable {
    let size: CGSize
    let input: MixVideoInput
    let master: [Float]

    init(size: CGSize, input: MixVideoInput) {
        self.size = size
        self.input = input
        let count = input.envelope.values.map(\.count).max() ?? 0
        master = (0..<count).map { i in
            let values = input.envelope.values.compactMap { i < $0.count ? $0[i] : nil }
            return values.isEmpty ? 0 : min(1, values.reduce(0, +) / Float(max(1, values.count)) * 1.6)
        }
    }

    func level(of pad: MixVideoPad, at time: Double) -> CGFloat {
        guard let env = input.envelope[pad.id], !env.isEmpty else { return 0 }
        let index = min(env.count - 1, Int(time * input.envelopeRate))
        return CGFloat(env[index])
    }

    func draw(frame: Int, fps: Int, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        let time = Double(frame) / Double(fps)
        let w = size.width, h = size.height

        // Background: sceneBg with a soft glow at the top.
        ctx.setFillColor(color(0x0B0F1A))
        ctx.fill(CGRect(origin: .zero, size: size))
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [color(0x15213D), color(0x0B0F1A, alpha: 0)] as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: w / 2, y: h * 0.82), startRadius: 0,
                                   endCenter: CGPoint(x: w / 2, y: h * 0.82), endRadius: w * 0.9, options: [])
        }

        // Title + wordmark (CG coordinates: origin bottom-left).
        drawText("foley", at: CGPoint(x: 80, y: h - 150), size: 44, weight: .semibold, color: color(0xF4F4F5), ctx: ctx)
        drawText(input.title, at: CGPoint(x: 80, y: h - 290), size: 72, weight: .semibold, color: color(0xF4F4F5), ctx: ctx, maxWidth: w - 160)
        drawText("\(input.pads.count) layers · \(format(input.duration))", at: CGPoint(x: 80, y: h - 350), size: 34, weight: .regular, color: color(0xA9B4CC), ctx: ctx)

        // Pads: 2 columns of orbs pulsing with their envelopes.
        let columns = 2
        let rows = max(1, Int((Double(input.pads.count) / Double(columns)).rounded(.up)))
        let cellW = (w - 160) / CGFloat(columns)
        let gridTop = h - 460
        let cellH = min(440, (gridTop - 520) / CGFloat(rows))
        for (i, pad) in input.pads.enumerated() {
            let col = i % columns, row = i / columns
            let centre = CGPoint(x: 80 + cellW * (CGFloat(col) + 0.5), y: gridTop - cellH * (CGFloat(row) + 0.45))
            let lv = level(of: pad, at: time)
            let radius = min(cellH * 0.36, 150) * (0.85 + lv * 0.25)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 40 + lv * 60, color: color(pad.tint.hexBase, alpha: 0.25 + 0.5 * lv))
            ctx.setFillColor(color(pad.tint.hexBase))
            ctx.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            ctx.restoreGState()
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [color(pad.tint.hexHighlight), color(pad.tint.hexBase), color(pad.tint.hexShadow)] as CFArray,
                                         locations: [0, 0.38, 0.78]) {
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
                ctx.clip()
                let focus = CGPoint(x: centre.x - radius * 0.28, y: centre.y + radius * 0.32)
                ctx.drawRadialGradient(gradient, startCenter: focus, startRadius: 0, endCenter: focus, endRadius: radius * 1.5, options: [.drawsAfterEndLocation])
                ctx.restoreGState()
            }
            drawText(pad.name, at: CGPoint(x: centre.x, y: centre.y - radius - 54), size: 32, weight: .medium,
                     color: color(0xF4F4F5, alpha: 0.6 + 0.4 * lv), ctx: ctx, centered: true, maxWidth: cellW - 20)
        }

        // Progress waveform: 48 bars across, played part bright.
        let bars = 48
        let played = input.duration > 0 ? time / input.duration : 0
        let barW = (w - 160) / CGFloat(bars)
        for b in 0..<bars {
            let sampleIndex = master.isEmpty ? 0 : min(master.count - 1, b * master.count / bars)
            let amp = master.isEmpty ? 0.1 : CGFloat(max(0.08, master[sampleIndex]))
            let tint = input.pads.isEmpty ? Tint.blue : input.pads[b * input.pads.count / bars].tint
            let x = 80 + CGFloat(b) * barW + barW * 0.25
            let height = 40 + amp * 160
            let isPlayed = Double(b) / Double(bars) <= played
            ctx.setFillColor(color(tint.hexBase, alpha: isPlayed ? 1 : 0.3))
            let rect = CGRect(x: x, y: 330 - height / 2, width: barW * 0.5, height: height)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barW * 0.25, cornerHeight: barW * 0.25, transform: nil))
            ctx.fillPath()
        }
        drawText("\(format(time)) / \(format(input.duration))", at: CGPoint(x: w - 80, y: 150), size: 30, weight: .regular,
                 color: color(0xA9B4CC), ctx: ctx, rightAligned: true)
        drawText("Sounds generated with ElevenLabs", at: CGPoint(x: 80, y: 150), size: 28, weight: .regular, color: color(0x8B8B94), ctx: ctx)
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down)); return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private func drawText(_ text: String, at point: CGPoint, size: CGFloat, weight: CTFontWeight, color: CGColor,
                          ctx: CGContext, centered: Bool = false, rightAligned: Bool = false, maxWidth: CGFloat? = nil) {
        let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: "SF Pro Display" as CFString,
            kCTFontTraitsAttribute: [kCTFontWeightTrait: weight.rawValue] as CFDictionary,
        ] as CFDictionary), size, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color,
            kCTKernAttributeName as NSAttributedString.Key: size > 60 ? -1.5 : 0,
        ])
        var line = CTLineCreateWithAttributedString(attributed)
        if let maxWidth {
            let truncationToken = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: color]))
            line = CTLineCreateTruncatedLine(line, Double(maxWidth), .end, truncationToken) ?? line
        }
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        var x = point.x
        if centered { x -= width / 2 } else if rightAligned { x -= width }
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: x, y: point.y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

private nonisolated struct CTFontWeight: RawRepresentable, Sendable {
    var rawValue: CGFloat
    static let regular = CTFontWeight(rawValue: 0)
    static let medium = CTFontWeight(rawValue: 0.23)
    static let semibold = CTFontWeight(rawValue: 0.3)
}
