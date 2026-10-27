import XCTest
@testable import TrainerKit

final class C25KTests: XCTestCase {
    func testAllTwentySevenSessionsExist() {
        XCTAssertEqual(C25K.all.count, 27)
        XCTAssertNil(C25K.session(week: 10, day: 1))
        XCTAssertNil(C25K.session(week: 1, day: 4))
    }

    func testWeekTwoDayOneMatchesTheClassicPlan() throws {
        let s = try XCTUnwrap(C25K.session(week: 2, day: 1))
        XCTAssertEqual(s.segments.first, Segment(.warmUp, 300))
        XCTAssertEqual(s.segments.last, Segment(.coolDown, 300))
        let middle = Array(s.segments.dropFirst().dropLast())
        XCTAssertEqual(middle.count, 12)
        XCTAssertEqual(s.runCount, 6)
        XCTAssertTrue(middle.enumerated().allSatisfy { i, seg in
            i.isMultiple(of: 2) ? seg == Segment(.run, 90) : seg == Segment(.walk, 120)
        })
        XCTAssertEqual(s.totalSeconds, 300 + 6 * 210 + 300)
    }

    func testWeekNineIsThirtyMinutesOfRunning() throws {
        let s = try XCTUnwrap(C25K.session(week: 9, day: 3))
        XCTAssertEqual(s.segments.filter { $0.kind.isRun }.map(\.seconds), [1800])
    }

    func testSegmentIndexAtBoundaries() throws {
        let s = try XCTUnwrap(C25K.session(week: 2, day: 1))
        XCTAssertEqual(s.segmentIndex(at: 0), 0)
        XCTAssertEqual(s.segmentIndex(at: 299.9), 0)
        XCTAssertEqual(s.segmentIndex(at: 300), 1)
        XCTAssertEqual(s.segmentIndex(at: 390), 2)
        XCTAssertNil(s.segmentIndex(at: Double(s.totalSeconds)))
    }
}

final class CueTimelineTests: XCTestCase {
    func testWeekTwoCues() throws {
        let s = try XCTUnwrap(C25K.session(week: 2, day: 1))
        let cues = CueTimeline.cues(for: s)
        XCTAssertEqual(cues.first?.text, "Week 2, day 1. Warm up with a brisk walk for 5 minutes.")
        XCTAssertTrue(cues.contains(Cue(at: 300, text: "Run 1 of 6. Run for 90 seconds.", priority: .transition)))
        XCTAssertTrue(cues.contains { $0.text == "Last run! Run for 90 seconds." })
        XCTAssertTrue(cues.contains(Cue(at: 390, text: "Walk for 2 minutes.", priority: .transition)))
        XCTAssertTrue(cues.contains(Cue(at: 360, text: "30 seconds left.", priority: .status)))
        XCTAssertEqual(cues.last?.at, Double(s.totalSeconds))
        XCTAssertTrue(cues.last?.text.hasPrefix("Workout complete") ?? false)
        // Sorted, and one countdown before each of the 13 changes.
        XCTAssertEqual(cues.map(\.at), cues.map(\.at).sorted())
        XCTAssertEqual(cues.filter { $0.text == "3. 2. 1." }.count, s.segments.count - 1)
    }

    func testCountdownIsBeepsEndingOnTheChange() throws {
        let s = try XCTUnwrap(C25K.session(week: 2, day: 1))
        let countdowns = CueTimeline.cues(for: s).filter { $0.kind == .countdown }
        XCTAssertEqual(countdowns.count, s.segments.count - 1)
        // The long beep lands exactly on each segment change.
        XCTAssertEqual(countdowns.map { $0.at + CueTimeline.countdownLead },
                       s.segmentStarts.dropFirst().map(Double.init))
        XCTAssertTrue(CueTimeline.cues(for: s).filter { $0.text != "3. 2. 1." }.allSatisfy { $0.kind == .speech })
    }

