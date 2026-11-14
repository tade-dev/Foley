import SwiftUI

/// One keyword chip in flight from the prompt to its pad slot.
struct FlightItem: Identifiable, Equatable {
    var id: UUID
    var name: String
    var tint: Tint
    var from: CGRect
    var to: CGRect
}

/// Draws the flying chips above the create screen. `flying` moves them from `from` to `to`,
/// staggered by `Motion.stagger`; ids in `hidden` fade out (their pad is ready).
struct FlightOverlay: View {
    var items: [FlightItem]
    var flying: Bool
    var hidden: Set<UUID>

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let rect = flying ? item.to : item.from
                SoundChip(name: item.name, tint: item.tint, isNew: flying)
                    .frame(width: item.from.width, height: item.from.height)
                    .position(x: rect.midX, y: rect.midY)
                    .scaleEffect(flying ? 0.92 : 1)
                    .shadow(color: item.tint.glow, radius: flying ? 14 : 0)
                    .opacity(hidden.contains(item.id) ? 0 : 1)
                    .animation(Motion.spring.delay(Double(index) * Motion.stagger), value: flying)
                    .animation(.easeOut(duration: 0.35), value: hidden)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Collects frames of chips (typing layout) and pad slots (generating layout), keyed by sound index.
struct FramesKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Resolves anchors collected under `FramesKey` to rects in this view's coordinate space.
    func resolveFrames(_ onChange: @escaping ([Int: CGRect]) -> Void) -> some View {
        overlayPreferenceValue(FramesKey.self) { anchors in
            GeometryReader { geo in
                let rects = anchors.mapValues { geo[$0] }
                Color.clear
                    .onChange(of: rects, initial: true) { _, new in onChange(new) }
            }
            .allowsHitTesting(false)
        }
    }
}
