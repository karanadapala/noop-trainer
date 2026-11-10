import Foundation

/// The Mobility plan (D127, D148; research 07 §7): range back for the hips, hamstrings and back in
/// planned weekly steps. Unloaded bending is practice ("relax and round"); loaded bending stays out for
/// 12 weeks. Hips and gentle ankle range from the start; deep-squat holds and heavy ankle work wait for
/// the shin (D148, Q145); end-range strength in weeks 9–12.
public enum Mobility {
    public static let planID = "mobility"
    public static let title = "Mobility"

    /// Weeks 1–4, 5–8, 9–12, then keeping it.
    public enum Phase: Int, CaseIterable, Codable, Sendable {
        case gentle = 1, fuller, strength, maintain

        /// Weeks in each phase before "keeping it".
        public static let weeks = 4

        public static func of(week: Int) -> Phase {
            Phase(rawValue: min(Phase.maintain.rawValue, (max(1, week) - 1) / weeks + 1)) ?? .maintain
        }

        public var label: String {
            switch self {
            case .gentle: return "Gentle range"
            case .fuller: return "Fuller range"
            case .strength: return "End-range strength"
            case .maintain: return "Keeping it"
            }
        }
    }

    /// Which session today: the full one, a short one after lifting, or hips only during a flare.
    public enum Session: String, Codable, Sendable { case full, short, hipsOnly }

    private static func ex(_ id: String, _ name: String, _ howTo: String, _ dose: Dose, phase2: Dose? = nil) -> Exercise {
        Exercise(id, name, .mobility, howTo: howTo, link: nil, loads: [],
                 [.learn: dose, .build: phase2 ?? dose, .strengthen: phase2 ?? dose])
    }

    static let catCamel = ex("catCamel", "Cat–camel",
                             "On hands and knees, slowly round your back up, then let it sag. Breathe; no pushing at the ends.",
                             Dose(sets: 2, .reps(6), rest: 10, variant: "Mid-range"), phase2: Dose(sets: 2, .reps(6), rest: 10, variant: "Full range, slowly"))
    static let rollDown = ex("rollDown", "Roll-down",
                             "Knees soft, chin in, let your back round and slide your hands down slowly. Relax and breathe out.",
                             Dose(sets: 2, .reps(5), rest: 10, variant: "Hands to your knees"),
                             phase2: Dose(sets: 2, .reps(5), rest: 10, variant: "To your toes; rest the last one at the bottom"))
    static let childsPose = ex("childsPose", "Child's pose",
                               "Knees wide, sit back towards your heels and let your back round. Breathe slowly.",
                               Dose(sets: 2, .hold(30), rest: 10, variant: "Knees wide"))
    static let hamstring = ex("hamstring", "Hamstring stretch with a towel",
                              "On your back, towel round the foot, knee slightly bent, foot relaxed. Pull only at the back of the thigh.",
                              Dose(sets: 2, .hold(30), perSide: true, rest: 10, variant: "Knee slightly bent, foot relaxed"),
                              phase2: Dose(sets: 2, .heldReps(3, holdSeconds: 25), perSide: true,
                                           variant: "Contract–relax: press the heel into the towel, then ease further"))
    static let hipFlexor = ex("hipFlexor", "Hip-flexor stretch",
                              "Half-kneeling, squeeze the glute of the back leg and tuck the pelvis; don't arch the back.",
                              Dose(sets: 2, .hold(30), perSide: true, rest: 10, variant: "Half-kneeling"),
                              phase2: Dose(sets: 2, .hold(40), perSide: true, rest: 10, variant: "Back foot up on the bench if comfortable"))
    static let figure4 = ex("figure4", "Figure-4 stretch",
                            "On your back, ankle on the opposite knee, pull that thigh in gently.",
                            Dose(sets: 2, .hold(30), perSide: true, rest: 10, variant: "Lying down"))
    static let ninetyNinety = ex("ninetyNinety", "90/90 hip switches",
                                 "Sit with both knees bent at 90 degrees, hands behind you. Tip both knees slowly to the other side.",
                                 Dose(sets: 2, .reps(6), rest: 10, variant: "Hands behind for support"))
    static let kneeToWall = ex("kneeToWall", "Knee-to-wall ankle rocks",
                               "Foot a hand's width from the wall, heel down, rock the knee to the wall and back. Gentle.",
                               Dose(sets: 1, .reps(10), perSide: true, rest: 10, variant: "Gentle, heel down"))
    static let sciaticSlider = ex("sciaticSlider", "Nerve slider, lying down",
                                  "Hold the thigh up; straighten the knee as you tip your head back, bend it as you lift your head. Anything below the knee: stop.",
                                  Dose(sets: 1, .reps(10), perSide: true, rest: 10, variant: "Slow, right leg first"))
    static let slumpSlider = ex("slumpSlider", "Nerve slider, seated",
                                "Sit and slump gently; straighten the knee as you lift your head, bend it as you drop your head. Anything below the knee: back to the lying one.",
                                Dose(sets: 1, .reps(10), perSide: true, rest: 10, variant: "Slow, right leg first"))
    static let deepSquat = ex("deepSquat", "Deep-squat hold",
                              "Hold the cable column, heels down, sit as deep as is comfortable and breathe.",
                              Dose(sets: 3, .hold(25), rest: 10, variant: "Holding the cable column"))
    static let heelDrops = ex("heelDrops", "Heel drops",
                              "Balls of the feet on a step, lower the heels slowly below the step, then up on both.",
                              Dose(sets: 2, .reps(10), rest: 10, variant: "Slow lowering on both feet"))
    static let cableHipRotation = ex("cableHipRotation", "Cable hip rotation",
                                     "Cable at knee height round the ankle or knee; turn the leg in and out, hips still.",
                                     Dose(sets: 2, .reps(10), perSide: true, rest: 10, variant: "Light, both ways"))
    static let rdl = ex("rdl", "Dumbbell Romanian deadlift",
                        "Brace, then push the hips back; spine stays neutral. Stop when the back starts to round. 3 s down.",
                        Dose(sets: 2, .reps(8), rest: 10, variant: "Moderate effort, never to failure"))
    static let gobletSquat = ex("gobletSquat", "Goblet squat with a pause",
                                "One dumbbell at the chest, sit to depth, 3 s pause at the bottom, back up.",
                                Dose(sets: 2, .reps(6), rest: 10, variant: "3 s pause"))
    static let splitSquat = ex("splitSquat", "Rear-foot-elevated split squat",
                               "Back foot on the bench, lower slowly; feel the stretch at the front of the back hip.",
                               Dose(sets: 2, .reps(6), perSide: true, rest: 10, variant: "Bodyweight to start"))

