import Foundation

/// What kind of illness it was (D219). The type sets how long the way back takes; it's optional, and
/// "not sure" counts as fever-type.
public enum IllnessKind: String, CaseIterable, Codable, Sendable {
    case cold, fever, stomach, covid, notSure

    public var label: String {
        switch self {
        case .cold: return "Cold"
        case .fever: return "Fever or flu"
        case .stomach: return "Stomach bug"
        case .covid: return "COVID-19"
        case .notSure: return "Not sure"
        }
    }

    /// One line under the choices, so the short labels stay short.
    public static let hint = "Cold: nose and throat only. Fever or flu: also chills or body aches."

    /// Whole-body illness: rest while it lasts, and easy days before the way back (research 12 §1).
    public var feverType: Bool { self != .cold }
}

/// The morning check while ill (D223).
public enum SickFeel: String, CaseIterable, Codable, Sendable {
    case worse, same, better, normal

    public var label: String {
        switch self {
        case .worse: return "Worse"
        case .same: return "Same"
        case .better: return "Better"
        case .normal: return "Back to normal"
        }
    }
}

public struct SickCheck: Codable, Equatable, Sendable {
    public let date: Date
    public let feel: SickFeel
    /// A fever in the last 24 hours.
    public let fever: Bool

    public init(date: Date, feel: SickFeel, fever: Bool) {
        self.date = date
        self.feel = feel
        self.fever = fever
    }
}

/// One illness, from the "I'm unwell" tap (or an answer to the gap check) to "Back to normal".
public struct SickEpisode: Codable, Equatable, Sendable {
    public let start: Date
    public var kind: IllnessKind?
    public var checks: [SickCheck]
    /// The day it ended; nil while it's on.
    public var end: Date?

    public init(start: Date, kind: IllnessKind? = nil, checks: [SickCheck] = [], end: Date? = nil) {
        self.start = start
        self.kind = kind
        self.checks = checks
        self.end = end
    }

    public var isOn: Bool { end == nil }

    /// Fever-type unless it was marked a cold: an unmarked illness is treated like "not sure".
    public var feverType: Bool { kind?.feverType ?? true }

    /// Calendar days from the start to the end (or to `now` while it's on), counting both.
    public func days(now: Date, calendar: Calendar = .current) -> Int {
        let last = end ?? now
        return (calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                        to: calendar.startOfDay(for: last)).day ?? 0) + 1
    }
}

/// Every number behind sick days and the way back (D220–D224, D233). Decoded key by key, so a stored
/// copy keeps working when a setting is added.
public struct SickDayOptions: Codable, Equatable, Sendable {
    /// After flu, COVID-19 or this many days ill, hard sessions wait `hardWaitDays` from the end (D220).
    public var hardWaitDays = 7
    public var longIllnessDays = 3
    /// Easy days after a fever-type illness before runs come back: a walk-only day, then walk + gentle
    /// plans (research 12 §7.3).
    public var easyDaysAfterFeverType = 2
    /// The 2-minute floor on cold days (D221): off for this user.
    public var floorOnColdDays = false
    /// The red-flag list shows by itself after this many "Worse" or "Same" mornings in a row (D223).
    public var redFlagsAfterWorse = 2
    public var redFlagsAfterSame = 5
    /// The app proposes "Back to normal" after this many "Better" mornings in a row.
    public var proposeEndAfterBetter = 2
    /// Days missed → the way back (D224). Read in order; the last band covers everything longer.
    public var bands: [WayBackBand] = [
        WayBackBand(upToDays: 3, step: .carryOn),
        WayBackBand(upToDays: 7, step: .repeatLast),
        WayBackBand(upToDays: 14, step: .repeatBlock),
        WayBackBand(upToDays: 28, step: .stepBack),
        WayBackBand(upToDays: nil, step: .restart),
    ]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SickDayOptions()
        hardWaitDays = try c.decodeIfPresent(Int.self, forKey: .hardWaitDays) ?? d.hardWaitDays
        longIllnessDays = try c.decodeIfPresent(Int.self, forKey: .longIllnessDays) ?? d.longIllnessDays
        easyDaysAfterFeverType = try c.decodeIfPresent(Int.self, forKey: .easyDaysAfterFeverType) ?? d.easyDaysAfterFeverType
        floorOnColdDays = try c.decodeIfPresent(Bool.self, forKey: .floorOnColdDays) ?? d.floorOnColdDays
        redFlagsAfterWorse = try c.decodeIfPresent(Int.self, forKey: .redFlagsAfterWorse) ?? d.redFlagsAfterWorse
        redFlagsAfterSame = try c.decodeIfPresent(Int.self, forKey: .redFlagsAfterSame) ?? d.redFlagsAfterSame
        proposeEndAfterBetter = try c.decodeIfPresent(Int.self, forKey: .proposeEndAfterBetter) ?? d.proposeEndAfterBetter
        bands = try c.decodeIfPresent([WayBackBand].self, forKey: .bands) ?? d.bands
    }
}

