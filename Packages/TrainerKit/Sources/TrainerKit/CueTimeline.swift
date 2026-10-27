import Foundation

/// Something the coach says at a point in the session.
public struct Cue: Equatable, Sendable {
    public enum Priority: Int, Comparable, Sendable {
        /// "Halfway", "30 seconds left".
        case status = 0
        /// Heart-rate corrections.
        case correction = 1
        /// Segment changes and the 3-2-1 countdown: must never be skipped.
        case transition = 2

        public static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Kind: Equatable, Sendable {
        /// Spoken aloud.
        case speech
        /// Beeps instead of words: short beeps on the last three seconds, then a long beep exactly at
        /// the change. `text` is kept only for the screen.
        case countdown
    }

    /// Seconds of active (unpaused) session time at which to speak.
    public let at: Double
    public let text: String
    public let priority: Priority
    public let kind: Kind

    public init(at: Double, text: String, priority: Priority, kind: Kind = .speech) {
        self.at = at
        self.text = text
        self.priority = priority
        self.kind = kind
    }
}

/// Builds the full, pre-scheduled list of spoken cues for a session (B4: everything is known up front,
/// so the app only has to say whatever is due whenever it gets a moment to run).
public enum CueTimeline {
    /// The countdown starts this many seconds before a change: beeps at -3, -2, -1 and a long one at 0.
    public static let countdownLead = 3.0

    public static func cues(for session: GuidedSession) -> [Cue] {
        var out: [Cue] = []
        let starts = session.segmentStarts
        let runTotal = session.runCount
        var runNumber = 0

        for (i, seg) in session.segments.enumerated() {
            let start = Double(starts[i])
            let end = start + Double(seg.seconds)
            if seg.kind.isRun { runNumber += 1 }

            out.append(Cue(at: start,
                           text: announcement(seg, runNumber: runNumber, runTotal: runTotal, isFirst: i == 0,
                                              week: session.week, day: session.day),
                           priority: .transition))

            // Halfway marker for anything 4 minutes or longer.
            if seg.seconds >= 240 {
                out.append(Cue(at: start + Double(seg.seconds) / 2, text: "Halfway.", priority: .status))
            }
            // A heads-up before the end of segments long enough for it to mean something.
            if seg.seconds >= 300 {
                out.append(Cue(at: end - 60, text: "One minute left.", priority: .status))
            } else if seg.seconds >= 75 {
                out.append(Cue(at: end - 30, text: "30 seconds left.", priority: .status))
            }
            // 3-2-1 beeps into the next segment (not after the final cool-down).
            if i < session.segments.count - 1 {
                out.append(Cue(at: end - countdownLead, text: "3. 2. 1.", priority: .transition, kind: .countdown))
            }
        }

        let done = session.week > 0
            ? "Workout complete. Week \(session.week), day \(session.day) done. Great job."
            : "Test complete."
        out.append(Cue(at: Double(session.totalSeconds), text: done, priority: .transition))
        return out.sorted { $0.at < $1.at }
    }

    static func announcement(_ seg: Segment, runNumber: Int, runTotal: Int, isFirst: Bool,
                             week: Int, day: Int) -> String {
        let length = spokenDuration(seg.seconds)
        switch seg.kind {
        case .warmUp:
            let intro = !isFirst ? "" : week > 0 ? "Week \(week), day \(day). " : "Test session. "
            return intro + "Warm up with a brisk walk for \(length)."
        case .run:
            if runTotal == 1 { return "Run for \(length). Steady and easy." }
            let label = runNumber == runTotal ? "Last run!" : "Run \(runNumber) of \(runTotal)."
            return "\(label) Run for \(length)."
        case .walk:
            return "Walk for \(length)."
        case .coolDown:
            return "Cool down. Walk easy for \(length)."
        }
    }

    /// "90 seconds", "2 minutes", "2 and a half minutes", "1 minute".
    public static func spokenDuration(_ seconds: Int) -> String {
        if seconds < 120 && seconds % 60 != 0 { return "\(seconds) seconds" }
        let minutes = seconds / 60
        let half = seconds % 60 == 30
        if half { return "\(minutes) and a half minutes" }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
