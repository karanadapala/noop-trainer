import Combine
import Foundation
import TrainerKit

/// The Mobility plan in the app (D127, D148): its start date, settings and log under
/// `trainer.mobility.*`. Sessions run on the rest-day routine player.
@MainActor
final class MobilityStore: ObservableObject {
    static let shared = MobilityStore()

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if enabled && start == nil { start = Date() }
        }
    }
    /// Week 1 starts here; flares set the weeks back from it.
    @Published private(set) var start: Date? { didSet { UserDefaults.standard.set(start, forKey: Self.startKey) } }
    @Published var options: MobilityOptions { didSet { Self.save(options, Self.optionsKey) } }
    @Published private(set) var log: [MobilityLog] { didSet { Self.save(log, Self.logKey) } }

    private var running: (session: Mobility.Session, week: Int)?

    private static let enabledKey = "trainer.mobility.enabled"
    private static let startKey = "trainer.mobility.start"
    private static let optionsKey = "trainer.mobility.options"
    private static let logKey = "trainer.mobility.log"

    private init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: Self.enabledKey)
        start = d.object(forKey: Self.startKey) as? Date
        options = Self.decode(MobilityOptions.self, Self.optionsKey) ?? MobilityOptions()
        log = Self.decode([MobilityLog].self, Self.logKey) ?? []
    }

    func plan(heavyDuty: HeavyDutyStore = .shared, runner: C25KRunner = .shared, now: Date = Date()) -> MobilityPlan {
        let (lift, done) = heavyDuty.liftToday(runner: runner, now: now)
        let legAreas: Set<BodyArea> = [.shins, .calves, .feet]
        let shinCleared = !runner.returnToRun.holdsRuns && !runner.painState.holds.contains { legAreas.contains($0.area) }
        return MobilityPlan(options: options, start: start ?? now, log: log, pain: runner.pain, shinCleared: shinCleared,
                            liftToday: lift, liftDone: done, wake: BackCareStore.shared.wake)
    }

    /// Hands a session to the player. False when another coach is running.
    func start(_ session: Mobility.Session, plan: MobilityPlan) -> Bool {
        running = (session, plan.week(now: Date()))
        if RoutineRunner.shared.start(plan.routine(for: session, now: Date())) { return true }
        running = nil
        return false
    }

    func finished() {
        guard let running else { return }
        log.append(MobilityLog(date: Date(), session: running.session, week: running.week))
        self.running = nil
    }

    var lastNerveSign: Bool? {
        log.last.flatMap { Calendar.current.isDateInToday($0.date) ? $0.nerveSign : nil }
    }

    /// The end-of-session answer. A yes is logged as back pain with tingling: the flare path (D104).
    func setNerveSign(_ yes: Bool) {
        guard !log.isEmpty, log[log.count - 1].nerveSign == nil else { return }
        log[log.count - 1].nerveSign = yes
        if yes {
            C25KRunner.shared.recordPain([PainEntry(area: .back, date: Date(), kind: .rating(2), feel: .tingling)])
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}
