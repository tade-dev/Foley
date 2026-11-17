import Foundation
import SwiftData

@Model
final class SoundScene {
    @Attribute(.unique) var id: UUID
    var title: String
    var sourcePrompt: String
    var moodRaw: String
    var createdAt: Date
    var isDemo: Bool
    @Relationship(deleteRule: .cascade, inverse: \Pad.scene) var pads: [Pad]
    @Relationship(deleteRule: .cascade, inverse: \Mix.scene) var mixes: [Mix]

    var mood: Tint {
        get { Tint(rawValue: moodRaw) ?? .blue }
        set { moodRaw = newValue.rawValue }
    }

    var orderedPads: [Pad] { pads.sorted { $0.sortIndex < $1.sortIndex } }

    init(title: String, sourcePrompt: String, mood: Tint, isDemo: Bool = false) {
        self.id = UUID()
        self.title = title
        self.sourcePrompt = sourcePrompt
        self.moodRaw = mood.rawValue
        self.createdAt = .now
        self.isDemo = isDemo
        self.pads = []
        self.mixes = []
    }
}

@Model
final class Pad {
    @Attribute(.unique) var id: UUID
    var name: String
    var keyword: String           // exact substring of the scene prompt ("" when unmatched)
    var tintRaw: String
    var kindRaw: String
    var spec: SoundSpec
    var cacheKey: String?         // set once a generated file is on disk
    var demoFile: String?         // bundled resource name (no extension) for demo pads
    var volume: Double = 0.8
    var pan: Double = 0           // -1 ... 1
    var version: Int = 1
    var sortIndex: Int = 0
    var scene: SoundScene?

    var tint: Tint { Tint(rawValue: tintRaw) ?? .blue }
    var kind: PadKind { PadKind(rawValue: kindRaw) ?? .loop }

    /// "Loop · 10s" / "One-shot · 4s"
    var meta: String {
        guard let d = spec.duration else { return kind.label }
        return "\(kind.label) · \(d.formatted(.number.precision(.fractionLength(0...1))))s"
    }

    init(name: String, keyword: String, tint: Tint, kind: PadKind, spec: SoundSpec, sortIndex: Int, demoFile: String? = nil) {
        self.id = UUID()
        self.name = name
        self.keyword = keyword
        self.tintRaw = tint.rawValue
        self.kindRaw = kind.rawValue
        self.spec = spec
        self.sortIndex = sortIndex
        self.demoFile = demoFile
    }
}

/// A recorded mix of a scene: the .m4a plus the per-pad level envelope used by the share video.
@Model
final class Mix {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var envelopeFileName: String
    var duration: Double
    var createdAt: Date
    var scene: SoundScene?

    init(fileName: String, envelopeFileName: String, duration: Double) {
        self.id = UUID()
        self.fileName = fileName
        self.envelopeFileName = envelopeFileName
        self.duration = duration
        self.createdAt = .now
    }
}
