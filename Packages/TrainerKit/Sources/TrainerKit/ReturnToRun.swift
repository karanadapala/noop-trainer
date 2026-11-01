import Foundation

/// Why a run was stopped early (D111, D119).
public enum StopReason: String, CaseIterable, Codable, Sendable {
    case pain, breathing, tiredLegs, other

    public var label: String {
        switch self {
        case .pain: return "Pain"
        case .breathing: return "Breathing"
        case .tiredLegs: return "Tired legs"
        case .other: return "Something else"
        }
    }
}

/// A run that ended early, and why.
public struct RunStop: Codable, Equatable, Sendable {
    public let date: Date
    public let week: Int
    public let day: Int
    public let reason: StopReason
    /// The 0–10 score while walking, when it was pain.
    public let painScore: Int?
    public let area: BodyArea?

    public init(date: Date, week: Int, day: Int, reason: StopReason, painScore: Int? = nil, area: BodyArea? = nil) {
        self.date = date
        self.week = week
        self.day = day
        self.reason = reason
        self.painScore = painScore
        self.area = area
    }

    /// Said at the start of each walk on the first run back (D117).
    public var checkIn: String? {
        guard reason == .pain else { return nil }
        let part = area.map { "How's the \($0.spokenName)?" } ?? "How does it feel?"
        return "\(part) 4 out of 10 or more, walk the rest."
    }
}

/// What the coach tells you right after a stop (D119). Advice, not a diagnosis.
public enum StopAdvice: Equatable, Sendable {
    /// Chest pain, feeling faint, or very short of breath.
    case urgent
    /// A bone spot, walking pain 5/10 or more, or nerve signs.
    case walkHomeGetChecked
    case walkOrHeadHome

    public static func after(reason: StopReason, score: Int?, spot: Bool, nerveSign: Bool,
                             breathingWarning: Bool) -> StopAdvice {
        if reason == .breathing && breathingWarning { return .urgent }
        if reason == .pain, spot || nerveSign || (score ?? 0) >= 5 { return .walkHomeGetChecked }
        return .walkOrHeadHome
    }

    public var text: String {
        switch self {
        case .urgent:
            return "Stop now and get help: call your local emergency number. Chest pain, feeling faint or being very short of breath needs checking straight away."
        case .walkHomeGetChecked:
            return "Walk home gently. Don't run until this has been checked by a GP or physio. I'll ask how it feels tomorrow morning."
        case .walkOrHeadHome:
            return "Walk the rest if it's comfortable, or head home. I'll check on it tomorrow morning."
        }
    }
}

/// One morning step towards running again (D116).
public struct GateEntry: Codable, Equatable, Sendable {
    public enum Step: String, Codable, CaseIterable, Sendable {
        /// No sore spot on the bone, no ache at rest or overnight, walking around is pain-free.
        case basics
        /// A pain-free 20–30 minute brisk walk.
        case walk
        /// 10 single-leg hops each side at 2/10 or less, and 15+ single-leg heel raises each side.
        case hopAndHeel
    }

    public let date: Date
    public let step: Step
    public let passed: Bool

    public init(date: Date, step: Step, passed: Bool) {
        self.date = date
        self.step = step
        self.passed = passed
    }
}

/// Where C25K picks up after a stop for pain (D117).
public enum RestartPoint: Equatable, Sendable {
    case repeatDay
    case redoWeek(Int)
    /// Back one week: that week and the one stopped in both come up again.
    case backToWeek(Int)

    public var text: String {
        switch self {
        case .repeatDay: return "Repeat the day you stopped on."
        case .redoWeek(let w): return "Week \(w) again from Day 1."
        case .backToWeek(let w): return "Back to week \(w), then on from there."
        }
    }
}

