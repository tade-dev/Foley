import SwiftUI

/// Full-width 56 pt capsule, light fill, dark text. "Build scene", "Regenerate".
struct PrimaryButton: View {
    var title: String
    var symbol: String? = nil
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol { Image(systemName: symbol).font(.system(size: 17, weight: .semibold)) }
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(isEnabled ? Theme.Colors.bg : Theme.Colors.disabledIcon)
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(isEnabled ? Theme.Colors.textPrimary : Theme.Colors.surfaceRaised, in: .capsule)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .disabled(!isEnabled)
        .animation(Motion.quick, value: isEnabled)
    }
}
