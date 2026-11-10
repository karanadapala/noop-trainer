import Foundation

/// Mike Mentzer's Heavy Duty (D81), tuned to the evidence (D75): his exercises and pre-exhaust pairs
/// merged into a weekly Upper and Legs (D88), with the back changes (D102) and calves after C25K
/// (D103). Sit-ups are replaced by Back care's Core B (D100), which is its own plan.
public enum HeavyDuty {
    public static let planID = "heavyDuty"
    public static let title = "Heavy Duty"

    public enum Workout: String, CaseIterable, Codable, Sendable {
        case upper, legs

        public var title: String { self == .upper ? "Upper" : "Legs" }
        public var works: Set<Muscle> { self == .upper ? [.chest, .back, .shoulders, .arms] : [.legs] }
    }

    /// How a set can end besides the last rep: a tap the plan offers for that exercise (D79, D102).
    public enum StopTap: String, Codable, Sendable {
        /// The lower back rounded or the hips rolled: the set ends there (leg press, rows).
        case formBroke
        /// The weight didn't move at all (leg extension).
        case couldntLift

        /// The tap's words, which are also the set's note in the Lift Log.
        public var label: String { self == .formBroke ? "Form broke" : "Couldn't lift it" }
    }

    public struct Exercise: Codable, Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let workout: Workout
        /// Lift Log muscle tokens (`LiftMuscle` raw values), first one primary.
        public let muscles: [String]
        public let kit: Equipment.Kind
        /// Pre-exhaust: go straight into this exercise, no rest.
        public let straightInto: String?
        public let stopTap: StopTap?
        public let cue: String
        /// Only once C25K is finished (D103: no toe press while it runs).
        public let afterC25K: Bool

        public init(id: String, name: String, workout: Workout, muscles: [String], kit: Equipment.Kind,
                    straightInto: String? = nil, stopTap: StopTap? = nil, cue: String, afterC25K: Bool = false) {
            self.id = id
            self.name = name
            self.workout = workout
            self.muscles = muscles
            self.kit = kit
            self.straightInto = straightInto
            self.stopTap = stopTap
            self.cue = cue
            self.afterC25K = afterC25K
        }
    }

    /// The routine, in order (Q84 b). One working set each after warm-ups.
    public static let exercises: [Exercise] = [
        Exercise(id: "crossover", name: "Cable crossover", workout: .upper, muscles: ["chest", "frontDelts"],
                 kit: .cableCrossover, straightInto: "inclinePress",
                 cue: "Elbows slightly bent, squeeze the hands together."),
        Exercise(id: "inclinePress", name: "Machine incline press", workout: .upper,
                 muscles: ["chest", "frontDelts", "triceps"], kit: .pressMachine,
                 cue: "Breathe out on each push."),
        Exercise(id: "straightArmPulldown", name: "Straight-arm pulldown", workout: .upper, muscles: ["lats"],
                 kit: .cableColumn, straightInto: "closeGripPulldown", stopTap: .formBroke,
                 cue: "Brace first: ribs down, hips still."),
        Exercise(id: "closeGripPulldown", name: "Close-grip palms-up pulldown", workout: .upper,
                 muscles: ["lats", "biceps"], kit: .pulldownRow, cue: "Pull the elbows down to your sides."),
        Exercise(id: "seatedRow", name: "Seated row", workout: .upper, muscles: ["upperBack", "lats", "biceps"],
                 kit: .pulldownRow, stopTap: .formBroke,
                 cue: "Brace and sit tall; the back doesn't rock. Breathe out on each pull."),
        Exercise(id: "lateralRaise", name: "Dumbbell lateral raise", workout: .upper, muscles: ["sideDelts"],
                 kit: .dumbbells, cue: "Lead with the elbows, up to shoulder height."),
        Exercise(id: "reverseFly", name: "Cable reverse fly", workout: .upper, muscles: ["rearDelts", "upperBack"],
                 kit: .cableCrossover, cue: "Stand tall; open the arms wide, shoulders down."),
        Exercise(id: "pushdown", name: "Triceps pushdown", workout: .upper, muscles: ["triceps"],
                 kit: .cableColumn, cue: "Elbows pinned to your sides."),
        Exercise(id: "legExtension", name: "Leg extension", workout: .legs, muscles: ["quads"],
                 kit: .legExtensionCurl, straightInto: "legPress", stopTap: .couldntLift,
                 cue: "Hold the top for a second."),
        Exercise(id: "legPress", name: "Leg press", workout: .legs, muscles: ["quads", "glutes", "hamstrings"],
                 kit: .legPress, stopTap: .formBroke,
                 cue: "Brace, then push. Lower back stays on the pad; stop before the hips roll up. Breathe out on each push."),
        Exercise(id: "toePress", name: "Toe press on the leg press", workout: .legs, muscles: ["calves"],
                 kit: .legPress, cue: "Full stretch at the bottom, pause at the top.", afterC25K: true),
    ]

    public static func exercises(_ workout: Workout, c25kFinished: Bool) -> [Exercise] {
        exercises.filter { $0.workout == workout && (c25kFinished || !$0.afterC25K) }
    }
}

