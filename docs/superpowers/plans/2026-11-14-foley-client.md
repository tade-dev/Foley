# Foley Client (Phase A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The complete Foley iOS app, all nine screens, playing two bundled demo scenes and running the whole create → generate → play → record → share flow against a mock generation service, with no network and no keys.

**Architecture:** SwiftUI views talk only to `SceneStore` (transient pad status, generation orchestration) and `AudioEngine` (AVAudioEngine, one player per pad, 60 Hz levels, recording). `GenerationService` is a protocol; this phase ships `MockGenerationService`, Phase B adds the live one behind the same interface. SwiftData persists `SoundScene`, `Pad`, `Mix`; audio files live on disk keyed by a hash of the sound spec.

**Tech Stack:** Swift 6 language mode, SwiftUI (iOS 26: Liquid Glass, `MeshGradient`, `keyframeAnimator`, `phaseAnimator`, `navigationTransition`), SwiftData, AVFoundation, Speech, Swift Testing (app-hosted unit tests), CryptoKit, Xcode 27.2 with the `xcodeproj` CLI, Python 3 + numpy + ffmpeg for placeholder audio.

**Spec:** `docs/superpowers/specs/2026-11-14-foley-design.md` (build decisions) and `docs/handoff/HANDOFF.md` (product spec: tokens, components, screens, motion, models). Screens: `docs/handoff/design/png/01..09`. Starter code to adapt, not copy blindly: `/Users/bstar/Downloads/Foley-Handoff/swift/*.swift`.

## Global Constraints

- iOS deployment target **26.0**, iPhone only, **portrait only**, dark only. Swift 6 language mode (`SWIFT_VERSION = 6`), default actor isolation MainActor (already set in the project).
- No hex colour literal in any view: every colour comes from `Theme.Colors` or `Tint` (`Foley/Design/Theme.swift`). The handoff starters contain a few inline `Color(hex:)` calls; move each into `Theme.Colors` when adapting them.
- Copy rules: sentence case everywhere; pad meta is `Loop · 10s` or `One-shot · 4s`; errors say what happened and offer one action. Fixed strings: "Couldn't make this one", "Too many at once, retrying", "Daily limit reached", "Describe a scene.", "Listening for sounds", "N sounds detected", "Build scene", "Building N of M sounds…", "N sounds · tap to play, hold to edit", "N of M playing · tap to toggle", "Mix saved", "Your scenes", "Sounds generated with ElevenLabs".
- Touch targets ≥ 44 pt. Icon buttons 44×44 circles, transport 64×64. Radii: pads 28, cards 28–32, sheet top 34, inputs 26, rows 20, chips/pills capsule.
- Springs everywhere; no linear timing except continuous loops. ≤ ~10 haptics/s. Reduce Motion: morphing, spinning and flight become opacity fades.
- Every pad is a `Button` with accessibility label "<name>, <loop|one-shot>", value "playing"/"not playing", and an "Edit" accessibility action.
- The SwiftData scene model is named `SoundScene` (not `Scene`) to avoid clashing with `SwiftUI.Scene`.
- No API key, proxy URL, or secret in the repo. `Config/Local.xcconfig` is gitignored.
- Build/test commands: `scripts/build.sh` and `scripts/test.sh [TestSuiteName]` (defined in Task 1). Every task ends green on `scripts/test.sh` and, for UI tasks, a simulator screenshot compared to the handoff PNG.
- Commit after every task with a conventional message.

## Review Focus

