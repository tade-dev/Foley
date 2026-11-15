import SwiftUI

/// 64 pt row with an icon tile. Busy shows a progress ring while exporting.
struct ShareRow: View {
    var symbol: String
    var title: String
    var subtitle: String
    var isBusy = false
    var progress: Double = 0
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(prominent ? Theme.Colors.textPrimary : Theme.Colors.surfaceRaised)
                        .frame(width: 52, height: 52)
                    if isBusy {
                        Circle().trim(from: 0, to: max(0.05, progress))
                            .stroke(prominent ? Theme.Colors.bg : Theme.Colors.textPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 26, height: 26)
                            .animation(.linear(duration: 0.2), value: progress)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(prominent ? Theme.Colors.bg : Theme.Colors.textPrimary)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text(isBusy ? "Exporting… \(Int(progress * 100))%" : subtitle)
                        .font(.system(size: 15)).foregroundStyle(Theme.Colors.textSecondary).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.Colors.surface, in: .rect(cornerRadius: Theme.Radius.row))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row).strokeBorder(Theme.Colors.border))
            .contentShape(.rect(cornerRadius: Theme.Radius.row))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .disabled(isBusy)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

/// UIActivityViewController for files and text.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ShareItems: Identifiable {
    let id = UUID()
    var items: [Any]
}
