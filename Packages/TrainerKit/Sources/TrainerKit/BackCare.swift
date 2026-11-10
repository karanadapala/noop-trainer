import Foundation

/// Back care (D98–D101; research 05 §7): McGill's Big 3 most days (Core A), and anti-movement work
/// after the lifts on lifting days (Core B), replacing Mentzer's sit-ups. Short holds, descending sets,
/// never to failure; not in the first hour after waking.
public enum BackCare {
    public static let planID = "backCare"
    public static let title = "Back care"

    /// Core A, the Big 3 (D99). Weeks 1–4 / 5–8 / later from research 05 §7, as the three stages.
    public static let coreA: [Exercise] = [
        Exercise("curlUp", "McGill curl-up", .core,
                 howTo: "One knee bent, hands under your low back. Lift head and shoulders a little; the neck stays still.",
                 link: nil, loads: [],
                 [.learn: Dose(pyramid: [4, 3, 2], holdSeconds: 8, rest: 12, variant: "Hands under the low back"),
                  .build: Dose(pyramid: [6, 4, 2], holdSeconds: 10, rest: 12, variant: "Hands under the low back"),
                  .strengthen: Dose(pyramid: [6, 4, 2], holdSeconds: 10, rest: 12, variant: "Elbows lifted off the floor")]),
        Exercise("big3SidePlank", "Side plank", .core,
                 howTo: "On your forearm, body in a straight line. Hips stay high; don't let them sag.",
                 link: nil, loads: [],
                 [.learn: Dose(pyramid: [3, 2, 1], holdSeconds: 8, perSide: true, rest: 12, variant: "From the knees"),
                  .build: Dose(pyramid: [4, 3, 2], holdSeconds: 8, perSide: true, rest: 12, variant: "From the feet, staggered"),
                  .strengthen: Dose(pyramid: [6, 4, 2], holdSeconds: 10, perSide: true, rest: 12, variant: "From the feet")]),
        Exercise("birdDog", "Bird dog", .core,
                 howTo: "On hands and knees, reach the opposite arm and leg out long. The back stays flat; nothing rocks.",
                 link: nil, loads: [],
                 [.learn: Dose(pyramid: [4, 3, 2], holdSeconds: 8, perSide: true, rest: 12, variant: "Opposite arm and leg"),
                  .build: Dose(pyramid: [6, 4, 2], holdSeconds: 10, perSide: true, rest: 12, variant: "Opposite arm and leg"),
                  .strengthen: Dose(pyramid: [6, 4, 2], holdSeconds: 10, perSide: true, rest: 12,
                                    variant: "Draw a small square with hand and foot")]),
    ]

    /// Core B (D100), at the gym after the lifts. The hip-hinge drill is for Legs day only.
    public static let coreB: [Exercise] = [
        Exercise("pallof", "Pallof press", .core,
                 howTo: "Side-on to the cable at chest height. Press the handle straight out and hold; don't let it turn you.",
                 link: nil, loads: [],
                 [.learn: Dose(sets: 2, .heldReps(6, holdSeconds: 5), perSide: true, variant: "Half-kneeling"),
                  .build: Dose(sets: 3, .heldReps(8, holdSeconds: 5), perSide: true, variant: "Standing"),
                  .strengthen: Dose(sets: 3, .heldReps(8, holdSeconds: 5), perSide: true, variant: "Standing, heavier stack")]),
        Exercise("suitcaseCarry", "Suitcase carry", .core,
                 howTo: "One dumbbell at your side. Brace, then hinge to pick it up; walk tall without leaning.",
                 link: nil, loads: [],
                 [.learn: Dose(sets: 2, .hold(30), perSide: true, variant: "About 25 m, a light dumbbell"),
                  .build: Dose(sets: 2, .hold(40), perSide: true, variant: "About 30 m, heavier"),
                  .strengthen: Dose(sets: 3, .hold(45), perSide: true, variant: "About 40 m, heavier")]),
        Exercise("deadBug", "Dead bug", .core,
                 howTo: "On your back, arms up, knees over hips. Lower the opposite arm and leg slowly; the low back stays down.",
                 link: nil, loads: [],
                 [.learn: Dose(sets: 2, .reps(6), perSide: true, variant: "Slow"),
                  .build: Dose(sets: 3, .reps(8), perSide: true, variant: "Slow"),
                  .strengthen: Dose(sets: 3, .reps(8), perSide: true, variant: "Holding a light dumbbell")]),
        Exercise("hingeDrill", "Braced hip-hinge drill", .core,
                 howTo: "Brace, then push the hips back with a broomstick along your spine; head, upper back and tailbone stay on it.",
                 link: nil, loads: [],
                 [.learn: Dose(sets: 2, .reps(8), variant: "Broomstick"),
                  .build: Dose(sets: 2, .reps(10), variant: "Broomstick"),
                  .strengthen: Dose(sets: 2, .reps(10), variant: "Light cable pull-through")]),
    ]

