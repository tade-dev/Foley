import CoreGraphics
import Foundation

/// The feel of the home-screen orb, kept out of the view so it can be tuned and tested.
/// A damped spring pulls it home; its speed stretches it along the direction of travel.
nonisolated struct OrbPhysics {
    /// Offset from the centre, in points.
    private(set) var position: CGPoint = .zero
    private(set) var velocity: CGVector = .zero
    private(set) var isDragging = false

    /// Stiffness and damping chosen so a hard fling crosses centre once or twice, then settles.
    var stiffness: Double = 120
    var damping: Double = 7.5
    /// How far past the ring the orb may travel before the spring hauls it back.
    var maxOffset: Double = 120

    var speed: Double { (velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot() }

    /// 0 at rest, up to 0.45 when flung hard: the fraction the blob stretches along its travel.
    var stretch: Double { min(0.45, speed / 4500) }

    /// Direction of travel, for pointing the stretch.
    var heading: Double { atan2(velocity.dy, velocity.dx) }

    mutating func beginDrag() {
        isDragging = true
        velocity = .zero
    }

    /// While held, the orb sits exactly under the finger; the spring is suspended.
    mutating func drag(to point: CGPoint) {
        let distance = (point.x * point.x + point.y * point.y).squareRoot()
        if distance > maxOffset {
            // Beyond the ring it rubber-bands, so the orb never flies off the screen.
            let pull = maxOffset + (distance - maxOffset) * 0.35
            position = CGPoint(x: point.x / distance * pull, y: point.y / distance * pull)
        } else {
            position = point
        }
    }

    mutating func release(velocity: CGVector) {
        isDragging = false
        // Cap the throw so one violent flick cannot outrun the integrator.
        let speed = (velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot()
        let capped = min(speed, 3000)
        self.velocity = speed > 0
            ? CGVector(dx: velocity.dx / speed * capped, dy: velocity.dy / speed * capped)
            : .zero
    }

    /// Semi-implicit Euler: stable at 60Hz and cheap enough to run every frame.
    mutating func step(dt: Double) {
        guard !isDragging else { return }
        let ax = -stiffness * position.x - damping * velocity.dx
        let ay = -stiffness * position.y - damping * velocity.dy
        velocity = CGVector(dx: velocity.dx + ax * dt, dy: velocity.dy + ay * dt)
        position = CGPoint(x: position.x + velocity.dx * dt, y: position.y + velocity.dy * dt)

        // Settle rather than jitter forever below the threshold of visibility.
        if speed < 1, abs(position.x) < 0.5, abs(position.y) < 0.5 {
            position = .zero
            velocity = .zero
        }
    }

    // MARK: Sound

    /// A pentatonic scale, so however the orb is played it never sounds wrong.
    static let pentatonic: [Double] = [
        220.00, 246.94, 277.18, 329.63, 369.99,   // A3 B3 C#4 E4 F#4
        440.00, 493.88, 554.37, 659.25, 739.99,   // A4 B4 C#5 E5 F#5
        880.00,
    ]

    /// Harder throws ring brighter. Clamped at both ends.
    static func note(forSpeed speed: Double) -> Double {
        let t = min(1, max(0, speed / 2600))
        let index = Int((t * Double(pentatonic.count - 1)).rounded())
        return pentatonic[min(pentatonic.count - 1, max(0, index))]
    }
}
