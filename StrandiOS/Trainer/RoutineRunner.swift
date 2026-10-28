import Foundation
import TrainerKit
import UIKit

/// Plays a voice-guided rest-day routine (D39), separate from `C25KRunner` so the run engine stays
/// untouched. Like the runs, the timing is wall-clock based and every cue is pre-scheduled
/// (`RoutineTimeline`). A home routine records no workout, so the voice coach plays silence under the
/// cues to keep the app running with the phone locked; the screen can stay on as an option. After any
/// gap only the latest change is said.
@MainActor
final class RoutineRunner: ObservableObject {
    enum State: Equatable { case idle, running, paused, finished }

    static let shared = RoutineRunner()

    @Published private(set) var state: State = .idle
    @Published private(set) var routine: RestRoutine?
    @Published private(set) var timeline: RoutineTimeline?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var lastSpoken: String?
    @Published private(set) var sessions: [RestSessionLog]
    @Published private(set) var benchmarks: [CalfBenchmark]
    /// This morning's "how do your legs feel?" (D38), with the day it was given.
    @Published private(set) var legs: (feel: LegFeel, date: Date)?
    /// Off by default: the routine is voice-guided, so the phone can be locked.
    @Published var keepScreenOn: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenOn, forKey: Self.screenOnKey)
            if state == .running || state == .paused { UIApplication.shared.isIdleTimerDisabled = keepScreenOn }
        }
    }

    private let voice = VoiceCoach()
    private var nextCue = 0
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    /// Time jumped forward by Skip exercise.
    private var skippedTime: TimeInterval = 0
    private var skippedIDs: [String] = []
    private var timer: Timer?

    private static let tick: TimeInterval = 0.25
    private static let staleAfter: TimeInterval = 4
    private static let sessionsKey = "trainer.c25k.rest.sessions"
    private static let benchmarksKey = "trainer.c25k.rest.benchmarks"
    private static let legsKey = "trainer.c25k.rest.legs"
    private static let screenOnKey = "trainer.c25k.rest.screenOn"

    private init() {
        sessions = Self.load(Self.sessionsKey) ?? []
        benchmarks = Self.load(Self.benchmarksKey) ?? []
        keepScreenOn = UserDefaults.standard.bool(forKey: Self.screenOnKey)
        if let saved: LegsAnswer = Self.load(Self.legsKey) { legs = (saved.feel, saved.date) }
    }

    // MARK: Check-in and history

    var legsToday: LegFeel? {
        guard let legs, Calendar.current.isDateInToday(legs.date) else { return nil }
        return legs.feel
    }

    func setLegs(_ feel: LegFeel) {
        legs = (feel, Date())
        Self.save(LegsAnswer(feel: feel, date: Date()), Self.legsKey)
    }

    var doneToday: RestSessionLog? { sessions.last { Calendar.current.isDateInToday($0.date) } }

    /// The strength block in the latest routine that had one, so Steady days alternate.
    var lastStrengthBlock: Block? {
        for s in sessions.reversed() {
            if s.did(.lowerLeg) { return .lowerLeg }
            if s.did(.hipThigh) { return .hipThigh }
        }
        return nil
    }

    func addBenchmark(left: Int, right: Int) {
        benchmarks.append(CalfBenchmark(date: Date(), left: left, right: right))
        Self.save(benchmarks, Self.benchmarksKey)
    }

    // MARK: Control

    var currentStep: RoutineStep? {
        guard let timeline, let i = timeline.stepIndex(at: elapsed) else { return nil }
        return timeline.steps[i]
    }

    var stepRemaining: TimeInterval { currentStep.map { max(0, $0.end - elapsed) } ?? 0 }

    /// The rep being done right now in a work step (1-based), or nil outside reps.
    var currentRep: Int? {
        guard let step = currentStep, step.kind == .work, step.reps > 0 else { return nil }
        let into = elapsed - step.start - Double(RoutineTimeline.getReady)
        guard into >= 0 else { return nil }
        let perRep = Double(step.seconds - RoutineTimeline.getReady) / Double(step.reps)
        return min(step.reps, Int(into / perRep) + 1)
    }

    var exerciseCount: Int { routine?.items.count ?? 0 }

    var exerciseNumber: Int? {
        guard let id = currentStep?.exerciseID, let routine else { return nil }
        return routine.items.firstIndex { $0.exercise.id == id }.map { $0 + 1 }
    }

    /// Starts a routine unless a C25K run is going (one coach at a time).
    func start(_ routine: RestRoutine) -> Bool {
        guard state == .idle || state == .finished, C25KRunner.shared.state == .idle else { return false }
        self.routine = routine
        timeline = RoutineTimeline(routine)
        nextCue = 0
        startedAt = Date()
        pausedAt = nil
        pausedTotal = 0
        skippedTime = 0
        skippedIDs = []
        elapsed = 0
        lastSpoken = nil
        state = .running
        voice.prepare()
        voice.keepAwake(true)
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn
        let t = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tickNow()
        return true
    }

    func pause() {
        guard state == .running else { return }
        pausedAt = Date()
        state = .paused
        voice.cancelCountdown()
        voice.say("Paused.", interrupt: true)
    }

    func resume() {
        guard state == .paused, let pausedAt else { return }
        pausedTotal += Date().timeIntervalSince(pausedAt)
        self.pausedAt = nil
        state = .running
        if let step = currentStep { voice.say("Resuming. \(step.title).", interrupt: true) }
        tickNow()
    }

    /// Jumps to the next exercise; the skipped one holds that block's progression (D57).
    func skipExercise() {
        guard let timeline, state == .running || state == .paused, let step = currentStep else { return }
        if let id = step.exerciseID, !skippedIDs.contains(id) { skippedIDs.append(id) }
        let target = timeline.nextExerciseStart(after: elapsed)
        skippedTime += target - elapsed
        voice.cancelCountdown()
        nextCue = timeline.cues.firstIndex { $0.at >= target } ?? timeline.cues.count
        tickNow()
    }

    /// Ends early. Exercises not reached count as skipped, so the session still logs but holds progress.
    func stop() {
        guard state == .running || state == .paused else { return }
        voice.say("Routine stopped.", interrupt: true)
        finish(early: true)
        state = .idle
    }

    func dismissFinished() {
        guard state == .finished else { return }
        state = .idle
        routine = nil
        timeline = nil
    }

    // MARK: Engine

    private var activeElapsed: TimeInterval {
        guard let startedAt else { return 0 }
        let now = Date()
        let pausedNow = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(startedAt) - pausedTotal - pausedNow) + skippedTime
    }

    private func tickNow() {
        guard state == .running, let timeline else { return }
        let t = activeElapsed
        elapsed = t
        speakDueCues(timeline.cues, at: t)
        if t >= Double(timeline.totalSeconds) { finish(early: false) }
    }

    private func speakDueCues(_ cues: [Cue], at t: TimeInterval) {
        var due: [Cue] = []
        while nextCue < cues.count,
              cues[nextCue].at <= t || (cues[nextCue].kind == .countdown && cues[nextCue].at - t <= Self.tick) {
            due.append(cues[nextCue])
            nextCue += 1
        }
        guard !due.isEmpty else { return }
        if let beeps = due.last(where: { $0.kind == .countdown }), t - beeps.at <= Self.tick {
            voice.countdown(delay: max(0, beeps.at - t), skip: max(0, t - beeps.at))
        }
        let speech = due.filter { $0.kind == .speech }
        let fresh = speech.filter { t - $0.at <= Self.staleAfter }
        // After a gap, say where we are now rather than replaying old cues.
        guard let pick = fresh.last(where: { $0.priority == .transition }) ?? fresh.last
            ?? speech.last(where: { $0.priority == .transition }) else { return }
        lastSpoken = pick.text
        voice.say(pick.text, interrupt: true)
    }

    private func finish(early: Bool) {
        timer?.invalidate()
        timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        voice.keepAwake(false)
        guard let routine, let timeline else { return }
        let reached = Set(timeline.steps.filter { $0.start <= elapsed }.compactMap(\.exerciseID))
        let ids = routine.items.map(\.exercise.id)
        let skipped = ids.filter { skippedIDs.contains($0) || (early && !reached.contains($0)) }
        let done = ids.filter { !skipped.contains($0) && reached.contains($0) }
        if !done.isEmpty {
            sessions.append(RestSessionLog(date: Date(), variant: routine.variant, stages: routine.stages,
                                           skipped: skipped, done: done))
            Self.save(sessions, Self.sessionsKey)
        }
        if !early { state = .finished }
    }

    // MARK: Storage

    private struct LegsAnswer: Codable {
        let feel: LegFeel
        let date: Date
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}
