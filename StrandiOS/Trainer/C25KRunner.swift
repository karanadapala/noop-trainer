import Combine
import Foundation
import TrainerKit

/// Runs one voice-guided C25K session on top of NOOP's normal workout recording (NOOP Trainer, Sprint 0).
///
/// Timing is wall-clock based: every cue is scheduled up front (`CueTimeline`) and `tick()` speaks
/// whatever is due. Ticks come from a half-second timer, from each HR update and from each GPS fix, so
/// when iOS throttles the timer in the background the BLE and location wake-ups still keep cues on time
/// (B4). If the app was asleep through several cues, only the latest segment change is spoken.
@MainActor
final class C25KRunner: ObservableObject {
    enum State: Equatable { case idle, running, paused, finished }

    /// Kept alive across navigation so leaving the screen never stops a run.
    static let shared = C25KRunner()

    @Published private(set) var state: State = .idle
    @Published private(set) var session: GuidedSession?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var segmentIndex: Int?
    @Published private(set) var lastSpoken: String?
    @Published private(set) var completed: Set<String>
    @Published private(set) var log: [String: C25KLogEntry]

    private weak var model: AppModel?
    private let voice = VoiceCoach()
    private let heartRateGuard = HeartRateGuard()
    private var cues: [Cue] = []
    private var nextCue = 0
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var lastCorrectionAt: TimeInterval?
    private var lastTransitionAt: TimeInterval = -.infinity
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()

    private static let completedKey = "trainer.c25k.completed"
    /// A cue more than this late is dropped rather than spoken out of context.
    private static let staleAfter: TimeInterval = 5
    private static let tick: TimeInterval = 0.5

    private init() {
        completed = Set(UserDefaults.standard.stringArray(forKey: Self.completedKey) ?? [])
        log = C25KLogStore.load()
    }

    // MARK: Progress

    static func key(_ s: GuidedSession) -> String { "w\(s.week)d\(s.day)" }

    func isCompleted(_ s: GuidedSession) -> Bool { completed.contains(Self.key(s)) }

    /// First session not yet completed, in plan order.
    var nextSession: GuidedSession {
        C25K.all.first { !isCompleted($0) } ?? C25K.all[C25K.all.count - 1]
    }

    func setCompleted(_ s: GuidedSession, _ done: Bool) {
        if done {
            completed.insert(Self.key(s))
        } else {
            completed.remove(Self.key(s))
            if log.removeValue(forKey: Self.key(s)) != nil { C25KLogStore.save(log) }
        }
        UserDefaults.standard.set(Array(completed).sorted(), forKey: Self.completedKey)
    }

    func logEntry(_ s: GuidedSession) -> C25KLogEntry? { log[Self.key(s)] }

    /// Counts an existing workout as this day's session.
    func link(_ s: GuidedSession, to entry: C25KLogEntry) {
        log[Self.key(s)] = entry
        C25KLogStore.save(log)
        setCompleted(s, true)
    }

    // MARK: Derived