1. **A prompt whose keyword the parser returns with different casing or trailing punctuation** ("Heavy Rain," vs "heavy rain"): highlights and the flight must still find the range, case-insensitively, and an unmatched keyword must not crash or misplace other highlights. Test in Task 4 (`KeywordMatcher`).
2. **Two pads with identical specs in one scene** (the LLM repeats itself): both must share one cache file and generate once, and deleting one pad must not delete the other's audio. Test in Task 6 (`AudioCache`) and Task 8 (`SceneStore`).
3. **Tapping Build, then leaving the screen mid-generation and coming back** (or the app going to background): generation must finish or fail in place, never leave pads stuck in `generating`, and the Board must reflect the stored state on return. Test in Task 8 (`SceneStore.generateAll` is cancellation-safe and marks cancelled pads `failed`).
4. **Recording with nothing playing, or stopping a recording under 0.5 s**: must not save an empty or corrupt mix; the Rec pill returns to idle and no Mix row appears. Test in Task 7 (`AudioEngine`) and Task 15 (`SceneStore.saveMix` rejects `duration < 0.5`).
5. **Audio route change or interruption while six loops play** (headphones unplugged, phone call in the simulator's equivalent): the engine must restart and the playing set must be cleared so the UI does not show glowing pads with no sound. Test in Task 7 (`AudioEngine.handleInterruption` clears `playing` and `levels`).

---

## File structure

```
Foley/
  FoleyApp.swift                       modify: ModelContainer for SoundScene/Pad/Mix, builds AppEnvironment, seeds demo
  App/
    AppEnvironment.swift               wires AudioEngine, AudioCache, GenerationService, SceneStore, ProxyConfig
    ProxyConfig.swift                  reads FOLEY_PROXY_URL from Info.plist; isConfigured
    RootView.swift                     NavigationStack + Route enum
  Design/
    Theme.swift                        tokens (from handoff) + Tint + SectionLabel + extra named colours
    Motion.swift                       Spring constants, ReduceMotion helpers
    GlassStyle.swift                   foleyGlass() modifier wrapping glassEffect
  Models/
    SoundSpec.swift                    SoundSpec + cacheKey
    PadTypes.swift                     PadKind, PadStatus
    SceneModels.swift                  @Model SoundScene, Pad, Mix
    SceneResponse.swift                proxy contracts + validation
    DemoScene.swift                    Codable shape of demo-scenes.json
  Services/
    KeywordMatcher.swift
    AudioCache.swift
    GenerationService.swift            protocol + GenerationError
    MockGenerationService.swift
    AudioEngine.swift                  engine + MeterStore + MixRecording
    WaveformSampler.swift
    DemoSeeder.swift
    SceneStore.swift
    MixRenderer.swift                  .m4a + envelope → 9:16 .mp4
    Dictation.swift
  Components/
    SoundOrb.swift, PadView.swift (PadView, LoopRing, MiniMeter), MasterMeter.swift,
    Chips.swift (SoundChip, SuggestionChip), Composer.swift (Composer, CircleIconButton),
    TransportDock.swift, RecPill.swift, WaveformView.swift, KeywordText.swift,
    OrbitNode.swift, SceneCard.swift, ShareRow.swift, SceneBackground.swift,
    PrimaryButton.swift, FlightOverlay.swift
  Screens/
    HomeView.swift (01), LibraryView.swift (09), CreateView.swift (02+03),
    BoardView.swift (04+05+06), PadSheetView.swift (07), MixSavedView.swift (08),
    MixesListView.swift, ProxySetupCard.swift
  Resources/
    Demo/demo-scenes.json, Demo/*.m4a
FoleyTests/                            app-hosted Swift Testing target
Config/Local.xcconfig.example, Config/Local.xcconfig (gitignored)
scripts/build.sh, scripts/test.sh, scripts/make_placeholder_sounds.py, scripts/make_app_icon.py
```

---

### Task 1: Project setup, test target, build scripts

**Files:**
- Modify: `Foley.xcodeproj/project.xcproj` (via the `xcodeproj` CLI only, never by hand)
- Create: `FoleyTests/SmokeTests.swift`, `scripts/build.sh`, `scripts/test.sh`, `Config/Local.xcconfig.example`, `Config/Local.xcconfig`, `.gitignore`
- Delete: `Foley/Item.swift`, `Foley/ContentView.swift`
- Modify: `Foley/FoleyApp.swift`

**Interfaces:**
- Produces: `scripts/build.sh` (builds the app for the simulator; exit code = result), `scripts/test.sh [Suite]` (runs all tests, or `-only-testing:FoleyTests/<Suite>`), the app-hosted `FoleyTests` target, and the proxy-URL plumbing: `Config/Local.xcconfig` defines the build setting `FOLEY_PROXY_URL`, and `Foley/Info.plist` carries the key `FOLEY_PROXY_URL` with value `$(FOLEY_PROXY_URL)`. Xcode merges this plist with the generated one (`GENERATE_INFOPLIST_FILE` stays `YES`), so `Bundle.main.object(forInfoDictionaryKey: "FOLEY_PROXY_URL")` reads it at runtime.

- [ ] **Step 1: Remove the template files and write a minimal app**

Delete `Foley/Item.swift` and `Foley/ContentView.swift`. Replace `Foley/FoleyApp.swift` with an `@main struct FoleyApp: App` whose body is a `WindowGroup { Text("Foley") }` (no SwiftData yet; Task 5 adds the container).

- [ ] **Step 2: Set project settings with the CLI**

```bash
X=/Applications/Xcode.app/Contents/Developer/usr/bin/xcodeproj
$X setting set IPHONEOS_DEPLOYMENT_TARGET 26.0
$X setting set SWIFT_VERSION 6 --target Foley
$X setting set TARGETED_DEVICE_FAMILY 1 --target Foley
$X setting set INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone UIInterfaceOrientationPortrait --target Foley
$X setting set INFOPLIST_KEY_NSMicrophoneUsageDescription "Foley uses the microphone for dictating a scene." --target Foley
$X setting set INFOPLIST_KEY_NSSpeechRecognitionUsageDescription "Foley turns your speech into a scene description." --target Foley
$X setting set INFOPLIST_FILE Foley/Info.plist --target Foley
```

Create `Foley/Info.plist` containing one key `FOLEY_PROXY_URL` with value `$(FOLEY_PROXY_URL)` and `UIBackgroundModes` = `[audio]`.

- [ ] **Step 3: xcconfig for the proxy URL**

`Config/Local.xcconfig.example` contains `FOLEY_PROXY_URL = ` (empty) with a comment explaining it is the Worker URL from Phase B. Copy it to `Config/Local.xcconfig`. `.gitignore`: `Config/Local.xcconfig`, `xcuserdata/`, `.DS_Store`, `build/`, `*.xcuserstate`, `DerivedData/`. Link it: `mkdir -p Config` then `$X group add Config --filesystem-path Config` and `$X config set Local.xcconfig --group Config --target Foley`. Remove the tracked `xcuserdata` files from git (`git rm -r --cached Foley.xcodeproj/xcuserdata Foley.xcodeproj/project.xcworkspace/xcuserdata`).

- [ ] **Step 4: Add the test target**

```bash
mkdir -p FoleyTests
$X target add FoleyTests --product-type unit-test-bundle
$X target phase add sources --target FoleyTests
$X target phase add frameworks --target FoleyTests
$X group add FoleyTests --filesystem-path FoleyTests
$X group include FoleyTests --target FoleyTests
$X target add-dependency FoleyTests Foley
$X setting set TEST_HOST '$(BUILT_PRODUCTS_DIR)/Foley.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Foley' --target FoleyTests
$X setting set BUNDLE_LOADER '$(TEST_HOST)' --target FoleyTests
$X setting set PRODUCT_BUNDLE_IDENTIFIER com.tade.FoleyTests --target FoleyTests
$X setting set SWIFT_VERSION 6 --target FoleyTests
$X setting set IPHONEOS_DEPLOYMENT_TARGET 26.0 --target FoleyTests
$X setting set SDKROOT iphoneos --target FoleyTests
$X setting set CODE_SIGN_STYLE Automatic --target FoleyTests
$X setting set DEVELOPMENT_TEAM <YOUR_TEAM_ID> --target FoleyTests
```

If `group include` is rejected for a synchronized group, check `$X group ls` and use the path it prints. Write a shared scheme `Foley.xcodeproj/xcshareddata/xcschemes/Foley.xcscheme` whose Test action lists `FoleyTests` (standard xcscheme XML; `BuildableName` `Foley.app` / `FoleyTests.xctest`), so `xcodebuild test -scheme Foley` works on a fresh clone.

- [ ] **Step 5: Write the smoke test**

```swift
import Testing
@testable import Foley

@Suite struct SmokeTests {
    @Test func appModuleLinks() { #expect(true) }
}
```

- [ ] **Step 6: Build scripts**

`scripts/build.sh`: `xcodebuild build -project Foley.xcodeproj -scheme Foley -destination "platform=iOS Simulator,name=${SIM:-iPhone 17}" -quiet` ; exit with xcodebuild's status and print the last 60 lines of output on failure.
`scripts/test.sh`: same with `test`, appending `-only-testing:FoleyTests/$1` when `$1` is given. Both `chmod +x`.

- [ ] **Step 7: Verify**

Run: `scripts/build.sh && scripts/test.sh SmokeTests`
Expected: both succeed; the test log shows `SmokeTests` passed. Then `ls $(xcodebuild -showBuildSettings -project Foley.xcodeproj -scheme Foley -destination 'platform=iOS Simulator,name=iPhone 17' 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/Foley.app/Info.plist` and confirm `plutil -p` shows `FOLEY_PROXY_URL => ""` and `UISupportedInterfaceOrientations => [UIInterfaceOrientationPortrait]`.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "chore: iOS 26 target, Swift 6, test target, build scripts, proxy xcconfig"
```

---

### Task 2: Design tokens, Tint, motion and glass helpers

**Files:**
- Create: `Foley/Design/Theme.swift`, `Foley/Design/Motion.swift`, `Foley/Design/GlassStyle.swift`
- Test: `FoleyTests/ThemeTests.swift`

**Interfaces:**
- Produces: `enum Theme { enum Colors; enum Radius; enum Space; enum Size; enum Fonts }` exactly as the handoff `Theme.swift`, plus `Theme.Colors.chipFill (0x17171C)`, `chipBorder (0x2A2A32)`, `dockFill (0x0E1422 @ 0.9)`, `dockBorder (0x22304D)`, `queuedBorder (0x2E3B5C)`, `failedFill (0x3C1420 @ 0.35)`, `failedBorder (0x5A2A3A)`, `failedText (0xE3B3BF)`, `playingMeta (0xDCE3F0)`, `chipText (0xE4E4E7)`, `disabledIcon (0x6B6B74)`.
- `enum Tint: String, Codable, CaseIterable, Sendable { amber, blue, teal, lavender, sky, pink }` with `highlight`, `base`, `shadow`, `glow`, `orbGradient(diameter:)` and `var hexBase: UInt32` (for tests and the video renderer).
- `struct SectionLabel: View`.
- `enum Motion { static let spring = Animation.spring(response: 0.55, dampingFraction: 0.72); static let quick = .spring(response: 0.25, dampingFraction: 0.7); static let seg = .spring(response: 0.35, dampingFraction: 0.8); static let level = .interactiveSpring(response: 0.12, dampingFraction: 0.8) }` and `extension View { func reduceMotionFade(_ reduce: Bool) -> some View }`.
- `extension View { func foleyGlass(_ shape: some Shape = Capsule(), tint: Color? = nil, interactive: Bool = false) -> some View }` wrapping `glassEffect(.regular[.tint(tint)][.interactive()], in: shape)`.

- [ ] **Step 1: Write the failing test**

```swift
@Suite struct ThemeTests {
    @Test func everyTintHasDistinctBase() {
        let bases = Set(Tint.allCases.map(\.hexBase))
        #expect(bases.count == Tint.allCases.count)
    }
    @Test func tintDecodesFromRawValue() throws {
        #expect(try JSONDecoder().decode(Tint.self, from: Data("\"lavender\"".utf8)) == .lavender)
    }
    @Test func amberBaseMatchesTokens() { #expect(Tint.amber.hexBase == 0xFFB547) }
}
```

- [ ] **Step 2: Run `scripts/test.sh ThemeTests`** — Expected: FAIL to compile (`Tint` undefined).

- [ ] **Step 3: Implement** `Theme.swift` from the handoff starter with the extra colours above, `Motion.swift`, `GlassStyle.swift`.

- [ ] **Step 4: Run `scripts/test.sh ThemeTests`** — Expected: PASS.

- [ ] **Step 5: Commit** `feat(design): theme tokens, tint, motion and glass helpers`

---

### Task 3: Models: SoundSpec, pad types, SwiftData models, proxy contracts

**Files:**
- Create: `Foley/Models/SoundSpec.swift`, `Foley/Models/PadTypes.swift`, `Foley/Models/SceneModels.swift`, `Foley/Models/SceneResponse.swift`
- Test: `FoleyTests/ModelTests.swift`

**Interfaces:**
- `struct SoundSpec: Codable, Hashable, Sendable { var prompt: String; var duration: Double?; var loop: Bool; var promptInfluence: Double = 0.3; var cacheKey: String }` — `cacheKey` = lowercase hex SHA-256 (CryptoKit) of `"\(prompt)|\(duration.map { String(format: "%.2f", $0) } ?? "auto")|\(loop)|\(String(format: "%.2f", promptInfluence))"`.
- `enum PadKind: String, Codable, Sendable { case loop, oneShot; var symbol: String; var label: String /* "Loop"/"One-shot" */ }`
- `enum PadStatus: Equatable, Sendable { case queued, generating, ready, playing, failed(String) }`
- `@Model final class SoundScene { @Attribute(.unique) var id: UUID; var title: String; var sourcePrompt: String; var moodRaw: String; var createdAt: Date; var isDemo: Bool; @Relationship(deleteRule: .cascade, inverse: \Pad.scene) var pads: [Pad]; @Relationship(deleteRule: .cascade, inverse: \Mix.scene) var mixes: [Mix]; var mood: Tint; var orderedPads: [Pad] /* by sortIndex */; init(title:sourcePrompt:mood:isDemo:) }`
- `@Model final class Pad { @Attribute(.unique) var id: UUID; var name, keyword, tintRaw, kindRaw: String; var spec: SoundSpec; var cacheKey: String?; var demoFile: String?; var volume: Double = 0.8; var pan: Double = 0; var version: Int = 1; var sortIndex: Int; var scene: SoundScene?; var tint: Tint; var kind: PadKind; var meta: String; init(name:keyword:tint:kind:spec:sortIndex:demoFile:) }` — `meta` per handoff: `"\(kind.label) · \(duration formatted 0…1 fraction digits)s"`, or just `kind.label` when duration is nil. `demoFile` is the bundled resource name (without extension) for demo pads; `cacheKey` is set when a generated file is on disk. `var audioURL: URL?` is NOT here (needs the cache) — `SceneStore` resolves it.
- `@Model final class Mix { @Attribute(.unique) var id: UUID; var fileName: String; var envelopeFileName: String; var duration: Double; var createdAt: Date; var scene: SoundScene?; init(fileName:envelopeFileName:duration:) }`
- `struct SceneResponse: Codable, Sendable, Equatable { struct Sound: Codable, Sendable, Equatable { var name, keyword: String; var tint: Tint; var kind: PadKind; var prompt: String; var duration: Double? }; var title: String; var mood: Tint; var sounds: [Sound] }` — custom `init(from:)` on `Sound` accepting `kind` values `loop`, `oneShot`, `one_shot`, `one-shot` and an unknown/missing `tint` as `nil` → caller's fallback. Provide `func validated(for prompt: String) -> SceneResponse` that: keeps max 8 sounds, drops sounds with empty `name` or `prompt`, clamps `duration` to 0.5…22 (nil stays nil), replaces a `keyword` not found case-insensitively in `prompt` with `""`, and fills missing tints round-robin from `Tint.allCases` by index.
- `struct SoundRequest: Codable` as the handoff (`text`, `duration_seconds`, `loop`, `prompt_influence`; `init(_ spec: SoundSpec)`).

- [ ] **Step 1: Write the failing tests**

```swift
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
        #expect(Tint.allCases.contains(r.sounds[1].tint))
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
```

- [ ] **Step 2: Run `scripts/test.sh ModelTests`** — Expected: FAIL to compile.
- [ ] **Step 3: Implement the four files.** SwiftData models need `import SwiftData`; `SoundSpec` stored as a Codable attribute works as-is.
- [ ] **Step 4: Run `scripts/test.sh ModelTests`** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(models): sound spec, pad types, SwiftData models, scene response validation`

---

### Task 4: KeywordMatcher

**Files:**
- Create: `Foley/Services/KeywordMatcher.swift`
- Test: `FoleyTests/KeywordMatcherTests.swift`

**Interfaces:**
- `enum KeywordMatcher { static func ranges(of keywords: [String], in text: String) -> [Range<String.Index>?] }` — case- and diacritic-insensitive, ignores surrounding punctuation in the keyword, returns the first occurrence not overlapping an earlier keyword's range; `nil` for empty or unfound keywords. Also `static func gapped(_ text: String, removing ranges: [Range<String.Index>]) -> AttributedString` is NOT here; it belongs to `KeywordText` (Task 10).

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct KeywordMatcherTests {
    let text = "A creaky pirate ship in a thunderstorm, heavy rain, howling wind, waves smashing the hull"
    @Test func findsCaseInsensitiveAndStripsPunctuation() {
        let r = KeywordMatcher.ranges(of: ["Heavy Rain,", "WAVES"], in: text)
        #expect(r[0].map { String(text[$0]) } == "heavy rain")
        #expect(r[1].map { String(text[$0]) } == "waves")
    }
    @Test func unknownKeywordIsNilAndDoesNotShiftOthers() {
        let r = KeywordMatcher.ranges(of: ["grumpy cat", "howling wind"], in: text)
        #expect(r[0] == nil)
        #expect(r[1].map { String(text[$0]) } == "howling wind")
    }
    @Test func repeatedWordTakesNextOccurrence() {
        let t = "rain then more rain"
        let r = KeywordMatcher.ranges(of: ["rain", "rain"], in: t)
        #expect(r[0] != r[1]); #expect(r[1] != nil)
    }
}
```

- [ ] **Step 2: Run `scripts/test.sh KeywordMatcherTests`** — Expected: FAIL to compile.
- [ ] **Step 3: Implement** using `text.range(of:options:[.caseInsensitive, .diacriticInsensitive], range:)` scanning past previously claimed ranges.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat: keyword matcher for prompt highlights`

---

### Task 5: Demo scene JSON, placeholder audio, DemoSeeder, app container

**Files:**
- Create: `scripts/make_placeholder_sounds.py`, `Foley/Resources/Demo/demo-scenes.json`, `Foley/Resources/Demo/*.m4a` (10 files), `Foley/Models/DemoScene.swift`, `Foley/Services/DemoSeeder.swift`
- Modify: `Foley/FoleyApp.swift`
- Test: `FoleyTests/DemoSeederTests.swift`

**Interfaces:**
- `demo-scenes.json`: `{ "scenes": [ { "title", "sourcePrompt", "mood", "sounds": [ { "name", "keyword", "tint", "kind", "prompt", "duration", "file" } ] } ] }`. Scene 1 "Pirate ship in a storm", prompt `"A creaky pirate ship in a thunderstorm, heavy rain, howling wind, waves smashing the hull and a grumpy cat below deck"`, mood blue, sounds exactly as mock 04: Creaking hull (amber, loop, 10, keyword "creaky pirate ship"), Thunder crack (blue, oneShot, 4, "thunderstorm"), Heavy rain (teal, loop, 15, "heavy rain"), Howling wind (lavender, loop, 12, "howling wind"), Waves on hull (sky, loop, 15, "waves"), Grumpy cat (pink, oneShot, 2, "grumpy cat"). Scene 2 "Rainy café in Tokyo", prompt `"A rainy café in Tokyo: rain on the window, an espresso machine hissing, quiet chatter and ceramic cups"`, mood teal, sounds: Rain on window (teal, loop, 12), Espresso machine (amber, oneShot, 3), Quiet chatter (pink, loop, 15), Ceramic cups (lavender, oneShot, 2). `file` values are kebab-case names (`creaking-hull`, …).
- `struct DemoSceneFile: Codable { var scenes: [DemoScene] }`, `struct DemoScene: Codable { title, sourcePrompt: String; mood: Tint; sounds: [DemoSound] }`, `struct DemoSound: Codable { name, keyword: String; tint: Tint; kind: PadKind; prompt: String; duration: Double; file: String }`.
- `enum DemoSeeder { @MainActor static func seedIfNeeded(context: ModelContext, bundle: Bundle = .main) throws -> Int }` — inserts the scenes with `isDemo = true`, pads with `demoFile` set and `spec = SoundSpec(prompt:, duration:, loop: kind == .loop)`, returns the number of scenes inserted; returns 0 when any `SoundScene` with `isDemo == true` already exists.
- `scripts/make_placeholder_sounds.py`: numpy synthesis (filtered noise, envelopes, seamless loop crossfade for loops) → WAV → ffmpeg → AAC `.m4a` at 44.1 kHz stereo, written to `Foley/Resources/Demo/`. Durations as in the JSON. Phase B overwrites these files.
- `FoleyApp`: `ModelContainer(for: SoundScene.self, Pad.self, Mix.self)`; `.modelContainer(container)`; a `.task` on the root that calls `DemoSeeder.seedIfNeeded`.

- [ ] **Step 1: Write the failing test**

```swift
@Suite struct DemoSeederTests {
    @MainActor @Test func seedsTwoScenesOnceAndFilesExist() throws {
        let container = try ModelContainer(for: SoundScene.self, Pad.self, Mix.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        #expect(try DemoSeeder.seedIfNeeded(context: ctx) == 2)
        #expect(try DemoSeeder.seedIfNeeded(context: ctx) == 0)
        let scenes = try ctx.fetch(FetchDescriptor<SoundScene>())
        let pirate = try #require(scenes.first { $0.title == "Pirate ship in a storm" })
        #expect(pirate.orderedPads.count == 6)
        #expect(pirate.orderedPads[0].name == "Creaking hull")
        for pad in scenes.flatMap(\.pads) {
            #expect(Bundle.main.url(forResource: pad.demoFile, withExtension: "m4a") != nil, "\(pad.name) audio missing")
        }
    }
}
```

- [ ] **Step 2: Run `scripts/test.sh DemoSeederTests`** — Expected: FAIL.
- [ ] **Step 3: Write the Python script and run it** (`python3 scripts/make_placeholder_sounds.py`); confirm 10 `.m4a` files exist and `ffprobe` reports the expected durations ±0.1 s.
- [ ] **Step 4: Implement `DemoScene.swift`, `DemoSeeder.swift`, the JSON, and the app container.**
- [ ] **Step 5: Run** — Expected: PASS. Also `scripts/build.sh` and confirm the `.app` bundle contains `demo-scenes.json` and the `.m4a` files at its root (`ls .../Foley.app | grep m4a`). If the synced folder nests them, the lookup must use `subdirectory: "Demo"` consistently in `DemoSeeder` and `SceneStore`; pick one and keep it.
- [ ] **Step 6: Commit** `feat: demo scenes JSON, placeholder audio, seeder`

---

### Task 6: AudioCache, GenerationService protocol, MockGenerationService

**Files:**
- Create: `Foley/Services/AudioCache.swift`, `Foley/Services/GenerationService.swift`, `Foley/Services/MockGenerationService.swift`
- Test: `FoleyTests/AudioCacheTests.swift`, `FoleyTests/MockGenerationServiceTests.swift`

**Interfaces:**
- `final class AudioCache: Sendable { init(directory: URL) throws /* creates dir */; static func appSupport() throws -> AudioCache /* Application Support/Foley/Audio */; func url(for key: String) -> URL /* <dir>/<key>.mp3 */; func contains(_ key: String) -> Bool; func store(_ data: Data, key: String) throws -> URL; func remove(_ key: String) }`
- `enum GenerationError: Error, Equatable { case notConfigured, busy, quota, offline, invalidResponse, server(Int); var userMessage: String }` — `quota` → "Daily limit reached", `busy` → "Too many at once, retrying", `offline` → "You're offline", all others → "Couldn't make this one".
- `protocol GenerationService: Sendable { func buildScene(prompt: String) async throws -> SceneResponse; func generateSound(_ spec: SoundSpec) async throws -> URL }` — `generateSound` returns a file URL already in the cache; implementations must return immediately on a cache hit.
- `final class MockGenerationService: GenerationService { init(cache: AudioCache, bundle: Bundle = .main, latency: Duration = .seconds(1.4), failEvery: Int = 0) }` — `buildScene`: if the prompt contains "pirate" return the pirate demo scene's response; otherwise split the prompt on `,`, ` and `, `;`, `.` into up to 6 phrases, name = phrase capitalised and trimmed to 3 words, keyword = phrase, tint round-robin, kind `.loop` if the phrase contains any of `rain|wind|hum|chatter|crowd|waves|fire|engine|traffic|drone|crickets` else `.oneShot`, duration 12 for loops / 3 for one-shots, title = first 5 words of the prompt capitalised, mood = first tint. Throws `.invalidResponse` for a blank prompt. `generateSound`: cache hit → return; else sleep `latency` (±30 % jitter), every `failEvery`th call throws `.server(500)`, otherwise copies a bundled demo `.m4a` chosen by `abs(spec.cacheKey.hashValue) % files.count` into the cache under `spec.cacheKey` and returns it. Sleeps are cancellable (`Task.sleep`).

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct AudioCacheTests {
    func temp() throws -> AudioCache { try AudioCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)) }
    @Test func storeThenContains() throws {
        let c = try temp(); let key = String(repeating: "a", count: 64)
        #expect(!c.contains(key))
        let url = try c.store(Data([1,2,3]), key: key)
        #expect(c.contains(key)); #expect(url == c.url(for: key))
        c.remove(key); #expect(!c.contains(key))
    }
}
@Suite struct MockGenerationServiceTests {
    @Test func buildSceneSplitsFreeText() async throws {
        let svc = MockGenerationService(cache: try AudioCacheTests().temp(), latency: .zero)
        let r = try await svc.buildScene(prompt: "campfire crackling, crickets and an owl hooting")
        #expect((1...6).contains(r.sounds.count))
        #expect(r.sounds.allSatisfy { !$0.name.isEmpty && !$0.prompt.isEmpty })
    }
    @Test func generateSoundCachesAndFailsEveryN() async throws {
        let cache = try AudioCacheTests().temp()
        let svc = MockGenerationService(cache: cache, latency: .zero, failEvery: 2)
        let a = SoundSpec(prompt: "a", duration: 2, loop: false)
        let b = SoundSpec(prompt: "b", duration: 2, loop: false)
        let u1 = try await svc.generateSound(a)
        #expect(cache.contains(a.cacheKey))
        await #expect(throws: GenerationError.server(500)) { try await svc.generateSound(b) }
        let u2 = try await svc.generateSound(a)   // cache hit, not counted as a call
        #expect(u1 == u2)
    }
}
```

- [ ] **Step 2: Run both suites** — Expected: FAIL to compile.
- [ ] **Step 3: Implement the three files.**
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat: audio cache, generation service protocol, mock service`

