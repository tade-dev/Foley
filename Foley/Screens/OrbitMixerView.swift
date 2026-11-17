import SwiftUI

/// Screen 06: pads orbit "you"; closer is louder, sides pan. Drag to mix.
struct OrbitMixerView: View {
    var scene: SoundScene
    @Binding var mode: TransportDock.Mode
    var namespace: Namespace.ID

    @Environment(SceneStore.self) private var store
    @Environment(AudioEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var angles: [UUID: Double] = [:]      // radians, 0 = up, clockwise
    @State private var dragging: UUID?
    @State private var dragOffset: CGSize = .zero
    @State private var haptic = 0
    @State private var lastQuarter: [UUID: Int] = [:]

    private let minRadius: CGFloat = 60
    private let maxRadius: CGFloat = 160
    private let area: CGFloat = 350

    private var pads: [Pad] { scene.orderedPads }

    var body: some View {
        VStack(spacing: 0) {
            orbitArea
                .frame(height: area + 40)
                .padding(.top, 8)
            HStack(spacing: 28) {
                Label("Closer = louder", systemImage: "arrow.down")
                Label("Sides = pan", systemImage: "arrow.left.and.right")
            }
            .font(.system(size: 15)).foregroundStyle(Theme.Colors.sceneSecondary)
            .padding(.top, 6)
            Spacer(minLength: 12)
            masterCard
                .padding(.horizontal, Theme.Space.l)
            segmented
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, 14)
                .padding(.bottom, Theme.Space.s)
        }
        .sensoryFeedback(.selection, trigger: haptic)
        .onAppear { seedAngles() }
        #if DEBUG
        .task { await runDemoIfNeeded() }
        #endif
    }

    // MARK: Orbit

