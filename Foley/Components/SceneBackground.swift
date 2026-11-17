import SwiftUI

/// The board's living background: a mesh over `sceneBg` whose glow leans toward the playing pads' tints.
struct SceneBackground: View {
    var mood: Tint
    var active: [(tint: Tint, level: Double)] = []

    private var glow: Color {
        var color = Theme.Colors.sceneGlow.mix(with: mood.base, by: 0.12)
        let total = active.reduce(0) { $0 + $1.level }
        guard total > 0 else { return color }
        for (tint, level) in active where level > 0 {
            color = color.mix(with: tint.base, by: 0.22 * min(level * 1.5, 1) / max(Double(active.count), 1))
        }
        return color
    }

    private var key: Int { active.reduce(0) { $0 &+ Int($1.level * 20) &* 31 &+ $1.tint.index } }

    var body: some View {
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.45], [0.5, 0.4], [1, 0.45],
            [0, 1], [0.5, 1], [1, 1],
        ], colors: [
            glow, glow.mix(with: Theme.Colors.sceneBg, by: 0.3), glow.mix(with: Theme.Colors.sceneBg, by: 0.5),
            Theme.Colors.sceneBg.mix(with: glow, by: 0.35), Theme.Colors.sceneBg.mix(with: glow, by: 0.2), Theme.Colors.sceneBg.mix(with: glow, by: 0.3),
            Theme.Colors.sceneBg, Theme.Colors.sceneBg, Theme.Colors.sceneBg,
        ])
        .animation(.easeOut(duration: 0.35), value: key)
        .ignoresSafeArea()
    }
}