    public static let all: [Exercise] = [catCamel, rollDown, childsPose, hamstring, hipFlexor, figure4, ninetyNinety,
                                         kneeToWall, sciaticSlider, slumpSlider, deepSquat, heelDrops, cableHipRotation,
                                         rdl, gobletSquat, splitSquat]

    /// Drills that need the shin cleared (D148: deep-squat holds and heavy ankle work wait).
    public static let needsShin: Set<String> = ["deepSquat", "heelDrops", "gobletSquat", "splitSquat"]

    /// Phase 1's roll-down goes a little further each week (research 07 §7).
    static func rollDownVariant(week: Int) -> String {
        ["Hands to your knees", "Hands to mid-shin", "Hands to your ankles", "As far as is comfortable"][max(0, min(3, week - 1))]
    }

    static let rules = "Slow, no bouncing, breathe out into each stretch. Some stretch is fine; anything below the knee or in the big toe, stop that drill."

    /// Today's session.
    /// - Parameters:
    ///   - week: the plan week (1-based, flare setbacks taken off).
    ///   - shinCleared: the shin's return-to-run checks are passed and no leg pain holds.
    ///   - strengthDay: phase 3 adds its strength drills on this session (2 of 5 a week).
    ///   - afterLifting: today's Heavy Duty workout, for the short session's choice.
    public static func session(_ kind: Session, week: Int, shinCleared: Bool, strengthDay: Bool = false,
                               afterLifting: HeavyDuty.Workout? = nil) -> RestRoutine {
        let phase = Phase.of(week: week)
        let stage: Stage = phase == .gentle ? .learn : .build
        func item(_ e: Exercise) -> RoutineItem {
            var dose = e.dose(stage)
            if e.id == "rollDown", phase == .gentle {
                dose = Dose(sets: dose.sets, dose.work, perSide: dose.perSide, rest: dose.restSeconds, variant: rollDownVariant(week: week))
            }
            if e.id == "catCamel", phase == .gentle, week >= 4 {
                dose = Dose(sets: dose.sets, dose.work, perSide: dose.perSide, rest: dose.restSeconds, variant: "Fuller range")
            }
            return RoutineItem(exercise: e, dose: dose)
        }
        var list: [Exercise]
        switch kind {
        case .hipsOnly:
            list = [figure4, ninetyNinety, kneeToWall]
        case .short:
            list = [hipFlexor, figure4] + (afterLifting == .upper ? [hamstring] : []) + [sciaticSlider]
        case .full:
            switch phase {
            case .gentle:
                list = [catCamel, rollDown, childsPose, hamstring, hipFlexor, figure4, ninetyNinety, kneeToWall, sciaticSlider]
            case .fuller:
                list = [catCamel, rollDown, hamstring, hipFlexor, figure4, cableHipRotation, kneeToWall, deepSquat,
                        heelDrops, slumpSlider]
            case .strength, .maintain:
                list = strengthDay
                    ? [catCamel, rdl, gobletSquat, splitSquat, cableHipRotation, hipFlexor]
                    : [catCamel, rollDown, hamstring, hipFlexor, figure4, kneeToWall, deepSquat, slumpSlider]
            }
        }
        if !shinCleared { list = list.filter { !needsShin.contains($0.id) } }
        let note = week <= 1 && kind == .full
            ? "Bending is a normal movement. We're re-teaching your back one small step at a time, and the plan backs off if anything flares. " + rules
            : rules
        return RestRoutine(variant: .mobility, walkMinutes: 0, items: list.map(item), skippedAreas: [], focusAreas: [],
                           stages: [:], note: note)
    }