/// The way back, in steps every plan understands; each plan says what a step means for it (D224).
public enum WayBackStep: String, CaseIterable, Codable, Sendable {
    /// Carry on as planned.
    case carryOn
    /// Do the last session again.
    case repeatLast
    /// Do the last block (a week, a phase) again.
    case repeatBlock
    /// Go back one block.
    case stepBack
    /// Start the plan again.
    case restart
}

public struct WayBackBand: Codable, Equatable, Sendable {
    /// The most days missed this band covers; nil for "anything longer".
    public var upToDays: Int?
    public var step: WayBackStep

    public init(upToDays: Int?, step: WayBackStep) {
        self.upToDays = upToDays
        self.step = step
    }
}

/// How hard a plan's sessions are, for when it comes back after an illness (D220): gentle plans first,
/// then moderate ones once the easy days are over, hard ones last.
public enum SessionIntensity: Int, Codable, Comparable, Sendable {
    case gentle, moderate, hard

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum SickDays {
    /// "Feeling ill? Check this first" (D220). Advice, not a diagnosis.
    public static func ruleCard(options: SickDayOptions) -> [String] {
        [
            "Fever, chills, body aches, a chest cough, vomiting or diarrhoea: no training. Rest, fluids and sleep.",
            "Only a runny nose, sneezing or a mild sore throat, and no fever: easy movement only, like a walk, mobility or back-care holds. No runs, no lifting to failure, no classes.",
            "Back to normal for 24 hours with no fever (without fever medicine): start the way back.",
            "After flu, COVID-19 or \(options.longIllnessDays)+ days ill: walks, back care and mobility come back first; hard sessions wait \(options.hardWaitDays) days.",
            "Any of the signs below: stop and get checked.",
        ]
    }

    /// The signs that mean see a doctor (research 12 §1).
    public static let redFlags = [
        "Chest pain or pressure, a racing or irregular heartbeat, fainting or nearly fainting: stop and get medical advice today; call 911 if it's severe.",
        "Breathless at rest, too breathless to speak in short sentences, or coughing up blood: call 911.",
        "A high temperature for 5 days or more, or one that doesn't come down with paracetamol: see a doctor.",
        "Getting worse instead of better after 3–4 days, or new symptoms after you seemed to recover: see a doctor.",
        "When you restart: unusual breathlessness, a heart rate much higher than usual for the effort, or crushing tiredness: stop the way back; see a doctor if it happens twice.",
        "Blood in stool or vomit, can't keep fluids down, diarrhoea over 7 days or vomiting over 2 days: see a doctor.",
        "A stiff neck with a headache and light hurting your eyes, a rash that doesn't fade under a glass, or confusion: call 911.",
    ]

    /// The red flags show by themselves after a run of "Worse" or "Same" mornings (D223).
    public static func showRedFlags(_ episode: SickEpisode, options: SickDayOptions) -> Bool {
        let feels = episode.checks.sorted { $0.date < $1.date }.map(\.feel)
        func run(of f: SickFeel) -> Int { feels.reversed().prefix { $0 == f }.count }
        return run(of: .worse) >= options.redFlagsAfterWorse || run(of: .same) >= options.redFlagsAfterSame
    }

    /// The app proposes "Back to normal" after enough "Better" mornings, with no fever, and resting HR
    /// near usual when the strap knows it.
    public static func proposeEnd(_ episode: SickEpisode, restingHRNearUsual: Bool?, options: SickDayOptions) -> Bool {
        let recent = episode.checks.sorted { $0.date < $1.date }.suffix(options.proposeEndAfterBetter)
        guard recent.count == options.proposeEndAfterBetter,
              recent.allSatisfy({ $0.feel == .better && !$0.fever }) else { return false }
        return restingHRNearUsual ?? true
    }

    /// Days missed → the way back.
    public static func step(daysMissed: Int, options: SickDayOptions) -> WayBackStep {
        for band in options.bands {
            guard let upTo = band.upToDays else { return band.step }
            if daysMissed <= upTo { return band.step }
        }
        return options.bands.last?.step ?? .carryOn
    }

    /// Days a plan missed: past its usual gap since its last session, or the illness's length, whichever
    /// is longer. Zero for a plan with no session yet.
    public static func daysMissed(plan: any TrainingPlan, episode: SickEpisode?, now: Date,
                                  calendar: Calendar = .current) -> Int {
        guard let last = plan.lastSession else { return 0 }
        let since = calendar.dateComponents([.day], from: calendar.startOfDay(for: last),
                                            to: calendar.startOfDay(for: now)).day ?? 0
        let gap = max(0, since - plan.usualGapDays)
        let ill = episode.map { $0.days(now: now, calendar: calendar) } ?? 0
        return max(gap, ill)
    }

    /// The first day back for each intensity, counted from the day after the illness ended.
    public static func resumes(after episode: SickEpisode, options: SickDayOptions,
                               calendar: Calendar = .current) -> [SessionIntensity: Date] {
        guard let end = episode.end else { return [:] }
        let first = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        func plus(_ d: Int) -> Date { calendar.date(byAdding: .day, value: d, to: first) ?? first }
        guard episode.feverType else { return [.gentle: first, .moderate: first, .hard: first] }
        let easy = options.easyDaysAfterFeverType
        let long = episode.kind == .covid || episode.kind == .fever || episode.days(now: end, calendar: calendar) >= options.longIllnessDays
        // Day 0 is walk-only; gentle plans join on day 1; moderate ones after the easy days.
        return [.gentle: plus(min(1, easy)), .moderate: plus(easy),
                .hard: plus(long ? max(easy, options.hardWaitDays - 1) : easy)]
    }

    /// Fever-type: the first easy day is a walk only.
    public static func walkOnly(after episode: SickEpisode, options: SickDayOptions, now: Date,
                                calendar: Calendar = .current) -> Bool {
        guard episode.feverType, options.easyDaysAfterFeverType > 0, let end = episode.end else { return false }
        let first = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        return calendar.isDate(now, inSameDayAs: first)
    }
}

/// Today for one plan while ill or on the way back (D224, D233): the same for every plan, through its
/// own answers to the plan interface.
public struct IllnessContext: Equatable, Sendable {
    /// The illness that's on, or the last one if it ended recently.
    public let episode: SickEpisode
    public let options: SickDayOptions

    public init(episode: SickEpisode, options: SickDayOptions) {
        self.episode = episode
        self.options = options
    }

    func today(for plan: any TrainingPlan, now: Date, calendar: Calendar) -> PlanToday {
        if episode.isOn {
            if options.floorOnColdDays, episode.kind == .cold || episode.checks.last?.feel == .better,
               let floor = plan.sickFloor(now: now, calendar: calendar) {
                return floor
            }
            return PlanToday(planID: plan.id, status: .hold, headline: "Paused",
                             detail: "Paused while you're unwell. Rest counts.")
        }
        let resume = SickDays.resumes(after: episode, options: options, calendar: calendar)[plan.intensity]
        if let resume, calendar.startOfDay(for: now) < resume {
            let walkOnly = SickDays.walkOnly(after: episode, options: options, now: now, calendar: calendar)
            return PlanToday(planID: plan.id, status: .hold, headline: "Back \(resume.formatted(.dateTime.weekday(.wide)))",
                             detail: walkOnly ? "Today is an easy walk only." : "Easy days first after being ill.")
        }
        return plan.today(now: now, calendar: calendar)
    }
}
