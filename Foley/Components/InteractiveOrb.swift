import SwiftUI

/// The home-screen orb, as something you can pick up and throw.
/// Drag it and it stretches along its travel with a luminous wake; let go and a spring pulls
/// it home, ringing as it lands.
///
/// Everything is drawn with plain views rather than a `Canvas`, because a canvas clips to its
/// own bounds: the orb would be sliced flat the moment it was dragged past the edge.
struct InteractiveOrb: View {
    var tint: Tint
    var size: CGFloat
    /// 0–1, how "awake" the orb looks; the composer raises it as the prompt grows.
    var excitement: Double = 0
    /// How far from centre the spring will let it rest. A drag may stretch past this, but
    /// `OrbPhysics` rubber-bands and caps it.
    var travel: Double = 92
    var onPluck: (Double) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var physics = OrbPhysics()
    @State private var trail: [CGPoint] = []
    @State private var lastTick = Date.now
    @State private var landed = 0

    private var radius: CGFloat { size / 2 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            ZStack {
                wake
                halo
                body(for: context.date)
                glint
            }
            .onChange(of: context.date) { _, now in advance(to: now) }
        }
        // Layout footprint only. The orb draws outside this when thrown, and nothing clips it.
        .frame(width: size * 1.5, height: size * 1.5)
        .contentShape(Circle())
        .gesture(drag)
        .onAppear { physics.maxOffset = travel }
        .sensoryFeedback(.impact(weight: .light), trigger: landed)
        .accessibilityLabel("Sound orb")
        .accessibilityHint("Drag to play it")
    }

    // MARK: Layers

    /// The light the orb leaves behind. Added rather than painted, so it reads as glow.
    private var wake: some View {
        ZStack {
            ForEach(Array(trail.enumerated()), id: \.offset) { index, point in
                let age = Double(index) / Double(max(trail.count - 1, 1))
                let r = radius * (0.5 + 0.5 * age)
                Circle()
                    .fill(RadialGradient(colors: [tint.base.opacity(0.18 * age * age), .clear],
                                         center: .center, startRadius: 0, endRadius: r))
                    .frame(width: r * 2, height: r * 2)
                    .offset(x: point.x, y: point.y)
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// Swells with speed, so a hard throw looks like it carries energy.
    private var halo: some View {
        let reach = radius * (1.5 + 0.7 * physics.stretch)
        return Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: tint.base.opacity(0.22 + 0.3 * physics.stretch + 0.1 * excitement), location: 0.35),
                    .init(color: .clear, location: 1),
                ],
                center: .center, startRadius: 0, endRadius: reach))
            .frame(width: reach * 2, height: reach * 2)
            .offset(x: physics.position.x, y: physics.position.y)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    private func body(for date: Date) -> some View {
        OrbBlob(stretch: reduceMotion ? 0 : physics.stretch,
                heading: physics.heading,
                breath: reduceMotion ? 1 : 1 + 0.02 * sin(date.timeIntervalSinceReferenceDate * 1.6))
            .fill(RadialGradient(
                stops: [
                    .init(color: tint.highlight, location: 0),
                    .init(color: tint.base, location: 0.38),
                    .init(color: tint.shadow, location: 0.95),
                ],
                center: UnitPoint(x: 0.36, y: 0.34), startRadius: 0, endRadius: radius * 1.25))
            .frame(width: size, height: size)
            .offset(x: physics.position.x, y: physics.position.y)
    }

    /// A specular dot that slides opposite the stretch, like light on a wet surface.
    private var glint: some View {
        let r = radius * 0.16
        return Circle()
            .fill(RadialGradient(colors: [.white.opacity(0.5 + 0.3 * excitement), .clear],
                                 center: .center, startRadius: 0, endRadius: r))
            .frame(width: r * 2, height: r * 2)
            .offset(x: physics.position.x - radius * 0.3 - cos(physics.heading) * radius * 0.12,
                    y: physics.position.y - radius * 0.34 - sin(physics.heading) * radius * 0.12)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    // MARK: Motion

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !physics.isDragging { physics.beginDrag() }
                physics.drag(to: CGPoint(x: value.translation.width, y: value.translation.height))
                pushTrail()
            }
            .onEnded { value in
                // A flick's predicted overshoot is a good stand-in for release velocity.
                let overshoot = CGVector(dx: value.predictedEndTranslation.width - value.translation.width,
                                         dy: value.predictedEndTranslation.height - value.translation.height)
                let release = CGVector(dx: overshoot.dx * 4, dy: overshoot.dy * 4)
                physics.release(velocity: release)
                let speed = (release.dx * release.dx + release.dy * release.dy).squareRoot()
                onPluck(max(speed, 180))        // even a tap should make a sound
                landed += 1
            }
    }

    private func advance(to now: Date) {
        let dt = min(1 / 30, now.timeIntervalSince(lastTick))
        lastTick = now
        guard dt > 0 else { return }
        physics.step(dt: dt)
        if !physics.isDragging { pushTrail() }
    }

    private func pushTrail() {
        guard !reduceMotion else { return }
        trail.append(physics.position)
        if trail.count > 10 { trail.removeFirst(trail.count - 10) }
        if physics.speed < 40, physics.position == .zero { trail.removeAll() }
    }
}

/// A circle stretched into an egg along `heading`, by `stretch`.
private nonisolated struct OrbBlob: Shape {
    var stretch: Double
    var heading: Double
    var breath: Double

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2
        var path = Path()
        let steps = 72
        for i in 0...steps {
            let angle = Double(i) / Double(steps) * 2 * .pi
            // Longer along the direction of travel, narrower across it.
            let along = cos(angle - heading)
            let lobe = along > 0 ? 1.0 : 0.55
            let r = base * breath * (1 + stretch * along * along * lobe - stretch * 0.35)
            let point = CGPoint(x: centre.x + cos(angle) * r, y: centre.y + sin(angle) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
