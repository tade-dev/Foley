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
    @State private var breathing = false

    private var radius: CGFloat { size / 2 }

    /// True only while something is actually moving. When it is false the timeline pauses and
    /// the view stops redrawing entirely: an orb sitting still should cost nothing.
    private var isMoving: Bool {
        physics.isDragging || physics.speed > 1 || physics.position != .zero
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !isMoving || reduceMotion)) { context in
            ZStack {
                wake
                halo
                orb
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
    //
    // Every layer is a fixed-size circle with a fixed gradient, moved and scaled with transforms.
    // Changing a gradient's size or stops forces Core Graphics to rasterise it again on the CPU
    // every frame, which is enough to starve the main thread and make the whole screen feel stuck.

    /// The light the orb leaves behind. Added rather than painted, so it reads as glow.
    private var wake: some View {
        ZStack {
            ForEach(Array(trail.enumerated()), id: \.offset) { index, point in
                let age = Double(index) / Double(max(trail.count - 1, 1))
                Circle()
                    .fill(RadialGradient(colors: [tint.base, .clear], center: .center,
                                         startRadius: 0, endRadius: radius))
                    .frame(width: size, height: size)
                    .scaleEffect(0.5 + 0.5 * age)
                    .opacity(0.18 * age * age)
                    .offset(x: point.x, y: point.y)
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// Swells with speed, so a hard throw looks like it carries energy.
    private var halo: some View {
        Circle()
            .fill(RadialGradient(
                stops: [.init(color: tint.base, location: 0.35), .init(color: .clear, location: 1)],
                center: .center, startRadius: 0, endRadius: radius * 1.5))
            .frame(width: size * 1.5, height: size * 1.5)
            .scaleEffect(1 + 0.45 * physics.stretch)
            .opacity(0.22 + 0.3 * physics.stretch + 0.1 * excitement)
            .offset(x: physics.position.x, y: physics.position.y)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    /// The body. Stretching is a scale along the direction of travel, not a new path: same look,
    /// none of the per-frame rasterising.
    private var orb: some View {
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: tint.highlight, location: 0),
                    .init(color: tint.base, location: 0.38),
                    .init(color: tint.shadow, location: 0.95),
                ],
                center: UnitPoint(x: 0.36, y: 0.34), startRadius: 0, endRadius: radius * 1.25))
            .frame(width: size, height: size)
            // Stretch along the direction of travel: rotate the travel axis onto x, scale, then
            // rotate back. The two rotations cancel for the gradient, so the highlight stays put
            // instead of spinning with the throw.
            .rotationEffect(.radians(-physics.heading))
            .scaleEffect(x: 1 + physics.stretch * 0.8, y: 1 - physics.stretch * 0.3, anchor: .center)
            .rotationEffect(.radians(physics.heading))
            .scaleEffect(breathing ? 1.02 : 0.98)
            .offset(x: physics.position.x, y: physics.position.y)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }

    /// A specular dot that slides opposite the stretch, like light on a wet surface.
    private var glint: some View {
        let r = radius * 0.16
        return Circle()
            .fill(RadialGradient(colors: [.white, .clear], center: .center, startRadius: 0, endRadius: r))
            .frame(width: r * 2, height: r * 2)
            .opacity(0.5 + 0.3 * excitement)
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

    /// Only records a wake while there is movement worth tracing, and clears it once, not every
    /// frame: appending and emptying on every tick kept the view invalidating forever.
    private func pushTrail() {
        guard !reduceMotion else { return }
        guard physics.isDragging || physics.speed > 60 else {
            if !trail.isEmpty { trail.removeAll() }
            return
        }
        trail.append(physics.position)
        if trail.count > 8 { trail.removeFirst(trail.count - 8) }
    }
}