---

### Task 7: AudioEngine

**Files:**
- Create: `Foley/Services/AudioEngine.swift`
- Test: `FoleyTests/AudioEngineTests.swift`

**Interfaces:**
- `@Observable @MainActor final class AudioEngine { private(set) var levels: [UUID: Float]; private(set) var masterLevels: [Float] /* 40 */; private(set) var playing: Set<UUID>; private(set) var isRecording: Bool; private(set) var recordingElapsed: Duration; var masterVolume: Double /* 0…1, default 0.8, drives mainMixerNode.outputVolume */; init(); func load(padID: UUID, kind: PadKind, url: URL) throws; func unload(padID: UUID); func toggle(_ padID: UUID); func isPlaying(_ padID: UUID) -> Bool; func playAll(_ ids: [UUID]) /* starts every loop in ids, triggers one-shots once */; func stopAll(); func setVolume(_ volume: Double, pan: Double, for padID: UUID); func loopProgress(for padID: UUID) -> Double; func startRecording() throws; func stopRecording() -> MixRecording?; func handleInterruption() }`
- `struct MixRecording: Sendable { var url: URL /* temp .m4a */; var duration: TimeInterval; var envelope: [UUID: [Float]] /* ~30 Hz per pad */; var padOrder: [UUID] }`
- Behaviour from the handoff starter: one `AVAudioPlayerNode` per pad, taps → `MeterStore` (lock-protected) → `CADisplayLink` pump with fast-attack/slow-release smoothing; one-shot completion removes from `playing`; `.loops` option for loops. Additions: audio session `.playback` without `mixWithOthers`; observe `AVAudioSession.interruptionNotification` and `routeChangeNotification` → `handleInterruption()` (stop all, clear `levels`, restart engine); recording writes the mixer tap to AAC and samples every playing pad's smoothed level into `envelope` 30× per second; `stopRecording` returns `nil` when `duration < 0.5`; `recordingElapsed` updates each pump tick.