public struct RepRange: Codable, Equatable, Hashable, Sendable {
    public var low: Int
    public var high: Int

    public init(_ low: Int, _ high: Int) {
        self.low = low
        self.high = max(low, high)
    }

    public var label: String { "\(low)–\(high)" }
}

/// What the plan may do when the place has no next weight (D107); each can be switched off.
public enum AcceptedStep: String, CaseIterable, Codable, Sendable {
    case slowerLowering, oneSide, alternative

    public var label: String {
        switch self {
        case .slowerLowering: return "Lower it more slowly (5 s instead of 3)"
        case .oneSide: return "One arm or one leg at a time"
        case .alternative: return "Switch to another exercise for the same muscle"
        }
    }

    public var advice: String {
        switch self {
        case .slowerLowering: return "You're at the heaviest weight here: lower it over 5 seconds instead of 3."
        case .oneSide: return "You're at the heaviest weight here: do it one side at a time, braced."
        case .alternative: return "You're at the heaviest weight here: swap in another exercise for the same muscle."
        }
    }
}

/// Heavy Duty's way back after an illness (D224, research 12 §3): lighter and short of failure first.
/// Stored on its own key, so adding it doesn't reset the other settings.
public struct HeavyDutyWayBack: Codable, Equatable, Sendable {
    /// After a week or less missed: one session this much lighter, this many reps short of failure.
    public var firstLighterPercent = 10.0
    public var repsShort = 2
    /// After up to two weeks: two lighter sessions, this much lighter, then `firstLighterPercent / 2`.
    public var blockLighterPercent = 12.5

    public init() {}

    /// The n-th session (0 = the first) after coming back: how much lighter and how many reps short of
    /// failure; nil once the way back is over. Stepping back or restarting goes through the break-in instead.
    public func adjustment(_ step: WayBackStep, sessionsSince n: Int) -> (lighterPercent: Double, repsShort: Int)? {
        switch step {
        case .repeatLast: return n == 0 ? (firstLighterPercent, repsShort) : nil
        case .repeatBlock:
            if n == 0 { return (blockLighterPercent, repsShort) }
            if n == 1 { return (firstLighterPercent / 2, repsShort) }
            return nil
        case .carryOn, .stepBack, .restart: return nil
        }
    }
}

/// Every Heavy Duty setting the user can change (D97, D108). Defaults follow D75 and research 04 §6.
public struct HeavyDutyOptions: Codable, Equatable, Sendable {
    public var upperReps = RepRange(8, 12)
    public var legReps = RepRange(12, 20)
    /// Days that must pass after a workout before the same one comes up again (once a week ≈ 5).
    public var daysBetween = 5
    /// Past this, the workout is overdue and goes on any free day (D75: about 10 days at most).
    public var maxGapDays = 10
    /// Break-in weeks short of failure (D93).
    public var breakInWeeks = 2
    /// Until C25K is finished, sets stop 1–2 reps short of failure (D93).
    public var shortOfFailureDuringC25K = true
    /// No lifting the day after a lifting day, so each week keeps a day with nothing hard (D86, D94).
    public var restDayAfterLifting = true
    /// Reaching the top of the range: add this much next time, rounded up to a real step.
    public var increasePercent = 7.5
    /// A next step bigger than this is earned with more reps first (research 04 §6c).
    public var biggestJumpPercent = 15.0
    /// How many reps the top of the range rises by while earning a big jump.
    public var ceilingRaise = 3
    /// After a second stall the weight drops by this much (D75).
    public var resetPercent = 10.0
    public var acceptedSteps: [AcceptedStep] = AcceptedStep.allCases
    /// For today's time (D235): minutes per exercise (one hard set, the setup and the walk to the next
    /// machine), plus the warm-up and getting set up.
    public var minutesPerExercise = 3
    public var setupMinutes = 5

