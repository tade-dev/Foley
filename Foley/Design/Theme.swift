import SwiftUI

// Foley design tokens. Mirrors docs/handoff/tokens.json — no hex values in views.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    enum Colors {
        static let bg = Color(hex: 0x0A0A0C)
        static let sceneBg = Color(hex: 0x0B0F1A)
        static let sceneGlow = Color(hex: 0x15213D)
        static let surface = Color(hex: 0x141418)
        static let surfaceRaised = Color(hex: 0x1F1F25)
        static let padSurface = Color(hex: 0x121A2C)
        static let padActive = Color(hex: 0x16213A)
        static let sheet = Color(hex: 0x121624)
        static let border = Color(hex: 0x26262D)
        static let sceneBorder = Color(hex: 0x243150)
        static let textPrimary = Color(hex: 0xF4F4F5)
        static let textSecondary = Color(hex: 0xA1A1AA)
        static let sceneSecondary = Color(hex: 0xA9B4CC)
        static let textTertiary = Color(hex: 0x8B8B94)
        static let waveformRest = Color(hex: 0x2E3A58)
        static let record = Color(hex: 0xFF5A5F)
        static let error = Color(hex: 0xFF8FA3)

        // Component-level colours used by the handoff starters.
        static let chipFill = Color(hex: 0x17171C)
        static let chipBorder = Color(hex: 0x2A2A32)
        static let chipText = Color(hex: 0xE4E4E7)
        static let dockFill = Color(hex: 0x0E1422, opacity: 0.9)
        static let dockBorder = Color(hex: 0x22304D)
        static let queuedBorder = Color(hex: 0x2E3B5C)
        static let failedFill = Color(hex: 0x3C1420, opacity: 0.35)
        static let failedBorder = Color(hex: 0x5A2A3A)
        static let failedText = Color(hex: 0xE3B3BF)
        static let playingMeta = Color(hex: 0xDCE3F0)
        static let disabledIcon = Color(hex: 0x6B6B74)
    }

    enum Radius {
        static let pad: CGFloat = 28
        static let card: CGFloat = 28
        static let cardLarge: CGFloat = 32
        static let sheet: CGFloat = 34
        static let input: CGFloat = 26
        static let row: CGFloat = 20
        static let dock: CGFloat = 40
    }

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 24
    }

    enum Size {
        static let touch: CGFloat = 44
        static let transport: CGFloat = 64
        static let padHeight: CGFloat = 150
        static let padHeightTall: CGFloat = 168
        static let chip: CGFloat = 34
        static let suggestionChip: CGFloat = 40
    }

    enum Fonts {
        static let hero = Font.system(size: 34, weight: .semibold)
        static let screenTitle = Font.system(size: 30, weight: .semibold)
        static let sheetTitle = Font.system(size: 28, weight: .semibold)
        static let cardTitle = Font.system(size: 22, weight: .semibold)
        static let padName = Font.system(size: 15, weight: .semibold)
        static let body = Font.system(size: 15)
        static let bodyLarge = Font.system(size: 16)
        static let meta = Font.system(size: 12)
        static let footnote = Font.system(size: 13)
        static let label = Font.system(size: 12, weight: .semibold)
    }
}

/// The six sound tints. The LLM must pick from these, never free hex.
enum Tint: String, Codable, CaseIterable, Sendable {
    case amber, blue, teal, lavender, sky, pink

    var hexHighlight: UInt32 {
        switch self {
        case .amber: 0xFFD9A0
        case .blue: 0xDCE8FF
        case .teal: 0xC8FAF2
        case .lavender: 0xECE5FF
        case .sky: 0xD6F2FF
        case .pink: 0xFFE0EA
        }
    }

    var hexBase: UInt32 {
        switch self {
        case .amber: 0xFFB547
        case .blue: 0x8FB8FF
        case .teal: 0x5EE0CF
        case .lavender: 0xC2AEFF
        case .sky: 0x7FD6FF
        case .pink: 0xFFA3C0
        }
    }

    var hexShadow: UInt32 {
        switch self {
        case .amber: 0x8A4E10
        case .blue: 0x2A4AA8
        case .teal: 0x1E7A6E
        case .lavender: 0x5A3FB8
        case .sky: 0x1F6D96
        case .pink: 0xA8385E
        }
    }

    var highlight: Color { Color(hex: hexHighlight) }
    var base: Color { Color(hex: hexBase) }
    var shadow: Color { Color(hex: hexShadow) }
    var glow: Color { base.opacity(0.28) }

    /// Index in the fixed list, used to de-phase animations between neighbouring pads.
    var index: Int { Tint.allCases.firstIndex(of: self) ?? 0 }

    /// The orb's radial gradient, sized to a diameter.
    func orbGradient(diameter: CGFloat) -> RadialGradient {
        RadialGradient(
            stops: [
                .init(color: highlight, location: 0),
                .init(color: base, location: 0.38),
                .init(color: shadow, location: 0.78),
            ],
            center: UnitPoint(x: 0.36, y: 0.34),
            startRadius: 0,
            endRadius: diameter * 0.62
        )
    }
}

/// Uppercase section label used across screens ("YOUR SCENE", "SHARE").
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(Theme.Fonts.label)
            .tracking(0.96)
            .foregroundStyle(Theme.Colors.textTertiary)
    }
}