    /// Days of the plan so far, with flare setbacks taken off (research 07 §6): each back flare costs its
    /// own days plus a week, or two weeks with a nerve sign.
    public static func planDay(start: Date, pain: [PainEntry], now: Date, calendar: Calendar = .current) -> Int {
        let total = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                            to: calendar.startOfDay(for: now)).day ?? 0
        let back = pain.filter { $0.area == .back && $0.date >= start }.sorted { $0.date < $1.date }
        var lost = 0
        var episodeStart: Date?
        var nerve = false
        func close(at end: Date) {
            guard let s = episodeStart else { return }
            let len = calendar.dateComponents([.day], from: calendar.startOfDay(for: s), to: calendar.startOfDay(for: end)).day ?? 0
            lost += len + (nerve ? 14 : 7)
            episodeStart = nil
            nerve = false
        }
        for e in back {
            if e.kind == .trend(.gone) { close(at: e.date); continue }
            if episodeStart == nil { episodeStart = e.date }
            if e.nerveSign { nerve = true }
        }
        close(at: now)
        return max(0, total - lost)
    }

    public static func week(start: Date, pain: [PainEntry], now: Date, calendar: Calendar = .current) -> Int {
        planDay(start: start, pain: pain, now: now, calendar: calendar) / 7 + 1
    }
}

public struct MobilityLog: Codable, Equatable, Sendable {
    public let date: Date
    public let session: Mobility.Session
    public let week: Int
    /// "Anything below the knee or in the big toe?", asked at the end.
    public var nerveSign: Bool?

    public init(date: Date, session: Mobility.Session, week: Int, nerveSign: Bool? = nil) {
        self.date = date
        self.session = session
        self.week = week
        self.nerveSign = nerveSign
    }
}

public struct MobilityOptions: Codable, Equatable, Sendable {
    /// No bending drills this soon after waking (research 07 §4).
    public var minutesAfterWaking = 60
    /// Phase 3: strength drills on every other full session (about 2 of 5).
    public var strengthEvery = 2
    /// Test days: weeks between them (D199), and not before this hour (afternoon, research 07 §5).
    public var testEveryWeeks = 4
    public var testFromHour = 12

    public init() {}
}

/// Mobility on the plan layer: a full session most days, a short one after lifting, hips only during
/// the first 48 hours of a back flare; never in the first hour after waking or before the lifts.
public struct MobilityPlan: TrainingPlan {
    public var id: String { Mobility.planID }
    public var title: String { Mobility.title }
    public var goals: [Goal] { [.mobility] }
    public var schedule: PlanSchedule { .rotation(minRestDays: 0, maxGapDays: 2) }
    public var lastSession: Date? { (log.map(\.date) + tests.map(\.date)).max() }
    public var intensity: SessionIntensity { .gentle }
    public var placeID: String? { place }

    public func wayBack(_ step: WayBackStep) -> String {
        switch step {
        case .carryOn, .repeatLast, .repeatBlock: return "Carries on where you were."
        case .stepBack: return "One phase back."
        case .restart: return "Two phases back."
        }
    }

    public let options: MobilityOptions
    public let start: Date
    public let log: [MobilityLog]
    public let pain: [PainEntry]
    public let shinCleared: Bool
    public let liftToday: HeavyDuty.Workout?
    public let liftDone: Bool
    public let wake: Date?
    public let tests: [MobilityTestResult]
    public let place: String

