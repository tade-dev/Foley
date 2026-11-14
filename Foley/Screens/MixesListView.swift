import SwiftUI

/// Placeholder until Task 16.
struct MixesListView: View {
    var scene: SoundScene
    var body: some View { Text("\(scene.mixes.count) mixes").foregroundStyle(Theme.Colors.textPrimary) }
}
