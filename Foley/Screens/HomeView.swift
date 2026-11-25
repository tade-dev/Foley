import SwiftUI

/// Screen 01: wordmark, idle orb, "Describe a scene.", suggestion chips, composer.
struct HomeView: View {
    @Environment(Router.self) private var router
    @Environment(AudioEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var typingTask: Task<Void, Never>?
    @State private var typedWords = 0
    @State private var dictation = Dictation()
    @FocusState private var composerFocused: Bool

    private let suggestions: [(String, Tint)] = [
        ("Rainy café in Tokyo", .teal), ("Haunted house", .lavender),
        ("Pirate ship in a storm", .blue), ("Campfire at night", .amber),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            // The hero sits outside the scroll view: a scroll view clips its contents, and the
            // orb is meant to be thrown past its own bounds.
            hero
                .padding(.top, composerFocused ? 10 : 28)
                .padding(.horizontal, Theme.Space.l)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Try one")
                    FlowLayout(spacing: 10) {
                        ForEach(suggestions, id: \.0) { title, tint in
                            SuggestionChip(title: title, tint: tint) { type(title) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 28)
                .padding(.horizontal, Theme.Space.l)
                // Empty space around the chips puts the keyboard away; the chips themselves still work.
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { composerFocused = false })
            }
            .scrollDismissesKeyboard(.interactively)
            Composer(text: $text, focused: $composerFocused, isListening: dictation.isListening,
                     onDictate: toggleDictation, onSubmit: submit)
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.xs)
        }
        .animation(Motion.keyboard, value: composerFocused)
        .background(
            Theme.Colors.bg
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { composerFocused = false }
        )
        .sensoryFeedback(.selection, trigger: typedWords)
        .onChange(of: dictation.transcript) { _, new in if dictation.isListening { text = new } }
        .onDisappear { dictation.stop() }
    }

    private var header: some View {
        HStack {
            Text("foley")
                .font(Theme.Fonts.hero)
                .tracking(-1)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            CircleIconButton(symbol: "square.grid.2x2", label: "Your scenes", size: 52, glass: true) {
                router.push(.library)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.xs)
    }

    /// At rest the orb sits inside its rings above the title. While you type it flies up and
    /// shrinks into a badge beside a smaller title, which frees the room the keyboard needs.
    ///
    /// `AnyLayout` re-places the same two views rather than swapping branches, so the orb keeps
    /// its identity and its physics, and SwiftUI interpolates the move for free.
    private var hero: some View {
        VStack(spacing: composerFocused ? 0 : 18) {
            let layout = composerFocused
                ? AnyLayout(HStackLayout(alignment: .center, spacing: 14))
                : AnyLayout(VStackLayout(spacing: 18))

            layout {
                orbCluster
                Text("Describe a scene.")
                    .font(.system(size: composerFocused ? 22 : 34, weight: .semibold))
                    .tracking(composerFocused ? -0.4 : -1)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize()
                if composerFocused { Spacer(minLength: 0) }
            }

            Text("Foley turns it into sounds you can tap,\nlayer and loop.")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: composerFocused ? 0 : nil)
                .opacity(composerFocused ? 0 : 1)
                .clipped()
        }
        .frame(maxWidth: .infinity, alignment: composerFocused ? .leading : .center)
        .contentShape(Rectangle())
        .onTapGesture { composerFocused = false }
    }

    /// The orb and its orbit rings. Both shrink together; the rings fade out on the way.
    private var orbCluster: some View {
        let side: CGFloat = composerFocused ? 46 : 240
        return ZStack {
            Circle()
                .strokeBorder(Theme.Colors.border, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .frame(width: 228, height: 228)
                .modifier(SlowSpin(enabled: !reduceMotion && !composerFocused))
                .opacity(composerFocused ? 0 : 1)
            Circle()
                .strokeBorder(Theme.Colors.border.opacity(0.6), lineWidth: 1)
                .frame(width: 176, height: 176)
                .opacity(composerFocused ? 0 : 1)
            InteractiveOrb(tint: .blue,
                           size: composerFocused ? 42 : 154,
                           excitement: min(1, Double(text.count) / 40),
                           travel: composerFocused ? 0 : 92) { speed in
                engine.pluck(speed: speed)
            }
            .saturation(0.25 + 0.75 * min(1, Double(text.count) / 40))
            .brightness(text.isEmpty ? -0.1 : 0)
            .animation(Motion.spring, value: text.count)
        }
        .frame(width: side, height: side)
    }

    // MARK: Actions

    /// Types the suggestion into the composer at ~30 characters per second.
    private func type(_ title: String) {
        typingTask?.cancel()
        text = ""
        guard !reduceMotion else { text = title; return }
        typingTask = Task {
            for ch in title {
                guard !Task.isCancelled else { return }
                text.append(ch)
                if ch == " " { typedWords += 1 }
                try? await Task.sleep(for: .milliseconds(33))
            }
            typedWords += 1
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dictation.stop()
        router.push(.create(initialText: trimmed))
    }

    private func toggleDictation() {
        if dictation.isListening { dictation.stop() } else { Task { await dictation.start() } }
    }
}

/// Rotates its content once every 40 seconds.
private struct SlowSpin: ViewModifier {
    var enabled: Bool
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !enabled)) { ctx in
            content.rotationEffect(.degrees(enabled ? ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 40) * 9 : 0))
        }
    }
}

/// Wraps chips onto as many rows as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, origin) in arrange(proposal: proposal, subviews: subviews).origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), origins)
    }
}