    public init() {}

    /// Decoded key by key, so stored settings survive a new setting being added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HeavyDutyOptions()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) throws -> T { try c.decodeIfPresent(T.self, forKey: k) ?? fallback }
        upperReps = try v(.upperReps, d.upperReps)
        legReps = try v(.legReps, d.legReps)
        daysBetween = try v(.daysBetween, d.daysBetween)
        maxGapDays = try v(.maxGapDays, d.maxGapDays)
        breakInWeeks = try v(.breakInWeeks, d.breakInWeeks)
        shortOfFailureDuringC25K = try v(.shortOfFailureDuringC25K, d.shortOfFailureDuringC25K)
        restDayAfterLifting = try v(.restDayAfterLifting, d.restDayAfterLifting)
        increasePercent = try v(.increasePercent, d.increasePercent)
        biggestJumpPercent = try v(.biggestJumpPercent, d.biggestJumpPercent)
        ceilingRaise = try v(.ceilingRaise, d.ceilingRaise)
        resetPercent = try v(.resetPercent, d.resetPercent)
        acceptedSteps = try v(.acceptedSteps, d.acceptedSteps)
        minutesPerExercise = try v(.minutesPerExercise, d.minutesPerExercise)
        setupMinutes = try v(.setupMinutes, d.setupMinutes)
    }

    public func minutes(exercises: Int) -> Int { exercises * minutesPerExercise + setupMinutes }

    public func reps(_ workout: HeavyDuty.Workout) -> RepRange { workout == .upper ? upperReps : legReps }
}

/// How hard the working set goes today (D93).
public enum LiftEffort: Equatable, Sendable {
    case breakIn, shortOfFailure, toFailure
    /// Back after a break (D224): this many reps short of failure.
    case wayBack(repsShort: Int)

    public static func on(_ now: Date, firstSession: Date?, c25kFinished: Bool, options: HeavyDutyOptions,
                          calendar: Calendar = .current) -> LiftEffort {
        if let first = firstSession,
           let end = calendar.date(byAdding: .day, value: options.breakInWeeks * 7, to: calendar.startOfDay(for: first)),
           now < end { return .breakIn }
        if firstSession == nil { return .breakIn }
        if options.shortOfFailureDuringC25K && !c25kFinished { return .shortOfFailure }
        return .toFailure
    }

    public var label: String {
        switch self {
        case .breakIn: return "Break-in"
        case .shortOfFailure: return "1–2 reps short of failure"
        case .toFailure: return "To failure"
        case .wayBack(let n): return "Back after a break: \(n) reps short of failure"
        }
    }

    public var detail: String {
        switch self {
        case .breakIn: return "Learn the lifts: slow, clean reps, stopping while 2–3 more would still be easy."
        case .shortOfFailure: return "Stop when you could do 1–2 more. Failure sets wait until C25K is done."
        case .toFailure: return "One set to the rep you can't finish, in good form."
        case .wayBack(let n): return "A little lighter than before, stopping when you could do \(n) more. Full effort comes back after this."
        }
    }
}

/// One working set as logged, in the place's unit.
public struct LiftResult: Codable, Equatable, Sendable {
    public let date: Date
    public let weight: Double?
    public let reps: Int
    /// "Couldn't lift it": the weight didn't move.
    public let didNotMove: Bool

    public init(date: Date, weight: Double?, reps: Int, didNotMove: Bool = false) {
        self.date = date
        self.weight = weight
        self.reps = reps
        self.didNotMove = didNotMove
    }
}

