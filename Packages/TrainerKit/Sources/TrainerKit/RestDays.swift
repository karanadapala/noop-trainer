import Foundation

/// Where today sits in the C25K rhythm. The plan's one scheduling rule is a rest day between runs,
/// so today depends only on when the last C25K run was.
public enum TrainingDay: Equatable, Sendable {
    /// No run yesterday or today: a good day for the next session.
    case runDay
    /// Already ran today. `nextRunFrom` is the first day the next run is due.
    case ranToday(nextRunFrom: Date)
    /// Ran yesterday: today is for recovery.
    case restDay(nextRunFrom: Date)

    public static func on(_ now: Date, lastRun: Date?, calendar: Calendar = .current) -> TrainingDay {
        guard let lastRun else { return .runDay }
        let today = calendar.startOfDay(for: now)
        let runDay = calendar.startOfDay(for: lastRun)
        let days = calendar.dateComponents([.day], from: runDay, to: today).day ?? 2
        let nextRun = calendar.date(byAdding: .day, value: 2, to: runDay) ?? today
        switch days {
        case ..<1: return .ranToday(nextRunFrom: nextRun)
        case 1: return .restDay(nextRunFrom: nextRun)
        default: return .runDay
        }
    }
}

/// What to do on a rest day, from the morning Charge score (0–100). The bands match the Trainer's
/// recovery rules (D21): below 34 is low, 67 and up is high.
public struct RestAdvice: Equatable, Sendable {
    public enum Band: Equatable, Sendable { case low, moderate, high, unknown }

    public let band: Band
    public let headline: String
    public let detail: String

    public static func band(forCharge charge: Double?) -> Band {
        guard let charge else { return .unknown }
        switch charge {
        case ..<34: return .low
        case ..<67: return .moderate
        default: return .high
        }
    }

    public static func forCharge(_ charge: Double?) -> RestAdvice {
        switch band(forCharge: charge) {
        case .low:
            return RestAdvice(band: .low, headline: "Take it easy today",
                              detail: "Your body is still catching up. Sleep, drink water, and keep any walk short and slow.")
        case .moderate:
            return RestAdvice(band: .moderate, headline: "Move gently",
                              detail: "A relaxed 20-minute walk or some stretching helps your legs recover. Keep it easy enough to chat.")
        case .high:
            return RestAdvice(band: .high, headline: "Recovered and ready",
                              detail: "Save the running for your next session. A 20–30 minute easy walk or mobility work keeps you loose.")
        case .unknown:
            return RestAdvice(band: .unknown, headline: "Rest between runs",
                              detail: "Your legs get stronger on the days in between. An easy walk or some stretching is plenty.")
        }
    }

    /// A one-line nudge for a run day when Charge is low, or nil when there's nothing to say.
    public static func runDayNote(forCharge charge: Double?) -> String? {
        band(forCharge: charge) == .low
            ? "Charge is low today. Run gently, or rest and run tomorrow."
            : nil
    }
}
