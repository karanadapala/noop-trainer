import XCTest
@testable import TrainerKit

final class MobilityTestTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ d: Int, _ hour: Int = 17) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    private func result(_ d: Int, _ fingertips: Double) -> MobilityTestResult {
        MobilityTestResult(date: at(d), values: [.fingertips: fingertips])
    }

    func testAChangeCountsWhenPastTheErrorTwiceInARow() {
        XCTAssertEqual(MobilityChange.of(.fingertips, in: [result(1, 20)])?.verdict, .baselineOnly)
        // 5 cm better once: not yet.
        XCTAssertEqual(MobilityChange.of(.fingertips, in: [result(1, 20), result(29, 15)])?.verdict, .noRealChange)
        // Held for a second test: real.
        let better = MobilityChange.of(.fingertips, in: [result(1, 20), result(29, 15), result(57, 14)])
        XCTAssertEqual(better?.verdict, .better)
        XCTAssertEqual(better?.improvement, 6)
        // Inside the error: no real change, even three times.
        XCTAssertEqual(MobilityChange.of(.fingertips, in: [result(1, 20), result(29, 17), result(57, 16)])?.verdict, .noRealChange)
        // Higher is better for the straight-leg raise.
        let slr = [MobilityTestResult(date: at(1), values: [.slrLeft: 60]), MobilityTestResult(date: at(29), values: [.slrLeft: 52]),
                   MobilityTestResult(date: at(57), values: [.slrLeft: 50])]
        XCTAssertEqual(MobilityChange.of(.slrLeft, in: slr)?.verdict, .worse)
    }

    func testTheTestDayFitsAfternoonsWithoutLiftingOrAFlare() {
        func plan(lift: HeavyDuty.Workout? = nil, pain: [PainEntry] = []) -> MobilityPlan {
            MobilityPlan(options: MobilityOptions(), start: at(1, 9), log: [], pain: pain, shinCleared: true,
                         liftToday: lift, liftDone: false, wake: nil)
        }
        // The baseline is due straight away, from the afternoon.
        XCTAssertTrue(plan().testFitsToday(tests: [], now: at(1, 17), calendar: cal))
        XCTAssertFalse(plan().testFitsToday(tests: [], now: at(1, 10), calendar: cal))
        XCTAssertFalse(plan(lift: .upper).testFitsToday(tests: [], now: at(1, 17), calendar: cal))
        XCTAssertFalse(plan(pain: [PainEntry(area: .back, date: at(1, 9), kind: .rating(3))])
                        .testFitsToday(tests: [], now: at(1, 17), calendar: cal))
        // Then every 4 weeks.
        let base = [result(1, 20)]
        XCTAssertFalse(plan().testFitsToday(tests: base, now: at(28), calendar: cal))
        XCTAssertTrue(plan().testFitsToday(tests: base, now: at(29), calendar: cal))
    }
}