/// The weight for the next working set (D71, D72, D107; research 04 §6c–6d). In the place's unit.
public struct WeightSuggestion: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// First time: the session finds the weight (D72).
        case findIt
        case keep
        case increase
        /// The last jump was too big: back to the weight before it.
        case backOff
        /// A big next step: more reps at this weight first.
        case raiseCeiling(to: Int)
        /// No heavier weight here: the plan's next accepted step (D107).
        case nextStep(AcceptedStep)
        /// Two sessions with no progress: an extra rest day first (Mentzer).
        case stalled
        /// Stalled again: down about 10% and build back up.
        case reset
        /// Last time it didn't move: a step lighter.
        case lighter
        /// Back after a break (D224): this much lighter than the plan would have said.
        case wayBack(percent: Double)
    }

    public let kind: Kind
    public let weight: Double?
    /// The reps to aim for after an increase (Epley estimate, unverified for machines).
    public let expectReps: Int?
    public let reps: RepRange

    public var note: String {
        switch kind {
        case .findIt:
            return "First time: start light. Sets of 10 slow reps, one step heavier each set; stop climbing when the 10th rep slows down. One step below that is your weight."
        case .keep:
            return "Same weight: beat last time's reps."
        case .increase:
            return expectReps.map { "Heavier: expect about \($0) reps." } ?? "Heavier this time."
        case .backOff:
            return "Back to the weight before: last time's jump was too big."
        case .raiseCeiling(let top):
            return "The next weight is a big jump. Same weight, aim for \(top) reps first."
        case .nextStep(let step):
            return step.advice
        case .stalled:
            return "No progress for two sessions: rest an extra day before this workout, same weight."
        case .reset:
            return "Stalled again: about 10% lighter, then build back up."
        case .lighter:
            return "It didn't move last time: a step lighter today."
        case .wayBack(let p):
            return "Back after a break: about \(p.formatted(.number.precision(.fractionLength(0...1))))% lighter today."
        }
    }

    /// The same suggestion, lighter for the way back (D224). A weight still to find stays as it is.
    public func wayBack(lighterPercent p: Double, kit: Equipment?) -> WeightSuggestion {
        guard let w = weight, kind != .findIt, p > 0 else { return self }
        return WeightSuggestion(kind: .wayBack(percent: p), weight: Self.lighterWeight(than: w, target: w * (1 - p / 100), kit: kit),
                                expectReps: nil, reps: reps)
    }

    /// - Parameters:
    ///   - history: the working sets for this exercise, oldest first, one per session.
    ///   - kit: the place's kit for it, for real steps and limits; nil when unknown.
    public static func next(history: [LiftResult], reps: RepRange, kit: Equipment?,
                            options: HeavyDutyOptions) -> WeightSuggestion {
        guard let last = history.last, let w = last.weight else {
            return WeightSuggestion(kind: .findIt, weight: history.last?.weight ?? kit?.lightest, expectReps: nil, reps: reps)
        }
        let previous = history.dropLast().last
        func keep(_ kind: Kind, _ weight: Double? = nil, _ range: RepRange? = nil) -> WeightSuggestion {
            WeightSuggestion(kind: kind, weight: weight ?? w, expectReps: nil, reps: range ?? reps)
        }

        // It didn't move: the weight before it if that was lighter, else one step down.
        if last.didNotMove {
            let back = history.dropLast().last { ($0.weight ?? .infinity) < w && !$0.didNotMove }?.weight
            return keep(.lighter, back ?? lighterWeight(than: w, target: w * (1 - options.resetPercent / 100), kit: kit))
        }

        // After a jump, more than 2 reps under the range: the step was too big.
        if let previous, let pw = previous.weight, pw < w, last.reps < reps.low - 2 {
            return keep(.backOff, pw)
        }

        let ceiling = reps.high + options.ceilingRaise
        let earning = previous.map { $0.weight == w && $0.reps >= reps.high } ?? false
        let top = earning ? ceiling : reps.high
        if last.reps >= top {
            let target = w * (1 + options.increasePercent / 100)
            guard let next = nextWeight(above: w, atLeast: target, kit: kit) else {
                if let step = options.acceptedSteps.first { return keep(.nextStep(step)) }
                return keep(.raiseCeiling(to: ceiling), nil, RepRange(reps.low, ceiling))
            }
            if (next - w) / w * 100 > options.biggestJumpPercent && !earning {
                return keep(.raiseCeiling(to: ceiling), nil, RepRange(reps.low, ceiling))
            }
            let oneRM = w * (1 + Double(last.reps) / 30)
            let expect = max(1, Int((30 * (oneRM / next - 1)).rounded()))
            return WeightSuggestion(kind: .increase, weight: next, expectReps: expect, reps: reps)
        }

        switch stallCount(history) {
        case 0, 1: return keep(.keep)
        case 2: return keep(.stalled)
        default:
            return keep(.reset, lighterWeight(than: w, target: w * (1 - options.resetPercent / 100), kit: kit))
        }
    }

    /// Sessions in a row, at the end, with no progress (more reps at the weight, or a heavier weight).
    /// A lighter weight starts the count again.
    static func stallCount(_ history: [LiftResult]) -> Int {
        var count = 0
        for (a, b) in zip(history.dropLast(), history.dropFirst()).reversed() {
            guard let aw = a.weight, let bw = b.weight, bw >= aw else { break }
            if bw > aw || b.reps > a.reps { break }
            count += 1
        }
        return count + (count > 0 ? 1 : 0)
    }

    /// A real weight at or below `target` and below `current`, never under the kit's lightest.
    static func lighterWeight(than current: Double, target: Double, kit: Equipment?) -> Double {
        guard let kit, let step = kit.step, step > 0 else { return target }
        let base = kit.lightest ?? 0
        var w = base + ((target - base) / step).rounded(.down) * step
        if w >= current { w = current - step }
        return max(w, kit.lightest ?? w)
    }

    /// The lightest real weight at or above `target` and above `current`; nil when the kit has none.
    static func nextWeight(above current: Double, atLeast target: Double, kit: Equipment?) -> Double? {
        guard let kit, let step = kit.step, step > 0 else {
            // Steps unknown: the target itself, until a "Not on this machine" tap teaches the limits.
            if let heaviest = kit?.heaviest, current >= heaviest { return nil }
            return target
        }
        let base = kit.lightest ?? 0
        var w = base + ((target - base) / step).rounded(.up) * step
        if w <= current { w = current + step }
        if let heaviest = kit.heaviest, w > heaviest { return nil }
        return w
    }
}

