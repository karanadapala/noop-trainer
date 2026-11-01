import Foundation

/// Quicker, shorter steps (D120): 5% more steps per minute than the user's own baseline lowers the
/// load on the shin. Pure: the caller measures steps per minute and remembers which run it cued.
public enum StepGuard {
    /// 5% above the baseline.
    public static let lift = 1.05
    /// Steps settle after the first half-minute of a run.
    public static let settle = 30.0
    public static let cue = "Quicker, shorter steps."

    /// The median steps per minute of earlier runs; nil until there are some.
    public static func baseline(_ perRun: [Double]) -> Double? { SpeedGuard.easySpeed(perRun) }

    public static func target(baseline: Double) -> Double { (baseline * lift).rounded() }

    public static func shouldCue(segment: Segment.Kind, secondsIntoSegment: Double, stepsPerMinute: Double?,
                                 baseline: Double?, cuedThisRun: Bool) -> Bool {
        guard segment.isRun, !cuedThisRun, secondsIntoSegment >= settle,
              let stepsPerMinute, let baseline else { return false }
        return stepsPerMinute < target(baseline: baseline) - 1
    }

    /// One number for a finished run: the median of the samples taken during its runs.
    public static func summary(_ samples: [Double]) -> Double? { SpeedGuard.easySpeed(samples) }
}
