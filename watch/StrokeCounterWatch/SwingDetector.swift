import Foundation

// Finds full golf swings in the watch's motion, one sample at a time (any rate; the watch uses 50 Hz). A swing is a fast turn of the wrist
// (rotation rate of at least 17 rad/s) with a hard jolt near it (user acceleration of at least 4 g within 0.4 s
// before and 0.8 s after the turn starts): the ball being hit, or the club meeting the ground. Walking, carrying the
// bag or tapping the watch stay well below. Only the strength counts, not the direction, so it works on either wrist
// and for left- and right-handed players. Chips around the green and putts are too gentle and are not found.
// Thresholds from two recorded rounds (swing detection step 1): 21 of 27 shots other than putts found, the six
// missed all short wedge shots near the green.
struct SwingDetector {
    struct Swing: Equatable {
        let t: Double          // seconds, on the same clock as the samples: when the turn peaked
        let rotation: Double   // peak rotation rate, rad/s
        let impact: Double     // peak acceleration, g
    }

    static let minRotation = 17.0
    static let minImpact = 4.0
    static let before = 0.4    // seconds of acceleration kept from before the turn
    static let after = 0.8     // seconds the turn is followed
    static let quiet = 1.5     // seconds after a peak before a new swing can start

    private var recent: [(t: Double, acceleration: Double)] = []
    private var candidate: (start: Double, peak: Double, rotation: Double, impact: Double)?
    private var quietUntil = -Double.infinity

    // Feeds one sample (magnitudes); returns a swing once one has been followed to its end.
    mutating func add(t: Double, rotation: Double, acceleration: Double) -> Swing? {
        recent.append((t, acceleration))
        while let first = recent.first, first.t < t - Self.before { recent.removeFirst() }

        if var c = candidate {
            if rotation > c.rotation { c.rotation = rotation; c.peak = t }
            c.impact = max(c.impact, acceleration)
            guard t >= c.start + Self.after else { candidate = c; return nil }
            candidate = nil
            quietUntil = c.peak + Self.quiet
            return c.impact >= Self.minImpact ? Swing(t: c.peak, rotation: c.rotation, impact: c.impact) : nil
        }
        if t >= quietUntil, rotation >= Self.minRotation {
            candidate = (t, t, rotation, recent.map(\.acceleration).max() ?? acceleration)
        }
        return nil
    }
}
