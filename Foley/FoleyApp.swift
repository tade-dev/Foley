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

    var body: some Scene {
        WindowGroup {
            Text("Foley")
                .task {
                    _ = try? DemoSeeder.seedIfNeeded(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}
