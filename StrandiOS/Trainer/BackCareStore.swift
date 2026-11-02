import Combine
import Foundation
import TrainerKit
import WhoopStore

/// Back care in the app (D98): its settings, levels and log under `trainer.backcare.*`. Sessions run on
/// the rest-day routine player, so the voice counts every hold with the phone locked.
@MainActor
final class BackCareStore: ObservableObject {
    static let shared = BackCareStore()

    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) } }
    @Published var options: BackCareOptions { didSet { Self.save(options, Self.optionsKey) } }
    @Published private(set) var levels: [String: Stage] { didSet { Self.save(levels, Self.levelsKey) } }
    @Published private(set) var lastLevelChange: Date? {
        didSet { UserDefaults.standard.set(lastLevelChange, forKey: Self.levelChangeKey) }
    }
    @Published private(set) var log: [BackCareLog] { didSet { Self.save(log, Self.logKey) } }
    /// When the strap saw you wake today, from last night's sleep (D101). Mobility reads it too.
    @Published private(set) var wake: Date?

    /// The session handed to the player, logged when it ends.
    private var running: BackCareLog.Session?

    private static let enabledKey = "trainer.backcare.enabled"
    private static let optionsKey = "trainer.backcare.options"
    private static let levelsKey = "trainer.backcare.levels"
    private static let levelChangeKey = "trainer.backcare.levelChange"
    private static let logKey = "trainer.backcare.log"

    private init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: Self.enabledKey)
        options = Self.decode(BackCareOptions.self, Self.optionsKey) ?? BackCareOptions()
        levels = Self.decode([String: Stage].self, Self.levelsKey) ?? [:]
        lastLevelChange = d.object(forKey: Self.levelChangeKey) as? Date
        log = Self.decode([BackCareLog].self, Self.logKey) ?? []
    }

    func level(_ id: String) -> Stage { levels[id] ?? .learn }

    func plan(heavyDuty: HeavyDutyStore = .shared, runner: C25KRunner = .shared, now: Date = Date()) -> BackCarePlan {
        let (lift, done) = heavyDuty.liftToday(runner: runner, now: now)
        return BackCarePlan(options: options, log: log, levels: levels, lastLevelChange: lastLevelChange,
                            liftToday: lift, liftDone: done, wake: wake,
                            flare: runner.painState.holds.contains { $0.area == .back })
    }

    /// Today's wake time: the end of the latest sleep that ended today.
    func updateWake(from sleeps: [CachedSleepSession]) {
        let ends = sleeps.map { Date(timeIntervalSince1970: TimeInterval($0.endTs)) }
            .filter { Calendar.current.isDateInToday($0) }
        wake = ends.max()
    }

    // MARK: Sessions

    func routine(for next: BackCarePlan.Next) -> RestRoutine? {
        switch next {
        case .coreA: return BackCare.coreA(levels: levels)
        case .warmUp: return BackCare.coreA(levels: levels, warmUp: true)
        case .coreB(let w): return BackCare.coreB(levels: levels, workout: w)
        case .later, .done: return nil
        }
    }

    /// Hands a session to the player. False when another coach is running.
    func start(_ session: BackCareLog.Session, routine: RestRoutine) -> Bool {
        running = session
        if RoutineRunner.shared.start(routine) { return true }
        running = nil
        return false
    }

    /// Called by the player when a Back care session ends with at least one exercise done.
    func finished() {
        guard let running else { return }
        log.append(BackCareLog(date: Date(), session: running))
        self.running = nil
    }

    /// The answer to "How did that feel?" for the session just logged.
    func setFeel(_ feel: BackCareFeel) {
        guard !log.isEmpty else { return }
        log[log.count - 1].feel = feel
    }

    var lastFeel: BackCareFeel? { log.last.flatMap { Calendar.current.isDateInToday($0.date) ? $0.feel : nil } }

    func levelUp(_ id: String) {
        let next = Stage(rawValue: level(id).rawValue + 1) ?? .strengthen
        levels[id] = next
        lastLevelChange = Date()
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}