/// Heavy Duty on the plan layer (D66, D94): Upper and Legs in turn, each about once a week. Legs only
/// when the next run is at least two days away (48 h, D86); Upper on a day without a run unless it's
/// overdue; never the day after a lifting day.
public struct HeavyDutyPlan: TrainingPlan {
    public var id: String { HeavyDuty.planID }
    public var title: String { HeavyDuty.title }
    public var goals: [Goal] { [.strength] }
    public var schedule: PlanSchedule { .rotation(minRestDays: options.daysBetween, maxGapDays: options.maxGapDays) }
    public var lastSession: Date? { last.values.max() }
    /// Two workouts in turn, each every `daysBetween`: a lift about every half of that.
    public var usualGapDays: Int { max(options.restDayAfterLifting ? 2 : 1, options.daysBetween / 2) }
    public var intensity: SessionIntensity { .hard }
    public var placeID: String? { place }

    /// How much lighter today's session is for the way back, if at all.
    public var wayBackLighter: Double? {
        wayBack.flatMap { wayBackOptions.adjustment($0.step, sessionsSince: sessionsSinceWayBack)?.lighterPercent }
    }

    /// Today's effort: the way back first, then the break-in (again, after stepping back or restarting),
    /// then the usual rule.
    public func effort(now: Date, calendar: Calendar = .current) -> LiftEffort {
        if let wb = wayBack {
            if let a = wayBackOptions.adjustment(wb.step, sessionsSince: sessionsSinceWayBack) { return .wayBack(repsShort: a.repsShort) }
            if wb.step == .stepBack || wb.step == .restart,
               let end = calendar.date(byAdding: .day, value: options.breakInWeeks * 7, to: calendar.startOfDay(for: wb.from)),
               now < end { return .breakIn }
        }
        return LiftEffort.on(now, firstSession: firstSession, c25kFinished: c25kFinished, options: options, calendar: calendar)
    }

