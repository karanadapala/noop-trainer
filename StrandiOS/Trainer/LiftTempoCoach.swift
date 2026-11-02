import Combine
import Foundation
import TrainerKit

/// Calls Heavy Duty's tempo during a set (D78): "One. Up." for 2 seconds, "Hold." for 1, "Down." for 3,
/// rep after rep, until the set ends. Silent in rests and in any Lift Log session Heavy Duty didn't
/// start, and while a run or routine is speaking. On by default; a Heavy Duty setting.
@MainActor
final class LiftTempoCoach {
    static let shared = LiftTempoCoach()

    static let enabledKey = "trainer.heavyduty.tempoVoice"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Seconds to get into position before the first rep.
    static let lead = 3.0
    /// Reps called past the top of the range, so the voice outlasts a strong set.
    static let extraReps = 4

    private let voice = VoiceCoach()
    private var watching: AnyCancellable?
    private var timer: Timer?
    private var slot: LiftSlot?
    private var startedAt: Date?
    private var cues: [(at: Double, text: String)] = []
    private var next = 0

    private init() {}

    /// Follows the session's stage from now on. Safe to call more than once.
    func watch(_ session: LiftSessionController) {
        guard watching == nil else { return }
        watching = session.$engine.sink { [weak self, weak session] engine in
            Task { @MainActor in self?.update(engine, programName: session?.programName) }
        }
    }

    private func update(_ engine: LiftSessionEngine?, programName: String?) {
        guard Self.enabled, let engine, programName?.hasPrefix(HeavyDutyStore.sessionPrefix) == true,
              case .working(let s) = engine.stage,
              ![.running, .paused].contains(RoutineRunner.shared.state),
              ![.running, .paused].contains(C25KRunner.shared.state) else {
            stop()
            return
        }
        guard s != slot else { return }
        begin(s, reps: (engine.planItem(for: s)?.targetRepsHigh ?? 12) + Self.extraReps)
    }

    static func cues(reps: Int) -> [(at: Double, text: String)] {
        var out: [(Double, String)] = [(0, "Two up, one hold, three down.")]
        for k in 0..<reps {
            let t = lead + Double(k * 6)
            out.append((t, "\(spelled(k + 1)). Up."))
            out.append((t + 2, "Hold."))
            out.append((t + 3, "Down."))
        }
        return out
    }

    private func begin(_ s: LiftSlot, reps: Int) {
        stop()
        slot = s
        cues = Self.cues(reps: reps)
        next = 0
        startedAt = Date()
        voice.prepare()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func tick() {
        guard let startedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        var due: String?
        while next < cues.count, cues[next].at <= elapsed {
            due = cues[next].text
            next += 1
        }
        if let due { voice.say(due, interrupt: true) }
        if next >= cues.count { stop() }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        slot = nil
        startedAt = nil
    }

    static func spelled(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        return (f.string(from: NSNumber(value: n)) ?? "\(n)").capitalized
    }
}