- [ ] **Step 1: Write the failing tests** (use a bundled demo file via `Bundle.main.url(forResource: "thunder-crack", withExtension: "m4a")`)

```swift
@Suite(.serialized) @MainActor struct AudioEngineTests {
    func engine() throws -> (AudioEngine, UUID) {
        let e = AudioEngine(); let id = UUID()
        try e.load(padID: id, kind: .loop, url: try #require(Bundle.main.url(forResource: "heavy-rain", withExtension: "m4a")))
        return (e, id)
    }
    @Test func toggleStartsAndStopsLoop() throws {
        let (e, id) = try engine()
        e.toggle(id); #expect(e.isPlaying(id))
        e.toggle(id); #expect(!e.isPlaying(id))
    }
    @Test func stopAllAndInterruptionClearState() throws {
        let (e, id) = try engine()
        e.toggle(id); e.stopAll(); #expect(e.playing.isEmpty)
        e.toggle(id); e.handleInterruption(); #expect(e.playing.isEmpty); #expect(e.levels.values.allSatisfy { $0 == 0 })
    }
    @Test func panIsClamped() throws {
        let (e, id) = try engine()
        e.setVolume(0.5, pan: 4, for: id)   // must not crash; internal clamp to 1
    }
    @Test func shortRecordingIsDiscarded() async throws {
        let (e, _) = try engine()
        try e.startRecording(); try await Task.sleep(for: .milliseconds(100))
        #expect(e.stopRecording() == nil); #expect(!e.isRecording)
    }
    @Test func recordingProducesFileAndEnvelope() async throws {
        let (e, id) = try engine()
        e.toggle(id); try e.startRecording()
        try await Task.sleep(for: .milliseconds(800))
        let rec = try #require(e.stopRecording())
        #expect(rec.duration >= 0.5)
        #expect(FileManager.default.fileExists(atPath: rec.url.path))
        #expect((rec.envelope[id]?.count ?? 0) >= 15)
    }
}
```

- [ ] **Step 2: Run `scripts/test.sh AudioEngineTests`** — Expected: FAIL to compile.
- [ ] **Step 3: Implement `AudioEngine.swift`** from the starter plus the additions. Keep `MeterStore` and `rms` private in the same file.
- [ ] **Step 4: Run** — Expected: PASS (the simulator has an audio device; if `engine.start()` fails in the test host, the test must still see `playing` state changes because `toggle` updates state before scheduling).
- [ ] **Step 5: Commit** `feat: audio engine with levels, loop progress, recording envelope`

---

### Task 8: SceneStore

