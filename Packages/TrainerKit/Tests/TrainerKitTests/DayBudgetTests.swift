import XCTest
@testable import TrainerKit

final class DayBudgetTests: XCTestCase {
    private struct Plan: TrainingPlan {
        let id: String
        let place: String?
        let today: PlanToday
        var title: String { id }
        var goals: [Goal] { [] }
        var schedule: PlanSchedule { .rotation(minRestDays: 1, maxGapDays: 3) }
        var placeID: String? { place }
        func today(now: Date, calendar: Calendar) -> PlanToday { today }
    }

    private func plan(_ id: String, _ place: String?, _ status: PlanToday.Status, _ minutes: Int?, later: Bool = false) -> Plan {
        Plan(id: id, place: place, today: PlanToday(planID: id, status: status, headline: "", detail: "",
                                                    minutes: minutes, laterToday: later))
    }

    func testTodayCountsWhatsLeftPlusOneBufferPerPlace() {
        let plans: [any TrainingPlan] = [
            plan("run", "outdoors", .session, 31),
            plan("lift", "gym", .done, nil),
            plan("back", "home", .rest, 8, later: true),
            plan("mobility", "home", .session, 12),
            plan("rest", "home", .rest, nil),
        ]
        let b = DayBudget(plans: plans, day: RegimenDay(plans: plans, now: Date()), options: DayBudgetOptions())
        XCTAssertEqual(b.items.map(\.planID), ["run", "lift", "back", "mobility"])
        XCTAssertEqual(b.minutes, 51)
        XCTAssertEqual(b.buffer, 10, "outdoors 5 + home 5, home counted once")
        XCTAssertEqual(b.keepFree, 75)
        XCTAssertEqual(DayBudget.spoken(b.keepFree), "1 h 15")
        XCTAssertEqual(DayBudget.spoken(60), "an hour")
        XCTAssertEqual(DayBudget.spoken(45), "45 min")
    }

    func testAPlanThatDoesntSayWhereGetsTheOtherBuffer() {
        var o = DayBudgetOptions()
        o.otherBuffer = 20
        o.roundTo = 10
        let plans: [any TrainingPlan] = [plan("new", nil, .session, 30)]
        let b = DayBudget(plans: plans, day: RegimenDay(plans: plans, now: Date()), options: o)
        XCTAssertEqual(b.buffer, 20)
        XCTAssertEqual(b.keepFree, 50)
        let done: [any TrainingPlan] = [plan("new", nil, .done, nil)]
        XCTAssertTrue(DayBudget(plans: done, day: RegimenDay(plans: done, now: Date()), options: o).clear)
    }

    func testHeavyDutyMinutesComeFromItsSettingsAndOldSettingsStillLoad() throws {
        var o = HeavyDutyOptions()
        o.minutesPerExercise = 4
        XCTAssertEqual(o.minutes(exercises: 6), 29)
        let old = Data(#"{"daysBetween": 6, "upperReps": {"low": 6, "high": 10}}"#.utf8)
        if let decoded = try? JSONDecoder().decode(HeavyDutyOptions.self, from: old) {
            XCTAssertEqual(decoded.daysBetween, 6)
            XCTAssertEqual(decoded.minutesPerExercise, 3)
        }
        let full = try JSONEncoder().encode(HeavyDutyOptions())
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: full) as? [String: Any])
        dict.removeValue(forKey: "minutesPerExercise")
        dict.removeValue(forKey: "setupMinutes")
        dict["daysBetween"] = 7
        let decoded = try JSONDecoder().decode(HeavyDutyOptions.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(decoded.daysBetween, 7, "a stored copy from before the new settings keeps its values")
        XCTAssertEqual(decoded.setupMinutes, 5)
    }
}
