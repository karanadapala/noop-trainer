import Foundation

/// Distance covered by `t` seconds into a session: one GPS fix.
public struct DistanceSample: Equatable, Sendable {
    public let t: Double
    public let metres: Double

    public init(t: Double, metres: Double) {
        self.t = t
        self.metres = metres
    }
}

/// Warns when a run gets faster than the user's own easy pace (D84). Speed reacts at once; heart rate
/// lags 30–60 s behind, so this speaks up first. Pure: the caller keeps the samples and remembers which
/// run it has already warned about.
public enum SpeedGuard {
    /// Speed is judged over this many seconds.
    public static let window = 15.0
    /// The first seconds of a run are the speed-up from walking; neither the baseline nor the warning
    /// looks at them.
    public static let settle = 20.0
    /// 10% faster than easy pace.
    public static let margin = 1.10
    public static let warning = "Ease off a little."

    /// Average speed (m/s) of each run in a past session.
    public static func runSpeeds(session: GuidedSession, samples: [DistanceSample]) -> [Double] {
        zip(session.segments, session.segmentStarts).compactMap { seg, start in
            guard seg.kind.isRun else { return nil }
            return speed(samples, from: Double(start) + settle, to: Double(start + seg.seconds))
        }
    }

    /// The median run speed: the user's own easy pace. Nil until there are earlier runs.
    public static func easySpeed(_ speeds: [Double]) -> Double? {
        let s = speeds.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !s.isEmpty else { return nil }
        return s.count.isMultiple(of: 2) ? (s[s.count / 2 - 1] + s[s.count / 2]) / 2 : s[s.count / 2]
    }

    /// Speed over the last `window` seconds before `t`.
    public static func recentSpeed(_ samples: [DistanceSample], at t: Double) -> Double? {
        speed(samples, from: t - window, to: t)
    }

    /// True when this run should get "Ease off a little": running, settled in, 10% over easy pace, and
    /// not yet warned during this run.
    public static func shouldWarn(segment: Segment.Kind, secondsIntoSegment: Double, speed: Double?,
                                  easySpeed: Double?, warnedThisRun: Bool) -> Bool {
        guard segment.isRun, !warnedThisRun, secondsIntoSegment >= settle,
              let speed, let easySpeed else { return false }
        return speed > easySpeed * margin
    }

    /// Distance over time between the samples nearest the two ends; nil when the fixes cover less than
    /// two-thirds of the span (weak GPS) or the distance went backwards (a restored route).
    static func speed(_ samples: [DistanceSample], from a: Double, to b: Double) -> Double? {
        let inside = samples.filter { $0.t >= a - 1 && $0.t <= b }
        guard let first = inside.first, let last = inside.last else { return nil }
        let dt = last.t - first.t
        let dm = last.metres - first.metres
        guard dt >= (b - a) * 2 / 3, dm >= 0 else { return nil }
        return dm / dt
    }
}
