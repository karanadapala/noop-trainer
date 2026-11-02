import XCTest
@testable import TrainerKit

final class HeavyDutyTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ d: Int, hour: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    private let options = HeavyDutyOptions()
    private let dumbbells = Equipment(.dumbbells, lightest: 5, heaviest: 40, step: 5)
    private let upper = RepRange(8, 12)

    private func set(_ d: Int, _ w: Double?, _ reps: Int) -> LiftResult { LiftResult(date: day(d), weight: w, reps: reps) }

    // MARK: Routine

    func testRoutineKeepsTheBackChangesAndCalvesWaitForC25K() {
        let up = HeavyDuty.exercises(.upper, c25kFinished: false).map(\.id)
        XCTAssertEqual(up.first, "crossover")
        XCTAssertTrue(up.contains("reverseFly"))
        XCTAssertFalse(HeavyDuty.exercises.contains { $0.name.lowercased().contains("bent-over") })
        XCTAssertFalse(HeavyDuty.exercises(.legs, c25kFinished: false).contains { $0.id == "toePress" })
        XCTAssertTrue(HeavyDuty.exercises(.legs, c25kFinished: true).contains { $0.id == "toePress" })
        let pairs = HeavyDuty.exercises.compactMap(\.straightInto)
        XCTAssertTrue(pairs.allSatisfy { id in HeavyDuty.exercises.contains { $0.id == id } })
        XCTAssertEqual(HeavyDuty.exercises.first { $0.id == "legPress" }?.stopTap, .formBroke)
    }

    // MARK: Weights

    func testFirstTimeFindsTheWeight() {
        let s = WeightSuggestion.next(history: [], reps: upper, kit: dumbbells, options: options)
        XCTAssertEqual(s.kind, .findIt)
        XCTAssertEqual(s.weight, 5)
    }

    func testTopOfTheRangeGoesUpToARealStep() {
        // 40 lb at 12 reps on a 10 lb-step stack: +7.5% is 43, the next real step is 50 (+25%) → earn it.
        let stack = Equipment(.cableColumn, lightest: 10, heaviest: 200, step: 10)
        let big = WeightSuggestion.next(history: [set(1, 40, 12)], reps: upper, kit: stack, options: options)
        XCTAssertEqual(big.kind, .raiseCeiling(to: 15))
        XCTAssertEqual(big.reps.high, 15)
        // Having earned it (12 then 15 at the same weight), the jump goes ahead.
        let earned = WeightSuggestion.next(history: [set(1, 40, 12), set(8, 40, 15)], reps: upper, kit: stack, options: options)
        XCTAssertEqual(earned.kind, .increase)
        XCTAssertEqual(earned.weight, 50)
        // A small step is taken straight away, with an expected rep count.
        let fine = Equipment(.cableColumn, lightest: 10, heaviest: 200, step: 5)
        let up = WeightSuggestion.next(history: [set(1, 100, 12)], reps: upper, kit: fine, options: options)
        XCTAssertEqual(up.weight, 110)
        XCTAssertNotNil(up.expectReps)
    }

    func testAtTheHeaviestTheNextAcceptedStep() {
        let s = WeightSuggestion.next(history: [set(1, 40, 12)], reps: upper, kit: dumbbells, options: options)
        XCTAssertEqual(s.kind, .nextStep(.slowerLowering))
        XCTAssertEqual(s.weight, 40)
        var only = options
        only.acceptedSteps = [.oneSide]
        XCTAssertEqual(WeightSuggestion.next(history: [set(1, 40, 12)], reps: upper, kit: dumbbells, options: only).kind,
                       .nextStep(.oneSide))
    }

    func testTooBigAJumpBacksOff() {
        let s = WeightSuggestion.next(history: [set(1, 20, 12), set(8, 25, 5)], reps: upper, kit: dumbbells, options: options)
        XCTAssertEqual(s.kind, .backOff)
        XCTAssertEqual(s.weight, 20)
    }

    func testStallRestsFirstThenResets() {
        XCTAssertEqual(WeightSuggestion.next(history: [set(1, 20, 9), set(8, 20, 10)], reps: upper, kit: dumbbells,
                                             options: options).kind, .keep)
        let stalled = WeightSuggestion.next(history: [set(1, 20, 10), set(8, 20, 10)], reps: upper, kit: dumbbells, options: options)
        XCTAssertEqual(stalled.kind, .stalled)
        let again = WeightSuggestion.next(history: [set(1, 20, 10), set(8, 20, 10), set(16, 20, 9)], reps: upper,
                                          kit: dumbbells, options: options)
        XCTAssertEqual(again.kind, .reset)
        XCTAssertEqual(again.weight, 15)   // 18 rounds down to a real dumbbell
        // A lighter weight starts the count again.
        XCTAssertEqual(WeightSuggestion.next(history: [set(1, 25, 8), set(8, 20, 10), set(16, 20, 10)], reps: upper,
                                             kit: dumbbells, options: options).kind, .stalled)
    }

    // MARK: Effort

    func testEffortBreakInThenShortOfFailureUntilC25KEnds() {
        XCTAssertEqual(LiftEffort.on(day(1), firstSession: nil, c25kFinished: false, options: options, calendar: cal), .breakIn)
        XCTAssertEqual(LiftEffort.on(day(10), firstSession: day(1), c25kFinished: false, options: options, calendar: cal), .breakIn)
        XCTAssertEqual(LiftEffort.on(day(16), firstSession: day(1), c25kFinished: false, options: options, calendar: cal), .shortOfFailure)
        XCTAssertEqual(LiftEffort.on(day(16), firstSession: day(1), c25kFinished: true, options: options, calendar: cal), .toFailure)
    }

    // MARK: Schedule (D94)

    private func plan(last: [HeavyDuty.Workout: Date] = [:], nextRun: Date?, ranToday: Bool = false,
                      holds: [String] = []) -> HeavyDutyPlan {
        HeavyDutyPlan(options: options, last: last, firstSession: last.values.min(), nextRun: nextRun,
                      ranToday: ranToday, c25kFinished: false, legHolds: holds)
    }

    func testTheSharedWeek() {
        // Day 1 run (the 2nd), next run the 4th: Upper on the 3rd, not Legs (run tomorrow).
        XCTAssertEqual(plan(nextRun: day(4)).due(now: day(3), calendar: cal), .upper)
        // On a run day, nothing (Upper isn't overdue).
        XCTAssertNil(plan(last: [.upper: day(3)], nextRun: day(4)).due(now: day(4), calendar: cal))
        // The day after Day 3 (next run two days away): Legs.
        XCTAssertEqual(plan(last: [.upper: day(3)], nextRun: day(9)).due(now: day(7), calendar: cal), .legs)
        // The day after Legs: rest for both.
        XCTAssertNil(plan(last: [.upper: day(3), .legs: day(7)], nextRun: day(9)).due(now: day(8), calendar: cal))
        // A week on, Upper again.
        XCTAssertEqual(plan(last: [.upper: day(3), .legs: day(7)], nextRun: day(11)).due(now: day(10), calendar: cal), .upper)
    }

    func testLegsWaitForAPainHoldAndPlanReportsIt() {
        let held = plan(nextRun: day(9), holds: ["Shins: checks first"])
        XCTAssertEqual(held.due(now: day(7), calendar: cal), .upper)
        let today = plan(last: [.upper: day(7)], nextRun: day(9), holds: ["Shins: checks first"]).today(now: day(9), calendar: cal)
        XCTAssertEqual(today.status, .rest)
        let done = plan(last: [.upper: day(7, hour: 8)], nextRun: day(9)).today(now: day(7, hour: 18), calendar: cal)
        XCTAssertEqual(done.status, .done)
    }
}
