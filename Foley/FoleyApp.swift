import SwiftData
import SwiftUI

@main
struct FoleyApp: App {
    let container: ModelContainer = {
        do {
            return try ModelContainer(for: SoundScene.self, Pad.self, Mix.self)
        } catch {
            fatalError("Could not create the model container: \(error)")
        }
    }()

    @ViewBuilder private var root: some View {
        #if DEBUG
        if CommandLine.arguments.contains(where: { $0.hasPrefix("-gallery") }) {
            DebugGallery()
        } else {
            Text("Foley")
        }
        #else
        Text("Foley")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            root
                .task {
                    _ = try? DemoSeeder.seedIfNeeded(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}