**Files:**
- Create: `Foley/Services/SceneStore.swift`, `Foley/App/ProxyConfig.swift`, `Foley/App/AppEnvironment.swift`
- Test: `FoleyTests/SceneStoreTests.swift`, `FoleyTests/ProxyConfigTests.swift`

**Interfaces:**
- `struct ProxyConfig: Sendable { let baseURL: URL?; var isConfigured: Bool { baseURL != nil }; static func fromBundle(_ bundle: Bundle = .main) -> ProxyConfig /* reads FOLEY_PROXY_URL; empty/invalid → nil */ }`
- `@Observable @MainActor final class SceneStore { private(set) var statuses: [UUID: PadStatus]; private(set) var progress: (done: Int, total: Int); let engine: AudioEngine; let cache: AudioCache; let generation: GenerationService; let proxy: ProxyConfig; init(context: ModelContext, engine: AudioEngine, cache: AudioCache, generation: GenerationService, proxy: ProxyConfig); func status(of pad: Pad) -> PadStatus /* .playing if ready and engine.isPlaying */; func createScene(from response: SceneResponse, sourcePrompt: String) -> SoundScene /* inserts, statuses = .queued */; func generateAll(for scene: SoundScene) async; func retry(_ pad: Pad) async; func regenerate(_ pad: Pad, with spec: SoundSpec) async /* version += 1 */; func prepare(_ scene: SoundScene) async /* demo/cached pads → load into engine, status .ready; missing audio → .queued then generateAll */; func audioURL(for pad: Pad) -> URL?; func toggle(_ pad: Pad); func playAll(_ scene: SoundScene); func stopAll(); func playingCount(in scene: SoundScene) -> Int; func delete(_ pad: Pad); func deleteScene(_ scene: SoundScene); func saveMix(_ recording: MixRecording, for scene: SoundScene) throws -> Mix; func mixURL(_ mix: Mix) -> URL; func envelope(for mix: Mix) -> [UUID: [Float]]; func deleteMix(_ mix: Mix) }`
- `generateAll`: for every pad whose status is `.queued` or `.failed`, run `generation.generateSound(pad.spec)` with at most **3** concurrent tasks (a `TaskGroup` with a semaphore pattern), setting `.generating` when a task starts; on success set `pad.cacheKey`, `engine.load`, status `.ready`; on `GenerationError.busy` retry up to 3 times with 1 s, 2 s, 4 s backoff; on any other error set `.failed(error.userMessage)`; on `CancellationError` set `.failed("Cancelled")`. `progress` = (ready+failed, total) and is updated after each pad settles. Idempotent: calling while a run is active for the same scene returns immediately.
- `enum MixError: Error, Equatable { case tooShort }`
- `saveMix`: copies the `.m4a` into Application Support/Foley/Mixes/<uuid>.m4a, writes the envelope JSON next to it, inserts a `Mix` on the scene; throws `MixError.tooShort` when `recording.duration < 0.5`.
- `@Observable @MainActor final class AppEnvironment { let engine: AudioEngine; let cache: AudioCache; let proxy: ProxyConfig; let generation: GenerationService; let store: SceneStore; var isDemoOnly: Bool { false }; init(context: ModelContext) }` — picks `MockGenerationService` always in Phase A (Phase B switches on `proxy.isConfigured` and makes `isDemoOnly` real).

- [ ] **Step 1: Write the failing tests** (use an in-memory `ModelContainer` and a `CountingService: GenerationService` test double that records max concurrency and can fail chosen specs)

```swift
@Suite(.serialized) @MainActor struct SceneStoreTests {
    final class CountingService: GenerationService, @unchecked Sendable {
        var active = 0, maxActive = 0, calls = 0; var failing: Set<String> = []; var busyOnce: Set<String> = []
        let cache: AudioCache; init(cache: AudioCache) { self.cache = cache }
        func buildScene(prompt: String) async throws -> SceneResponse { fatalError() }
        func generateSound(_ spec: SoundSpec) async throws -> URL {
            if cache.contains(spec.cacheKey) { return cache.url(for: spec.cacheKey) }
            calls += 1; active += 1; maxActive = max(maxActive, active); defer { active -= 1 }
            try await Task.sleep(for: .milliseconds(50))
            if busyOnce.remove(spec.cacheKey) != nil { throw GenerationError.busy }
            if failing.contains(spec.cacheKey) { throw GenerationError.server(500) }
            let demo = Bundle.main.url(forResource: "thunder-crack", withExtension: "m4a")!
            return try cache.store(try Data(contentsOf: demo), key: spec.cacheKey)
        }
    }
    func make() throws -> (SceneStore, CountingService, SoundScene) { /* in-memory container, pirate response from DemoScene JSON, createScene */ }
    @Test func generatesWithConcurrencyThreeAndMarksReady() async throws {
        let (store, svc, scene) = try make()
        await store.generateAll(for: scene)
        #expect(svc.maxActive == 3)
        #expect(scene.pads.allSatisfy { store.status(of: $0) == .ready })
        #expect(store.progress == (6, 6))
    }
    @Test func duplicateSpecsGenerateOnce() async throws {
        let (store, svc, scene) = try make()   // make() gives two pads the same spec
        await store.generateAll(for: scene)
        #expect(svc.calls == 5)
    }
    @Test func failedPadRetriesInPlace() async throws {
        let (store, svc, scene) = try make(); let pad = scene.orderedPads[2]
        svc.failing = [pad.spec.cacheKey]
        await store.generateAll(for: scene)
        #expect(store.status(of: pad) == .failed("Couldn't make this one"))
        svc.failing = []; await store.retry(pad)
        #expect(store.status(of: pad) == .ready)
    }
    @Test func busyIsRetriedAutomatically() async throws {
        let (store, svc, scene) = try make(); let pad = scene.orderedPads[0]
        svc.busyOnce = [pad.spec.cacheKey]
        await store.generateAll(for: scene)
        #expect(store.status(of: pad) == .ready)
    }
    @Test func cancellationMarksFailedNotStuck() async throws {
        let (store, _, scene) = try make()
        let t = Task { await store.generateAll(for: scene) }
        try await Task.sleep(for: .milliseconds(20)); t.cancel(); await t.value
        #expect(scene.pads.allSatisfy { store.status(of: $0) != .generating && store.status(of: $0) != .queued })
    }
    @Test func saveMixRejectsShortRecordings() throws {
        let (store, _, scene) = try make()
        let rec = MixRecording(url: URL(fileURLWithPath: "/dev/null"), duration: 0.2, envelope: [:], padOrder: [])
        #expect(throws: MixError.tooShort) { try store.saveMix(rec, for: scene) }
    }
}
@Suite struct ProxyConfigTests {
    @Test func emptyURLMeansNotConfigured() { #expect(!ProxyConfig.fromBundle(.main).isConfigured) }
}
```

- [ ] **Step 2: Run both suites** — Expected: FAIL to compile.
- [ ] **Step 3: Implement `ProxyConfig`, `SceneStore`, `AppEnvironment`.** Busy backoff delays must be injectable (`init(..., busyDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)])`) so the test passes `[.zero]`.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat: scene store with concurrent generation, retries, mixes`

---

### Task 9: Core components in previews: SoundOrb, PadView, LoopRing, MiniMeter, MasterMeter

**Files:**
- Create: `Foley/Components/SoundOrb.swift`, `Foley/Components/PadView.swift`, `Foley/Components/MasterMeter.swift`
- Test: none (visual; previews + screenshot)

**Interfaces:**
- `struct SoundOrb: View { enum Mode { idle, generating, ready, playing }; var tint: Tint; var size: CGFloat = 96; var mode: Mode = .ready; var level: Double = 0 }` as the starter. Generating blob via `TimelineView(.animation)` + `Canvas` with blur, breathing period 2.8–3.6 s chosen from the tint's index so neighbours drift apart; Reduce Motion → static blurred circle. Ready pops in with `keyframeAnimator` scale 0.6 → 1.08 → 1.
- `struct PadDisplay: Identifiable, Equatable { id, name, meta, tint, kind, status }` and `extension PadDisplay { init(_ pad: Pad, status: PadStatus) }`.
- `struct PadView: View { var pad: PadDisplay; var level: Double; var loopProgress: Double; var onTap, onEdit, onRetry: () -> Void }` — exactly the starter's five states, shake on failure, `.sensoryFeedback` success/error, accessibility per Global Constraints, press style scale 0.96 with the orb lagging 40 ms (secondary motion: animate the orb's offset with `Motion.quick.delay(0.04)`). Long-press 0.4 s → `onEdit` with `.sensoryFeedback(.impact(weight: .medium))`.
- `struct LoopRing: View { tint, progress }`, `struct MiniMeter: View { level }`, `struct MasterMeter: View { levels: [Float]; tints: [Tint] }` as the starter.

- [ ] **Step 1: Write the three files** adapting the starters; replace every inline `Color(hex:)` with the `Theme.Colors` names from Task 2.
- [ ] **Step 2: Add a `#Preview("Pad states")` with all five states and a `#Preview("Orb modes")`.** Build: `scripts/build.sh` — Expected: success.
- [ ] **Step 3: Visual check.** Temporarily set `RootView`-less `FoleyApp` body to the pad-states preview content on the `sceneBg` background, run on the simulator, screenshot, compare with `03-Generating.png` and `05-Playing.png` pad cards (orb position top-right partly clipped, 28 pt radius, meta copy). Fix mismatches. Revert the temporary body.
- [ ] **Step 4: Commit** `feat(ui): sound orb, pad view, meters`

