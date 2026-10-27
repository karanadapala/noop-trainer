import Foundation

/// Decides when to speak up about heart rate during a run/walk session (D12, D20). Pure: the caller
/// passes the current zone and remembers when the last correction was spoken.
public struct HeartRateGuard: Sendable {
    /// Highest zone that's fine while running. C25K runs should feel conversational, so anything above
    /// zone 4 gets a "slow down".
    public var runCeilingZone: Int
    /// Walks are for recovery: if HR is still at or above this zone this long into a walk, say so.
    public var walkRecoveryZone: Int
    public var walkGraceSeconds: Double
    /// Minimum gap between corrections, so it never nags.
    public var cooldownSeconds: Double

    public init(runCeilingZone: Int = 4, walkRecoveryZone: Int = 4,
                walkGraceSeconds: Double = 60, cooldownSeconds: Double = 40) {
        self.runCeilingZone = runCeilingZone
        self.walkRecoveryZone = walkRecoveryZone
        self.walkGraceSeconds = walkGraceSeconds
        self.cooldownSeconds = cooldownSeconds
    }

    /// - Parameters:
    ///   - zone: current HR zone (1–5), nil when there's no fresh HR.
    ///   - secondsIntoSegment: active seconds since the current segment began.
    ///   - secondsSinceLastCorrection: nil if none has been spoken yet this session.
    public func correction(segment: Segment.Kind, zone: Int?, secondsIntoSegment: Double,
                           secondsSinceLastCorrection: Double?) -> String? {
        guard let zone else { return nil }
        if let since = secondsSinceLastCorrection, since < cooldownSeconds { return nil }
        // Give a new segment a few seconds before judging it; HR lags effort.
        guard secondsIntoSegment >= 10 else { return nil }

        if segment.isRun, zone > runCeilingZone {
            return "Heart rate is high. Slow down to an easy jog."
        }
        if segment == .walk, zone >= walkRecoveryZone, secondsIntoSegment >= walkGraceSeconds {
            return "Keep the walk easy and let your heart rate come down."
        }
        return nil
    }
}