    func testRehearsalCues() {
        let cues = CueTimeline.cues(for: C25K.rehearsal)
        XCTAssertEqual(cues.first?.text, "Test session. Warm up with a brisk walk for 30 seconds.")
        XCTAssertEqual(cues.last?.text, "Test complete.")
        XCTAssertEqual(cues.filter { $0.text == "3. 2. 1." }.count, 3)
    }

    func testSpokenDurations() {
        XCTAssertEqual(CueTimeline.spokenDuration(60), "1 minute")
        XCTAssertEqual(CueTimeline.spokenDuration(90), "90 seconds")
        XCTAssertEqual(CueTimeline.spokenDuration(120), "2 minutes")
        XCTAssertEqual(CueTimeline.spokenDuration(150), "2 and a half minutes")
        XCTAssertEqual(CueTimeline.spokenDuration(1800), "30 minutes")
    }

    func testSingleRunSessionHasNoRunNumbering() throws {
        let cues = CueTimeline.cues(for: try XCTUnwrap(C25K.session(week: 7, day: 1)))
        XCTAssertTrue(cues.contains { $0.text == "Run for 25 minutes. Steady and easy." })
        XCTAssertTrue(cues.contains { $0.text == "One minute left." })
    }
}

final class HeartRateGuardTests: XCTestCase {
    let guardRule = HeartRateGuard()

    func testSlowDownWhenAboveCeilingWhileRunning() {
        XCTAssertNotNil(guardRule.correction(segment: .run, zone: 5, secondsIntoSegment: 30,
                                             secondsSinceLastCorrection: nil))
        XCTAssertNil(guardRule.correction(segment: .run, zone: 4, secondsIntoSegment: 30,
                                          secondsSinceLastCorrection: nil))
    }

    func testCooldownAndSettleTime() {
        XCTAssertNil(guardRule.correction(segment: .run, zone: 5, secondsIntoSegment: 30,
                                          secondsSinceLastCorrection: 20))
        XCTAssertNil(guardRule.correction(segment: .run, zone: 5, secondsIntoSegment: 5,
                                          secondsSinceLastCorrection: nil))
        XCTAssertNil(guardRule.correction(segment: .run, zone: nil, secondsIntoSegment: 30,
                                          secondsSinceLastCorrection: nil))
    }

    func testWalkRecoveryOnlyAfterGrace() {
        XCTAssertNil(guardRule.correction(segment: .walk, zone: 4, secondsIntoSegment: 30,
                                          secondsSinceLastCorrection: nil))
        XCTAssertNotNil(guardRule.correction(segment: .walk, zone: 4, secondsIntoSegment: 70,
                                             secondsSinceLastCorrection: nil))
        XCTAssertNil(guardRule.correction(segment: .warmUp, zone: 5, secondsIntoSegment: 120,
                                          secondsSinceLastCorrection: nil))
    }
}

final class RestDayTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testRhythmFollowsTheLastRun() {
        XCTAssertEqual(TrainingDay.on(date(27, 9), lastRun: nil, calendar: calendar), .runDay)
        // Ran Sunday the 26th at 7 am: Monday is a rest day, the next run is due Tuesday.
        XCTAssertEqual(TrainingDay.on(date(27, 9), lastRun: date(26, 7), calendar: calendar),
                       .restDay(nextRunFrom: calendar.startOfDay(for: date(28, 0))))
        XCTAssertEqual(TrainingDay.on(date(26, 21), lastRun: date(26, 7), calendar: calendar),
                       .ranToday(nextRunFrom: calendar.startOfDay(for: date(28, 0))))
        XCTAssertEqual(TrainingDay.on(date(29, 6), lastRun: date(26, 7), calendar: calendar), .runDay)
        // A late-evening run still makes the next calendar day a rest day.
        XCTAssertEqual(TrainingDay.on(date(27, 6), lastRun: date(26, 23), calendar: calendar),
                       .restDay(nextRunFrom: calendar.startOfDay(for: date(28, 0))))
    }

    func testAdviceBands() {
        XCTAssertEqual(RestAdvice.forCharge(20).band, .low)
        XCTAssertEqual(RestAdvice.forCharge(33.9).band, .low)
        XCTAssertEqual(RestAdvice.forCharge(34).band, .moderate)
        XCTAssertEqual(RestAdvice.forCharge(67).band, .high)
        XCTAssertEqual(RestAdvice.forCharge(nil).band, .unknown)
        XCTAssertNotNil(RestAdvice.runDayNote(forCharge: 25))
        XCTAssertNil(RestAdvice.runDayNote(forCharge: 50))
        XCTAssertNil(RestAdvice.runDayNote(forCharge: nil))
    }
}

