import Foundation

/// Finds where each parsed keyword lives in the source prompt, for highlights and the flight.
nonisolated enum KeywordMatcher {
    /// One optional range per keyword, in order. Case- and diacritic-insensitive; surrounding
    /// punctuation and whitespace in the keyword are ignored; each keyword takes the first
    /// occurrence that does not overlap an earlier keyword's range. Empty or unfound → nil.
    static func ranges(of keywords: [String], in text: String) -> [Range<String.Index>?] {
        var claimed: [Range<String.Index>] = []
        return keywords.map { raw in
            let keyword = raw.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            guard !keyword.isEmpty else { return nil }
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let found = text.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive],
                                         range: searchStart..<text.endIndex) {
                if !claimed.contains(where: { $0.overlaps(found) }) {
                    claimed.append(found)
                    return found
                }
                searchStart = found.upperBound
            }
            return nil
        }
    }
}
