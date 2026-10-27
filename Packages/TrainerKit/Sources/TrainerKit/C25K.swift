import Foundation

/// One block of a guided run/walk session.
public struct Segment: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case warmUp, run, walk, coolDown

        /// Running segments get the "slow down" heart-rate guard; everything else is recovery.
        public var isRun: Bool { self == .run }
    }

    public let kind: Kind
    public let seconds: Int

    public init(_ kind: Kind, _ seconds: Int) {
        self.kind = kind
        self.seconds = seconds
    }
}

/// One C25K day: a warm-up walk, the run/walk intervals, and a cool-down walk.
public struct GuidedSession: Equatable, Sendable {
    public let week: Int
    public let day: Int
    public let segments: [Segment]

    public init(week: Int, day: Int, segments: [Segment]) {
        self.week = week
        self.day = day
        self.segments = segments
    }

    public var totalSeconds: Int { segments.reduce(0) { $0 + $1.seconds } }
    public var runCount: Int { segments.filter { $0.kind.isRun }.count }

    /// Start offset (seconds from session start) of each segment.
    public var segmentStarts: [Int] {
        var starts: [Int] = []
        var t = 0
        for s in segments {
            starts.append(t)
            t += s.seconds
        }
        return starts
    }

    /// The segment in progress at `elapsed` seconds, or nil once the session is over.
    public func segmentIndex(at elapsed: TimeInterval) -> Int? {
        guard elapsed >= 0 else { return 0 }
        for (i, start) in segmentStarts.enumerated() where elapsed < Double(start + segments[i].seconds) {
            return i
        }
        return nil
    }
}

/// The classic 9-week Couch to 5K (Josh Clark / Cool Running): three days a week, each with a 5-minute
/// warm-up walk and a 5-minute cool-down walk around the intervals.
public enum C25K {
    public static let weeks = 9
    public static let daysPerWeek = 3
    static let warmUp = Segment(.warmUp, 300)
    static let coolDown = Segment(.coolDown, 300)

    public static func session(week: Int, day: Int) -> GuidedSession? {
        guard (1...weeks).contains(week), (1...daysPerWeek).contains(day) else { return nil }
        let middle = intervals(week: week, day: day)
        return GuidedSession(week: week, day: day, segments: [warmUp] + middle + [coolDown])
    }

    /// A 2-minute rehearsal (30 s per segment) for checking voice, ducking and lock-screen behaviour
    /// without walking a full warm-up. Week/day 0 marks it as not part of the plan.
    public static let rehearsal = GuidedSession(week: 0, day: 0, segments: [
        Segment(.warmUp, 30), Segment(.run, 30), Segment(.walk, 30), Segment(.coolDown, 30),
    ])

    /// All 27 sessions in order.
    public static var all: [GuidedSession] {
        (1...weeks).flatMap { w in (1...daysPerWeek).compactMap { d in session(week: w, day: d) } }
    }

    private static func run(_ minutes: Double) -> Segment { Segment(.run, Int(minutes * 60)) }
    private static func walk(_ minutes: Double) -> Segment { Segment(.walk, Int(minutes * 60)) }

    private static func repeated(_ pair: [Segment], times: Int) -> [Segment] {
        Array((0..<times).map { _ in pair }.joined())
    }

    private static func intervals(week: Int, day: Int) -> [Segment] {
        switch week {
        case 1: return repeated([run(1), walk(1.5)], times: 8)
        case 2: return repeated([run(1.5), walk(2)], times: 6)
        case 3: return repeated([run(1.5), walk(1.5), run(3), walk(3)], times: 2)
        case 4: return [run(3), walk(1.5), run(5), walk(2.5), run(3), walk(1.5), run(5)]
        case 5:
            switch day {
            case 1: return [run(5), walk(3), run(5), walk(3), run(5)]
            case 2: return [run(8), walk(5), run(8)]
            default: return [run(20)]
            }
        case 6:
            switch day {
            case 1: return [run(5), walk(3), run(8), walk(3), run(5)]
            case 2: return [run(10), walk(3), run(10)]
            default: return [run(22)]
            }
        case 7: return [run(25)]
        case 8: return [run(28)]
        default: return [run(30)]
        }
    }
}

extension GuidedSession: Identifiable {
    /// "w2d1"; the rehearsal is "w0d0".
    public var id: String { "w\(week)d\(day)" }
}
