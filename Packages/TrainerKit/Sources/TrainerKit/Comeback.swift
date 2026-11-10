import Foundation

/// The messages when you go quiet (D226, D228): kind, never "missed", always one next step.
public enum GapMessage: String, Codable, CaseIterable, Sendable {
    case allOK, onHold, freshStart, stillHere

    /// `days`: counted gap days; `next`: what's next in the main plan ("Week 2 · Day 2").
    public func body(days: Int, next: String?) -> String {
        switch self {
        case .allOK:
            return "Haven't seen you for \(days) days. All OK?"
        case .onHold:
            return "Your plan is on hold. Nothing's lost: a few days off costs almost no fitness. When you're ready, start with one short session."
        case .freshStart:
            if let next { return "New week, fresh start: \(next), take two, can start today." }
            return "New week, fresh start. One short session can start today."
        case .stillHere:
            return "Still here when you are. Want me to plan the first week back?"
        }
    }
}

/// Every number behind going quiet and coming back (D226, D227). Decoded key by key.
public struct GapOptions: Codable, Equatable, Sendable {
    public var enabled = true
    /// Counted gap days (days that had a session planned) → the message sent that day.
    public var steps: [GapStep] = [
        GapStep(day: 2, message: .allOK), GapStep(day: 4, message: .onHold),
        GapStep(day: 7, message: .freshStart), GapStep(day: 14, message: .stillHere),
    ]
    /// When they're sent.
    public var hour = 12
    public var minute = 0
    /// The comeback screen shows on the first open after this many counted gap days.
    public var comebackAfterDays = 2
    /// "Back tomorrow": the reminder's time.
    public var tomorrowHour = 9

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GapOptions()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        steps = try c.decodeIfPresent([GapStep].self, forKey: .steps) ?? d.steps
        hour = try c.decodeIfPresent(Int.self, forKey: .hour) ?? d.hour
        minute = try c.decodeIfPresent(Int.self, forKey: .minute) ?? d.minute
        comebackAfterDays = try c.decodeIfPresent(Int.self, forKey: .comebackAfterDays) ?? d.comebackAfterDays
        tomorrowHour = try c.decodeIfPresent(Int.self, forKey: .tomorrowHour) ?? d.tomorrowHour
    }
}

public struct GapStep: Codable, Equatable, Sendable {
    public var day: Int
    public var message: GapMessage

    public init(day: Int, message: GapMessage) {
        self.day = day
        self.message = message
    }
}

/// Why you were away, asked once on the way back in (D227).
public enum GapReason: String, CaseIterable, Codable, Sendable {
    case ill, injured, busy, aBreak, rather

    public var label: String {
        switch self {
        case .ill: return "Ill"
        case .injured: return "Injured"
        case .busy: return "Busy"
        case .aBreak: return "Just a break"
        case .rather: return "Rather not say"
        }
    }
}

public enum Comeback {
    /// The plan for next time, saved on the comeback screen (D227); editable.
    public static let defaultCopingPlan = "If I'm sick, I tap \"I'm unwell\". The app pauses everything. When I'm better, it plans my way back and I do the first step the next day."

    /// Days after `lastSeen`, up to and including `now`'s day, that had a session planned. Rest days
    /// don't count (D226).
    public static func gapDays(lastSeen: Date, now: Date, calendar: Calendar = .current,
                               isSessionDay: (Date) -> Bool) -> Int {
        let start = calendar.startOfDay(for: lastSeen)
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day ?? 0
        guard days > 0 else { return 0 }
        return (1...days).filter { d in
            calendar.date(byAdding: .day, value: d, to: start).map(isSessionDay) ?? false
        }.count
    }

    /// When each message goes out if you don't come back: the day the n-th counted gap day falls on, at
    /// the set time. Looks no further ahead than `horizonDays`.
    public static func schedule(lastSeen: Date, options: GapOptions, calendar: Calendar = .current,
                                horizonDays: Int = 60,
                                isSessionDay: (Date) -> Bool) -> [(step: GapStep, date: Date)] {
        guard options.enabled else { return [] }
        let start = calendar.startOfDay(for: lastSeen)
        var counted = 0
        var dayOf: [Int: Date] = [:]
        for d in 1...max(1, horizonDays) {
            guard let day = calendar.date(byAdding: .day, value: d, to: start) else { continue }
            if isSessionDay(day) {
                counted += 1
                dayOf[counted] = day
            }
        }
        return options.steps.compactMap { step in
            guard let day = dayOf[step.day],
                  let at = calendar.date(bySettingHour: options.hour, minute: options.minute, second: 0, of: day),
                  at > lastSeen else { return nil }
            return (step, at)
        }
    }
}
