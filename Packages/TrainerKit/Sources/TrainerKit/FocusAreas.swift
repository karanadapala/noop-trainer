import Foundation

/// Which sore areas get their own strengthening block, and for how long (D110, D118). Pure: worked out
/// from the pain answers, stopped runs, finished runs and calf-raise tests, so there is no state to drift.
///
/// - An area **comes into focus** with a report of 3/10 or more, a sharp spot, or a run stopped for pain
///   there. A later flag starts the clock again.
/// - It **stays** at least 3 weeks, and until 6 runs in a row since its last report of 2/10 or more,
///   and until it passes its test: calves and shins about 20 single-leg heel raises each side, within
///   3 of each other; feet 10 each side. Knees and hips have no test.
/// - At most **two** areas at a time, the most recent first.
public enum FocusAreas {
    public static let maxAreas = 2
    public static let minDays = 21
    public static let clearRunsNeeded = 6

    public static func current(pain: [PainEntry], stops: [RunStop], runs: [Date], benchmarks: [CalfBenchmark],
                               now: Date, calendar: Calendar = .current) -> [BodyArea] {
        var started: [(BodyArea, Date)] = []
        for area in BodyArea.focusable {
            let entries = pain.filter { $0.area == area }
            let reported: [Date] = entries.filter { e in e.kind == .spot || (e.value ?? 0) >= PainScale.limit }.map { $0.date }
            let stopped: [Date] = stops.filter { s in s.reason == .pain && s.area == area }.map { $0.date }
            let flags = reported + stopped
            guard let start = flags.max() else { continue }
            let noticed: [Date] = entries.filter { e in e.kind == .spot || (e.value ?? 0) >= 2 }.map { $0.date }
            let lastNoticed = noticed.max() ?? start
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                               to: calendar.startOfDay(for: now)).day ?? 0
            let clearRuns = runs.filter { $0 > lastNoticed }.count
            let passed = testPassed(area, benchmarks.filter { $0.date > start })
            if days >= minDays && clearRuns >= clearRunsNeeded && passed { continue }
            started.append((area, start))
        }
        return started.sorted { $0.1 > $1.1 }.prefix(maxAreas).map(\.0)
    }

    static func testPassed(_ area: BodyArea, _ benchmarks: [CalfBenchmark]) -> Bool {
        guard let last = benchmarks.max(by: { $0.date < $1.date }) else { return area == .knees || area == .hips }
        switch area {
        case .shins, .calves: return min(last.left, last.right) >= 20 && abs(last.left - last.right) <= 3
        case .feet: return min(last.left, last.right) >= 10
        case .knees, .hips, .back: return true
        }
    }
}
