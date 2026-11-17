import SwiftData
import SwiftUI

/// Screen 09: "Your scenes" with search and scene cards.
struct LibraryView: View {
    @Environment(Router.self) private var router
    @Environment(SceneStore.self) private var store
    @Query(sort: \SoundScene.createdAt, order: .reverse) private var scenes: [SoundScene]
    @State private var search = ""
    @State private var pendingDelete: SoundScene?

    private var filtered: [SoundScene] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? scenes : scenes.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.sourcePrompt.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your scenes").font(Theme.Fonts.screenTitle).tracking(-0.8).foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                CircleIconButton(symbol: "plus", label: "New scene", fill: Theme.Colors.textPrimary, tint: Theme.Colors.bg, size: 52) {
                    router.popToRoot()
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.xs)

            searchField
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, 22)

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(filtered) { scene in
                        SceneCard(scene: scene) {
                            router.autoPlaySceneID = scene.id
                            router.push(.board(scene))
                        }
                        .onTapGesture { router.push(.board(scene)) }
                        .contextMenu {
                            Button("Delete scene", systemImage: "trash", role: .destructive) { pendingDelete = scene }
                        }
                        .scrollTransition(topLeading: .identity, bottomTrailing: .interactive, axis: .vertical) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                .opacity(phase.isIdentity ? 1 : 0.55)
                                .offset(y: phase.value * -8)
                        }
                    }
                    if filtered.isEmpty {
                        Text(search.isEmpty ? "No scenes yet. Describe one to get started." : "No scenes match")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Theme.Colors.bg.ignoresSafeArea())
        .confirmationDialog("Delete this scene?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let s = pendingDelete { store.deleteScene(s) }; pendingDelete = nil }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { Text("Its sounds and mixes go with it.") }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Colors.textTertiary)
            TextField("Search scenes", text: $search)
                .font(.system(size: 17))
                .foregroundStyle(Theme.Colors.textPrimary)
                .tint(Theme.Colors.textPrimary)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.textTertiary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 18).frame(height: 54)
        .foleyGlass(Capsule(), tint: Theme.Colors.surface.opacity(0.6))
        .overlay(Capsule().strokeBorder(Theme.Colors.border))
    }
}
