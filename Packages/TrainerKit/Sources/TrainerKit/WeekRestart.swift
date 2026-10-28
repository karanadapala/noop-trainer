import Foundation

/// "Restart this week" (D53): run a C25K week again, labelled "2nd time".
public enum WeekRestart {
    /// The week a restart applies to: the current week once any of it is done, otherwise the week just
    /// finished (after Week 2 Day 3 it repeats week 2, not week 3). Nil before the first run.
    public static func week(next: GuidedSession, allDone: Bool, isDone: (GuidedSession) -> Bool) -> Int? {
        if allDone { return C25K.weeks }
        let started = (1...C25K.daysPerWeek).contains { d in C25K.session(week: next.week, day: d).map(isDone) ?? false }
        if started { return next.week }
        return next.week > 1 ? next.week - 1 : nil
    }

    /// "2nd time", "3rd time"; nil the first time through.
    public static func label(attempt: Int) -> String? {
        guard attempt > 1 else { return nil }
        let suffix: String
        switch (attempt % 100, attempt % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(attempt)\(suffix) time"
    }
}
