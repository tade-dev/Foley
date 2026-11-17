import Foundation

/// Shape of Resources/Demo/demo-scenes.json: the two scenes bundled so the app plays with no keys.
nonisolated struct DemoSceneFile: Codable, Sendable {
    var scenes: [DemoScene]
}

nonisolated struct DemoScene: Codable, Sendable {
    var title: String
    var sourcePrompt: String
    var mood: Tint
    var sounds: [DemoSound]
}

nonisolated struct DemoSound: Codable, Sendable {
    var name: String
    var keyword: String
    var tint: Tint
    var kind: PadKind
    var prompt: String
    var duration: Double
    var file: String

    var spec: SoundSpec { SoundSpec(prompt: prompt, duration: duration, loop: kind == .loop) }
}
