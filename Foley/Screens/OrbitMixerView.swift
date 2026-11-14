import SwiftUI

/// Placeholder until Task 14.
struct OrbitMixerView: View {
    var scene: SoundScene
    @Binding var mode: TransportDock.Mode
    var namespace: Namespace.ID
    var body: some View {
        VStack { Spacer(); Text("Orbit mixer").foregroundStyle(Theme.Colors.textPrimary); Button("Grid") { mode = .grid }; Spacer() }
    }
}