final class PainCheckTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func state(_ entries: [PainEntry], _ now: Date) -> PainState {
        PainState(entries: entries, now: now, calendar: calendar)
    }

    func testReportThenMorningChecks() {
        let report = PainEntry(area: .feet, date: at(27, 12), kind: .report(.mild))
        // Same day: active, no check yet, no hold.
        var s = state([report], at(27, 20))
        XCTAssertEqual(s.active, [.feet])
        XCTAssertEqual(s.needsCheck, [])
        XCTAssertFalse(s.isOnHold)
        // Next morning: a check is due, and skipping it doesn't hold.
        s = state([report], at(28, 7))
        XCTAssertEqual(s.needsCheck, [.feet])
        XCTAssertFalse(s.isOnHold)
        // "Same" holds today only...
        let same = PainEntry(area: .feet, date: at(28, 7), kind: .trend(.same))
        s = state([report, same], at(28, 9))
        XCTAssertTrue(s.isOnHold)
        XCTAssertEqual(s.holds.first?.reason, "Feet: same as yesterday")
        XCTAssertFalse(s.showRedFlags)
        // ...and the next morning asks again rather than holding on yesterday's answer.
        s = state([report, same], at(29, 7))
        XCTAssertFalse(s.isOnHold)
        XCTAssertEqual(s.needsCheck, [.feet])
        // "Less" lifts it but keeps checking; "gone" ends it.
        let less = PainEntry(area: .feet, date: at(29, 7), kind: .trend(.less))
        s = state([report, same, less], at(29, 8))
        XCTAssertFalse(s.isOnHold)
        XCTAssertEqual(s.active, [.feet])
        let gone = PainEntry(area: .feet, date: at(30, 7), kind: .trend(.gone))
        s = state([report, same, less, gone], at(30, 8))
        XCTAssertEqual(s.active, [])
        XCTAssertNil(s.summary(.feet))
    }

    func testWorseAndSharpRaiseRedFlags() {
        let report = PainEntry(area: .shins, date: at(26, 9), kind: .report(.mild))
        let worse = PainEntry(area: .shins, date: at(27, 7), kind: .trend(.worse))
        let s = state([report, worse], at(27, 8))
        XCTAssertTrue(s.isOnHold)
        XCTAssertTrue(s.showRedFlags)
        XCTAssertTrue(s.suggestRepeatingWeek)
        // A sharp report holds until a later morning says gone or less, even on following days.
        let sharp = PainEntry(area: .knees, date: at(27, 18), kind: .report(.sharp))
        let later = state([sharp], at(29, 8))
        XCTAssertTrue(later.isOnHold)
        XCTAssertTrue(later.showRedFlags)
        XCTAssertEqual(later.needsCheck, [.knees])
        XCTAssertFalse(state([sharp, PainEntry(area: .knees, date: at(29, 8), kind: .trend(.less))], at(29, 9)).isOnHold)
    }

    func testEntriesRoundTripAsJSON() throws {
        let entries = [PainEntry(area: .feet, date: at(27, 12), kind: .report(.worsening)),
                       PainEntry(area: .feet, date: at(28, 7), kind: .trend(.less))]
        let decoded = try JSONDecoder().decode([PainEntry].self, from: JSONEncoder().encode(entries))
        XCTAssertEqual(decoded, entries)
    }
}
