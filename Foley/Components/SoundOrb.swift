import SwiftUI

/// The visual heart of Foley: a glowing sound orb.
/// - idle: slow breathing, dimmed
/// - generating: blurred, morphing blob
/// - ready: solid orb (pops in when it arrives)
/// - playing: scale + glow follow the live level (0–1)
struct SoundOrb: View {
    enum Mode: Equatable { case idle, generating, ready, playing }

    var tint: Tint
    var size: CGFloat = 96
    var mode: Mode = .ready
    var level: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popTrigger = 0

    var body: some View {
        ZStack {
            switch mode {
            case .generating:
                GeneratingBlob(tint: tint, size: size * 0.8, animate: !reduceMotion)
                    .transition(.opacity)
            case .idle:
                orb.opacity(0.5)
                    .phaseAnimator(reduceMotion ? [1.0] : [0.94, 1.05]) { view, scale in
                        view.scaleEffect(scale)
                    } animation: { _ in .easeInOut(duration: 2.5) }
            case .ready:
                orb
                    .keyframeAnimator(initialValue: 1.0, trigger: popTrigger) { view, scale in
                        view.scaleEffect(scale)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(0.6, duration: 0.0001)
                            SpringKeyframe(1.08, duration: 0.28, spring: .bouncy)
                            SpringKeyframe(1.0, duration: 0.22, spring: .smooth)
                        }
                    }
                    .transition(.opacity)
            case .playing:
                orb
                    .scaleEffect(1 + level * 0.12)
                    .shadow(color: tint.base.opacity(0.35 + level * 0.4), radius: 16 + level * 28)
                    .animation(Motion.level, value: level)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: mode) { old, new in
            if new == .ready, old == .generating, !reduceMotion { popTrigger += 1 }
        }
    }

    private var orb: some View {
        Circle()
            .fill(tint.orbGradient(diameter: size))
            .frame(width: size, height: size)
            .shadow(color: tint.glow, radius: 20)
    }
}

/// Breathing, shape-shifting blob shown while a sound generates.
/// Period 2.8–3.6 s chosen from the tint, so neighbouring pads drift apart.
private struct GeneratingBlob: View {
    var tint: Tint
    var size: CGFloat
    var animate: Bool

    private var period: Double { 2.8 + 0.16 * Double(tint.index) }

    var body: some View {
        TimelineView(.animation(paused: !animate)) { ctx in
            let t = animate ? ctx.date.timeIntervalSinceReferenceDate * (2 * .pi / period) : 0
            Canvas { gc, canvasSize in
                let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let r = size / 2 * (0.9 + 0.08 * sin(t))
                var path = Path()
                let steps = 64
                for i in 0...steps {
                    let a = Double(i) / Double(steps) * .pi * 2
                    let wobble = 1 + 0.08 * sin(a * 3 + t * 1.7) + 0.05 * cos(a * 2 - t * 1.3)
                    let p = CGPoint(x: c.x + cos(a) * r * wobble, y: c.y + sin(a) * r * wobble)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                path.closeSubpath()
                gc.addFilter(.blur(radius: 7))
                gc.fill(path, with: .radialGradient(
                    Gradient(colors: [tint.highlight, tint.base, tint.shadow.opacity(0.2)]),
                    center: CGPoint(x: c.x - r * 0.25, y: c.y - r * 0.3),
                    startRadius: 0, endRadius: r * 1.3))
            }
        }
        .frame(width: size * 2.2, height: size * 2.2)
    }
}

#Preview("SoundOrb modes") {
    HStack(spacing: 24) {
        SoundOrb(tint: .amber, size: 72, mode: .idle)
        SoundOrb(tint: .teal, size: 72, mode: .generating)
        SoundOrb(tint: .blue, size: 72, mode: .ready)
        SoundOrb(tint: .lavender, size: 72, mode: .playing, level: 0.7)
    }
    .padding(40)
    .background(Theme.Colors.sceneBg)
}
