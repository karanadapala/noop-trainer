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
    /// Where "1.2 kilometres so far." goes in `text` (characters from the start), for the halfway cue.
    public let distanceAt: Int?

    public init(at: Double, text: String, priority: Priority, kind: Kind = .speech, distanceAt: Int? = nil) {
        self.at = at
        self.text = text
        self.priority = priority
        self.kind = kind
        self.distanceAt = distanceAt
    }

    /// The words to say, with the distance so far added where the cue has room for it.
    public func spoken(distanceSoFar: String?) -> String {
        guard let distanceAt, let distanceSoFar else { return text }
        let i = text.index(text.startIndex, offsetBy: min(distanceAt, text.count))
        return text[..<i] + " \(distanceSoFar) so far." + text[i...]
    }
}

/// What the coach says halfway through the whole session (D82, D83), chosen on the start screen.
public enum HalfwayCue: String, CaseIterable, Sendable {
    /// "Halfway. Turn around." plus the distance so far, so the way back ends at home.
    case outAndBack
    /// "Halfway done." for laps and treadmills.
    case loop
    case off

    var sentence: String? {
        switch self {
        case .outAndBack: return "Halfway. Turn around."
        case .loop: return "Halfway done."
        case .off: return nil
        }
    }
}

/// Builds the full, pre-scheduled list of spoken cues for a session (B4: everything is known up front,
/// so the app only has to say whatever is due whenever it gets a moment to run).
public enum CueTimeline {
    /// The countdown starts this many seconds before a change: beeps at -3, -2, -1 and a long one at 0.
    public static let countdownLead = 3.0

    /// A halfway cue this close to another cue joins it instead of talking over it.
    public static let halfwayJoinWindow = 15.0

    public static func cues(for session: GuidedSession, halfway: HalfwayCue = .off) -> [Cue] {
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

            // Halfway marker for anything 4 minutes or longer. With the whole session's halfway cue on, only
            // long runs keep one, worded so it can't be mistaken for the turn-around point.
            if seg.seconds >= 240 {
                let text = halfway == .off ? "Halfway." : seg.kind.isRun ? "Halfway through this run." : nil
                if let text { out.append(Cue(at: start + Double(seg.seconds) / 2, text: text, priority: .status)) }
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
        if let sentence = halfway.sentence { addHalfway(sentence, at: Double(session.totalSeconds) / 2, to: &out) }
        return out.sorted { $0.at < $1.at }
    }

    /// Joins the nearest spoken cue within the window (a segment change first), or stands alone. A long
    /// run's own halfway nearby is dropped, so halfway is never said twice.
    static func addHalfway(_ sentence: String, at half: Double, to out: inout [Cue]) {
        out.removeAll { $0.text == "Halfway through this run." && abs($0.at - half) <= halfwayJoinWindow }
        let host = out.indices
            .filter { out[$0].kind == .speech && abs(out[$0].at - half) <= halfwayJoinWindow }
            .min { a, b in
                (out[a].priority == .transition ? 0 : 1, abs(out[a].at - half))
                    < (out[b].priority == .transition ? 0 : 1, abs(out[b].at - half))
            }
        guard let host else {
            out.append(Cue(at: half, text: sentence, priority: .status, distanceAt: sentence.count))
            return
        }
        let c = out[host]
        out[host] = Cue(at: c.at, text: sentence + " " + c.text, priority: c.priority, kind: c.kind,
                        distanceAt: sentence.count)
    }

    /// "850 metres", "1.2 kilometres", "0.7 miles": rounded the way a runner would say it.
    public static func spokenDistance(metres: Double, miles: Bool) -> String? {
        guard metres >= 50 else { return nil }
        if miles {
            let mi = oneDecimal(metres / 1609.344)
            return mi == "1" ? "1 mile" : "\(mi) miles"
        }
        if metres < 1000 { return "\(Int((metres / 10).rounded()) * 10) metres" }
        let km = oneDecimal(metres / 1000)
        return km == "1" ? "1 kilometre" : "\(km) kilometres"
    }

    /// "1.2", or "2" rather than "2.0".
    static func oneDecimal(_ x: Double) -> String {
        let s = String(format: "%.1f", x)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
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
