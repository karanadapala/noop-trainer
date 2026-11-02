import Foundation

/// Muscles a session works hard, for the conflict rules (D86): 48 h between hard sessions on the same
/// muscles, and a run is hard for the legs.
public enum Muscle: String, CaseIterable, Codable, Sendable {
    case legs, chest, back, shoulders, arms, core
}

/// How a plan's sessions fall on the calendar (D66).
public enum PlanSchedule: Equatable, Sendable {
    /// A fixed ladder of weeks with a set number of sessions each (C25K).
    case fixedWeeks(weeks: Int, perWeek: Int)
    /// Sessions in turn, each after at least `minRestDays` and ideally before `maxGapDays` (Heavy Duty).
    case rotation(minRestDays: Int, maxGapDays: Int)
    /// Sessions on days the user enters (club classes).
    case timetable
}

/// What a plan has for today, in the same shape for every plan so the Regimen can line them up.
public struct PlanToday: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// A session is due today.
        case session
        /// A planned rest day.
        case rest
        /// Today's session is done.
        case done
        /// A session would be due, but pain or a check holds it.
        case hold
        /// The plan is complete.
        case finished
    }

    public let planID: String
    public let status: Status
    /// "Week 2 · Day 2", "Rest day".
    public let headline: String
    public let detail: String
    /// Length of today's session, when there is one.
    public let minutes: Int?
    /// What today's session works hard (empty on rest days).
    public let works: Set<Muscle>

    public init(planID: String, status: Status, headline: String, detail: String, minutes: Int? = nil,
                works: Set<Muscle> = []) {
        self.planID = planID
        self.status = status
        self.headline = headline
        self.detail = detail
        self.minutes = minutes
        self.works = works
    }
}

/// The one interface every plan plugs in through (D97). A plan knows its own schedule and state and
/// nothing about other plans; the Regimen lines them up.
public protocol TrainingPlan: Sendable {
    var id: String { get }
    var title: String { get }
    var goals: [Goal] { get }
    var schedule: PlanSchedule { get }
    func today(now: Date, calendar: Calendar) -> PlanToday
}

/// All active plans for one day (D67, D139).
public struct RegimenDay: Equatable, Sendable {
    /// One entry per plan, in the order the plans were given (the main goal's plan first).
    public let plans: [PlanToday]

    public init(plans: [any TrainingPlan], now: Date, calendar: Calendar = .current) {
        self.plans = plans.map { $0.today(now: now, calendar: calendar) }
    }

    /// The first session due today and not on hold: what the Regimen card offers to start.
    public var next: PlanToday? { plans.first { $0.status == .session } }

    public var allDone: Bool { !plans.isEmpty && plans.allSatisfy { $0.status != .session && $0.status != .hold } }
}

public extension Goal {
    /// The goals the Regimen shows (D191): the ones you picked in setup, plus any goal an active plan
    /// serves, since a running plan can't sit under a goal that isn't there. Always in `allCases` order.
    static func shown(chosen: [Goal], plans: [any TrainingPlan]) -> [Goal] {
        let served = Set(plans.flatMap(\.goals))
        return allCases.filter { chosen.contains($0) || served.contains($0) }
    }
}

/// C25K on the plan layer. A view of the runner's state: the rules themselves (rest rhythm, holds, the
/// way back) are unchanged and worked out where they always were; this only reports them.
public struct C25KPlan: TrainingPlan {
    public static let planID = "c25k"

    public var id: String { Self.planID }
    public var title: String { "C25K" }
    public var goals: [Goal] { [.cardio] }
    public var schedule: PlanSchedule { .fixedWeeks(weeks: C25K.weeks, perWeek: C25K.daysPerWeek) }

    public let completed: Set<String>
    public let lastRun: Date?
    public let lastRunDay: Int?
    /// Why runs are held today (pain answers, checks after a stop); empty when they aren't.
    public let holdReasons: [String]

    public init(completed: Set<String>, lastRun: Date?, lastRunDay: Int?, holdReasons: [String]) {
        self.completed = completed
        self.lastRun = lastRun
        self.lastRunDay = lastRunDay
        self.holdReasons = holdReasons
    }

    /// The first session not done yet, in plan order; nil when all 27 are done.
    public var nextSession: GuidedSession? { C25K.all.first { !completed.contains($0.id) } }

    public func today(now: Date, calendar: Calendar = .current) -> PlanToday {
        guard let next = nextSession else {
            return PlanToday(planID: id, status: .finished, headline: "Plan complete",
                             detail: "All 27 sessions done.")
        }
        let label = "Week \(next.week) · Day \(next.day)"
        let minutes = next.totalSeconds / 60
        switch TrainingDay.on(now, lastRun: lastRun, lastRunDay: lastRunDay, calendar: calendar) {
        case .ranToday:
            return PlanToday(planID: id, status: .done, headline: "Done for today", detail: "Next: \(label).")
        case .restDay:
            return PlanToday(planID: id, status: .rest, headline: "Rest day", detail: "Next: \(label).")
        case .runDay where !holdReasons.isEmpty:
            return PlanToday(planID: id, status: .hold, headline: label,
                             detail: holdReasons.joined(separator: ". "), minutes: minutes, works: [.legs])
        case .runDay:
            return PlanToday(planID: id, status: .session, headline: label, detail: Self.summary(next),
                             minutes: minutes, works: [.legs])
        }
    }

    /// "31 min · 6 runs of 90 seconds", "38 min · 3 runs, longest 5 minutes". The C25K screen shows
    /// the same line.
    public static func summary(_ s: GuidedSession) -> String {
        let runs = s.segments.filter(\.kind.isRun).map(\.seconds)
        let total = "\(s.totalSeconds / 60) min"
        guard let longest = runs.max() else { return total }
        if runs.count == 1 { return "\(total) · one \(CueTimeline.spokenDuration(longest)) run" }
        if Set(runs).count == 1 { return "\(total) · \(runs.count) runs of \(CueTimeline.spokenDuration(longest))" }
        return "\(total) · \(runs.count) runs, longest \(CueTimeline.spokenDuration(longest))"
    }
}
