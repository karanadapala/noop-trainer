import XCTest
@testable import Strand
import WhoopStore

/// A plan's suggested weight for today (Trainer: Heavy Duty) shows ahead of last session's weight, and a
/// session started in a place's unit keeps it through a relaunch. An ordinary target stays behind last
/// session, as before.
@MainActor
final class LiftSessionSuggestedWeightTests: XCTestCase {

    private let t0 = 1_700_000_000
    private let first = LiftSlot(exerciseIndex: 0, setIndex: 1)
    private let lastSession = [1: LiftSetCarry(weightKg: 20, reps: 12)]

    override func tearDown() {
        LiftSessionPersistence.clear()
        super.tearDown()
    }

    func testASuggestedWeightBeatsLastSession() {
        let suggested = LiftSessionEngine(plan: [LiftPlanItem(exercise: "Seated row", targetRepsLow: 8,
                                                              targetWeightKg: 22.5, weightSuggested: true)], startTs: t0)
        XCTAssertEqual(suggested.carry(for: first, lastSession: lastSession).weightKg, 22.5)
        // Reps still carry from last time.
        XCTAssertEqual(suggested.carry(for: first, lastSession: lastSession).reps, 12)

        let target = LiftSessionEngine(plan: [LiftPlanItem(exercise: "Seated row", targetRepsLow: 8,
                                                           targetWeightKg: 22.5)], startTs: t0)
        XCTAssertEqual(target.carry(for: first, lastSession: lastSession).weightKg, 20)
    }

    func testTheSuggestionAndThePlacesUnitSurviveARelaunch() throws {
        let c = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in })
        c.start(plan: [LiftPlanItem(exercise: "Seated row", targetWeightKg: 22.5, weightSuggested: true)],
                programId: nil, programName: "Heavy Duty · Upper", unit: .imperial)
        let snapshot = try XCTUnwrap(LiftSessionPersistence.load())
        let resumed = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in })
        resumed.resume(from: snapshot)
        XCTAssertEqual(resumed.unitOverride, .imperial)
        XCTAssertTrue(try XCTUnwrap(resumed.engine?.plan.first).weightSuggested)
        c.discard()
    }

    func testAnOrdinarySessionWritesNeitherField() throws {
        let engine = LiftSessionEngine(plan: [LiftPlanItem(exercise: "Bench press", targetWeightKg: 50)], startTs: t0)
        let data = try XCTUnwrap(LiftSessionPersistence.encode(LiftSessionPersistence.snapshot(
            engine: engine, programId: "p", programName: "Upper A", pendingValues: [:], pendingWarmups: [])))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("weightSuggested"))
        XCTAssertFalse(json.contains("unitSystem"))
    }
}