    public static var all: [Exercise] { coreA + coreB }

    /// Core A at today's levels. `warmUp`: the first descending set of each, before lifting (D99).
    public static func coreA(levels: [String: Stage], warmUp: Bool = false) -> RestRoutine {
        let items = coreA.map { ex -> RoutineItem in
            let dose = ex.dose(levels[ex.id] ?? .learn)
            return RoutineItem(exercise: ex, dose: warmUp ? dose.withSets(1) : dose)
        }
        return RestRoutine(variant: .coreA, walkMinutes: 0, items: items, skippedAreas: [], focusAreas: [], stages: [:])
    }

    /// The sick-day floor (D221): one set of each, the same as the warm-up before lifting.
    public static func floor(levels: [String: Stage]) -> RestRoutine { coreA(levels: levels, warmUp: true) }

    /// Core B after the lifts. Upper day: Pallof press and carry; Legs day: dead bug, hinge drill and
    /// carry (research 05 §7).
    public static func coreB(levels: [String: Stage], workout: HeavyDuty.Workout) -> RestRoutine {
        let ids = workout == .upper ? ["pallof", "suitcaseCarry"] : ["deadBug", "hingeDrill", "suitcaseCarry"]
        let items = ids.compactMap { id in coreB.first { $0.id == id } }
            .map { RoutineItem(exercise: $0, dose: $0.dose(levels[$0.id] ?? .learn)) }
        return RestRoutine(variant: .coreB, walkMinutes: 0, items: items, skippedAreas: [], focusAreas: [], stages: [:])
    }

    /// The rest-day exercise Core A replaces when Back care is on (D99: the knee side plank).
    public static let replacesInRestDay: Set<String> = ["sidePlank"]
}

/// How a Back care session felt, asked at the end; a week of "easy" offers the next level (D99).
public enum BackCareFeel: String, CaseIterable, Codable, Sendable {
    case easy, right, hard

    public var label: String {
        switch self {
        case .easy: return "Easy"
        case .right: return "About right"
        case .hard: return "Hard"
        }
    }
}

public struct BackCareLog: Codable, Equatable, Sendable {
    public enum Session: String, Codable, Sendable { case coreA, warmUp, coreB }

    public let date: Date
    public let session: Session
    public var feel: BackCareFeel?

    public init(date: Date, session: Session, feel: BackCareFeel? = nil) {
        self.date = date
        self.session = session
        self.feel = feel
    }
}

public struct BackCareOptions: Codable, Equatable, Sendable {
    /// No core work this soon after waking (D101).
    public var minutesAfterWaking = 60
    /// Easy Core A sessions in a row, over at least `levelUpDays`, before the next level is offered.
    public var easySessionsToLevelUp = 5
    public var levelUpDays = 7
    /// A short Big 3 set before lifting (D99).
    public var warmUpBeforeLifting = true

    public init() {}
}

/// Back care on the plan layer (D98). Core A every day it isn't done; on a lifting day a warm-up set
/// before and Core B after.
public struct BackCarePlan: TrainingPlan {
    public var id: String { BackCare.planID }
    public var title: String { BackCare.title }
    public var goals: [Goal] { [.mobility] }
    public var schedule: PlanSchedule { .rotation(minRestDays: 0, maxGapDays: 2) }
    public var lastSession: Date? { log.map(\.date).max() }
    public var intensity: SessionIntensity { .gentle }
    public var placeID: String? { place }

    /// The 2-minute floor (D221): one round of the Big 3, shorter holds.
    public func sickFloor(now: Date, calendar: Calendar) -> PlanToday? {
        if log.contains(where: { calendar.isDate($0.date, inSameDayAs: now) }) {
            return PlanToday(planID: id, status: .done, headline: "Done for today", detail: "Rest counts too.")
        }
        let m = BackCare.floor(levels: levels).estimatedMinutes
        return PlanToday(planID: id, status: .session, headline: "One round of the Big 3",
                         detail: "Only if you feel like it · about \(m) min", minutes: m, works: [.core])
    }

    /// Back care is the anchor habit: it comes back as it was (research 12 §7.2).
    public func wayBack(_ step: WayBackStep) -> String { "Carries on at your levels." }

    public let options: BackCareOptions
    public let log: [BackCareLog]
    public let levels: [String: Stage]
    public let lastLevelChange: Date?
    /// Heavy Duty's workout today (due or done), and whether it's done.
    public let liftToday: HeavyDuty.Workout?
    public let liftDone: Bool
    /// When the strap saw you wake today.
    public let wake: Date?
    /// A back flare is on (D104): the Big 3 only, and only if it doesn't bring symptoms on.
    public let flare: Bool
    /// Where Core A happens (Core B goes with the lifts).
    public let place: String

