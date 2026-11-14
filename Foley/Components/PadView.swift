import SwiftUI

/// What a pad needs to draw itself. Keeps the view independent of SwiftData,
/// so previews and the gallery work without a model container.
struct PadDisplay: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var meta: String          // "Loop · 10s"
    var tint: Tint
    var kind: PadKind
    var status: PadStatus
}

extension PadDisplay {
    init(_ pad: Pad, status: PadStatus) {
        self.init(id: pad.id, name: pad.name, meta: pad.meta, tint: pad.tint, kind: pad.kind, status: status)
    }
}

struct PadView: View {
    var pad: PadDisplay
    var level: Double = 0          // live level 0–1 while playing
    var loopProgress: Double = 0   // 0–1 position in the loop
    var onTap: () -> Void = {}
    var onEdit: () -> Void = {}
    var onRetry: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shake = 0
    @State private var pressed = false
    @State private var editTrigger = 0

    private var isPlaying: Bool { pad.status == .playing }
    private var isFailed: Bool { if case .failed = pad.status { true } else { false } }
    private var isBusy: Bool { pad.status == .queued || pad.status == .generating }

    var body: some View {
        card
            .buttonStyle(PadPressStyle(isPressed: $pressed))
            .disabled(isBusy)
            .simultaneousGesture(longPress)
            .modifier(ShakeModifier(trigger: shake))
            .onChange(of: isFailed, shakeIfFailed)
            .sensoryFeedback(.success, trigger: pad.status, condition: becameReady)
            .sensoryFeedback(.error, trigger: isFailed) { _, new in new }
            .sensoryFeedback(.impact(weight: .medium), trigger: editTrigger)
            .animation(Motion.spring, value: pad.status)
            .accessibilityLabel("\(pad.name), \(pad.kind == .loop ? "loop" : "one-shot")")
            .accessibilityValue(isPlaying ? "playing" : "not playing")
            .accessibilityAction(named: "Edit", onEdit)
    }

    private var card: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                orbLayer
                    .scaleEffect(pressed ? 0.94 : 1)
                    .animation(Motion.quick.delay(0.04), value: pressed)   // the orb lags the card
                VStack(alignment: .leading) {
                    topRow
                    Spacer(minLength: 0)
                    labels
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.padHeight)
            .background(background, in: .rect(cornerRadius: Theme.Radius.pad))
            .overlay(border)
            .clipShape(.rect(cornerRadius: Theme.Radius.pad))
            .shadow(color: isPlaying ? pad.tint.glow : .clear, radius: 18)
            .contentShape(.rect(cornerRadius: Theme.Radius.pad))
        }
    }

    private var longPress: some Gesture {
        LongPressGesture(minimumDuration: 0.4).onEnded { _ in
            guard !isBusy else { return }
            editTrigger += 1
            onEdit()
        }
    }

    private func shakeIfFailed(_ old: Bool, _ failed: Bool) {
        if failed, !reduceMotion { shake += 1 }
    }

    private func becameReady(_ old: PadStatus, _ new: PadStatus) -> Bool {
        new == .ready && (old == .generating || old == .queued)
    }

    // MARK: Layers

    @ViewBuilder private var orbLayer: some View {
        switch pad.status {
        case .queued:
            SoundOrb(tint: pad.tint, size: 38, mode: .generating)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 30)
        case .generating:
            SoundOrb(tint: pad.tint, size: 82, mode: .generating)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 30)
        case .ready:
            SoundOrb(tint: pad.tint, size: 96, mode: .ready)
                .opacity(0.55)
                .offset(x: 16, y: -16)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        case .playing:
            ZStack {
                if pad.kind == .loop { LoopRing(tint: pad.tint, progress: loopProgress) }
                SoundOrb(tint: pad.tint, size: 100, mode: .playing, level: level)
            }
            .offset(x: 10, y: -10)
        case .failed:
            EmptyView()
        }
    }

    @ViewBuilder private var topRow: some View {
        switch pad.status {
        case .ready:
            Image(systemName: pad.kind.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.35), in: .circle)
        case .playing:
            MiniMeter(level: level)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Colors.error)
                .frame(width: 28, height: 28)
                .background(Theme.Colors.error.opacity(0.16), in: .circle)
        default:
            Color.clear.frame(height: 28)
        }
    }

    @ViewBuilder private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pad.name).font(Theme.Fonts.padName).lineLimit(1)
            switch pad.status {
            case .queued:
                Text("Queued").font(Theme.Fonts.meta).foregroundStyle(Theme.Colors.sceneSecondary)
            case .generating:
                Text("Generating…").font(Theme.Fonts.meta).foregroundStyle(Theme.Colors.sceneSecondary)
                    .phaseAnimator(reduceMotion ? [1.0] : [0.45, 1.0]) { v, o in v.opacity(o) } animation: { _ in .easeInOut(duration: 0.8) }
            case .failed:
                Text("Couldn't make this one").font(Theme.Fonts.meta).foregroundStyle(Theme.Colors.failedText)
                Button("Retry", action: onRetry)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.bg)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Theme.Colors.textPrimary, in: .capsule)
                    .padding(.top, 6)
                    .buttonStyle(.plain)
            case .playing:
                Text(pad.kind == .loop ? "Looping" : "Playing").font(Theme.Fonts.meta).foregroundStyle(Theme.Colors.playingMeta)
            case .ready:
                Text(pad.meta).font(Theme.Fonts.meta).foregroundStyle(Theme.Colors.sceneSecondary)
            }
        }
        .foregroundStyle(Theme.Colors.textPrimary)
    }

    private var background: Color {
        switch pad.status {
        case .playing: Theme.Colors.padActive
        case .failed: Theme.Colors.failedFill
        case .queued: .clear
        case .generating: Theme.Colors.padSurface.opacity(0.6)
        case .ready: Theme.Colors.padSurface
        }
    }

    @ViewBuilder private var border: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.pad)
        switch pad.status {
        case .playing: shape.strokeBorder(pad.tint.base, lineWidth: 1.5)
        case .failed: shape.strokeBorder(Theme.Colors.failedBorder, lineWidth: 1)
        case .queued: shape.strokeBorder(Theme.Colors.queuedBorder, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        default: shape.strokeBorder(Theme.Colors.sceneBorder, lineWidth: 1)
        }
    }
}