/// The way back to running after a run stopped for pain (D116, D117). Pure: the caller passes the
/// stops, the morning steps and the pain answers.
public struct ReturnToRun: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// No stop for pain since the last completed run.
        case notNeeded
        /// The next step to do. `daysPassed` counts mornings in a row with the basics and the walk.
        case checking(next: GateEntry.Step, daysPassed: Int, failedToday: Bool)
        /// Nothing more today: the basics and walk passed, or it's the day of the stop itself (0 days).
        /// The next step is tomorrow morning.
        case doneForToday(daysPassed: Int)
        case ready(RestartPoint)
        case seeClinician(String)
    }

    public static let daysNeeded = 2
    /// Not cleared by then: a GP or physio should look at it.
    public static let giveUpAfterDays = 10
    /// Checks that took longer than this mean the whole week again.
    public static let slowAfterDays = 5

    public let status: Status
    /// The stop this is about, for the restart and the run-bout check-ins.
    public let stop: RunStop?

    public var holdsRuns: Bool {
        switch status {
        case .checking, .doneForToday, .seeClinician: return true
        case .notNeeded, .ready: return false
        }
    }

    /// - Parameters:
    ///   - lastCompletedRun: when the latest finished run was; a run after the stop ends all this.
    ///   - redFlag: the pain answers show a red flag for the area (bone spot, nerve signs, worse).
    public init(stops: [RunStop], gates: [GateEntry], pain: [PainEntry], lastCompletedRun: Date?,
                redFlag: Bool, now: Date, calendar: Calendar = .current) {
        guard let stop = stops.filter({ $0.reason == .pain }).max(by: { $0.date < $1.date }),
              lastCompletedRun.map({ $0 < stop.date }) ?? true else {
            self.status = .notNeeded
            self.stop = nil
            return
        }
        self.stop = stop
        let stopDay = calendar.startOfDay(for: stop.date)
        let today = calendar.startOfDay(for: now)
        func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }
        let after = gates.filter { day($0.date) > stopDay }.sorted { $0.date < $1.date }

        // A day counts when both the basics and the walk passed that day.
        var streak = 0
        var lastPassDay: Date?
        var hopsPassed: Date?
        var cursor = calendar.date(byAdding: .day, value: 1, to: stopDay) ?? today
        while cursor <= today {
            let todays = after.filter { day($0.date) == cursor }
            let basics = todays.last { $0.step == .basics }
            let walk = todays.last { $0.step == .walk }
            if basics?.passed == true && walk?.passed == true {
                streak += 1
                lastPassDay = cursor
            } else if basics?.passed == false || walk?.passed == false {
                streak = 0
            } else if cursor < today && !todays.contains(where: { $0.step == .hopAndHeel }) {
                streak = 0      // a missed day breaks the run of days
            }
            if streak >= Self.daysNeeded, todays.contains(where: { $0.step == .hopAndHeel && $0.passed }) {
                hopsPassed = cursor
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? today.addingTimeInterval(86_400)
        }
        let daysSince = calendar.dateComponents([.day], from: stopDay, to: today).day ?? 0

        if redFlag {
            self.status = .seeClinician("A red flag showed up. Get it checked before running again.")
        } else if let ready = hopsPassed {
            let took = calendar.dateComponents([.day], from: stopDay, to: ready).day ?? 0
            self.status = .ready(Self.restart(after: stop, stops: stops, pain: pain, checksTook: took,
                                              calendar: calendar))
        } else if daysSince > Self.giveUpAfterDays {
            self.status = .seeClinician("Still not clear after \(Self.giveUpAfterDays) days. A GP or physio should look at it.")
        } else {
            let todays = after.filter { day($0.date) == today }
            let failedToday = todays.contains { !$0.passed }
            if today == stopDay {
                // Checks start the morning after the stop.
                self.status = .doneForToday(daysPassed: 0)
            } else if streak >= Self.daysNeeded && lastPassDay != nil {
                self.status = .checking(next: .hopAndHeel, daysPassed: streak, failedToday: failedToday)
            } else if lastPassDay == today {
                self.status = .doneForToday(daysPassed: streak)
            } else if !todays.contains(where: { $0.step == .basics && $0.passed }) {
                self.status = .checking(next: .basics, daysPassed: streak, failedToday: failedToday)
            } else {
                self.status = .checking(next: .walk, daysPassed: streak, failedToday: failedToday)
            }
        }
    }

    /// D117: pain 4/10 or more that lasted into the next day → back a week; checks over 5 days, or a
    /// second stop in the same week → that week again; otherwise repeat the day.
    static func restart(after stop: RunStop, stops: [RunStop], pain: [PainEntry], checksTook: Int,
                        calendar: Calendar) -> RestartPoint {
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: stop.date)) ?? stop.date
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: nextDay) ?? nextDay
        let nextMorning = pain.filter { $0.date >= nextDay && $0.date < dayAfter }
        // No answer that morning counts as not settled.
        let settled = !nextMorning.isEmpty && nextMorning.allSatisfy { e in
            if case .trend(.gone) = e.kind { return true }
            return (e.value ?? 0) == 0
        }
        if (stop.painScore ?? 0) >= 4 && !settled && stop.week > 1 { return .backToWeek(stop.week - 1) }
        let painStopsThisWeek = stops.filter { $0.reason == .pain && $0.week == stop.week }.count
        if (stop.painScore ?? 0) >= 4 && !settled { return .redoWeek(stop.week) }
        if checksTook > Self.slowAfterDays || painStopsThisWeek >= 2 { return .redoWeek(stop.week) }
        return .repeatDay
    }
}
