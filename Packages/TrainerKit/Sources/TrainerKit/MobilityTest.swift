import Foundation

/// The Mobility test day (D148, D199; research 07 §5): eight self-tests, a baseline before week 1, then
/// every 4 weeks, afternoon or evening, after the same warm-up. Self-measured with a phone, which no study
/// has validated, so a change only counts when it's past the test's measurement error and holds for two
/// tests in a row.
public enum MobilityMetric: String, CaseIterable, Codable, Sendable {
    case fingertips, slrLeft, slrRight, hipInLeft, hipInRight, hipOutLeft, hipOutRight, thomasLeft, thomasRight,
         squatSeconds, kneeWallLeft, kneeWallRight, crossLegged

    public var label: String {
        switch self {
        case .fingertips: return "Fingertips to floor"
        case .slrLeft: return "Straight-leg raise, left"
        case .slrRight: return "Straight-leg raise, right"
        case .hipInLeft: return "Hip turn-in, left"
        case .hipInRight: return "Hip turn-in, right"
        case .hipOutLeft: return "Hip turn-out, left"
        case .hipOutRight: return "Hip turn-out, right"
        case .thomasLeft: return "Hip-flexor length, left"
        case .thomasRight: return "Hip-flexor length, right"
        case .squatSeconds: return "Deep-squat hold"
        case .kneeWallLeft: return "Knee to wall, left"
        case .kneeWallRight: return "Knee to wall, right"
        case .crossLegged: return "Sitting cross-legged"
        }
    }

    public var unit: String {
        switch self {
        case .fingertips, .kneeWallLeft, .kneeWallRight: return "cm"
        case .squatSeconds: return "s"
        case .crossLegged: return "min"
        default: return "°"
        }
    }

    /// The fingertips go down (to the floor and past it); the thigh in the Thomas test drops towards
    /// level. Everything else is better higher.
    public var lowerIsBetter: Bool {
        switch self {
        case .fingertips, .thomasLeft, .thomasRight: return true
        default: return false
        }
    }

    /// The smallest change that's more than measurement error. Clinician figures from research 07 §5
    /// (fingertips 4.5 cm, SLR about 6°, hip rotation 5°); the rest are working thresholds (opinion).
    public var smallestRealChange: Double {
        switch self {
        case .fingertips: return 4.5
        case .slrLeft, .slrRight: return 6
        case .hipInLeft, .hipInRight, .hipOutLeft, .hipOutRight, .thomasLeft, .thomasRight: return 5
        case .squatSeconds: return 5
        case .kneeWallLeft, .kneeWallRight: return 2
        case .crossLegged: return 1
        }
    }
}

public struct MobilityTestResult: Codable, Equatable, Sendable {
    public let date: Date
    public var values: [MobilityMetric: Double]
    /// Deep squat: heels stayed down, hips went below the knees, held something.
    public var squatHeelsDown: Bool?
    public var squatHipsBelowKnees: Bool?
    public var squatSupport: Bool?
    /// "How confident did bending feel, 0–10?" (research 07 §5).
    public var confidence: Int?
    /// Back unease the next morning, 0–10.
    public var nextDayUnease: Int?
    /// The straight-leg raise brought something below the knee or in the big toe.
    public var nerveSign: Bool

    public init(date: Date, values: [MobilityMetric: Double] = [:], squatHeelsDown: Bool? = nil,
                squatHipsBelowKnees: Bool? = nil, squatSupport: Bool? = nil, confidence: Int? = nil,
                nextDayUnease: Int? = nil, nerveSign: Bool = false) {
        self.date = date
        self.values = values
        self.squatHeelsDown = squatHeelsDown
        self.squatHipsBelowKnees = squatHipsBelowKnees
        self.squatSupport = squatSupport
        self.confidence = confidence
        self.nextDayUnease = nextDayUnease
        self.nerveSign = nerveSign
    }
}

/// One metric across the test days: from the baseline to the latest, and whether it's real yet.
public struct MobilityChange: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable { case baselineOnly, noRealChange, better, worse }

    public let metric: MobilityMetric
    public let baseline: Double
    public let latest: Double
    public let verdict: Verdict

    /// Signed so that positive is better.
    public var improvement: Double { metric.lowerIsBetter ? baseline - latest : latest - baseline }

    public static func of(_ metric: MobilityMetric, in results: [MobilityTestResult]) -> MobilityChange? {
        let series = results.sorted { $0.date < $1.date }.compactMap { $0.values[metric] }
        guard let first = series.first, let last = series.last else { return nil }
        guard series.count >= 2 else { return MobilityChange(metric: metric, baseline: first, latest: last, verdict: .baselineOnly) }
        func gain(_ v: Double) -> Double { metric.lowerIsBetter ? first - v : v - first }
        let mdc = metric.smallestRealChange
        let lastTwo = series.suffix(2).map(gain)
        let verdict: Verdict
        if series.count >= 3 && lastTwo.allSatisfy({ $0 >= mdc }) { verdict = .better }
        else if series.count >= 3 && lastTwo.allSatisfy({ $0 <= -mdc }) { verdict = .worse }
        else { verdict = .noRealChange }
        return MobilityChange(metric: metric, baseline: first, latest: last, verdict: verdict)
    }
}

extension MobilityPlan {
    /// When the next test day is due: right away for the baseline, then every `testEveryWeeks`.
    public func testDue(tests: [MobilityTestResult], now: Date, calendar: Calendar = .current) -> Date {
        guard let last = tests.map(\.date).max() else { return now }
        return calendar.date(byAdding: .day, value: options.testEveryWeeks * 7, to: calendar.startOfDay(for: last)) ?? now
    }

    /// Today suits a test day: it's due, it's the afternoon or later, no lifting today, no flare (research 07 §5).
    public func testFitsToday(tests: [MobilityTestResult], now: Date, calendar: Calendar = .current) -> Bool {
        guard testDue(tests: tests, now: now, calendar: calendar) <= now else { return false }
        if calendar.component(.hour, from: now) < options.testFromHour { return false }
        if liftToday != nil { return false }
        if BackFlare.current(entries: pain, now: now, calendar: calendar) != nil { return false }
        return !log.contains { calendar.isDate($0.date, inSameDayAs: now) }
    }
}
