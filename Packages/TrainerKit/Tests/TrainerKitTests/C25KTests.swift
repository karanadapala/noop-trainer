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

    func testTwoRestDaysAfterTheWeeksThirdRun() {
        // Week 1 Day 3 on Monday the 26th: Tuesday and Wednesday rest, the next run is due Thursday.
        let thursday = calendar.startOfDay(for: date(29, 0))
        XCTAssertEqual(TrainingDay.on(date(26, 21), lastRun: date(26, 7), lastRunDay: 3, calendar: calendar),
                       .ranToday(nextRunFrom: thursday))
        XCTAssertEqual(TrainingDay.on(date(27, 9), lastRun: date(26, 7), lastRunDay: 3, calendar: calendar),
                       .restDay(nextRunFrom: thursday))
        XCTAssertEqual(TrainingDay.on(date(28, 9), lastRun: date(26, 7), lastRunDay: 3, calendar: calendar),
                       .restDay(nextRunFrom: thursday))
        XCTAssertEqual(TrainingDay.on(date(29, 6), lastRun: date(26, 7), lastRunDay: 3, calendar: calendar), .runDay)
        // Days 1 and 2 keep the single rest day.
        XCTAssertEqual(TrainingDay.on(date(28, 9), lastRun: date(26, 7), lastRunDay: 2, calendar: calendar), .runDay)
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

final class RestRoutineTests: XCTestCase {
    let noPain = PainState(entries: [], now: Date())

    func input(charge: Double? = 80, legs: LegFeel = .fresh, pain: PainState? = nil, inARow: Int = 2,
               week: Int = 4, stages: [Block: Stage] = [:]) -> RoutineBuilder.Input {
        RoutineBuilder.Input(charge: charge, legs: legs, pain: pain ?? noPain, restDayInARow: inARow,
                             programWeek: week, stages: stages)
    }

    func testLegsLeadAndChargeOnlyNudgesDown() {
        XCTAssertEqual(RoutineBuilder.variant(for: input()), .build)
        XCTAssertEqual(RoutineBuilder.variant(for: input(legs: .usual)), .steady)
        XCTAssertEqual(RoutineBuilder.variant(for: input(legs: .limiting)), .restore)
        XCTAssertEqual(RoutineBuilder.variant(for: input(charge: 50)), .steady)
        XCTAssertEqual(RoutineBuilder.variant(for: input(charge: 20)), .restore)
        // A high score never lifts sore legs.
        XCTAssertEqual(RoutineBuilder.variant(for: input(charge: 95, legs: .limiting)), .restore)
        // No score: legs alone decide.
        XCTAssertEqual(RoutineBuilder.variant(for: input(charge: nil)), .build)
    }

    func testFirstRestDayAfterARunIsSteadyAtMost() {
        XCTAssertEqual(RoutineBuilder.variant(for: input(inARow: 1)), .steady)
    }

    func testHoldMeansProtectAndSoreAreasAreLeftOut() {
        let now = Date()
        let feet = [PainEntry(area: .feet, date: now.addingTimeInterval(-86_400), kind: .report(.mild)),
                    PainEntry(area: .feet, date: now, kind: .trend(.same))]
        let held = PainState(entries: feet, now: now)
        XCTAssertEqual(RoutineBuilder.variant(for: input(pain: held)), .protect)
        // Mild feet without a hold: still Build, but nothing that loads the feet.
        let mild = PainState(entries: [feet[0]], now: now.addingTimeInterval(-3_600))
        let r = RoutineBuilder.routine(for: input(pain: mild))
        XCTAssertEqual(r.variant, .build)
        XCTAssertFalse(r.items.contains { $0.exercise.loads.contains(.feet) })
        XCTAssertEqual(r.skippedAreas, [.feet])
        XCTAssertTrue(r.items.contains { $0.exercise.id == "bridge" })
    }

    func testLengthsMatchTheDesign() {
        let build = RoutineBuilder.routine(for: input(week: 4, stages: [.footBalance: .build, .lowerLeg: .build, .hipThigh: .build]))
        let steady = RoutineBuilder.routine(for: input(legs: .usual, week: 4))
        let restore = RoutineBuilder.routine(for: input(legs: .limiting, week: 4))
        XCTAssertTrue((12...21).contains(build.estimatedMinutes), "build \(build.estimatedMinutes)")
        XCTAssertTrue((10...16).contains(steady.estimatedMinutes), "steady \(steady.estimatedMinutes)")
        XCTAssertTrue((11...16).contains(restore.estimatedMinutes), "restore \(restore.estimatedMinutes)")
        // Full Strengthen stage still fits, and rotation brings up different exercises.
        let late = RoutineBuilder.Input(charge: 80, legs: .fresh, pain: noPain, restDayInARow: 2, programWeek: 8,
                                        stages: [.footBalance: .strengthen, .lowerLeg: .strengthen, .hipThigh: .strengthen])
        XCTAssertLessThanOrEqual(RoutineBuilder.routine(for: late).estimatedMinutes, 21)
        var next = late
        next.rotation = 1
        XCTAssertNotEqual(RoutineBuilder.routine(for: late).items.map(\.exercise.id),
                          RoutineBuilder.routine(for: next).items.map(\.exercise.id))
        XCTAssertFalse(restore.items.contains { $0.exercise.block == .lowerLeg || $0.exercise.block == .hipThigh })
        // Steady: walk, feet, one strength block; the optional stretch is the first thing trimmed.
        XCTAssertEqual(Array(steady.blocks.prefix(3)), [.walk, .footBalance, .lowerLeg])
    }

    func testEarlyWeeksUseAboutHalfTheSets() {
        let early = RoutineBuilder.routine(for: input(week: 2))
        let later = RoutineBuilder.routine(for: input(week: 3))
        let bridgeEarly = early.items.first { $0.exercise.id == "bridge" }!.dose.sets
        let bridgeLater = later.items.first { $0.exercise.id == "bridge" }!.dose.sets
        XCTAssertEqual(bridgeLater, 2)
        XCTAssertEqual(bridgeEarly, 1)
    }

    func testStagesFollowTheCalendar() {
        XCTAssertEqual(Stage.forWeek(1), .learn)
        XCTAssertEqual(Stage.forWeek(4), .build)
        XCTAssertEqual(Stage.forWeek(9), .strengthen)
        XCTAssertEqual(RestDayCatalogue.all.first { $0.id == "bentKneeCalf" }!.dose(.strengthen).variant,
                       "One leg on the stair edge, holding the dumbbells")
    }
}

final class RestDayProgressTests: XCTestCase {
    let day: TimeInterval = 86_400
    let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    func session(_ n: Int, _ stage: Stage, skipped: [String] = []) -> RestSessionLog {
        RestSessionLog(date: t0.addingTimeInterval(Double(n) * 2 * day), variant: .build,
                       stages: [.lowerLeg: stage], skipped: skipped,
                       done: ["bentKneeCalf", "tibRaise"].filter { !skipped.contains($0) })
    }

    func testMovesUpOnlyWhenCalendarAndTwoCleanSessionsAgree() {
        let two = [session(0, .learn), session(1, .learn)]
        XCTAssertEqual(RestDayProgress.stages(log: two, pain: [], programWeek: 3, repeatingWeek: false)[.lowerLeg], .learn)
        XCTAssertEqual(RestDayProgress.stages(log: two, pain: [], programWeek: 4, repeatingWeek: false)[.lowerLeg], .build)
        XCTAssertEqual(RestDayProgress.stages(log: two, pain: [], programWeek: 4, repeatingWeek: true)[.lowerLeg], .learn)
        // A skip in the block holds it.
        let skip = [session(0, .learn), session(1, .learn, skipped: ["tibRaise"])]
        XCTAssertEqual(RestDayProgress.stages(log: skip, pain: [], programWeek: 4, repeatingWeek: false)[.lowerLeg], .learn)
        // A pain report the day after holds it.
        let flag = PainEntry(area: .calves, date: two[1].date.addingTimeInterval(day / 2), kind: .report(.mild))
        XCTAssertEqual(RestDayProgress.stages(log: two, pain: [flag], programWeek: 4, repeatingWeek: false)[.lowerLeg], .learn)
        // One step at a time: Build needs two clean Build sessions before Strengthen.
        let built = two + [session(2, .build)]
        XCTAssertEqual(RestDayProgress.stages(log: built, pain: [], programWeek: 7, repeatingWeek: false)[.lowerLeg], .build)
        XCTAssertEqual(RestDayProgress.stages(log: built + [session(3, .build)], pain: [], programWeek: 7,
                                              repeatingWeek: false)[.lowerLeg], .strengthen)
        // Blocks never done start at Learn.
        XCTAssertEqual(RestDayProgress.stages(log: two, pain: [], programWeek: 7, repeatingWeek: false)[.hipThigh], .learn)
    }

    func testBenchmarkEveryThreeWeeks() {
        XCTAssertTrue(RestDayProgress.benchmarkDue([], now: t0))
        let b = [CalfBenchmark(date: t0, left: 18, right: 15)]
        XCTAssertFalse(RestDayProgress.benchmarkDue(b, now: t0.addingTimeInterval(20 * day)))
        XCTAssertTrue(RestDayProgress.benchmarkDue(b, now: t0.addingTimeInterval(21 * day)))
    }
}

final class RoutineTimelineTests: XCTestCase {
    func routine(legs: LegFeel = .usual) -> RestRoutine {
        RoutineBuilder.routine(for: .init(charge: 60, legs: legs, pain: PainState(entries: [], now: Date()),
                                          restDayInARow: 1, programWeek: 4,
                                          stages: [.footBalance: .build, .lowerLeg: .build]))
    }

    func testStepsAreContiguousAndCuesSorted() {
        let tl = RoutineTimeline(routine())
        XCTAssertEqual(tl.steps.first?.kind, .walk)
        for (a, b) in zip(tl.steps, tl.steps.dropFirst()) { XCTAssertEqual(a.end, b.start) }
        XCTAssertEqual(tl.cues.map(\.at), tl.cues.map(\.at).sorted())
        XCTAssertEqual(tl.cues.last?.text, "Routine complete. Nice work.")
        XCTAssertEqual(tl.cues.last?.at, Double(tl.totalSeconds))
        // The player's length matches the routine's estimate to within a few minutes.
        XCTAssertLessThan(abs(tl.totalSeconds / 60 - routine().estimatedMinutes), 4)
    }

    func testPerSideSetsAnnounceTheSideAndSwitch() throws {
        let tl = RoutineTimeline(routine())
        let calf = try XCTUnwrap(tl.steps.first { $0.exerciseID == "bentKneeCalf" && $0.kind == .work })
        XCTAssertTrue(calf.detail.contains("Left leg"), calf.detail)
        XCTAssertTrue(tl.cues.contains { $0.text == "Switch sides." })
        XCTAssertTrue(tl.cues.contains { $0.text == "Last one. Up." })
        XCTAssertTrue(tl.cues.contains { $0.text == "One. Up." })
        XCTAssertEqual(RoutineTimeline.spelled(12), "Twelve")
        XCTAssertTrue(tl.cues.contains { $0.text.hasPrefix("Next: Bent-knee calf raise.") })
    }

    func testSkipJumpsToTheNextExercise() throws {
        let tl = RoutineTimeline(routine())
        let first = try XCTUnwrap(tl.steps.first { $0.kind == .work })
        let next = tl.nextExerciseStart(after: first.start + 1)
        let landed = try XCTUnwrap(tl.steps.first { $0.start == next })
        XCTAssertEqual(landed.kind, .change)
        XCTAssertNotEqual(landed.exerciseID, first.exerciseID)
    }
}

final class RestCardExtrasTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    func day(_ d: Int, hour: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }

    func testSleepTipUsesLastNight() {
        XCTAssertTrue(RestTip.forRestDay(sleepMinutes: 370)[0].text.hasPrefix("You slept 6 h 10 min. Aim for 7 hours"))
        XCTAssertTrue(RestTip.forRestDay(sleepMinutes: 460)[0].text.contains("Keep that up"))
        XCTAssertTrue(RestTip.forRestDay(sleepMinutes: nil)[0].text.hasPrefix("Aim for 7 hours"))
        XCTAssertFalse(RestTip.forRestDay(sleepMinutes: nil).contains { $0.text.lowercased().contains("weight") })
    }

    func testRestDaysGoToTheLatestEarlierRun() {
        let runs = ["w1d3": day(26, hour: 7), "w1d2": day(24)]
        // Oct 25 follows w1d2; Oct 27 (twice the same day) follows w1d3; a routine on a run day doesn't count.
        let rest = [day(25), day(27), day(27, hour: 18), day(24, hour: 20)]
        XCTAssertEqual(RestDayProgress.restDaysAfterRuns(runs, restDates: rest, calendar: cal), ["w1d2": 1, "w1d3": 1])
    }

    func testRestartPicksTheCurrentOrJustFinishedWeek() throws {
        let w2d1 = try XCTUnwrap(C25K.session(week: 2, day: 1))
        let w2d2 = try XCTUnwrap(C25K.session(week: 2, day: 2))
        let w1d1 = try XCTUnwrap(C25K.session(week: 1, day: 1))
        // Week 1 done, nothing of week 2 yet: repeat week 1.
        XCTAssertEqual(WeekRestart.week(next: w2d1, allDone: false) { $0.week == 1 }, 1)
        // Week 2 started: restart week 2.
        XCTAssertEqual(WeekRestart.week(next: w2d2, allDone: false) { $0.week == 1 || $0 == w2d1 }, 2)
        XCTAssertNil(WeekRestart.week(next: w1d1, allDone: false) { _ in false })
        XCTAssertNil(WeekRestart.label(attempt: 1))
        XCTAssertEqual(WeekRestart.label(attempt: 2), "2nd time")
        XCTAssertEqual(WeekRestart.label(attempt: 3), "3rd time")
        XCTAssertEqual(WeekRestart.label(attempt: 11), "11th time")
    }
}
