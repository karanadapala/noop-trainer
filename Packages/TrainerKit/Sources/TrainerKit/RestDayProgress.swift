import Foundation

/// One finished rest-day routine (D45), kept so stages can move up (D57).
public struct RestSessionLog: Codable, Equatable, Sendable {
    public let date: Date
    public let variant: RoutineVariant
    /// The stage each progressive block was done at.
    public let stages: [Block: Stage]
    /// Exercise ids that were skipped (D39). Skips hold progression.
    public let skipped: [String]
    /// Exercise ids that were done.
    public let done: [String]

    public init(date: Date, variant: RoutineVariant, stages: [Block: Stage], skipped: [String], done: [String]) {
        self.date = date
        self.variant = variant
        self.stages = stages
        self.skipped = skipped
        self.done = done
    }

    public func did(_ block: Block) -> Bool {
        (done + skipped).contains { id in RestDayCatalogue.all.first { $0.id == id }?.block == block }
    }

    func skippedAny(in block: Block) -> Bool {
        skipped.contains { id in RestDayCatalogue.all.first { $0.id == id }?.block == block }
    }
}

/// Single-leg calf raises to fatigue, counted per leg, every three weeks (D57).
public struct CalfBenchmark: Codable, Equatable, Sendable {
    public let date: Date
    public let left: Int
    public let right: Int

    public init(date: Date, left: Int, right: Int) {
        self.date = date
        self.left = left
        self.right = right
    }
}

/// D57's interim rule, read from the log so there is no separate state to drift. A block's stage is
/// the highest it has been done at; it moves up one when the calendar allows it (weeks 4 and 7) **and**
/// its last two sessions at that stage had no skips **and** no pain flags followed them. A repeated
/// C25K week holds every block. Temporary until reps and effort are measured automatically.
public enum RestDayProgress {
    public static func stages(log: [RestSessionLog], pain: [PainEntry], programWeek: Int,
                              repeatingWeek: Bool, calendar: Calendar = .current) -> [Block: Stage] {
        let allowed = Stage.forWeek(programWeek)
        var result: [Block: Stage] = [:]
        for block in Block.progressive {
            let sessions = log.filter { $0.did(block) }.sorted { $0.date < $1.date }
            var stage = sessions.compactMap { $0.stages[block] }.max() ?? .learn
            let lastTwo = sessions.filter { $0.stages[block] == stage }.suffix(2)
            if !repeatingWeek, stage < allowed, lastTwo.count == 2,
               lastTwo.allSatisfy({ isClean($0, block: block, pain: pain, calendar: calendar) }),
               let next = Stage(rawValue: stage.rawValue + 1) {
                stage = next
            }
            result[block] = stage
        }
        return result
    }

    /// No skips in the block, and no pain report or "same"/"worse" morning within a day after it.
    static func isClean(_ s: RestSessionLog, block: Block, pain: [PainEntry], calendar: Calendar) -> Bool {
        guard !s.skippedAny(in: block) else { return false }
        let until = calendar.date(byAdding: .hour, value: 30, to: s.date) ?? s.date
        return !pain.contains { e in
            guard e.date > s.date, e.date <= until else { return false }
            switch e.kind {
            case .report: return true
            case .trend(let t): return t == .same || t == .worse
            }
        }
    }

    /// Whether a calf-raise benchmark is due: none yet, or three weeks since the last one.
    public static func benchmarkDue(_ benchmarks: [CalfBenchmark], now: Date, calendar: Calendar = .current) -> Bool {
        guard let last = benchmarks.map(\.date).max() else { return true }
        // Calendar days, not 24-hour blocks, so a clock change doesn't shift it.
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return days >= 21
    }

    /// How many rest days with a routine followed each run, for the dots on the plan (D45). Each rest
    /// day counts once, towards the latest run on an earlier calendar day.
    public static func restDaysAfterRuns(_ runs: [String: Date], restDates: [Date],
                                         calendar: Calendar = .current) -> [String: Int] {
        let ordered = runs.map { (key: $0.key, day: calendar.startOfDay(for: $0.value)) }.sorted { $0.day < $1.day }
        var counts: [String: Int] = [:]
        for day in Set(restDates.map { calendar.startOfDay(for: $0) }) {
            if let run = ordered.last(where: { $0.day < day }) { counts[run.key, default: 0] += 1 }
        }
        return counts
    }
}