    public func wayBack(_ step: WayBackStep) -> String {
        let w = wayBackOptions
        func pct(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) + "%" }
        switch step {
        case .carryOn: return "Same weights as planned."
        case .repeatLast: return "First session \(pct(w.firstLighterPercent)) lighter, \(w.repsShort) reps short of failure."
        case .repeatBlock: return "Two lighter sessions: \(pct(w.blockLighterPercent)) less, then \(pct(w.firstLighterPercent / 2)) less."
        case .stepBack: return "The \(options.breakInWeeks)-week break-in again."
        case .restart: return "The break-in from scratch, finding each weight again."
        }
    }

    public let options: HeavyDutyOptions
    public let last: [HeavyDuty.Workout: Date]
    public let firstSession: Date?
    /// C25K's next run: today (not yet run), or the first day it's due. Nil when no run is planned.
    public let nextRun: Date?
    public let ranToday: Bool
    public let c25kFinished: Bool
    /// Pain holds that also stop leg work today (D86 rule 6).
    public let legHolds: [String]
    /// "Not lifting today": nothing is offered for the rest of that day.
    public let skipped: Date?
    /// Holds that stop all lifting (a back flare, D104).
    public let liftHolds: [String]
    public let wayBackOptions: HeavyDutyWayBack
    public let place: String?
    /// The way back after a break, and how many sessions have been done since it began.
    public let wayBack: WayBackRecord?
    public let sessionsSinceWayBack: Int

    public init(options: HeavyDutyOptions, last: [HeavyDuty.Workout: Date], firstSession: Date?, nextRun: Date?,
                ranToday: Bool, c25kFinished: Bool, legHolds: [String] = [], skipped: Date? = nil,
                liftHolds: [String] = [], wayBackOptions: HeavyDutyWayBack = HeavyDutyWayBack(), place: String? = nil,
                wayBack: WayBackRecord? = nil, sessionsSinceWayBack: Int = 0) {
        self.wayBack = wayBack
        self.sessionsSinceWayBack = sessionsSinceWayBack
        self.place = place
        self.wayBackOptions = wayBackOptions
        self.skipped = skipped
        self.liftHolds = liftHolds
        self.options = options
        self.last = last
        self.firstSession = firstSession
        self.nextRun = nextRun
        self.ranToday = ranToday
        self.c25kFinished = c25kFinished
        self.legHolds = legHolds
    }

    /// The workout that fits today, if any.
    public func due(now: Date, calendar: Calendar = .current) -> HeavyDuty.Workout? {
        if let skipped, calendar.isDate(skipped, inSameDayAs: now) { return nil }
        if !liftHolds.isEmpty { return nil }
        let today = calendar.startOfDay(for: now)
        func days(since date: Date?) -> Int? {
            date.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: today).day ?? 0 }
        }
        let lastLift = last.values.max()
        if let d = days(since: lastLift), d < 1 { return nil }
        if options.restDayAfterLifting, let d = days(since: lastLift), d < 2 { return nil }
        let runIn = nextRun.map { calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: $0)).day ?? 0 }
        let runToday = ranToday || runIn.map { $0 <= 0 } ?? false
        func ready(_ w: HeavyDuty.Workout) -> Bool { days(since: last[w]).map { $0 >= options.daysBetween } ?? true }
        func overdue(_ w: HeavyDuty.Workout) -> Bool { days(since: last[w]).map { $0 >= options.maxGapDays } ?? false }

        if ready(.legs), legHolds.isEmpty, !runToday, runIn.map({ $0 >= 2 }) ?? true { return .legs }
        if ready(.upper), !runToday || overdue(.upper) { return .upper }
        return nil
    }

    public func today(now: Date, calendar: Calendar = .current) -> PlanToday {
        if let lastLift = last.values.max(), calendar.isDate(lastLift, inSameDayAs: now) {
            let w = last.first { calendar.isDate($0.value, inSameDayAs: now) }?.key ?? .upper
            return PlanToday(planID: id, status: .done, headline: "Done for today",
                             detail: "\(w.title) done. Recovery is where the strength comes from.", works: w.works)
        }
        if !liftHolds.isEmpty {
            return PlanToday(planID: id, status: .hold, headline: "On hold", detail: liftHolds.joined(separator: ". ") + ".")
        }
        if let skipped, calendar.isDate(skipped, inSameDayAs: now) {
            return PlanToday(planID: id, status: .rest, headline: "Not today",
                             detail: "Skipped for today. It comes up again on the next day it fits.")
        }
        guard let workout = due(now: now, calendar: calendar) else {
            return PlanToday(planID: id, status: .rest, headline: "Rest day", detail: restReason(now: now, calendar: calendar))
        }
        let effort = effort(now: now, calendar: calendar)
        let count = HeavyDuty.exercises(workout, c25kFinished: c25kFinished).count
        let minutes = options.minutes(exercises: count)
        return PlanToday(planID: id, status: .session, headline: workout.title,
                         detail: "About \(minutes) min · \(count) exercises, one working set each · \(effort.label)",
                         minutes: minutes, works: workout.works)
    }

    private func restReason(now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let runIn = nextRun.map { calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: $0)).day ?? 0 }
        if ranToday || runIn.map({ $0 <= 0 }) == true {
            return "A run day: lifting goes on a day without a run."
        }
        if !legHolds.isEmpty, (last[.legs].map { (calendar.dateComponents([.day], from: $0, to: now).day ?? 0) >= options.daysBetween } ?? true) {
            return "Legs wait: \(legHolds.joined(separator: ". "))."
        }
        if let lastLift = last.values.max(), calendar.dateComponents([.day], from: calendar.startOfDay(for: lastLift),
                                                                       to: calendar.startOfDay(for: now)).day ?? 0 < 2 {
            return "The day after lifting is for recovery."
        }
        return "Nothing fits today: legs need two days before a run, and each workout about a week."
    }
}