---

### Task 10: Text components: chips, composer, keyword text, primary button, rec pill, waveform, transport dock

**Files:**
- Create: `Foley/Components/Chips.swift`, `Foley/Components/Composer.swift`, `Foley/Components/KeywordText.swift`, `Foley/Components/PrimaryButton.swift`, `Foley/Components/RecPill.swift`, `Foley/Components/WaveformView.swift`, `Foley/Components/TransportDock.swift`, `Foley/Services/WaveformSampler.swift`
- Test: `FoleyTests/WaveformSamplerTests.swift`

**Interfaces:**
- `SoundChip(name:tint:isNew:)`, `SuggestionChip(title:tint:action:)`, `Composer(text: Binding<String>, isListening: Bool, onDictate:onSubmit:)`, `CircleIconButton(symbol:label:fill:tint:size:action:)` (glass variant: `CircleIconButton(..., glass: true)` uses `foleyGlass(Circle(), interactive: true)`), `PrimaryButton(title:symbol:isEnabled:action:)` (full-width 56 pt capsule, textPrimary fill, bg text), `RecPill(elapsed: Duration)` with glass, `WaveformView(samples:progress:tint:drawProgress:)`, `TransportDock(mode: Binding<Mode>, isPlaying:isRecording:onPlayStop:onRecord:)` — the dock sits in a `GlassEffectContainer` and uses `foleyGlass(RoundedRectangle(cornerRadius: 40))`; play/stop uses `contentTransition(.symbolEffect(.replace))`.
- `struct KeywordText: View { var text: String; var matches: [KeywordMatch]; var gapped: Set<UUID> = [] }` with `struct KeywordMatch: Identifiable { id: UUID; range: Range<String.Index>; tint: Tint }` — renders an `AttributedString` where each match gets `backgroundColor = tint.base.opacity(0.16)` and `underlineStyle = .single` with `underlineColor = tint.base`; ids in `gapped` render as the keyword's width of `"‌" + dotted leader` (replace the substring with spaces of equal character count, underlined with `.patternDot` in `sceneBorder`).
- `enum WaveformSampler { static func peaks(url: URL, count: Int) async throws -> [Float] }` — reads the file with `AVAudioFile`, splits frames into `count` buckets, bucket value = max abs sample, normalised so the max bucket is 1 (all-zero file → all zeros).

- [ ] **Step 1: Write the failing test**

```swift
@Suite struct WaveformSamplerTests {
    @Test func peaksAreNormalisedToCount() async throws {
        let url = try #require(Bundle.main.url(forResource: "thunder-crack", withExtension: "m4a"))
        let p = try await WaveformSampler.peaks(url: url, count: 56)
        #expect(p.count == 56); #expect(p.max() == 1); #expect(p.allSatisfy { (0...1).contains($0) })
    }
}
```

- [ ] **Step 2: Run** — Expected: FAIL to compile.
- [ ] **Step 3: Implement all files**; add a `#Preview("Controls")` like the starter's showing every component.
- [ ] **Step 4: Run the test and `scripts/build.sh`** — Expected: PASS / success. Screenshot the preview content on the simulator against `02-Typing.png` (chips, highlighted prompt) and `05-Playing.png` (dock, REC pill).
- [ ] **Step 5: Commit** `feat(ui): chips, composer, keyword text, transport dock, waveform`

---

### Task 11: Navigation shell, Home (01) and Library (09)

**Files:**
- Create: `Foley/App/RootView.swift`, `Foley/Screens/HomeView.swift`, `Foley/Screens/LibraryView.swift`, `Foley/Components/SceneCard.swift`, `Foley/Components/SceneBackground.swift`
- Modify: `Foley/FoleyApp.swift` (inject via `.environment(env)`, `.environment(env.store)` and `.environment(env.engine)`)

**Interfaces:**
- `enum Route: Hashable { case library; case create(initialText: String); case board(SoundScene); case mixSaved(Mix) }` (`SoundScene`/`Mix` are `@Model` classes, hashable by identity via `PersistentIdentifier`; wrap as `case board(PersistentIdentifier)` if direct use fails to compile).
- `struct RootView: View` — `NavigationStack(path: $path)` rooted at `HomeView`, `.navigationDestination(for: Route.self)`, hides the system navigation bar on every screen (custom headers per the designs), `.preferredColorScheme(.dark)`, and runs `DemoSeeder` in `.task`.
- `HomeView`: wordmark "foley" (34 pt semibold, lowercase), top-right 44 pt glass circle button (`square.grid.2x2`) → `.library`; centred idle `SoundOrb(tint: .blue, size: 160, mode: .idle)` rendered desaturated (`.saturation(0.1)`) with a dashed orbit ring (220 pt, 1 pt, `border`, rotating 360° over 40 s, static under Reduce Motion); "Describe a scene." hero + "Foley turns it into sounds you can tap, layer and loop."; `SectionLabel("Try one")` + four `SuggestionChip`s (Rainy café in Tokyo/teal, Haunted house/lavender, Pirate ship in a storm/blue, Campfire at night/amber) in a wrapping flow layout; `Composer` pinned above the keyboard. Tapping a chip types its text into the composer at 30 chars/s with `.sensoryFeedback(.selection)` per word; the orb's saturation rises with `min(1, text.count / 40)`. Submit → `.create(initialText: text)`. Mic → `Dictation` (Task 17; stub the call for now).
- `LibraryView`: "Your scenes" title + glass "+" button (pops to Home); glass search field; `@Query(sort: \SoundScene.createdAt, order: .reverse)`; `SceneCard` rows with `.scrollTransition` scale 0.94/fade at edges and a slight orb-row parallax; empty state after search "No scenes match"; swipe/long-press context menu "Delete" (demo scenes can be deleted too). Tap → `.board(scene)`; play button → `.board(scene)` then `store.playAll`.
- `SceneCard(scene:mixCount:onPlay:)`: mood-tinted gradient top-left, row of small orbs (one per pad, 36 pt), title (22 pt), meta "N sounds · M mixes · <relative date>" (omit the mixes part when 0), 44 pt play button.
- `SceneBackground(mood: Tint, active: [(Tint, Double)])`: `MeshGradient` 3×3 over `sceneBg`, top colour `sceneGlow` blended toward each active tint weighted by its level (max 35 % influence), animated with `Motion.level`.

- [ ] **Step 1: Implement the files.** `scripts/build.sh` — Expected: success.
- [ ] **Step 2: Run on the simulator.** Screenshot Home and compare with `01-Main.png`; tap the library button, compare with `09-Library.png` (two demo cards visible). Tap a suggestion chip and confirm it types in. Fix mismatches.
- [ ] **Step 3: Run `scripts/test.sh`** — Expected: all PASS.
- [ ] **Step 4: Commit** `feat(screens): navigation shell, home and library`

---

### Task 12: Create flow (02 Typing + 03 Generating) with the word-to-pad flight

**Files:**
- Create: `Foley/Screens/CreateView.swift`, `Foley/Components/FlightOverlay.swift`, `Foley/Screens/ProxySetupCard.swift`
- Test: none beyond existing suites (logic lives in Task 3/4/8)

