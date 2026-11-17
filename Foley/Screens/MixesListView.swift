import SwiftUI

/// A scene's saved mixes, newest first. Tap to reopen, swipe to delete.
struct MixesListView: View {
    var scene: SoundScene

    @Environment(Router.self) private var router
    @Environment(SceneStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var mixes: [Mix] { scene.mixes.sorted { $0.createdAt > $1.createdAt } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mixes").font(Theme.Fonts.cardTitle).foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Space.l).padding(.top, 26)
            if mixes.isEmpty {
                Text("No mixes yet. Tap Rec on the board to record one.")
                    .font(.system(size: 15)).foregroundStyle(Theme.Colors.sceneSecondary)
                    .padding(Theme.Space.l)
                Spacer()
            } else {
                List {
                    ForEach(mixes) { mix in
                        Button {
                            dismiss()
                            router.push(.mixSaved(mix))
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.Colors.textPrimary)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.Colors.padSurface, in: .rect(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(format(mix.duration)).font(.system(size: 17, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.Colors.textPrimary)
                                    Text(mix.createdAt.formatted(.relative(presentation: .named))).font(.system(size: 14)).foregroundStyle(Theme.Colors.sceneSecondary)
                                }
                                Spacer()
                                Image(systemName: "play.fill").foregroundStyle(Theme.Colors.sceneSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Theme.Colors.sheet)
                        .listRowSeparatorTint(Theme.Colors.sceneBorder)
                    }
                    .onDelete { offsets in
                        for i in offsets { store.deleteMix(mixes[i]) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.Colors.sheet.ignoresSafeArea())
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down)); return String(format: "%d:%02d", s / 60, s % 60)
    }
}
