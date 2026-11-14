import SwiftData
import SwiftUI

@main
struct FoleyApp: App {
    private let container: ModelContainer
    @State private var environment: AppEnvironment

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: SoundScene.self, Pad.self, Mix.self)
        } catch {
            fatalError("Could not create the model container: \(error)")
        }
        self.container = container
        _environment = State(initialValue: AppEnvironment(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(environment)
                .environment(environment.store)
                .environment(environment.engine)
        }
        .modelContainer(container)
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
        if CommandLine.arguments.contains(where: { $0.hasPrefix("-gallery") }) {
            DebugGallery()
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}
