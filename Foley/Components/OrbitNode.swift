import SwiftUI

/// A pad in the orbit mixer: an orb whose size follows volume, with its name underneath.
/// Dragging shows a halo and the volume/pan readout.
struct OrbitNode: View {
    var pad: PadDisplay
    var level: Double
    var volume: Double
    var pan: Double
    var isDragging: Bool
    var namespace: Namespace.ID
    var isSource: Bool

    private var diameter: CGFloat { 40 + volume * 36 }
    private var isPlaying: Bool { pad.status == .playing }

    var readout: String {
        let side = abs(pan) < 0.03 ? "C" : (pan < 0 ? "L\(Int(abs(pan) * 100))" : "R\(Int(abs(pan) * 100))")
        return "\(Int(volume * 100))% · \(side)"
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if isDragging {
                    Circle().strokeBorder(pad.tint.base.opacity(0.5), lineWidth: 1.5)
                        .frame(width: diameter + 22, height: diameter + 22)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Circle()
                    .fill(pad.tint.orbGradient(diameter: diameter))
                    .frame(width: diameter, height: diameter)
                    .shadow(color: pad.tint.base.opacity(isPlaying ? 0.35 + level * 0.4 : 0.15), radius: isPlaying ? 14 + level * 20 : 8)
                    .saturation(isPlaying ? 1 : 0.55)
                    .scaleEffect(isPlaying ? 1 + level * 0.1 : 1)
                    .animation(Motion.level, value: level)
                    .matchedGeometryEffect(id: pad.id, in: namespace, isSource: isSource)
            }
            .scaleEffect(isDragging ? 1.06 : 1)
            .animation(Motion.quick, value: isDragging)
            Text(pad.name)
                .font(.system(size: 13, weight: .medium))
                .shadow(color: Theme.Colors.sceneBg.opacity(0.9), radius: 3)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .fixedSize()
        }
        .overlay(alignment: .topTrailing) {
            if isDragging {
                Text(readout)
                    .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.Colors.bg)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Theme.Colors.textPrimary, in: .capsule)
                    .fixedSize()
                    .offset(x: diameter * 0.6 + 20, y: -14)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(Motion.quick, value: isDragging)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pad.name), volume \(Int(volume * 100)) percent, pan \(readout.split(separator: "·").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "C")")
    }
}
