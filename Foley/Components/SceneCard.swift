import SwiftUI

/// Library row: mood-tinted gradient, a row of small orbs, title, meta, play.
struct SceneCard: View {
    var scene: SoundScene
    var onPlay: () -> Void

    private var meta: String {
        var parts = ["\(scene.pads.count) sound\(scene.pads.count == 1 ? "" : "s")"]
        if !scene.mixes.isEmpty { parts.append("\(scene.mixes.count) mix\(scene.mixes.count == 1 ? "" : "es")") }
        parts.append(scene.createdAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ForEach(scene.orderedPads.prefix(6)) { pad in
                        Circle()
                            .fill(pad.tint.orbGradient(diameter: 36))
                            .frame(width: 36, height: 36)
                            .shadow(color: pad.tint.glow, radius: 6)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(scene.title).font(Theme.Fonts.cardTitle).foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(meta).font(.system(size: 14)).foregroundStyle(Theme.Colors.textSecondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CircleIconButton(symbol: "play.fill", label: "Play \(scene.title)", fill: Theme.Colors.surfaceRaised, size: 48, action: onPlay)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Colors.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .fill(LinearGradient(colors: [scene.mood.shadow.opacity(0.55), .clear],
                                             startPoint: .topLeading, endPoint: UnitPoint(x: 0.7, y: 0.9)))
                }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Colors.border))
        .contentShape(.rect(cornerRadius: Theme.Radius.card))
    }
}
