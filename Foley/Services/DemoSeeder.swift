import Foundation
import SwiftData

/// Inserts the bundled demo scenes on first launch.
enum DemoSeeder {
    static let fileName = "demo-scenes"

    /// Returns the number of scenes inserted (0 when demo scenes already exist).
    @MainActor
    static func seedIfNeeded(context: ModelContext, bundle: Bundle = .main) throws -> Int {
        var existing = FetchDescriptor<SoundScene>(predicate: #Predicate { $0.isDemo })
        existing.fetchLimit = 1
        guard try context.fetchCount(existing) == 0 else { return 0 }

        let file = try load(from: bundle)
        for (sceneIndex, demo) in file.scenes.enumerated() {
            let scene = SoundScene(title: demo.title, sourcePrompt: demo.sourcePrompt, mood: demo.mood, isDemo: true)
            // Keep the authored order stable in the library: first scene is newest.
            scene.createdAt = Date.now.addingTimeInterval(-Double(sceneIndex) * 60)
            context.insert(scene)
            for (i, s) in demo.sounds.enumerated() {
                let pad = Pad(name: s.name, keyword: s.keyword, tint: s.tint, kind: s.kind,
                              spec: s.spec, sortIndex: i, demoFile: s.file)
                pad.scene = scene
                context.insert(pad)
            }
        }
        try context.save()
        return file.scenes.count
    }

    static func load(from bundle: Bundle = .main) throws -> DemoSceneFile {
        guard let url = bundle.url(forResource: fileName, withExtension: "json")
                ?? bundle.url(forResource: fileName, withExtension: "json", subdirectory: "Demo") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(DemoSceneFile.self, from: Data(contentsOf: url))
    }

    /// Where a bundled demo sound lives. Tries the bundle root, then the Demo folder.
    static func audioURL(file: String, bundle: Bundle = .main) -> URL? {
        guard !file.isEmpty else { return nil }
        return bundle.url(forResource: file, withExtension: "m4a")
            ?? bundle.url(forResource: file, withExtension: "m4a", subdirectory: "Demo")
    }
}