    public init(options: MobilityOptions, start: Date, log: [MobilityLog], pain: [PainEntry], shinCleared: Bool,
                liftToday: HeavyDuty.Workout?, liftDone: Bool, wake: Date?, tests: [MobilityTestResult] = [],
                place: String = "home") {
        self.place = place
        self.tests = tests
        self.options = options
        self.start = start
        self.log = log
        self.pain = pain
        self.shinCleared = shinCleared
        self.liftToday = liftToday
        self.liftDone = liftDone
        self.wake = wake
    }

    public enum Next: Equatable, Sendable {
        case session(Mobility.Session)
        case afterLifts(HeavyDuty.Workout)
        case later(Date)
        case done
    }

    public func week(now: Date, calendar: Calendar = .current) -> Int {
        Mobility.week(start: start, pain: pain, now: now, calendar: calendar)
    }

    /// `ignoringWake`: what comes once the first hour awake is over.
    public func next(now: Date, calendar: Calendar = .current, ignoringWake: Bool = false) -> Next {
        if log.contains(where: { calendar.isDate($0.date, inSameDayAs: now) })
            || tests.contains(where: { calendar.isDate($0.date, inSameDayAs: now) }) { return .done }
        if !ignoringWake, let wake, calendar.isDate(wake, inSameDayAs: now) {
            let from = wake.addingTimeInterval(TimeInterval(options.minutesAfterWaking * 60))
            if now < from { return .later(from) }
        }
        if let flare = BackFlare.current(entries: pain, now: now, calendar: calendar), flare.easy(now: now) {
            return .session(.hipsOnly)
        }
        if let lift = liftToday { return liftDone ? .session(.short) : .afterLifts(lift) }
        return .session(.full)
    }

    /// Phase 3 alternates strength and range on full sessions.
    public func strengthDay(now: Date, calendar: Calendar = .current) -> Bool {
        let w = week(now: now, calendar: calendar)
        guard Mobility.Phase.of(week: w).rawValue >= Mobility.Phase.strength.rawValue else { return false }
        let fullInPhase = log.filter { $0.session == .full && $0.week >= 9 }.count
        return fullInPhase % max(1, options.strengthEvery) == 0
    }

    public func routine(for session: Mobility.Session, now: Date, calendar: Calendar = .current) -> RestRoutine {
        Mobility.session(session, week: week(now: now, calendar: calendar), shinCleared: shinCleared,
                         strengthDay: session == .full && strengthDay(now: now, calendar: calendar), afterLifting: liftToday)
    }

    public func today(now: Date, calendar: Calendar = .current) -> PlanToday {
        let w = week(now: now, calendar: calendar)
        let phase = Mobility.Phase.of(week: w)
        if testFitsToday(tests: tests, now: now, calendar: calendar), next(now: now, calendar: calendar) == .session(.full) {
            return PlanToday(planID: id, status: .session, headline: tests.isEmpty ? "Test day: your baseline" : "Test day",
                             detail: "8 tests after a short warm-up · about 25 min", minutes: 25, works: [.legs, .back])
        }
        switch next(now: now, calendar: calendar) {
        case .session(let s):
            let r = routine(for: s, now: now, calendar: calendar)
            let headline: String
            switch s {
            case .full: headline = "Week \(w) · \(phase.label)"
            case .short: headline = "Short session after the lifts"
            case .hipsOnly: headline = "Hips only today"
            }
            let detail = s == .hipsOnly ? "Back flare: no bending or nerve drills for 48 hours · about \(r.estimatedMinutes) min"
                : "About \(r.estimatedMinutes) min · \(r.items.count) drills"
            return PlanToday(planID: id, status: .session, headline: headline, detail: detail,
                             minutes: r.estimatedMinutes, works: [.legs, .back])
        case .afterLifts(let lift):
            return PlanToday(planID: id, status: .rest, headline: "After the lifts",
                             detail: "Long holds go after training: a short session once \(lift.title) is done.",
                             minutes: routine(for: .short, now: now, calendar: calendar).estimatedMinutes, laterToday: true)
        case .later(let from):
            var minutes: Int?
            if case .session(let s) = next(now: now, calendar: calendar, ignoringWake: true) {
                minutes = routine(for: s, now: now, calendar: calendar).estimatedMinutes
            }
            return PlanToday(planID: id, status: .rest, headline: "Later today",
                             detail: "Not in the first hour after waking: from \(from.formatted(date: .omitted, time: .shortened)).",
                             minutes: minutes, laterToday: minutes != nil)
        case .done:
            return PlanToday(planID: id, status: .done, headline: "Done for today", detail: "Mobility done.")
        }
    }
}