**Interfaces:**
- `CreateView(initialText: String)` with `@State private var phase: Phase` where `enum Phase { case typing, generating(SoundScene) }`, `@State private var text`, `@State private var parsed: SceneResponse?`, `@State private var parseTask: Task<Void, Never>?`, settings `ambientLoops: Bool = true`, `clipLength: ClipLength = .auto` (`enum ClipLength { auto, short /* 5 */, medium /* 10 */, long /* 15 */ }` applied to loops only when not auto; one-shots keep the parser's duration).
- Typing layout (mock 02): close button (pops), status pill "Listening for sounds" with a teal dot (pulsing while a parse is in flight); card with `KeywordText` over a `TextEditor`-backed field (use a `TextField(axis: .vertical)` with the attributed overlay drawn behind it at matching font/metrics, or a `TextEditor` with transparent text and the `KeywordText` as an overlay); "N sounds detected" / "Max 8" with the chip row (extras beyond 8 greyed, `isNew` on the most recent); settings card (toggle "Ambient sounds loop", "Clip length" menu); `PrimaryButton("Build scene", symbol: "sparkles")` disabled with a hint "Describe at least one sound" while `parsed?.sounds.isEmpty != false`.
- Live parse: on `text` change, cancel `parseTask`, sleep 900 ms, call `store.generation.buildScene(prompt:)`, `validated(for:)`, store in `parsed`, animate chip insertions with `Motion.spring` and `.sensoryFeedback(.selection)`. If `env.isDemoOnly` (an `AppEnvironment` property; always `false` in Phase A, wired for real in Phase B) show `ProxySetupCard` instead of parsing.
- Build: if `parsed` is nil or stale (text changed since), parse first. Then capture chip anchors (`.anchorPreference(key: ChipAnchors.self)` keyed by sound index) and pad-slot anchors from the generating layout (rendered invisibly for one frame, or computed from the known grid geometry: 2 columns, 12 pt gap, 20 pt side padding, 150 pt rows, grid origin below the header), create the scene with `store.createScene`, switch `phase` to `.generating(scene)`, and run `FlightOverlay`: each chip animates from its source rect to its pad slot's top-left (inset 14 pt) with `Motion.spring.delay(Double(i) * 0.08)` and `.sensoryFeedback(.impact(weight: .soft))` per landing; the source `KeywordText` marks each flown id as `gapped`. After the last landing, start `store.generateAll(for: scene)`. Reduce Motion: chips fade out and pads fade in.
- Generating layout (mock 03): back button + title + "Building N of M sounds…" + progress bar that fills with a spring per settled pad; the pad grid (`PadView` per pad with `store.status(of:)`); source prompt card at the bottom with `KeywordText` gapped for landed keywords (chips still hover over generating pads until they turn ready). When `store.progress.done == total`: if every pad failed show a full-screen "Couldn't build this scene" + Retry; otherwise replace the path with `.board(scene)` inside `withTransaction(\.disablesAnimations, true)` so the grid stays put while the header morphs on the Board.
- `ProxySetupCard`: title "Connect your proxy to generate new sounds", body "Foley needs its Cloudflare Worker URL in Config/Local.xcconfig. The demo scenes work without it.", a "How to set it up" link to the repo README (`https://github.com/<owner>/Foley#proxy`), and "Open a demo scene" → `.library`.

- [ ] **Step 1: Implement.** `scripts/build.sh` — Expected: success.
- [ ] **Step 2: Simulator check.** From Home type the pirate prompt; chips appear after a pause; screenshot vs `02-Typing.png`. Tap Build; record a short video (`xcrun simctl io booted recordVideo`) and confirm chips fly staggered into the grid and pads move queued → generating → ready; screenshot vs `03-Generating.png`. Toggle Reduce Motion in the simulator's Accessibility settings and confirm fades.
- [ ] **Step 3: Run `scripts/test.sh`** — Expected: PASS.
- [ ] **Step 4: Commit** `feat(screens): create flow with live parsing and word-to-pad flight`

---

### Task 13: Board (04) and Playing (05)

**Files:**
- Create: `Foley/Screens/BoardView.swift`
- Modify: `Foley/App/RootView.swift` (destination)

**Interfaces:**
- `BoardView(scene: SoundScene)` with `@State private var mode: TransportDock.Mode = .grid`, `@Namespace private var orbNS`, `@State private var editing: Pad?`, `@State private var showMixes = false`.
- Header (mock 04/05): glass back circle (stops nothing; playback continues until the user stops it, but `stopAll` when the view disappears from the stack), optional `RecPill` centred while recording, glass "more" circle with a `Menu`: "Mixes (N)", "Share scene" (share sheet with a text summary: title, prompt, pad names), "Delete scene" (confirm; pops). Title 30 pt; subtitle "N sounds · tap to play, hold to edit" when nothing plays, else "N of M playing · tap to toggle"; "Demo" capsule badge next to the title when `scene.isDemo`. `MasterMeter` under the subtitle only while something plays (`.transition(.opacity.combined(with: .move(edge: .top)))`).
- Grid: `LazyVGrid` 2 columns, gap 12, `PadView` per `orderedPads` with `level: engine.levels[id]`, `loopProgress: engine.loopProgress(for:)` read inside a `TimelineView(.animation)` so it ticks at display rate; tap → `store.toggle(pad)` with a Core Haptics-free `.sensoryFeedback(.impact(weight: pad.kind == .oneShot ? .heavy : .light))`; long-press → `editing = pad` (sheet, Task 15). Pads re-flow for 1–8 pads. Failed pads show Retry → `store.retry`.
- Dock pinned bottom: `TransportDock`; play/stop → `store.playAll(scene)` / `store.stopAll()`; Rec → `engine.startRecording()`; Done → `engine.stopRecording()` → `store.saveMix` → push `.mixSaved(mix)`; a `nil` recording shows a brief toast "Recording too short".
- `SceneBackground` behind everything with `active` = playing pads' `(tint, level)`.
- `.onAppear { Task { await store.prepare(scene) } }` so demo and cached scenes load into the engine; pads with missing audio go through `generateAll`.
- Orbit mode is Task 14; for now the toggle switches `mode` and shows a placeholder.

- [ ] **Step 1: Implement.** `scripts/build.sh` — Expected: success.
- [ ] **Step 2: Simulator check.** Open the pirate demo from the Library; screenshot vs `04-Board.png`. Tap three pads; confirm sound plays, orbs pulse, loop rings rotate, `MasterMeter` appears and the background tints; screenshot vs `05-Playing.png`. Tap Rec, wait, tap Done; confirm navigation to a placeholder Mix saved route does not crash (Task 16 builds the screen; until then push and show the mix id). Back out and reopen; pads are still `.ready`.
- [ ] **Step 3: Run `scripts/test.sh`** — Expected: PASS.
- [ ] **Step 4: Commit** `feat(screens): board and playing with live glow and recording`

---

### Task 14: Orbit mixer (06)

**Files:**
- Create: `Foley/Components/OrbitNode.swift`
- Modify: `Foley/Screens/BoardView.swift` (orbit layout)

**Interfaces:**
- `OrbitNode(pad: PadDisplay, level: Double, volume: Double, pan: Double, isDragging: Bool)` — orb diameter `44 + volume * 40`, name under it (13 pt), dragging: scale 1.06, ring halo, readout pill above-right `"\(Int(volume*100))% · \(pan == 0 ? "C" : (pan < 0 ? "L" : "R") + String(Int(abs(pan)*100)))"` in a glass capsule.
- Orbit layout in `BoardView` when `mode == .orbit` (mock 06): header "Mixer" with a glass reset button (animates all nodes back to defaults volume 0.8 / pan 0 with `Motion.spring`), a 350 pt square orbit area: three dashed rings at radii 60/110/160, a "YOU" glass node (64 pt) in the centre, "L"/"R" markers at the horizontal extremes; each pad's node at polar position: radius = `(1 - volume) * 160 + 20`, angle = `asin(clamped pan)` mirrored so pan maps to x offset / radius, initial angle spread evenly when pan == 0 (`-80°…80°` from the top, by `sortIndex`); legend "↓ Closer = louder  ↔ Sides = pan"; master volume card with `Slider` bound to `engine.masterVolume` and "NN%" `.monospacedDigit()`; bottom segmented "Grid | Orbit" (glass) that also drives `mode`.
- Drag: `DragGesture` on each node; volume = `1 - min(distance, 160) / 160` clamped 0.05…1, pan = `clamp(dx / 160, -1, 1)`; rubber-band beyond 160 (`distance = 160 + (d - 160) * 0.25`), release springs back inside; `store`/`engine.setVolume` applied live; `.sensoryFeedback(.selection)` when crossing 25/50/75/100 %; on release write `pad.volume`/`pad.pan`. Dashed line from the node to centre while dragging.
- Grid ↔ orbit: the orb inside each `PadView` and the `OrbitNode` orb share `.matchedGeometryEffect(id: pad.id, in: orbNS)` so switching modes flies the orbs; pads' cards fade. Under Reduce Motion, cross-fade.
- Accessibility: each node `accessibilityAdjustableAction` adjusting volume by 0.1; label "<name>, volume NN percent, pan <L/C/R>".

- [ ] **Step 1: Implement.** `scripts/build.sh` — Expected: success.
- [ ] **Step 2: Simulator check.** Switch to Orbit with three pads playing; screenshot vs `06-Mixer.png`; drag a node outward and confirm the readout, the dashed line, and that the sound gets quieter; reset restores; switch back to Grid and the orbs fly home.
- [ ] **Step 3: Commit** `feat(screens): orbit mixer with drag volume and pan`

---

### Task 15: Pad sheet (07)

**Files:**
- Create: `Foley/Screens/PadSheetView.swift`
- Modify: `Foley/Screens/BoardView.swift` (`.sheet(item: $editing)` with `.presentationDetents([.large])`, `.presentationBackground(Theme.Colors.sheet)`, `.presentationCornerRadius(34)`)

**Interfaces:**
- `PadSheetView(pad: Pad)` reads `store`/`engine` from the environment. Header: `SoundOrb(size: 88, mode: regenerating ? .generating : .ready)` + name (28 pt) + meta "One-shot · 4.0s · version N" + glass close. Play button + `WaveformView` (peaks via `WaveformSampler.peaks(url:count: 56)`, `progress` from a 60 Hz `TimelineView` reading `engine.loopProgress` while this pad plays). "Sound prompt" `SectionLabel` + multi-line field bound to a local `draft: SoundSpec`. Glass segmented Loop / One-shot. "Length" slider 0.5…22 (step 0.5, label "4.0s"); "Follow my prompt" slider 0…1 (label "0.6", captions "More creative" / "More literal"). Bottom: "Delete" (outlined, `error` text; confirm → `store.delete(pad)`, dismiss) and `PrimaryButton("Regenerate", symbol: "arrow.clockwise")` enabled only when `draft != pad.spec` or the pad is failed.
- Regenerate: set `regenerating = true`, disable controls, `await store.regenerate(pad, with: draft)` (which bumps `version`, generates, reloads the engine), then `regenerating = false`; on failure show "Couldn't make this one" inline with Retry. The orb cross-fades to the blob with `Motion.spring`.
- Presentation: the sheet opens from the long-pressed pad with `.navigationTransition(.zoom(sourceID: pad.id, in: zoomNS))` where available for sheets; if the zoom transition does not apply to `.sheet`, use the standard sheet with the pad's `matchedTransitionSource`.

- [ ] **Step 1: Implement.** `scripts/build.sh` — Expected: success.
- [ ] **Step 2: Simulator check.** Long-press "Thunder crack"; screenshot vs `07-PadSheet.png`; change the length and tap Regenerate: orb melts to a blob, controls disable, pad returns ready with "version 2"; Delete removes the pad and the grid reflows.
- [ ] **Step 3: Run `scripts/test.sh`** — Expected: PASS.
- [ ] **Step 4: Commit** `feat(screens): pad sheet with regenerate and delete`

---

### Task 16: MixRenderer (9:16 video), Mix saved (08), Mixes list, share rows

**Files:**
- Create: `Foley/Services/MixRenderer.swift`, `Foley/Screens/MixSavedView.swift`, `Foley/Screens/MixesListView.swift`, `Foley/Components/ShareRow.swift`
- Test: `FoleyTests/MixRendererTests.swift`

**Interfaces:**
- `struct MixVideoInput: Sendable { var title: String; var pads: [(id: UUID, name: String, tint: Tint)]; var envelope: [UUID: [Float]]; var envelopeRate: Double /* 30 */; var duration: TimeInterval; var audioURL: URL }`
- `final class MixRenderer: Sendable { init(size: CGSize = CGSize(width: 1080, height: 1920), fps: Int = 30); func render(_ input: MixVideoInput, to outputURL: URL, progress: @Sendable @escaping (Double) -> Void) async throws -> URL }` — `AVAssetWriter` H.264 video track fed from a `CVPixelBufferPool` drawn with Core Graphics per frame: `sceneBg` background with a vertical gradient to `sceneGlow`, title at the top (SF semibold 64 px), the pads' orbs laid out in a 2-column grid of circles whose radius and glow alpha follow their envelope sample at that frame (`Tint` colours via `hexBase`/highlight/shadow radial gradient), a 40-bar progress waveform near the bottom, and "Sounds generated with ElevenLabs" at the bottom; audio track appended from `audioURL` via `AVAssetReader` (AAC passthrough into the writer's audio input, or re-encoded with `AVAssetExportSession` after muxing — pick the one that works first). Runs off the main actor; `progress` 0…1.
- `MixSavedView(mix: Mix)`: header back + "✓ Mix saved"; hero card (radius 32, mood gradient) with the pads' orb row doing a staggered pop on appear, title, "N layers · 0:42 · <relative time>", `WaveformView` (peaks of the mix, tinted by cycling pad tints per bucket, drawing left to right on first appear), play button + "0:00 / 0:42" `.monospacedDigit()` using an `AVAudioPlayer`; `SectionLabel("Share")` + three `ShareRow`s: "Share video" / "Pads animate to your mix · 9:16" (renders with `MixRenderer` into `temporaryDirectory`, busy ring from `progress`, then `ShareLink`-style `UIActivityViewController` via `.sheet`), "Save audio" / ".m4a to Files" (`fileExporter`), "Share scene" / "Friends can remix the board" (share sheet with the text summary). Footer "Sounds generated with ElevenLabs". Export failure → inline "Couldn't export the video" + Retry.
- `ShareRow(symbol:title:subtitle:isBusy:progress:action:)` — 64 pt row, glass icon tile, progress ring when busy.
- `MixesListView(scene: SoundScene)` — sheet listing `scene.mixes` newest first (duration, relative date, play glyph), tap → `.mixSaved(mix)`, swipe to delete → `store.deleteMix`.

