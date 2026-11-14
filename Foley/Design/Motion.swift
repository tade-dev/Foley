import SwiftUI

/// Spring vocabulary for the whole app. Springs everywhere; linear only for continuous loops.
enum Motion {
    /// The hero spring: word-to-pad flight, pad pops, mode switches.
    static let spring = Animation.spring(response: 0.55, dampingFraction: 0.72)
    /// Press feedback and small state changes.
    static let quick = Animation.spring(response: 0.25, dampingFraction: 0.7)
    /// Segmented controls and toggles.
    static let seg = Animation.spring(response: 0.35, dampingFraction: 0.8)
    /// Following live audio levels.
    static let level = Animation.interactiveSpring(response: 0.12, dampingFraction: 0.8)
    /// Stagger between neighbouring items in a flight or pop.
    static let stagger: Double = 0.08
}

extension View {
    /// Under Reduce Motion, replace a transition with a plain fade.
    @ViewBuilder
    func reduceMotionFade(_ reduce: Bool) -> some View {
        if reduce { transition(.opacity) } else { self }
    }
}