    private var orbitArea: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                ForEach([minRadius, (minRadius + maxRadius) / 2, maxRadius], id: \.self) { r in
                    Circle().strokeBorder(Theme.Colors.sceneBorder.opacity(r == maxRadius ? 1 : 0.7),
                                          style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                        .frame(width: r * 2, height: r * 2)
                        .position(centre)
                }
                Text("L").position(x: centre.x - maxRadius - 18, y: centre.y)
                Text("R").position(x: centre.x + maxRadius + 18, y: centre.y)

                if let id = dragging, let pad = pads.first(where: { $0.id == id }) {
                    let p = position(for: pad, centre: centre)
                    Path { path in path.move(to: centre); path.addLine(to: p) }
                        .stroke(pad.tint.base.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }

                Text("YOU")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.Colors.bg)
                    .frame(width: 64, height: 64)
                    .background(Theme.Colors.textPrimary, in: .circle)
                    .shadow(color: Theme.Colors.textPrimary.opacity(0.25), radius: 16)
                    .position(centre)
                    .accessibilityHidden(true)

                ForEach(pads) { pad in
                    let p = position(for: pad, centre: centre)
                    OrbitNode(pad: PadDisplay(pad, status: store.status(of: pad)),
                              level: Double(engine.levels[pad.id] ?? 0),
                              volume: pad.volume, pan: pad.pan,
                              isDragging: dragging == pad.id,
                              namespace: namespace, isSource: mode == .orbit)
                        .position(x: p.x, y: p.y + 10)
                        .zIndex(dragging == pad.id ? 10 : 1)
                        .gesture(dragGesture(for: pad, centre: centre))
                        .onTapGesture { store.toggle(pad) }
                        .accessibilityAdjustableAction { direction in
                            let delta = direction == .increment ? 0.1 : -0.1
                            apply(volume: pad.volume + delta, pan: pad.pan, to: pad)
                        }
                        .accessibilityAddTraits(.isButton)
                        .animation(dragging == pad.id ? nil : Motion.spring, value: pad.volume)
                        .animation(dragging == pad.id ? nil : Motion.spring, value: pad.pan)
                }
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Theme.Colors.sceneSecondary)
            .coordinateSpace(name: "orbit")
        }
    }

    /// Square-root mapping: the 0.8 default sits near the middle ring instead of hugging the centre.
    private func radius(for volume: Double) -> CGFloat {
        minRadius + CGFloat((1 - max(0, min(1, volume))).squareRoot()) * (maxRadius - minRadius)
    }

    private func volume(for distance: CGFloat) -> Double {
        let t = Double((max(distance, minRadius) - minRadius) / (maxRadius - minRadius))
        return 1 - min(1, t * t)
    }

    private func position(for pad: Pad, centre: CGPoint) -> CGPoint {
        let a = angles[pad.id] ?? 0
        let r = radius(for: pad.volume) + (dragging == pad.id ? rubberBand(dragOffset) : 0)
        return CGPoint(x: centre.x + sin(a) * r, y: centre.y - cos(a) * r)
    }

    /// Extra distance beyond the outer ring, softened to a quarter.
    private func rubberBand(_ offset: CGSize) -> CGFloat { offset.width }

    private func dragGesture(for pad: Pad, centre: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("orbit"))
            .onChanged { value in
                dragging = pad.id
                let dx = value.location.x - centre.x
                let dy = value.location.y - centre.y - 10
                let d = max(1, hypot(dx, dy))
                angles[pad.id] = atan2(dx, -dy)
                let clamped = min(d, maxRadius)
                dragOffset = CGSize(width: d > maxRadius ? (d - maxRadius) * 0.25 : 0, height: 0)
                let volume = volume(for: clamped)
                let pan = max(-1, min(1, Double(dx / maxRadius)))
                apply(volume: max(0.05, volume), pan: pan, to: pad)
                let quarter = Int((volume * 100).rounded() / 25)
                if lastQuarter[pad.id] != quarter { lastQuarter[pad.id] = quarter; haptic += 1 }
            }
            .onEnded { _ in
                withAnimation(Motion.spring) { dragOffset = .zero; dragging = nil }
            }
    }

    private func apply(volume: Double, pan: Double, to pad: Pad) {
        let v = max(0.05, min(1, volume)), p = max(-1, min(1, pan))
        pad.volume = v
        pad.pan = p
        engine.setVolume(v, pan: p, for: pad.id)
    }

    /// Untouched pads fan out around the circle; panned pads sit where their pan puts them.
    private func seedAngles() {
        for (i, pad) in pads.enumerated() where angles[pad.id] == nil {
            if abs(pad.pan) > 0.02 {
                angles[pad.id] = asin(max(-1, min(1, pad.pan))) * (i.isMultiple(of: 2) ? 1 : -1) + (i.isMultiple(of: 2) ? 0 : .pi)
            } else {
                angles[pad.id] = (Double(i) / Double(max(pads.count, 1))) * 2 * .pi - .pi / 6
            }
            engine.setVolume(pad.volume, pan: pad.pan, for: pad.id)
        }
    }

    #if DEBUG
    /// Animates one node being dragged out to quiet and back in to loud, for the demo recording.
    /// Only one node moves, so the others keep their spacing and the labels stay readable.
    private func runDemoIfNeeded() async {
        guard DemoDirector.isRunning("orbit"), let subject = pads.first else { return }
        await DemoDirector.pause(1.8)

        let home = angles[subject.id] ?? 0
        dragging = subject.id

        // Out: quieter and panned left, drifting only slightly off its own angle.
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            let eased = step * step * (3 - 2 * step)
            angles[subject.id] = home - 0.22 * eased
            apply(volume: 0.8 - 0.65 * eased, pan: -0.8 * eased, to: subject)
            await DemoDirector.pause(0.04)
        }
        await DemoDirector.pause(1.3)

        // Back in: louder and panned right.
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            let eased = step * step * (3 - 2 * step)
            angles[subject.id] = home - 0.22 + 0.44 * eased
            apply(volume: 0.15 + 0.85 * eased, pan: -0.8 + 1.6 * eased, to: subject)
            await DemoDirector.pause(0.04)
        }
        await DemoDirector.pause(1.4)

        withAnimation(Motion.spring) { dragging = nil }
        await DemoDirector.pause(1.6)
        resetForDemo()
        withAnimation(Motion.spring) { angles[subject.id] = home }
    }

    private func resetForDemo() {
        withAnimation(Motion.spring) {
            for pad in pads {
                pad.volume = 0.8; pad.pan = 0
                engine.setVolume(0.8, pan: 0, for: pad.id)
            }
        }
    }
    #endif

    // MARK: Master + segmented

    private var masterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Master volume").font(.system(size: 17)).foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("\(Int(engine.masterVolume * 100))%").font(.system(size: 17)).monospacedDigit().foregroundStyle(Theme.Colors.sceneSecondary)
            }
            Slider(value: Binding(get: { engine.masterVolume }, set: { engine.masterVolume = $0 }), in: 0...1)
                .tint(Theme.Colors.textPrimary)
                .accessibilityLabel("Master volume")
        }
        .padding(20)
        .background(Theme.Colors.padSurface.opacity(0.7), in: .rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Colors.sceneBorder))
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            segment("Grid", .grid)
            segment("Orbit", .orbit)
        }
        .padding(5)
        .foleyGlass(Capsule(), tint: Theme.Colors.dockFill)
        .overlay(Capsule().strokeBorder(Theme.Colors.dockBorder))
    }

    private func segment(_ title: String, _ m: TransportDock.Mode) -> some View {
        Button { withAnimation(Motion.seg) { mode = m } } label: {
            Text(title).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(mode == m ? Theme.Colors.bg : Theme.Colors.sceneSecondary)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background { if mode == m { Capsule().fill(Theme.Colors.textPrimary) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == m ? .isSelected : [])
    }
}
