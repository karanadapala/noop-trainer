import Foundation

/// One timed piece of a guided rest-day routine (D39).
public struct RoutineStep: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Easy walking before the exercises.
        case walk
        /// Getting into position for the next exercise; its how-to is read out.
        case change
        /// A set (or one side of a set).
        case work
        /// Between sets, or switching sides.
        case rest
    }

    public let kind: Kind
    public let start: Double
    public let seconds: Int
    /// The exercise this step belongs to (nil for the walk).
    public let exerciseID: String?
    /// "Bent-knee calf raise".
    public let title: String
    /// "Set 1 of 2 · Left leg · 12 reps".
    public let detail: String
    /// Reps in a work step (0 for holds), for the on-screen count.
    public let reps: Int

    public var end: Double { start + Double(seconds) }
}

/// Turns a routine into timed steps and pre-scheduled cues, like `CueTimeline` does for runs (B4):
/// everything is known up front, so the player only says whatever is due.
public struct RoutineTimeline: Equatable, Sendable {
    public let steps: [RoutineStep]
    public let cues: [Cue]
    public var totalSeconds: Int { Int(steps.last?.end ?? 0) }

    /// Seconds to get set before each round of work (the set is announced in it).
    public static let getReady = 4
    static let switchSides = 6

    public init(_ routine: RestRoutine) {
        var steps: [RoutineStep] = []
        var cues: [Cue] = []
        var t = 0.0

        func add(_ kind: RoutineStep.Kind, _ seconds: Int, _ ex: Exercise?, _ title: String, _ detail: String,
                 reps: Int = 0) -> Double {
            let start = t
            steps.append(RoutineStep(kind: kind, start: start, seconds: seconds, exerciseID: ex?.id,
                                     title: title, detail: detail, reps: reps))
            t += Double(seconds)
            return start
        }
        func countdown(into time: Double) {
            cues.append(Cue(at: time - CueTimeline.countdownLead, text: "3. 2. 1.", priority: .transition, kind: .countdown))
        }

        let intro = "\(routine.variant.label) routine, about \(routine.estimatedMinutes) minutes."
        if routine.walkMinutes > 0 {
            let s = add(.walk, routine.walkMinutes * 60, nil, "Easy walk", "\(routine.walkMinutes) minutes, easy enough to chat")
            cues.append(Cue(at: s, text: "\(intro) Start with an easy walk for \(CueTimeline.spokenDuration(routine.walkMinutes * 60)). Keep it conversational.",
                            priority: .transition))
            if routine.walkMinutes >= 3 {
                cues.append(Cue(at: t - 60, text: "One minute left of the walk.", priority: .status))
            }
            countdown(into: t)
        }

        for (index, item) in routine.items.enumerated() {
            let ex = item.exercise
            let dose = item.dose
            let changeSeconds = index == 0 && routine.walkMinutes == 0 ? 15 : Exercise.changeover
            let c = add(.change, changeSeconds, ex, ex.name, dose.variant)
            let lead = index == 0 && routine.walkMinutes == 0 ? "\(intro) First: " : "Next: "
            cues.append(Cue(at: c, text: "\(lead)\(ex.name). \(dose.variant). \(ex.howTo)", priority: .transition))
            countdown(into: t)

            let sides: [String?] = dose.perSide ? [Self.side(ex, left: true), Self.side(ex, left: false)] : [nil]
            for set in 1...dose.sets {
                for (sideIndex, side) in sides.enumerated() {
                    let (seconds, reps, count) = Self.work(dose.work)
                    var detail = dose.sets > 1 ? "Set \(set) of \(dose.sets)" : "One set"
                    if let side { detail += " · \(side.capitalizingFirst)" }
                    detail += " · \(count)"
                    let w = add(.work, Self.getReady + seconds, ex, ex.name, detail, reps: reps)
                    var announce = dose.sets > 1 ? "Set \(set) of \(dose.sets)" : ""
                    if let side { announce += announce.isEmpty ? side.capitalizingFirst : ", \(side)" }
                    announce += announce.isEmpty ? "\(count.capitalizingFirst)." : ". \(count)."
                    cues.append(Cue(at: w, text: announce, priority: .transition))
                    cues += Self.workCues(dose.work, from: w + Double(Self.getReady))

                    let lastRound = set == dose.sets && sideIndex == sides.count - 1
                    if lastRound { continue }
                    if sideIndex < sides.count - 1 {
                        let r = add(.rest, Self.switchSides, ex, "Switch sides", "Get set on the other side")
                        cues.append(Cue(at: r, text: "Switch sides.", priority: .transition))
                    } else {
                        let r = add(.rest, Exercise.restBetweenSets, ex, "Rest", "Next: set \(set + 1) of \(dose.sets)")
                        cues.append(Cue(at: r, text: "Rest \(Exercise.restBetweenSets) seconds.", priority: .transition))
                        countdown(into: t)
                    }
                }
            }
        }
        cues.append(Cue(at: t, text: "Routine complete. Nice work.", priority: .transition))
        self.steps = steps
        self.cues = cues.sorted { $0.at < $1.at }
    }

