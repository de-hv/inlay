import Foundation

/// A cubic Bézier timing curve from (0, 0) to (1, 1), like the 'bezier' of Hyprland and the cubic-bezier() of CSS:
/// the progress of the time on X, the progress of the movement on Y. Pure.
/// Y can go below 0 or above 1: the window then goes past its frame and comes back (an overshoot)
struct AnimationCurve: Equatable, Sendable {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double

    /// Quick to leave, gentle to arrive: 1 - (1 - t)³ exactly. The curve of Inlay until there were curves
    static let easeOut = AnimationCurve(x1: 1.0 / 3, y1: 1, x2: 2.0 / 3, y2: 1)

    /// The curves that every config has, by name. A curve of [animations.curves] with the same name wins
    static let presets: [String: AnimationCurve] = [
        "ease-out": .easeOut,
        "linear": AnimationCurve(x1: 0, y1: 0, x2: 1, y2: 1),
        "ease": AnimationCurve(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1),
        "ease-in-out": AnimationCurve(x1: 0.42, y1: 0, x2: 0.58, y2: 1),
        "snappy": AnimationCurve(x1: 0.2, y1: 0.9, x2: 0.1, y2: 1),
        "overshot": AnimationCurve(x1: 0.05, y1: 0.9, x2: 0.1, y2: 1.1),
        // easeOutQuint, the curve of the windows in Hyprland and Omarchy
        "quint": AnimationCurve(x1: 0.23, y1: 1, x2: 0.32, y2: 1),
        // easeOutExpo: fast to leave and very gentle to arrive, like the animations of macOS
        "expo": AnimationCurve(x1: 0.16, y1: 1, x2: 0.3, y2: 1),
        // The 'quick' curve of Hyprland
        "quick": AnimationCurve(x1: 0.15, y1: 0, x2: 0.1, y2: 1),
    ]

    /// The progress of the movement when `progress` of the time has passed. 0 at 0 and 1 at 1
    func value(_ progress: Double) -> Double {
        if progress <= 0 { return 0 }
        if progress >= 1 { return 1 }
        if x1 == y1 && x2 == y2 { return progress } // A straight line
        return sample(y1, y2, solveT(forX: progress))
    }

    private func sample(_ p1: Double, _ p2: Double, _ t: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }

    private func slope(_ p1: Double, _ p2: Double, _ t: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * p1 + 6 * u * t * (p2 - p1) + 3 * t * t * (1 - p2)
    }

    /// The parameter of the curve whose X is `x`. X grows with t (x1 and x2 are in 0 ... 1): Newton first, bisection if it stalls
    private func solveT(forX x: Double) -> Double {
        var t = x
        for _ in 0 ..< 8 {
            let error = sample(x1, x2, t) - x
            if abs(error) < 1e-7 { return t }
            let d = slope(x1, x2, t)
            if abs(d) < 1e-6 { break }
            t -= error / d
        }
        var low = 0.0
        var high = 1.0
        t = x
        for _ in 0 ..< 40 {
            let value = sample(x1, x2, t)
            if abs(value - x) < 1e-7 { return t }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return t
    }
}
