import Foundation

/// POST /scene response. Decoding is lenient; `validated(for:)` enforces the contract.
nonisolated struct SceneResponse: Codable, Sendable, Equatable {
    nonisolated struct Sound: Codable, Sendable, Equatable {
        var name: String
        var keyword: String
        /// nil when the model gave no usable tint; `validated(for:)` spreads those across the palette.
        var tint: Tint?
        var kind: PadKind
        var prompt: String
        var duration: Double?

        /// Always set after `validated(for:)`; the fallback only matters for a raw decoded response.
        var resolvedTint: Tint { tint ?? .blue }

        init(name: String, keyword: String, tint: Tint?, kind: PadKind, prompt: String, duration: Double?) {
            self.name = name; self.keyword = keyword; self.tint = tint
            self.kind = kind; self.prompt = prompt; self.duration = duration
        }

        private enum CodingKeys: String, CodingKey { case name, keyword, tint, kind, prompt, duration }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            keyword = try c.decodeIfPresent(String.self, forKey: .keyword) ?? ""
            prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
            duration = try c.decodeIfPresent(Double.self, forKey: .duration)
            let rawTint = try c.decodeIfPresent(String.self, forKey: .tint) ?? ""
            tint = Tint(rawValue: rawTint.lowercased())
            let rawKind = (try c.decodeIfPresent(String.self, forKey: .kind) ?? "loop").lowercased()
            kind = rawKind == "loop" ? .loop : .oneShot
        }

    }

    var title: String
    var mood: Tint
    var sounds: [Sound]

    init(title: String, mood: Tint, sounds: [Sound]) {
        self.title = title; self.mood = mood; self.sounds = sounds
    }

    private enum CodingKeys: String, CodingKey { case title, mood, sounds }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        let rawMood = try c.decodeIfPresent(String.self, forKey: .mood) ?? ""
        mood = Tint(rawValue: rawMood.lowercased()) ?? .blue
        sounds = try c.decodeIfPresent([Sound].self, forKey: .sounds) ?? []
    }

    static let maxSounds = 8
    static let durationRange: ClosedRange<Double> = 0.5...22

    /// Enforce the contract: ≤ 8 sounds, non-empty name/prompt, clamped durations,
    /// keywords that really occur in the prompt, tints from the fixed list.
    func validated(for prompt: String) -> SceneResponse {
        var out = self
        if out.title.trimmingCharacters(in: .whitespaces).isEmpty {
            out.title = prompt.split(separator: " ").prefix(5).joined(separator: " ")
        }
        out.sounds = sounds
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && !$0.prompt.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(Self.maxSounds)
            .enumerated()
            .map { index, sound in
                var s = sound
                if let d = s.duration { s.duration = min(max(d, Self.durationRange.lowerBound), Self.durationRange.upperBound) }
                // Match the way KeywordMatcher searches, so a keyword it would find is never cleared here.
                let trimmed = s.keyword.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
                s.keyword = trimmed.isEmpty || prompt.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == nil
                    ? "" : trimmed
                if s.tint == nil { s.tint = Tint.allCases[index % Tint.allCases.count] }
                return s
            }
        return out
    }
}

/// POST /sound request — the proxy adds model_id "eleven_text_to_sound_v2".
nonisolated struct SoundRequest: Codable, Sendable {
    var text: String
    var durationSeconds: Double?
    var loop: Bool
    var promptInfluence: Double

    enum CodingKeys: String, CodingKey {
        case text, loop
        case durationSeconds = "duration_seconds"
        case promptInfluence = "prompt_influence"
    }

    init(_ spec: SoundSpec) {
        text = spec.prompt
        durationSeconds = spec.duration
        loop = spec.loop
        promptInfluence = spec.promptInfluence
    }
}
