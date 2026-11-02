import XCTest
@testable import TrainerKit

final class MobilityTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ d: Int, _ hour: Int = 18) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    private func plan(start: Int = 1, log: [MobilityLog] = [], pain: [PainEntry] = [], shin: Bool = false,
                      lift: HeavyDuty.Workout? = nil, done: Bool = false, wake: Date? = nil) -> MobilityPlan {
        MobilityPlan(options: MobilityOptions(), start: at(start, 9), log: log, pain: pain, shinCleared: shin,
                     liftToday: lift, liftDone: done, wake: wake)
    }

    func testPhaseOneGoesALittleFurtherEachWeekAndWaitsForTheShin() {
        let w1 = Mobility.session(.full, week: 1, shinCleared: false)
        XCTAssertEqual(w1.items.first { $0.exercise.id == "rollDown" }?.dose.variant, "Hands to your knees")
        XCTAssertTrue(w1.note?.hasPrefix("Bending is a normal movement") == true)
        let w3 = Mobility.session(.full, week: 3, shinCleared: false)
        XCTAssertEqual(w3.items.first { $0.exercise.id == "rollDown" }?.dose.variant, "Hands to your ankles")
        XCTAssertTrue((10...20).contains(w1.estimatedMinutes), "\(w1.estimatedMinutes)")
        // Phase 2 adds the deep squat and heel drops only once the shin is cleared.
        XCTAssertFalse(Mobility.session(.full, week: 5, shinCleared: false).items.contains { $0.exercise.id == "deepSquat" })
        XCTAssertTrue(Mobility.session(.full, week: 5, shinCleared: true).items.contains { $0.exercise.id == "deepSquat" })
        // No loaded bending in any session.
        for w in 1...14 {
            XCTAssertFalse(Mobility.session(.full, week: w, shinCleared: true, strengthDay: true).items
                .contains { $0.exercise.name.lowercased().contains("jefferson") })
        }
        // The nerve slider starts on the right leg.
        let t = RoutineTimeline(w1)
        XCTAssertTrue(t.cues.contains { $0.text.hasPrefix("Right leg") })
    }

    func testTheDay() {
        XCTAssertEqual(plan().next(now: at(5), calendar: cal), .session(.full))
        XCTAssertEqual(plan(lift: .upper).next(now: at(5), calendar: cal), .afterLifts(.upper))
        XCTAssertEqual(plan(lift: .upper, done: true).next(now: at(5), calendar: cal), .session(.short))
        XCTAssertEqual(plan(wake: at(5, 7)).next(now: at(5, 7), calendar: cal), .later(at(5, 8)))
        XCTAssertEqual(plan(log: [MobilityLog(date: at(5, 17), session: .full, week: 1)]).next(now: at(5), calendar: cal), .done)
        // A back flare: hips only for the first 48 hours.
        let flare = PainEntry(area: .back, date: at(5, 9), kind: .rating(3))
        XCTAssertEqual(plan(pain: [flare]).next(now: at(5), calendar: cal), .session(.hipsOnly))
        XCTAssertFalse(Mobility.session(.hipsOnly, week: 3, shinCleared: true).items
            .contains { ["rollDown", "catCamel", "sciaticSlider", "hamstring"].contains($0.exercise.id) })
    }

    func testAFlareSetsTheWeeksBack() {
        // 20 days in, no flares: week 3.
        XCTAssertEqual(Mobility.week(start: at(1, 9), pain: [], now: at(21), calendar: cal), 3)
        // A 3-day flare: its days plus a week back.
        let pain = [PainEntry(area: .back, date: at(10), kind: .rating(3)),
                    PainEntry.morning(area: .back, date: at(13, 8), score: 0, previous: 3)]
        XCTAssertEqual(Mobility.planDay(start: at(1, 9), pain: pain, now: at(21), calendar: cal), 20 - 3 - 7)
        // With tingling: two weeks back.
        let nerve = [PainEntry(area: .back, date: at(10), kind: .rating(3), feel: .tingling),
                     PainEntry.morning(area: .back, date: at(13, 8), score: 0, previous: 3)]
        XCTAssertEqual(Mobility.planDay(start: at(1, 9), pain: nerve, now: at(30), calendar: cal), 29 - 3 - 14)
    }

    func testPhaseThreeAlternatesStrength() {
        let start = at(1, 9)
        let p = MobilityPlan(options: MobilityOptions(), start: start, log: [], pain: [], shinCleared: true,
                             liftToday: nil, liftDone: false, wake: nil)
        let day60 = cal.date(byAdding: .day, value: 60, to: start)!
        XCTAssertEqual(Mobility.Phase.of(week: p.week(now: day60, calendar: cal)), .strength)
        XCTAssertTrue(p.strengthDay(now: day60, calendar: cal))
        let one = MobilityPlan(options: MobilityOptions(), start: start, log: [MobilityLog(date: day60, session: .full, week: 9)],
                               pain: [], shinCleared: true, liftToday: nil, liftDone: false, wake: nil)
        XCTAssertFalse(one.strengthDay(now: day60, calendar: cal))
        XCTAssertTrue(one.routine(for: .full, now: day60, calendar: cal).items.contains { $0.exercise.id == "rollDown" })
    }
}
