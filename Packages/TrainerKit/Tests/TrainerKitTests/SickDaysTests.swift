import XCTest
@testable import TrainerKit

final class SickDaysTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ n: Int, hour: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: n, hour: hour))!
    }

    /// A plan that only says what the test needs; everything else is the interface's default.
    private struct Plan: TrainingPlan {
        var id = "x"
        var last: Date?
        var level: SessionIntensity?
        var floor = false
        var title: String { id }
        var goals: [Goal] { [] }
        var schedule: PlanSchedule { .rotation(minRestDays: 2, maxGapDays: 10) }
        var lastSession: Date? { last }
        var intensity: SessionIntensity { level ?? .hard }
        func today(now: Date, calendar: Calendar) -> PlanToday {
            PlanToday(planID: id, status: .session, headline: "Session", detail: "")
        }
        func sickFloor(now: Date, calendar: Calendar) -> PlanToday? {
            floor ? PlanToday(planID: id, status: .session, headline: "Floor", detail: "") : nil
        }
    }

    /// A plan that implements nothing beyond the required members.
    private struct Bare: TrainingPlan {
        var id: String { "bare" }
        var title: String { "Bare" }
        var goals: [Goal] { [] }
        var schedule: PlanSchedule { .fixedWeeks(weeks: 4, perWeek: 3) }
        func today(now: Date, calendar: Calendar) -> PlanToday {
            PlanToday(planID: id, status: .session, headline: "Session", detail: "")
        }
    }

    func testDaysMissedPicksTheBand() {
        let o = SickDayOptions()
        XCTAssertEqual(SickDays.step(daysMissed: 0, options: o), .carryOn)
        XCTAssertEqual(SickDays.step(daysMissed: 3, options: o), .carryOn)
        XCTAssertEqual(SickDays.step(daysMissed: 5, options: o), .repeatLast)
        XCTAssertEqual(SickDays.step(daysMissed: 14, options: o), .repeatBlock)
        XCTAssertEqual(SickDays.step(daysMissed: 20, options: o), .stepBack)
        XCTAssertEqual(SickDays.step(daysMissed: 90, options: o), .restart)

        var custom = SickDayOptions()
        custom.bands = [WayBackBand(upToDays: 10, step: .carryOn), WayBackBand(upToDays: nil, step: .repeatBlock)]
        XCTAssertEqual(SickDays.step(daysMissed: 9, options: custom), .carryOn)
        XCTAssertEqual(SickDays.step(daysMissed: 11, options: custom), .repeatBlock)
    }

    func testDaysMissedCountsPastTheUsualGapOrTheIllness() {
        let plan = Plan(last: day(1))
        XCTAssertEqual(plan.usualGapDays, 2)
        XCTAssertEqual(SickDays.daysMissed(plan: plan, episode: nil, now: day(9), calendar: cal), 6)
        let ill = SickEpisode(start: day(2), kind: .cold, end: day(10))
        XCTAssertEqual(SickDays.daysMissed(plan: plan, episode: ill, now: day(11), calendar: cal), 9, "9 days ill beats 8 past the gap")
        XCTAssertEqual(SickDays.daysMissed(plan: Plan(last: nil), episode: ill, now: day(11), calendar: cal), 0)
        // The default gap comes from the schedule: three a week is every 2 days.
        XCTAssertEqual(Bare().usualGapDays, 2)
    }

    func testFeverTypeComesBackGentleFirstAndHardLast() {
        let o = SickDayOptions()
        let cold = SickEpisode(start: day(3), kind: .cold, end: day(5))
        let c = SickDays.resumes(after: cold, options: o, calendar: cal)
        XCTAssertEqual(c[.gentle], cal.startOfDay(for: day(6)))
        XCTAssertEqual(c[.hard], cal.startOfDay(for: day(6)))

        let flu = SickEpisode(start: day(3), kind: .fever, end: day(5))
        let f = SickDays.resumes(after: flu, options: o, calendar: cal)
        XCTAssertEqual(f[.gentle], cal.startOfDay(for: day(7)))
        XCTAssertEqual(f[.moderate], cal.startOfDay(for: day(8)))
        XCTAssertEqual(f[.hard], cal.startOfDay(for: day(12)), "hard sessions wait 7 days after flu")

        let bug = SickEpisode(start: day(3), kind: .stomach, end: day(4))
        XCTAssertEqual(SickDays.resumes(after: bug, options: o, calendar: cal)[.hard], cal.startOfDay(for: day(7)),
                       "a 2-day stomach bug isn't a long illness: hard sessions come back after the easy days")
        XCTAssertTrue(SickDays.walkOnly(after: bug, options: o, now: day(5), calendar: cal))
        XCTAssertFalse(SickDays.walkOnly(after: bug, options: o, now: day(6), calendar: cal))
    }

    func testEveryPlanPausesWhileIllAndTheFloorIsOptIn() {
        let ill = SickEpisode(start: day(3), kind: .cold)
        let plans: [any TrainingPlan] = [Plan(id: "back", level: .gentle, floor: true), Plan(id: "run"), Bare()]
        let off = RegimenDay(plans: plans, now: day(4), calendar: cal,
                             illness: IllnessContext(episode: ill, options: SickDayOptions()))
        XCTAssertTrue(off.plans.allSatisfy { $0.status == .hold })
        XCTAssertNil(off.next)

        var o = SickDayOptions()
        o.floorOnColdDays = true
        let on = RegimenDay(plans: plans, now: day(4), calendar: cal, illness: IllnessContext(episode: ill, options: o))
        XCTAssertEqual(on.next?.planID, "back")
        XCTAssertEqual(on.plans.filter { $0.status == .hold }.map(\.planID), ["run", "bare"])
    }

    func testOnTheWayBackEachPlanWaitsForItsIntensity() {
        let flu = SickEpisode(start: day(3), kind: .fever, end: day(5))
        let ctx = IllnessContext(episode: flu, options: SickDayOptions())
        let plans: [any TrainingPlan] = [Plan(id: "back", level: .gentle), Plan(id: "run", level: .moderate), Bare()]
        let walkDay = RegimenDay(plans: plans, now: day(6), calendar: cal, illness: ctx)
        XCTAssertTrue(walkDay.plans.allSatisfy { $0.status == .hold })
        XCTAssertEqual(walkDay.plans.first?.detail, "Today is an easy walk only.")
        let next = RegimenDay(plans: plans, now: day(7), calendar: cal, illness: ctx)
        XCTAssertEqual(next.plans.map(\.status), [.session, .hold, .hold])
        let later = RegimenDay(plans: plans, now: day(12), calendar: cal, illness: ctx)
        XCTAssertEqual(later.plans.map(\.status), [.session, .session, .session], "a plan that says nothing counts as hard")
    }

    func testAnEasyDayHoldsAllButGentlePlans() {
        let plans: [any TrainingPlan] = [Plan(id: "back", level: .gentle), Plan(id: "run", level: .moderate), Bare()]
        let r = RegimenDay(plans: plans, now: day(4), calendar: cal, easyDay: true)
        XCTAssertEqual(r.plans.map(\.status), [.session, .hold, .hold])
        XCTAssertEqual(r.plans[1].headline, "Easy day")
    }

    func testRedFlagsAndEndingSickMode() {
        let o = SickDayOptions()
        var e = SickEpisode(start: day(1), kind: .fever)
        e.checks = [SickCheck(date: day(2), feel: .worse, fever: true), SickCheck(date: day(3), feel: .worse, fever: true)]
        XCTAssertTrue(SickDays.showRedFlags(e, options: o))
        e.checks = [SickCheck(date: day(2), feel: .worse, fever: true), SickCheck(date: day(3), feel: .better, fever: false),
                    SickCheck(date: day(4), feel: .better, fever: false)]
        XCTAssertFalse(SickDays.showRedFlags(e, options: o))
        XCTAssertTrue(SickDays.proposeEnd(e, restingHRNearUsual: nil, options: o))
        XCTAssertFalse(SickDays.proposeEnd(e, restingHRNearUsual: false, options: o), "resting HR still up")
        e.checks[2] = SickCheck(date: day(4), feel: .better, fever: true)
        XCTAssertFalse(SickDays.proposeEnd(e, restingHRNearUsual: true, options: o))
    }

    func testEachPlanSaysWhatTheWayBackMeans() {
        XCTAssertEqual(Bare().wayBack(.repeatBlock), "The last block again.")
        let c25k = C25KPlan(completed: ["w1d1", "w1d2", "w1d3", "w2d1"], lastRun: day(1), lastRunDay: 1, holdReasons: [])
        XCTAssertEqual(c25k.intensity, .moderate)
        XCTAssertEqual(c25k.wayBack(.restart), "Week 1 · Day 1 again.")
        let hd = HeavyDutyPlan(options: HeavyDutyOptions(), last: [.upper: day(1)], firstSession: day(1), nextRun: nil,
                               ranToday: false, c25kFinished: false)
        XCTAssertEqual(hd.wayBack(.repeatLast), "First session 10% lighter, 2 reps short of failure.")
        XCTAssertEqual(hd.lastSession, day(1))
    }

    func testStoredOptionsKeepWorkingWhenSettingsAreAdded() throws {
        let partial = Data(#"{"hardWaitDays": 5}"#.utf8)
        let o = try JSONDecoder().decode(SickDayOptions.self, from: partial)
        XCTAssertEqual(o.hardWaitDays, 5)
        XCTAssertEqual(o.bands, SickDayOptions().bands)
        XCTAssertFalse(o.floorOnColdDays)
    }
}