/// Dashed ring that rotates with the loop position.
struct LoopRing: View {
    var tint: Tint
    var progress: Double
    var body: some View {
        Circle()
            .strokeBorder(tint.base, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            .frame(width: 122, height: 122)
            .rotationEffect(.degrees(progress * 360))
    }
}

/// Three small white bars that bounce with the pad's level.
struct MiniMeter: View {
    var level: Double
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                let factor = [0.8, 1.0, 0.65][i]
                Capsule().fill(Theme.Colors.textPrimary)
                    .frame(width: 4, height: max(5, 22 * level * factor))
            }
        }
        .frame(height: 28, alignment: .bottom)
        .animation(.interactiveSpring(response: 0.1), value: level)
        .accessibilityHidden(true)
    }
}

/// One horizontal shake (3 oscillations, 6 pt) when a pad fails.
private struct ShakeModifier: ViewModifier {
    var trigger: Int
    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(-6, duration: 0.06); SpringKeyframe(6, duration: 0.06)
                SpringKeyframe(-4, duration: 0.06); SpringKeyframe(4, duration: 0.06)
                SpringKeyframe(0, duration: 0.08)
            }
        }
    }
}

/// Scales the card on press and reports the pressed state so the orb can lag behind.
private struct PadPressStyle: ButtonStyle {
    @Binding var isPressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, new in isPressed = new }
    }
}

#Preview("Pad states") {
    let states: [PadStatus] = [.queued, .generating, .ready, .playing, .failed("timeout")]
    ScrollView {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            ForEach(Array(states.enumerated()), id: \.offset) { i, s in
                PadView(pad: PadDisplay(name: ["Waves on hull", "Heavy rain", "Thunder crack", "Howling wind", "Grumpy cat"][i],
                                        meta: "Loop · 12s",
                                        tint: [.sky, .teal, .blue, .lavender, .pink][i],
                                        kind: i == 2 ? .oneShot : .loop,
                                        status: s),
                        level: 0.6, loopProgress: 0.3)
            }
        }
        .padding(20)
    }
    .background(Theme.Colors.sceneBg)
}
