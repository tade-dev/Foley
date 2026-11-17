import Testing
import Foundation
@testable import Foley

@Suite struct ModelTests {
    @Test func cacheKeyIsStableAndSensitiveToInfluence() {
        let a = SoundSpec(prompt: "Rain", duration: 10, loop: true, promptInfluence: 0.3)
        let b = SoundSpec(prompt: "Rain", duration: 10, loop: true, promptInfluence: 0.3)
        var c = a; c.promptInfluence = 0.6
        #expect(a.cacheKey == b.cacheKey)
        #expect(a.cacheKey != c.cacheKey)
        #expect(a.cacheKey.count == 64)
    }
    @Test func padMetaCopy() {
        let loop = Pad(name: "Rain", keyword: "rain", tint: .teal, kind: .loop, spec: .init(prompt: "x", duration: 10, loop: true), sortIndex: 0)
        let shot = Pad(name: "Thunder", keyword: "thunder", tint: .blue, kind: .oneShot, spec: .init(prompt: "x", duration: 4, loop: false), sortIndex: 1)
        #expect(loop.meta == "Loop · 10s")
        #expect(shot.meta == "One-shot · 4s")
    }
    @Test func sceneResponseDecodesLooseKinds() throws {
        let json = """
        {"title":"T","mood":"blue","sounds":[{"name":"A","keyword":"a","tint":"amber","kind":"one_shot","prompt":"p","duration":3},
        {"name":"B","keyword":"b","tint":"nope","kind":"loop","prompt":"p"}]}
        """
        let r = try JSONDecoder().decode(SceneResponse.self, from: Data(json.utf8)).validated(for: "a and b")
        #expect(r.sounds[0].kind == .oneShot)
        #expect(r.sounds[1].kind == .loop)
        #expect(Tint.allCases.contains(r.sounds[1].resolvedTint))
    }
    @Test func missingTintsAreSpreadAcrossThePalette() throws {
        let json = #"{"title":"T","mood":"blue","sounds":[{"name":"A","keyword":"a","prompt":"p"},{"name":"B","keyword":"b","prompt":"p"},{"name":"C","keyword":"c","prompt":"p"}]}"#
        let r = try JSONDecoder().decode(SceneResponse.self, from: Data(json.utf8)).validated(for: "a b c")
        #expect(Set(r.sounds.map(\.resolvedTint)).count == 3, "a response with no tints gave every pad the same colour")
    }

    @Test func keywordWithTrailingPunctuationSurvivesValidation() throws {
        let s = SceneResponse(title: "T", mood: .blue, sounds: [
            .init(name: "Rain", keyword: "heavy rain,", tint: .teal, kind: .loop, prompt: "p", duration: 10)])
        let v = s.validated(for: "A storm with heavy rain and wind")
        #expect(v.sounds[0].keyword.isEmpty == false, "punctuation stripped the highlight the matcher would have found")
        #expect(KeywordMatcher.ranges(of: [v.sounds[0].keyword], in: "A storm with heavy rain and wind")[0] != nil)
    }

    @Test func validationClampsAndDropsBadKeywords() throws {
        let s = SceneResponse(title: "T", mood: .blue, sounds: (0..<10).map {
            .init(name: "N\($0)", keyword: $0 == 0 ? "RAIN" : "zzz", tint: .pink, kind: .loop, prompt: "p", duration: $0 == 1 ? 99 : 5) })
        let v = s.validated(for: "heavy rain at night")
        #expect(v.sounds.count == 8)
        #expect(v.sounds[0].keyword == "RAIN")
        #expect(v.sounds[1].keyword == "")
        #expect(v.sounds[1].duration == 22)
    }
}
