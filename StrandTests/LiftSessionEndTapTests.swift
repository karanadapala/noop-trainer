import XCTest
@testable import Strand
import WhoopStore

/// A plan's end-of-set taps (Trainer: Heavy Duty's "Form broke", "Couldn't lift it"): the tap ends the
/// set being performed, becomes its note, and "didn't move" records it at its weight with 0 reps. Both
/// survive a relaunch; a session without taps encodes as before.
@MainActor
final class LiftSessionEndTapTests: XCTestCase {

    private let formBroke = LiftEndTap(label: "Form broke", noReps: false)
    private let stuck = LiftEndTap(label: "Couldn't lift it", noReps: true)

    override func tearDown() {
        LiftSessionPersistence.clear()
        super.tearDown()
    }

    private func controller() -> LiftSessionController {
        LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in })
    }

    func testATapEndsTheSetAndBecomesItsNote() throws {
        let c = controller()
        c.start(plan: [LiftPlanItem(exercise: "Leg press", targetSets: 1, targetRepsLow: 12, targetWeightKg: 100,
                                    weightSuggested: true, endTaps: [formBroke]),
                       LiftPlanItem(exercise: "Toe press", targetSets: 1)],
                programId: nil, programName: "Heavy Duty · Legs")
        let first = LiftSlot(exerciseIndex: 0, setIndex: 1)
        c.start(first)
        c.updateSet(first, weightKg: 100, reps: 9, rpe: nil, isWarmup: false)
        c.endSet(note: formBroke.label)
        XCTAssertEqual(c.setNotes[first], "Form broke")
        XCTAssertNotNil(c.engine?.recordedSet(for: first))
        XCTAssertEqual(c.values(of: first).reps, 9)
        // Survives a relaunch.
        let resumed = controller()
        resumed.resume(from: try XCTUnwrap(LiftSessionPersistence.load()))
        XCTAssertEqual(resumed.setNotes[first], "Form broke")
        XCTAssertEqual(resumed.engine?.plan.first?.endTaps, [formBroke])
        c.discard()
    }

    func testCouldntLiftItRecordsZeroRepsAtTheWeight() {
        let c = controller()
        c.start(plan: [LiftPlanItem(exercise: "Leg extension", targetSets: 1, targetRepsLow: 12, targetWeightKg: 60,
                                    weightSuggested: true, endTaps: [stuck])],
                programId: nil, programName: "Heavy Duty · Legs")
        let slot = LiftSlot(exerciseIndex: 0, setIndex: 1)
        c.start(slot)
        c.endSet(note: stuck.label, zeroReps: stuck.noReps)
        XCTAssertEqual(c.values(of: slot).reps, 0)
        XCTAssertEqual(c.values(of: slot).weightKg, 60)
        XCTAssertEqual(c.setNotes[slot], "Couldn't lift it")
        c.discard()
    }

    func testNoTapNoChange() throws {
        let engine = LiftSessionEngine(plan: [LiftPlanItem(exercise: "Bench press", targetWeightKg: 50)], startTs: 1_700_000_000)
        let json = String(decoding: try XCTUnwrap(LiftSessionPersistence.encode(LiftSessionPersistence.snapshot(
            engine: engine, programId: "p", programName: "Upper A", pendingValues: [:], pendingWarmups: []))), as: UTF8.self)
        XCTAssertFalse(json.contains("endTaps"))
        XCTAssertFalse(json.contains("setNotes"))
        // Outside a set, a tap does nothing.
        let c = controller()
        c.start(plan: [LiftPlanItem(exercise: "Bench press")], programId: nil, programName: nil)
        c.endSet(note: "Form broke")
        XCTAssertTrue(c.setNotes.isEmpty)
        c.discard()
    }
}