    var activeElapsed: TimeInterval {
        guard let startedAt else { return 0 }
        let now = Date()
        let pausedNow = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(startedAt) - pausedTotal - pausedNow)
    }

    var currentSegment: Segment? {
        guard let session, let segmentIndex else { return nil }
        return session.segments[segmentIndex]
    }

    var segmentRemaining: TimeInterval {
        guard let session, let i = segmentIndex else { return 0 }
        return Double(session.segmentStarts[i] + session.segments[i].seconds) - elapsed
    }

    var nextSegment: Segment? {
        guard let session, let i = segmentIndex, i + 1 < session.segments.count else { return nil }
        return session.segments[i + 1]
    }

    // MARK: Control

    /// Returns false (and does nothing) if another workout is already being recorded.
    @discardableResult
    func start(_ s: GuidedSession, model: AppModel) -> Bool {
        guard state == .idle || state == .finished, model.activeWorkout == nil else { return false }
        self.model = model
        session = s
        cues = CueTimeline.cues(for: s)
        nextCue = 0
        startedAt = Date()
        pausedAt = nil
        pausedTotal = 0
        lastCorrectionAt = nil
        lastTransitionAt = -.infinity
        elapsed = 0
        segmentIndex = 0
        state = .running

        model.startWorkout(sport: "Running")
        model.startRealtimeHR()
        voice.prepare()

        let t = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        model.$bpm.sink { [weak self] _ in self?.tick() }.store(in: &subscriptions)
        model.gpsRecorder.$distanceM.sink { [weak self] _ in self?.tick() }.store(in: &subscriptions)
        tick()
        return true
    }

    func pause() {
        guard state == .running else { return }
        pausedAt = Date()
        state = .paused
        if model?.activeWorkout?.isPaused == false { model?.toggleWorkoutPause() }
        voice.cancelCountdown()
        voice.say("Paused.", interrupt: true)
    }

    func resume() {
        guard state == .paused, let pausedAt else { return }
        pausedTotal += Date().timeIntervalSince(pausedAt)
        self.pausedAt = nil
        state = .running
        if model?.activeWorkout?.isPaused == true { model?.toggleWorkoutPause() }
        if let seg = currentSegment {
            voice.say("Resuming. \(Self.verb(seg.kind)), \(CueTimeline.spokenDuration(Int(segmentRemaining.rounded()))) left.",
                      interrupt: true)
        }
        tick()
    }

    /// Ends early: the workout is still saved, but the day isn't marked complete.
    func stop() {
        guard state == .running || state == .paused else { return }
        voice.cancelCountdown()
        voice.say("Workout stopped.", interrupt: true)
        tearDown()
        state = .idle
    }

    func dismissFinished() {
        if state == .finished { state = .idle }
    }

    // MARK: Engine

    func tick() {
        guard state == .running, let session else { return }
        let t = activeElapsed
        elapsed = t
        segmentIndex = session.segmentIndex(at: t)

        speakDueCues(at: t)
        coachHeartRate(at: t, session: session)

        if t >= Double(session.totalSeconds) { finish(session) }
    }

    private func speakDueCues(at t: TimeInterval) {
        var due: [Cue] = []
        // A countdown is taken one tick early and scheduled to the exact moment, so the beeps don't
        // wander by up to a tick.
        while nextCue < cues.count,
              cues[nextCue].at <= t || (cues[nextCue].kind == .countdown && cues[nextCue].at - t <= Self.tick) {
            due.append(cues[nextCue])
            nextCue += 1
        }
        guard !due.isEmpty else { return }
        // Beeps only make sense on time; a late one is dropped and the segment announcement follows.
        if let beeps = due.last(where: { $0.kind == .countdown }), t - beeps.at <= Self.tick {
            lastTransitionAt = t
            lastSpoken = beeps.text
            voice.countdown(delay: max(0, beeps.at - t), skip: max(0, t - beeps.at))
        }
        let speech = due.filter { $0.kind == .speech }
        let fresh = speech.filter { t - $0.at <= Self.staleAfter }
        // Late wake-up: say where we are now instead of replaying old cues.
        let pick = fresh.last { $0.priority == .transition } ?? fresh.last
            ?? speech.last { $0.priority == .transition }
        guard let pick else { return }
        if pick.priority == .transition { lastTransitionAt = t }
        say(pick.text, interrupt: pick.priority == .transition)
    }

    private func coachHeartRate(at t: TimeInterval, session: GuidedSession) {
        guard let model, let i = segmentIndex, let bpm = model.bpm, model.live.streamingLiveHR else { return }
        // Never talk over a segment change or the countdown just before one.
        if t - lastTransitionAt < 6 { return }
        if nextCue < cues.count, cues[nextCue].priority == .transition, cues[nextCue].at - t < 8 { return }
        let zone = model.profile.hrZoneSet.zoneNumber(forBPM: Double(bpm))
        let into = t - Double(session.segmentStarts[i])
        let since = lastCorrectionAt.map { t - $0 }
        if let text = heartRateGuard.correction(segment: session.segments[i].kind, zone: zone,
                                                secondsIntoSegment: into, secondsSinceLastCorrection: since) {
            lastCorrectionAt = t
            say(text, interrupt: false)
        }
    }

    private func say(_ text: String, interrupt: Bool) {
        lastSpoken = text
        voice.say(text, interrupt: interrupt)
    }

    private func finish(_ session: GuidedSession) {
        if session.week > 0, let w = model?.activeWorkout {
            link(session, to: C25KLogEntry(startTs: Int(w.start.timeIntervalSince1970),
                                           durationS: session.totalSeconds,
                                           avgHr: w.avgHr > 0 ? w.avgHr : nil,
                                           distanceM: model.map { $0.gpsRecorder.distanceM },
                                           source: .coach))
        } else if session.week > 0 {
            setCompleted(session, true)
        }
        tearDown()
        state = .finished
    }

    private func tearDown() {
        timer?.invalidate()
        timer = nil
        subscriptions.removeAll()
        if let model {
            if model.activeWorkout != nil { model.endWorkout() }
            model.stopRealtimeHR()
        }
        pausedAt = nil
    }

    static func verb(_ kind: Segment.Kind) -> String {
        switch kind {
        case .warmUp: return "Warm-up walk"
        case .run: return "Run"
        case .walk: return "Walk"
        case .coolDown: return "Cool-down walk"
        }
    }
}