    public init(options: BackCareOptions, log: [BackCareLog], levels: [String: Stage], lastLevelChange: Date?,
                liftToday: HeavyDuty.Workout?, liftDone: Bool, wake: Date?, flare: Bool = false, place: String = "home") {
        self.place = place
        self.flare = flare
        self.options = options
        self.log = log
        self.levels = levels
        self.lastLevelChange = lastLevelChange
        self.liftToday = liftToday
        self.liftDone = liftDone
        self.wake = wake
    }

    /// What Back care offers now.
    public enum Next: Equatable, Sendable {
        case coreA, warmUp(HeavyDuty.Workout), coreB(HeavyDuty.Workout)
        /// Too soon after waking: from this time.
        case later(Date)
        case done
    }

    /// `ignoringWake`: what comes once the first hour awake is over.
    public func next(now: Date, calendar: Calendar = .current, ignoringWake: Bool = false) -> Next {
        let today = log.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let didA = today.contains { $0.session == .coreA || $0.session == .warmUp }
        let didB = today.contains { $0.session == .coreB }
        if !ignoringWake, let wake, calendar.isDate(wake, inSameDayAs: now), !didA || (liftDone && !didB) {
            let from = wake.addingTimeInterval(TimeInterval(options.minutesAfterWaking * 60))
            if now < from { return .later(from) }
        }
        if flare { return didA ? .done : .coreA }
        if let lift = liftToday {
            if liftDone { return didB ? (didA ? .done : .coreA) : .coreB(lift) }
            if !didA && options.warmUpBeforeLifting { return .warmUp(lift) }
            return .done
        }
        return didA ? .done : .coreA
    }

    public func today(now: Date, calendar: Calendar = .current) -> PlanToday {
        today(now: now, calendar: calendar, showing: next(now: now, calendar: calendar))
    }

    private func today(now: Date, calendar: Calendar, showing: Next) -> PlanToday {
        switch showing {
        case .coreA:
            let m = BackCare.coreA(levels: levels).estimatedMinutes
            return PlanToday(planID: id, status: .session, headline: "Big 3",
                             detail: flare ? "Back flare: only if it doesn't bring symptoms on. Stop at the first twinge."
                                 : "Curl-up, side plank, bird dog · about \(m) min", minutes: m, works: [.core])
        case .warmUp(let w):
            // Today's time counts both: the warm-up now and Core B after the lifts.
            let warm = BackCare.coreA(levels: levels, warmUp: true).estimatedMinutes
            let b = BackCare.coreB(levels: levels, workout: w).estimatedMinutes
            return PlanToday(planID: id, status: .session, headline: "Warm-up before \(w.title)",
                             detail: "One short Big 3 set each (about \(warm) min), then Core B after the lifts (about \(b) min)",
                             minutes: warm + b, works: [.core])
        case .coreB(let w):
            let m = BackCare.coreB(levels: levels, workout: w).estimatedMinutes
            return PlanToday(planID: id, status: .session, headline: "Core B",
                             detail: "After the lifts · about \(m) min", minutes: m, works: [.core])
        case .later(let from):
            let then = today(now: now, calendar: calendar, showing: next(now: now, calendar: calendar, ignoringWake: true))
            return PlanToday(planID: id, status: .rest, headline: "Later today",
                             detail: "Not in the first hour after waking: from \(from.formatted(date: .omitted, time: .shortened)).",
                             minutes: then.minutes, works: then.works, laterToday: then.status == .session)
        case .done:
            return PlanToday(planID: id, status: .done, headline: "Done for today", detail: "Back care done.")
        }
    }

    /// The Core A exercise to level up next, when the last sessions have all been easy for long enough
    /// (one exercise at a time, the lowest level first). Nil: not yet.
    public func levelUpOffer(now: Date, calendar: Calendar = .current) -> Exercise? {
        let since = log.filter { $0.session == .coreA && $0.date > (lastLevelChange ?? .distantPast) }
        let recent = since.suffix(options.easySessionsToLevelUp)
        guard recent.count == options.easySessionsToLevelUp, recent.allSatisfy({ $0.feel == .easy }),
              let first = since.first,
              (calendar.dateComponents([.day], from: calendar.startOfDay(for: first.date),
                                          to: calendar.startOfDay(for: now)).day ?? 0) >= options.levelUpDays - 1
        else { return nil }
        return BackCare.coreA
            .filter { (levels[$0.id] ?? .learn) < .strengthen }
            .min { (levels[$0.id] ?? .learn) < (levels[$1.id] ?? .learn) }
    }
}
