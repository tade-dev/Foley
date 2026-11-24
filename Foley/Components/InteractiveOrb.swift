import SwiftUI

/// The home-screen orb, as something you can pick up and throw.
/// Drag it and it stretches along its travel; let go and it springs home, ringing as it lands.
struct InteractiveOrb: View {
    var tint: Tint
    var size: CGFloat
    /// 0–1, how "awake" the orb looks; the composer raises it as the prompt grows.
    var excitement: Double = 0
    /// How far from centre it may be pulled. Kept small enough that the orb and its glow stay
    /// inside the canvas, which clips, and the canvas stays inside the screen.
    var travel: Double = 54
    var onPluck: (Double) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var physics = OrbPhysics()
    @State private var trail: [CGPoint] = []
    @State private var lastTick = Date.now
    @State private var landed = 0

    private var radius: CGFloat { size / 2 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            Canvas { canvas, canvasSize in
                let centre = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                draw(in: &canvas, centre: centre, bounds: canvasSize)
            }
            .onChange(of: context.date) { _, now in advance(to: now) }
        }
        // Width follows the parent: a fixed width wider than the phone would push the whole
        // screen's content out past both edges.
        .frame(maxWidth: .infinity)
        .frame(height: size * 1.75)
        .contentShape(Circle())
        .onAppear { physics.maxOffset = travel }
        .gesture(drag)
        .sensoryFeedback(.impact(weight: .light), trigger: landed)
        .accessibilityLabel("Sound orb")
        .accessibilityHint("Drag to play it")

    }

    // MARK: Drawing

    private func draw(in canvas: inout GraphicsContext, centre: CGPoint, bounds: CGSize) {
        let origin = CGPoint(x: centre.x + physics.position.x, y: centre.y + physics.position.y)
        // The canvas clips, so keep every glow inside it: a gradient cut before it reaches
        // transparent leaves a hard edge, which is what draws the eye to a rectangle.
        let room = min(min(bounds.width, bounds.height) / 2 - 1,
                       min(bounds.width / 2 - abs(physics.position.x),
                           bounds.height / 2 - abs(physics.position.y)))

        // Trail and halo are radial gradients that reach full transparency at their own edge.
        // A blurred shape would be cut off square at the canvas bounds and show its frame.
        if trail.count > 1 {
            canvas.drawLayer { layer in
                layer.blendMode = .plusLighter
                for (index, point) in trail.enumerated() {
                    let age = Double(index) / Double(trail.count - 1)   // 0 oldest, 1 newest
                    let r = radius * (0.45 + 0.55 * age)
                    let at = CGPoint(x: centre.x + point.x, y: centre.y + point.y)
                    layer.fill(Circle().path(in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)),
                               with: .radialGradient(
                                Gradient(colors: [tint.base.opacity(0.16 * age * age), .clear]),
                                center: at, startRadius: 0, endRadius: r))
                }
            }
        }

        // A halo that swells with speed, so a hard throw looks like it carries energy.
        let halo = min(radius * (1.5 + 0.7 * physics.stretch), max(radius * 1.05, room))
        canvas.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.fill(Circle().path(in: CGRect(x: origin.x - halo, y: origin.y - halo,
                                                width: halo * 2, height: halo * 2)),
                       with: .radialGradient(
                        Gradient(stops: [
                            .init(color: tint.base.opacity(0.22 + 0.3 * physics.stretch + 0.1 * excitement), location: 0.35),
                            .init(color: .clear, location: 1),
                        ]),
                        center: origin, startRadius: 0, endRadius: halo))
        }

        // The orb itself, stretched along its direction of travel.
        let path = blobPath(around: origin)
        canvas.fill(path, with: .radialGradient(
            Gradient(stops: [
                .init(color: tint.highlight, location: 0),
                .init(color: tint.base, location: 0.38),
                .init(color: tint.shadow, location: 0.95),
            ]),
            center: CGPoint(x: origin.x - radius * 0.28, y: origin.y - radius * 0.32),
            startRadius: 0, endRadius: radius * 1.25))

        // A specular dot that slides opposite the stretch, like light on a wet surface.
        let glintOffset = CGSize(width: -cos(physics.heading) * radius * 0.12,
                                 height: -sin(physics.heading) * radius * 0.12)
        let glintRadius = radius * 0.16
        let glint = CGRect(x: origin.x - radius * 0.3 + glintOffset.width - glintRadius,
                           y: origin.y - radius * 0.34 + glintOffset.height - glintRadius,
                           width: glintRadius * 2, height: glintRadius * 2)
        canvas.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.fill(Circle().path(in: glint), with: .radialGradient(
                Gradient(colors: [.white.opacity(0.5 + 0.3 * excitement), .clear]),
                center: CGPoint(x: glint.midX, y: glint.midY), startRadius: 0, endRadius: glintRadius))
        }
    }

    /// A circle stretched into an egg along `heading`, by `stretch`.
    private func blobPath(around origin: CGPoint) -> Path {
        var path = Path()
        let steps = 72
        let stretch = reduceMotion ? 0 : physics.stretch
        let breathe = 1 + 0.02 * sin(Date.now.timeIntervalSinceReferenceDate * 1.6)
        for i in 0...steps {
            let angle = Double(i) / Double(steps) * 2 * .pi
            // Longer along the direction of travel, narrower across it.
            let along = cos(angle - physics.heading)
            let r = radius * breathe * (1 + stretch * along * along * (along > 0 ? 1 : 0.55) - stretch * 0.35)
            let point = CGPoint(x: origin.x + cos(angle) * r, y: origin.y + sin(angle) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
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
                let v = CGVector(dx: value.predictedEndTranslation.width - value.translation.width,
                                 dy: value.predictedEndTranslation.height - value.translation.height)
                // A flick's predicted overshoot is a good stand-in for release velocity.
                let release = CGVector(dx: v.dx * 4, dy: v.dy * 4)
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
        if trail.count > 16 { trail.removeFirst(trail.count - 16) }
        if physics.speed < 40, physics.position == .zero { trail.removeAll() }
    }
}
