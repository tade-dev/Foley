import SwiftData
import SwiftUI

enum Route: Hashable {
    case library
    case create(initialText: String)
    case board(SoundScene)
    case mixSaved(Mix)
}

/// Navigation state shared by every screen.
@Observable
@MainActor
final class Router {
    var path: [Route] = []
    /// Set by the Library's play button; the Board starts the scene once it is prepared.
    var autoPlaySceneID: UUID?

    func push(_ route: Route) { path.append(route) }
    func pop() { _ = path.popLast() }
    func popToRoot() { path.removeAll() }
    /// Swap the top screen without a push animation (Create → Board).
    func replaceTop(with route: Route) {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            if path.isEmpty { path = [route] } else { path[path.count - 1] = route }
        }
    }
}

struct RootView: View {
    @State private var router = Router()
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    destination(route).toolbar(.hidden, for: .navigationBar)
                }
        }
        .environment(router)
        .preferredColorScheme(.dark)
        .task {
            _ = try? DemoSeeder.seedIfNeeded(context: context)
            openDebugRoute()
        }
    }

    /// DEBUG: `-route library|create|board|board2|mix` opens a screen directly for screenshots.
    private func openDebugRoute() {
        #if DEBUG
        guard let i = CommandLine.arguments.firstIndex(of: "-route"), i + 1 < CommandLine.arguments.count else { return }
        let all = (try? context.fetch(FetchDescriptor<SoundScene>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        let scenes = all.filter(\.isDemo) + all.filter { !$0.isDemo }
        switch CommandLine.arguments[i + 1] {
        case "library": router.push(.library)
        case "create":
            let custom = CommandLine.arguments.firstIndex(of: "-prompt").flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil }
            router.push(.create(initialText: custom ?? scenes.first?.sourcePrompt ?? "Campfire at night, crickets and an owl"))
        case "board": if let s = scenes.first { router.push(.board(s)) }
        case "board2": if scenes.count > 1 { router.push(.board(scenes[1])) }
        case "mix":
            let mixes = (try? context.fetch(FetchDescriptor<Mix>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
            if let mix = mixes.first, let scene = mix.scene {
                router.path = [.board(scene), .mixSaved(mix)]
            }
        default: break
        }
        #endif
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .library: LibraryView()
        case .create(let text): CreateView(initialText: text)
        case .board(let scene): BoardView(scene: scene)
        case .mixSaved(let mix): MixSavedView(mix: mix)
        }
    }
}
