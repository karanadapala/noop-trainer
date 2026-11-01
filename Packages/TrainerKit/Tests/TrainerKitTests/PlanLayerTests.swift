import XCTest
@testable import TrainerKit

final class PlanLayerTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ d: Int, hour: Int = 8) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    private func c25k(done: [String], lastRun: Date? = nil, lastRunDay: Int? = nil, holds: [String] = []) -> C25KPlan {
        C25KPlan(completed: Set(done), lastRun: lastRun, lastRunDay: lastRunDay, holdReasons: holds)
    }

    // MARK: C25K adapter

    func testC25KOffersTheNextSessionOnARunDay() {
        let today = c25k(done: ["w1d1", "w1d2", "w1d3", "w2d1"], lastRun: day(1), lastRunDay: 1).today(now: day(3), calendar: cal)
        XCTAssertEqual(today.status, .session)
        XCTAssertEqual(today.headline, "Week 2 · Day 2")
        XCTAssertEqual(today.detail, "31 min · 6 runs of 90 seconds")
        XCTAssertEqual(today.works, [.legs])
    }

    func testC25KFollowsTheRestRhythm() {
        let plan = c25k(done: ["w1d1", "w1d2", "w1d3"], lastRun: day(1), lastRunDay: 3)
        XCTAssertEqual(plan.today(now: day(1, hour: 18), calendar: cal).status, .done)
        XCTAssertEqual(plan.today(now: day(2), calendar: cal).status, .rest)
        XCTAssertEqual(plan.today(now: day(3), calendar: cal).status, .rest, "two rest days after Day 3")
        XCTAssertEqual(plan.today(now: day(4), calendar: cal).status, .session)
    }

    func testC25KHoldsWithTheRunnersReasons() {
        let today = c25k(done: ["w1d1"], lastRun: day(1), lastRunDay: 1, holds: ["Shins: same as yesterday"])
            .today(now: day(5), calendar: cal)
        XCTAssertEqual(today.status, .hold)
        XCTAssertEqual(today.detail, "Shins: same as yesterday")
    }

    func testC25KFinished() {
        let all = C25K.all.map(\.id)
        XCTAssertEqual(c25k(done: all).today(now: day(1), calendar: cal).status, .finished)
    }

    func testSummaries() throws {
        XCTAssertEqual(C25KPlan.summary(try XCTUnwrap(C25K.session(week: 1, day: 1))), "30 min · 8 runs of 1 minute")
        XCTAssertEqual(C25KPlan.summary(try XCTUnwrap(C25K.session(week: 5, day: 3))), "30 min · one 20 minutes run")
        XCTAssertEqual(C25KPlan.summary(try XCTUnwrap(C25K.session(week: 3, day: 1))), "28 min · 4 runs, longest 3 minutes")
    }

    // MARK: Regimen

    private struct Fixed: TrainingPlan {
        let id: String
        let status: PlanToday.Status
        var title: String { id }
        var goals: [Goal] { [.strength] }
        var schedule: PlanSchedule { .rotation(minRestDays: 2, maxGapDays: 10) }
        func today(now: Date, calendar: Calendar) -> PlanToday {
            PlanToday(planID: id, status: status, headline: id, detail: "")
        }
    }

    func testRegimenOffersTheFirstSessionNotOnHold() {
        let r = RegimenDay(plans: [Fixed(id: "a", status: .hold), Fixed(id: "b", status: .session)], now: day(1), calendar: cal)
        XCTAssertEqual(r.next?.planID, "b")
        XCTAssertFalse(r.allDone)
        let rest = RegimenDay(plans: [Fixed(id: "a", status: .rest), Fixed(id: "b", status: .done)], now: day(1), calendar: cal)
        XCTAssertNil(rest.next)
        XCTAssertTrue(rest.allDone)
    }

    // MARK: Places and the health profile

    func testEquipmentRoundsToWhatTheKitHas() {
        let dumbbells = Equipment(.dumbbells, lightest: 5, heaviest: 40, step: 5)
        XCTAssertEqual(dumbbells.rounded(23), 25)
        XCTAssertEqual(dumbbells.rounded(2), 5)
        XCTAssertEqual(dumbbells.rounded(55), 40)
        XCTAssertEqual(Equipment(.legPress).rounded(137.5), 137.5, "unknown steps leave the weight alone")
    }

    func testPresetsAndProfileRoundTrip() throws {
        XCTAssertEqual(Place.presets.map(\.id), ["gym", "home", "outdoors"])
        XCTAssertEqual(Place.presets[2].phone, .glance)
        let profile = HealthProfile(injuries: [
            Injury(region: .shins, side: .left, title: "Shin tightness", status: .active),
            Injury(region: .lowerBack, side: .left, title: "Disc bulges", since: "2019", status: .settled),
        ])
        let back = try JSONDecoder().decode(HealthProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(back, profile)
        XCTAssertEqual(profile.regions, [.shins, .lowerBack])
        XCTAssertFalse(RedFlags.for(.lowerBack).urgent.isEmpty)
    }

    // MARK: Correcting the pain log (D151)

    func testChangingAMorningAnswerRecomputesLaterTrends() throws {
        let log: [PainEntry] = [
            PainEntry(area: .shins, date: day(1), kind: .rating(4)),
            .morning(area: .shins, date: day(2), score: 3, previous: 4),   // a mis-tap: meant 2
            .morning(area: .shins, date: day(3), score: 2, previous: 3),
        ]
        XCTAssertEqual(log[2].kind, .trend(.less))
        let fixed = PainHistory.changing(log[1], to: 2, in: log)
        XCTAssertEqual(fixed[1].score, 2)
        XCTAssertEqual(fixed[1].kind, .trend(.less))
        XCTAssertEqual(fixed[2].kind, .trend(.same), "the next morning now compares against 2")
    }

    func testDeletingAnAnswerRecomputesAndLiftsTheHold() {
        let log: [PainEntry] = [
            PainEntry(area: .shins, date: day(1), kind: .rating(2)),
            .morning(area: .shins, date: day(2, hour: 7), score: 3, previous: 2),
        ]
        XCTAssertTrue(PainState(entries: log, now: day(2, hour: 9), calendar: cal).isOnHold)
        let fixed = PainHistory.deleting(log[1], from: log)
        XCTAssertEqual(fixed.count, 1)
        XCTAssertFalse(PainState(entries: fixed, now: day(2, hour: 9), calendar: cal).isOnHold)
    }

    func testRecomputeLeavesAnUneditedLogAlone() {
        let log: [PainEntry] = [
            PainEntry(area: .feet, date: day(1), kind: .report(.mild)),
            .morning(area: .feet, date: day(2), score: 2, previous: 2),
            PainEntry(area: .shins, date: day(2), kind: .spot),
            .morning(area: .shins, date: day(3), score: 3, previous: nil),
            .morning(area: .feet, date: day(3), score: 0, previous: 2),
        ]
        XCTAssertEqual(PainHistory.recomputed(log), log)
    }
}
