import SwiftUI

/// A keyword the parser found in the prompt, with the tint of its pad.
struct KeywordMatch: Identifiable, Equatable {
    var id: UUID
    var range: Range<String.Index>
    var tint: Tint
}

/// The prompt with highlighted keyword ranges: tint at 16 % fill + underline in the tint.
/// Ids in `gapped` render as a dotted gap where the word flew out.
struct KeywordText: View {
    var text: String
    var matches: [KeywordMatch]
    var gapped: Set<UUID> = []
    var font: Font = .system(size: 22, weight: .regular)
    var color: Color = Theme.Colors.textPrimary

    var body: some View {
        Text(attributed)
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(6)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.3), value: gapped)
    }

    private var attributed: AttributedString { build() }

    /// One pass over the plain text, in keyword order; overlapping matches are skipped.
    private func build() -> AttributedString {
        var out = AttributedString()
        var cursor = text.startIndex
        for match in matches.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            guard match.range.lowerBound >= cursor else { continue }
            out.append(AttributedString(String(text[cursor..<match.range.lowerBound])))
            if gapped.contains(match.id) {
                let count = max(3, text.distance(from: match.range.lowerBound, to: match.range.upperBound))
                var gap = AttributedString(String(repeating: "\u{00A0}", count: count))
                gap.underlineStyle = Text.LineStyle(pattern: .dot, color: Theme.Colors.sceneBorder)
                gap.foregroundColor = .clear
                out.append(gap)
            } else {
                var word = AttributedString(String(text[match.range]))
                word.backgroundColor = match.tint.base.opacity(0.16)
                word.underlineStyle = Text.LineStyle(pattern: .solid, color: match.tint.base)
                out.append(word)
            }
            cursor = match.range.upperBound
        }
        out.append(AttributedString(String(text[cursor...])))
        return out
    }
}
