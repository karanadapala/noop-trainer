import Combine
import Foundation
import TrainerKit
import WhoopStore

/// Heavy Duty in the app (D65, D81): its settings under `trainer.heavyduty.*`, and its history read back
/// from the Lift Log, which is where every set is stored (in kg). A session is the Lift Log's own
/// session screen, started with Heavy Duty's exercises and today's suggested weights.
@MainActor
final class HeavyDutyStore: ObservableObject {
    static let shared = HeavyDutyStore()

    /// Name prefix of the Lift Log sessions Heavy Duty starts; how its history is found again.
    static let sessionPrefix = "\(HeavyDuty.title) · "

    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) } }
    @Published var placeID: String { didSet { UserDefaults.standard.set(placeID, forKey: Self.placeKey) } }
    @Published var options: HeavyDutyOptions { didSet { Self.save(options, Self.optionsKey) } }
    /// When each workout was last done, and the first session ever (the break-in clock). Kept so the
    /// Regimen is right before the Lift Log has been read.
    @Published private(set) var last: [HeavyDuty.Workout: Date] { didSet { Self.save(last, Self.lastKey) } }
    @Published private(set) var firstSession: Date? { didSet { UserDefaults.standard.set(firstSession, forKey: Self.firstKey) } }
    /// "Not lifting today", by date.
    @Published private(set) var skipped: Date? { didSet { UserDefaults.standard.set(skipped, forKey: Self.skippedKey) } }
    /// Each exercise's working sets, oldest first, one per session, weights in kg.
    @Published private(set) var history: [String: [LiftResult]] = [:]

    private static let enabledKey = "trainer.heavyduty.enabled"
    private static let placeKey = "trainer.heavyduty.place"
    private static let optionsKey = "trainer.heavyduty.options"
    private static let lastKey = "trainer.heavyduty.last"
    private static let firstKey = "trainer.heavyduty.first"
    private static let skippedKey = "trainer.heavyduty.skipped"

    private init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: Self.enabledKey)
        placeID = d.string(forKey: Self.placeKey) ?? "gym"
        options = Self.decode(HeavyDutyOptions.self, Self.optionsKey) ?? HeavyDutyOptions()
        last = Self.decode([HeavyDuty.Workout: Date].self, Self.lastKey) ?? [:]
        firstSession = d.object(forKey: Self.firstKey) as? Date
        skipped = d.object(forKey: Self.skippedKey) as? Date
    }

    var skippedToday: Bool { skipped.map(Calendar.current.isDateInToday) ?? false }

    func skipToday() { skipped = Date() }

    func undoSkip() { skipped = nil }

    // MARK: The plan

    func plan(runner: C25KRunner, now: Date = Date()) -> HeavyDutyPlan {
        let c25k = runner.plan
        let finished = c25k.nextSession == nil
        var nextRun: Date?
        var ranToday = false
        if !finished {
            switch TrainingDay.on(now, lastRun: runner.lastRunDate, lastRunDay: runner.lastRunDay) {
            // A run on hold isn't today's; it could come back tomorrow, so legs still wait.
            case .runDay: nextRun = runner.holdReasons.isEmpty ? now : Calendar.current.date(byAdding: .day, value: 1, to: now)
            case .ranToday(let from): ranToday = true; nextRun = from
            case .restDay(let from): nextRun = from
            }
        }
        return HeavyDutyPlan(options: options, last: last, firstSession: firstSession, nextRun: nextRun,
                             ranToday: ranToday, c25kFinished: finished,
                             legHolds: runner.painState.holds.map(\.reason), skipped: skipped,
                             liftHolds: runner.painState.holds.filter { $0.area == .back }.map(\.reason))
    }

    /// Today's workout for the plans that fit around lifting (Back care, Mobility): done today, or due.
    func liftToday(runner: C25KRunner, now: Date = Date()) -> (workout: HeavyDuty.Workout?, done: Bool) {
        guard enabled else { return (nil, false) }
        if let w = last.first(where: { Calendar.current.isDate($0.value, inSameDayAs: now) })?.key { return (w, true) }
        return (plan(runner: runner, now: now).due(now: now), false)
    }

    func place(_ regimen: RegimenStore) -> Place? { regimen.place(id: placeID) ?? regimen.places.first }

    /// Today's weight for one exercise at a place, in the place's unit.
    func suggestion(_ exercise: HeavyDuty.Exercise, at place: Place?) -> WeightSuggestion {
        let unit = place?.unit ?? .kg
        let inUnit = (history[exercise.name] ?? []).map {
            LiftResult(date: $0.date, weight: $0.weight.map { Self.fromKg($0, unit) }, reps: $0.reps)
        }
        return WeightSuggestion.next(history: inUnit, reps: options.reps(exercise.workout),
                                     kit: place?.equipment(exercise.kit), options: options)
    }

    // MARK: Starting a session

    /// Hands the workout to the Lift Log's session screen. False when another session is running (it's
    /// brought up instead) or nothing in the workout fits the place.
    @discardableResult
    func start(_ workout: HeavyDuty.Workout, at place: Place?, runner: C25KRunner, session: LiftSessionController) -> Bool {
        guard !session.isActive else {
            session.isPresented = true
            return false
        }
        let unit = place?.unit ?? .kg
        let effort = LiftEffort.on(Date(), firstSession: firstSession, c25kFinished: runner.plan.nextSession == nil,
                                   options: options)
        let list = HeavyDuty.exercises(workout, c25kFinished: runner.plan.nextSession == nil)
            .filter { place?.has($0.kit) ?? true }
        guard !list.isEmpty else { return false }
        let items = list.map { ex -> LiftPlanItem in
            let s = suggestion(ex, at: place)
            let muscles = ex.muscles.compactMap(LiftMuscle.init(rawValue:))
            let pairsOn = ex.straightInto != nil
            return LiftPlanItem(exercise: ex.name,
                                primaryMuscle: muscles.first,
                                secondaryMuscles: Array(muscles.dropFirst()),
                                targetSets: 1,
                                restSec: pairsOn ? 0 : LiftPlanItem.defaultRestSec,
                                targetRepsLow: s.reps.low,
                                targetRepsHigh: s.reps.high,
                                targetWeightKg: s.weight.map { Self.toKg($0, unit) },
                                note: Self.note(ex, s, effort),
                                weightSuggested: s.weight != nil,
                                endTaps: ex.stopTap.map { [LiftEndTap(label: $0.label, noReps: $0 == .couldntLift)] } ?? [])
        }
        session.start(plan: items, programId: nil, programName: Self.sessionPrefix + workout.title,
                      unit: unit == .lb ? .imperial : .metric)
        return true
    }

    /// The line under each exercise in the session: today's weight advice, the effort, the cue, tempo.
    static func note(_ ex: HeavyDuty.Exercise, _ s: WeightSuggestion, _ effort: LiftEffort) -> String {
        var parts = [s.note, effort.label + ".", "2 s up, 1 s hold, 3 s down.", ex.cue]
        if let next = ex.straightInto.flatMap({ id in HeavyDuty.exercises.first { $0.id == id } }) {
            parts.append("Straight into the \(next.name.lowercased()), no rest.")
        }
        if ex.stopTap == .formBroke { parts.append("If your form breaks, the set ends there.") }
        if ex.stopTap == .couldntLift { parts.append("If it won't move, that's the set.") }
        return parts.joined(separator: " ")
    }

    // MARK: History from the Lift Log

    /// Reads Heavy Duty's sessions back from the Lift Log: the last date of each workout, the first
    /// session, and each exercise's best working set per session.
    func refresh(repo: Repository) async {
        guard let store = await repo.storeHandle() else { return }
        let now = Int(Date().timeIntervalSince1970)
        let sessions = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: 0, toTs: now)) ?? [])
            .filter { $0.programName?.hasPrefix(Self.sessionPrefix) == true }
            .sorted { $0.startTs < $1.startTs }
        var lastDates: [HeavyDuty.Workout: Date] = [:]
        var results: [String: [LiftResult]] = [:]
        for s in sessions {
            let date = Date(timeIntervalSince1970: TimeInterval(s.startTs))
            if let w = HeavyDuty.Workout.allCases.first(where: { s.programName == Self.sessionPrefix + $0.title }) {
                lastDates[w] = date
            }
            let didNotMove = HeavyDuty.StopTap.couldntLift.label
            let sets = ((try? await store.liftSets(sessionId: s.id)) ?? [])
                .filter { !$0.isWarmup && (($0.reps ?? 0) > 0 || $0.note == didNotMove) }
            for (name, group) in Dictionary(grouping: sets, by: \.exercise) {
                let moved = group.filter { ($0.reps ?? 0) > 0 }
                if let best = moved.max(by: { ($0.weightKg ?? 0, $0.reps ?? 0) < ($1.weightKg ?? 0, $1.reps ?? 0) }) {
                    results[name, default: []].append(LiftResult(date: date, weight: best.weightKg, reps: best.reps ?? 0))
                } else if let stuck = group.first {
                    results[name, default: []].append(LiftResult(date: date, weight: stuck.weightKg, reps: 0, didNotMove: true))
                }
            }
        }
        history = results
        last = lastDates
        firstSession = sessions.first.map { Date(timeIntervalSince1970: TimeInterval($0.startTs)) }
    }

    // MARK: Units and storage

    static func fromKg(_ kg: Double, _ unit: WeightUnit) -> Double {
        unit == .lb ? kg * UnitFormatter.poundsPerKilogram : kg
    }

    static func toKg(_ value: Double, _ unit: WeightUnit) -> Double {
        unit == .lb ? value / UnitFormatter.poundsPerKilogram : value
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Every active plan, the main goal's first (D86): C25K, then the ones you've added.
@MainActor
enum ActivePlans {
    static func all(runner: C25KRunner = .shared, heavyDuty: HeavyDutyStore = .shared,
                    backCare: BackCareStore = .shared) -> [any TrainingPlan] {
        var plans: [any TrainingPlan] = [runner.plan]
        if heavyDuty.enabled { plans.append(heavyDuty.plan(runner: runner)) }
        if backCare.enabled { plans.append(backCare.plan(heavyDuty: heavyDuty, runner: runner)) }
        if MobilityStore.shared.enabled { plans.append(MobilityStore.shared.plan(heavyDuty: heavyDuty, runner: runner)) }
        return plans
    }
}
