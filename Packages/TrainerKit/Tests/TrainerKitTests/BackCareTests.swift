import XCTest
@testable import TrainerKit

final class BackCareTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ d: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour, minute: minute))!
    }

    private func plan(log: [BackCareLog] = [], levels: [String: Stage] = [:], lastChange: Date? = nil,
                      lift: HeavyDuty.Workout? = nil, liftDone: Bool = false, wake: Date? = nil) -> BackCarePlan {
        BackCarePlan(options: BackCareOptions(), log: log, levels: levels, lastLevelChange: lastChange,
                     liftToday: lift, liftDone: liftDone, wake: wake)
    }

    func testBig3IsDescendingHoldsAndTheWarmUpIsTheFirstSet() {
        let a = BackCare.coreA(levels: [:])
        XCTAssertEqual(a.items.map(\.exercise.id), ["curlUp", "big3SidePlank", "birdDog"])
        XCTAssertEqual(a.items[0].dose.sets, 3)
        XCTAssertEqual(a.items[0].dose.work(forSet: 1), .heldReps(4, holdSeconds: 8))
        XCTAssertEqual(a.items[0].dose.work(forSet: 3), .heldReps(2, holdSeconds: 8))
        XCTAssertTrue((6...11).contains(a.estimatedMinutes), "\(a.estimatedMinutes)")
        let warm = BackCare.coreA(levels: [:], warmUp: true)
        XCTAssertTrue(warm.items.allSatisfy { $0.dose.sets == 1 })
        XCTAssertEqual(warm.items[0].dose.work(forSet: 1), .heldReps(4, holdSeconds: 8))
        // The timeline speaks each descending set's own count and rests 12 s between them.
        let t = RoutineTimeline(a)
        XCTAssertTrue(t.cues.contains { $0.text == "Set 2 of 3. 3 holds of 8 seconds." })
        XCTAssertTrue(t.cues.contains { $0.text == "Rest 12 seconds." })
        XCTAssertTrue(t.cues.first?.text.hasPrefix("The Big 3, about") == true)
    }

    func testCoreBDependsOnTheWorkout() {
        XCTAssertEqual(BackCare.coreB(levels: [:], workout: .upper).items.map(\.exercise.id), ["pallof", "suitcaseCarry"])
        XCTAssertEqual(BackCare.coreB(levels: [:], workout: .legs).items.map(\.exercise.id),
                       ["deadBug", "hingeDrill", "suitcaseCarry"])
    }

    func testTheDay() {
        XCTAssertEqual(plan().next(now: at(5, 18), calendar: cal), .coreA)
        XCTAssertEqual(plan(log: [BackCareLog(date: at(5, 9), session: .coreA)]).next(now: at(5, 18), calendar: cal), .done)
        // Lifting day: warm-up first, Core B after the lifts.
        XCTAssertEqual(plan(lift: .upper).next(now: at(5, 18), calendar: cal), .warmUp(.upper))
        XCTAssertEqual(plan(log: [BackCareLog(date: at(5, 17), session: .warmUp)], lift: .upper, liftDone: true)
                        .next(now: at(5, 19), calendar: cal), .coreB(.upper))
        XCTAssertEqual(plan(log: [BackCareLog(date: at(5, 17), session: .warmUp), BackCareLog(date: at(5, 19), session: .coreB)],
                            lift: .legs, liftDone: true).next(now: at(5, 20), calendar: cal), .done)
        // Not in the first hour after waking.
        XCTAssertEqual(plan(wake: at(5, 7)).next(now: at(5, 7, 30), calendar: cal), .later(at(5, 8)))
        XCTAssertEqual(plan(wake: at(5, 7)).next(now: at(5, 8, 1), calendar: cal), .coreA)
        XCTAssertEqual(plan(wake: at(5, 7)).today(now: at(5, 7, 30), calendar: cal).status, .rest)
    }

    func testAWeekOfEasyOffersTheNextLevelOneExerciseAtATime() {
        let easy = (1...5).map { BackCareLog(date: at($0 + 1, 18), session: .coreA, feel: .easy) }
        XCTAssertEqual(plan(log: easy).levelUpOffer(now: at(8, 9), calendar: cal)?.id, "curlUp")
        // Too soon: five easy sessions in three days.
        let quick = (0..<5).map { BackCareLog(date: at(2 + $0 / 2, 9 + $0), session: .coreA, feel: .easy) }
        XCTAssertNil(plan(log: quick).levelUpOffer(now: at(4, 20), calendar: cal))
        // One hard one: not yet.
        var mixed = easy
        mixed[2].feel = .hard
        XCTAssertNil(plan(log: mixed).levelUpOffer(now: at(8, 9), calendar: cal))
        // After the curl-up moved up, the next offer is the lowest-level one left, and counts start again.
        let levels: [String: Stage] = ["curlUp": .build]
        XCTAssertNil(plan(log: easy, levels: levels, lastChange: at(7, 0)).levelUpOffer(now: at(8, 9), calendar: cal))
        XCTAssertEqual(plan(log: easy, levels: levels).levelUpOffer(now: at(8, 9), calendar: cal)?.id, "big3SidePlank")
    }

    func testRestDayRoutineLeavesOutWhatBackCareCovers() {
        let input = RoutineBuilder.Input(charge: 80, legs: .fresh, pain: PainState(entries: [], now: at(5, 9)),
                                         restDayInARow: 2, programWeek: 4, rotation: 0,
                                         leaveOut: BackCare.replacesInRestDay)
        for r in 0..<6 {
            var i = input
            i.rotation = r
            XCTAssertFalse(RoutineBuilder.routine(for: i).items.contains { $0.exercise.id == "sidePlank" })
        }
    }
}