- [ ] **Step 1: Write the failing test**

```swift
@Suite struct MixRendererTests {
    @Test func rendersPortraitVideoWithAudio() async throws {
        let audio = try #require(Bundle.main.url(forResource: "thunder-crack", withExtension: "m4a"))
        let id = UUID()
        let input = MixVideoInput(title: "Test", pads: [(id, "Thunder", .blue)],
            envelope: [id: (0..<60).map { Float($0 % 10) / 10 }], envelopeRate: 30, duration: 2, audioURL: audio)
        let out = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).mp4")
        _ = try await MixRenderer(fps: 15).render(input, to: out) { _ in }
        let asset = AVURLAsset(url: out)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await video.load(.naturalSize) == CGSize(width: 1080, height: 1920))
        #expect(abs(try await asset.load(.duration).seconds - 2) < 0.3)
    }
}
```

- [ ] **Step 2: Run `scripts/test.sh MixRendererTests`** — Expected: FAIL to compile.
- [ ] **Step 3: Implement `MixRenderer`**, then the views and the Board's "Mixes" menu item.
- [ ] **Step 4: Run the test and `scripts/build.sh`** — Expected: PASS / success. Simulator: record a 10 s mix, screenshot vs `08-Export.png`, tap Share video and confirm the share sheet opens with an `.mp4`; Save audio opens the file exporter; reopen the mix from the Board's Mixes list.
- [ ] **Step 5: Commit** `feat: mix video renderer, mix saved screen, mixes list`

---

### Task 17: Dictation, app icon, polish pass (haptics, Reduce Motion, VoiceOver, glass audit)

**Files:**
- Create: `Foley/Services/Dictation.swift`, `scripts/make_app_icon.py`, `Foley/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (+ `Contents.json` update)
- Modify: any screen/component found wanting in the audit

**Interfaces:**
- `@Observable @MainActor final class Dictation { private(set) var transcript: String; private(set) var isListening: Bool; private(set) var isAvailable: Bool; func start() async throws; func stop() }` using `SFSpeechRecognizer` + `AVAudioEngine` input tap (a separate engine instance from playback; stop playback levels pump interference by pausing `AudioEngine` while listening). `HomeView` appends `transcript` to the composer live; mic button shows `isListening` state; unavailable → toast "Dictation isn't available".
- `scripts/make_app_icon.py`: 1024×1024 PNG with `bg` background and an amber→blue radial orb matching `Tint.orbGradient`, glow included; `Contents.json` single-size universal entry.

- [ ] **Step 1: Implement `Dictation` and wire it into `HomeView`.** Build; on the simulator tap the mic, grant permission, speak via the Mac mic, confirm text appears.
- [ ] **Step 2: Generate the icon** (`python3 scripts/make_app_icon.py`), build, confirm it shows on the simulator home screen.
- [ ] **Step 3: Audit against the handoff motion table and the spec's "Interaction additions"** — walk every screen with (a) Reduce Motion on, (b) VoiceOver on (`xcrun simctl spawn booted defaults` or Settings), (c) 1 pad and 8 pads scenes (make one with the mock), (d) the mock's `failEvery: 3` to see failed/retry on every surface. Fix what's broken. Confirm no view file contains `Color(hex:` (`grep -rn "Color(hex" Foley/Components Foley/Screens` is empty).
- [ ] **Step 4: Run `scripts/test.sh`** — Expected: PASS.
- [ ] **Step 5: Commit** `feat: dictation, app icon, accessibility and motion polish`

---

### Task 18: Phase A acceptance

- [ ] **Step 1: Fresh-clone check.** `git clone` the repo into the scratchpad, `cp Config/Local.xcconfig.example Config/Local.xcconfig`, run `scripts/build.sh` and `scripts/test.sh` there. Expected: both succeed with no changes.
- [ ] **Step 2: Secret scan.** `git log -p | grep -iE "sk-|xi-api|api_key|FOLEY_PROXY_URL ?= ?https" ` returns nothing.
- [ ] **Step 3: Walkthrough video.** Record the simulator: Home → chip → Typing → Build → flight → Board → play 3 pads → Orbit drag → Pad sheet regenerate → Rec → Mix saved → Share video. Save to `docs/qa/phase-a.mp4` (gitignored) for the user to review.
- [ ] **Step 4: Commit any fixes** `chore: phase A acceptance fixes`.
