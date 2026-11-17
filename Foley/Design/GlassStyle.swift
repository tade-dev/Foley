import SwiftUI

extension View {
    /// Liquid Glass for floating chrome: docks, header buttons, pills, sheets' segmented controls.
    /// Pads stay solid so the glow reads against a dark fill.
    func foleyGlass(_ shape: some Shape = Capsule(), tint: Color? = nil, interactive: Bool = false) -> some View {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: shape)
    }
}