    /// Index of the step running at `t`, or nil once the routine is over.
    public func stepIndex(at t: Double) -> Int? {
        steps.firstIndex { t >= $0.start && t < $0.end }
    }

    /// Where the next exercise starts after `t` (Skip exercise), or the end.
    public func nextExerciseStart(after t: Double) -> Double {
        guard let i = stepIndex(at: t) else { return Double(totalSeconds) }
        let current = steps[i].exerciseID
        return steps[(i + 1)...].first { $0.kind == .change && $0.exerciseID != current }?.start ?? Double(totalSeconds)
    }

    static func side(_ ex: Exercise, left: Bool) -> String {
        let limb = ex.id == "sidePlank" || ex.id == "sideLegRaise" ? "side" : "leg"
        return "\(left ? "left" : "right") \(limb)"
    }

    /// Seconds of work, reps for the count, and the spoken amount.
    static func work(_ w: Dose.Work) -> (Int, Int, String) {
        switch w {
        case .reps(let n): return (n * Exercise.secondsPerRep, n, "\(n) reps")
        case .hold(let s): return (s, 0, "hold \(s) seconds")
        case .heldReps(let n, let hold): return (n * (hold + 2), n, "\(n) holds of \(hold) seconds")
        }
    }

    /// The tempo: each rep's number on the way up and "down" for the 3-second lowering; for held reps
    /// "lift" and "relax"; for holds, a halfway mark and beeps into the end.
    static func workCues(_ w: Dose.Work, from start: Double) -> [Cue] {
        switch w {
        case .reps(let n):
            return (0..<n).flatMap { k -> [Cue] in
                let at = start + Double(k * Exercise.secondsPerRep)
                return [Cue(at: at, text: k == n - 1 ? "Last one, up." : "\(k + 1), up.", priority: .status),
                        Cue(at: at + 3, text: "Down.", priority: .status)]
            }
        case .heldReps(let n, let hold):
            return (0..<n).flatMap { k -> [Cue] in
                let at = start + Double(k * (hold + 2))
                return [Cue(at: at, text: k == n - 1 ? "Last one, lift." : "\(k + 1), lift.", priority: .status),
                        Cue(at: at + Double(hold), text: "Relax.", priority: .status)]
            }
        case .hold(let s):
            var out = [Cue(at: start, text: "Go. Hold for \(s) seconds.", priority: .status)]
            if s >= 30 { out.append(Cue(at: start + Double(s) / 2, text: "Halfway.", priority: .status)) }
            out.append(Cue(at: start + Double(s) - CueTimeline.countdownLead, text: "3. 2. 1.", priority: .transition, kind: .countdown))
            return out
        }
    }
}

private extension String {
    var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() }
}
