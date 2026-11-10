import Combine
import Foundation
import TrainerKit

/// Going quiet and coming back (D226, D227): when the app was last open, the gap ladder booked ahead
/// each time it goes to the background (so it reaches you even if you never open the app), and the
/// comeback screen on the first open after a gap. Under `trainer.gap.*`.
@MainActor
final class ComebackStore: ObservableObject {
    static let shared = ComebackStore()

    @Published var options: GapOptions { didSet { Self.save(options, Self.optionsKey) } }
    /// "Next time you're ill, what should I do?" (D227), shown again on "I'm unwell".
    @Published var copingPlan: String { didSet { UserDefaults.standard.set(copingPlan, forKey: Self.copingKey) } }
    @Published private(set) var lastSeen: Date? { didSet { UserDefaults.standard.set(lastSeen, forKey: Self.lastSeenKey) } }
    /// Counted gap days when the comeback screen should show; nil otherwise.
    @Published var comeback: Int?
    /// The day you came back, for "Done. That's the hardest one." after the first session.
    @Published private(set) var cameBack: Date? { didSet { UserDefaults.standard.set(cameBack, forKey: Self.cameBackKey) } }

    private static let optionsKey = "trainer.gap.options"
    private static let copingKey = "trainer.gap.copingPlan"
    private static let lastSeenKey = "trainer.gap.lastSeen"
    private static let cameBackKey = "trainer.gap.cameBack"
    private static let ladderID = "trainer.gap.ladder."

    private init() {
        let d = UserDefaults.standard
        options = d.data(forKey: Self.optionsKey).flatMap { try? JSONDecoder().decode(GapOptions.self, from: $0) } ?? GapOptions()
        copingPlan = d.string(forKey: Self.copingKey) ?? Comeback.defaultCopingPlan
        lastSeen = d.object(forKey: Self.lastSeenKey) as? Date
        cameBack = d.object(forKey: Self.cameBackKey) as? Date
    }

    /// A day with at least one session planned, across every active plan (rest days don't count).
    static func isSessionDay(_ day: Date) -> Bool {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        return ActivePlans.day(now: noon).plans.contains { $0.status == .session }
    }

    // MARK: The app opening and closing

    func appBecameActive(now: Date = Date()) {
        if let lastSeen, SickDayStore.shared.current == nil {
            let gap = Comeback.gapDays(lastSeen: lastSeen, now: now, isSessionDay: Self.isSessionDay)
            if gap >= options.comebackAfterDays { comeback = gap }
        }
        lastSeen = now
        TrainerNotifications.cancel(prefix: Self.ladderID)
    }

    /// Books the ladder from now; the next open cancels it.
    func appWentToBackground(now: Date = Date()) {
        lastSeen = now
        bookLadder(from: now)
    }

    private func bookLadder(from now: Date) {
        TrainerNotifications.cancel(prefix: Self.ladderID)
        guard options.enabled, SickDayStore.shared.current == nil else { return }
        let next = ActivePlans.all().first.map { $0.today(now: now, calendar: .current) }
        let headline = next.flatMap { $0.status == .finished ? nil : $0.headline }
        for (i, item) in Comeback.schedule(lastSeen: now, options: options, isSessionDay: Self.isSessionDay).enumerated() {
            TrainerNotifications.schedule(id: Self.ladderID + "\(i)", at: item.date,
                                          body: item.step.message.body(days: item.step.day, next: headline),
                                          category: TrainerNotifications.gapCategory + "." + item.step.message.rawValue)
        }
    }

    // MARK: Answers

    /// A button on a gap notification. Answering counts as being back in touch.
    func handle(_ action: TrainerNotifications.Action?) {
        let now = Date()
        switch action {
        case .ill?:
            SickDayStore.shared.markUnwell(kind: nil, start: dayAfterLastSeen(now))
        case .tomorrow?:
            if let at = Calendar.current.date(byAdding: .day, value: 1, to: now)
                .flatMap({ Calendar.current.date(bySettingHour: options.tomorrowHour, minute: 0, second: 0, of: $0) }) {
                TrainerNotifications.schedule(id: "trainer.gap.tomorrow", at: at,
                                              body: "Today's first step is ready. Open the Regimen to see how long it takes.")
            }
        case .busy?, .startNow?, .slot0?, .slot1?, .slot2?, nil:
            break
        }
        lastSeen = now
        bookLadder(from: now)
    }

    /// The comeback screen's answers (D227). Ill with a fever: still unwell. Ill and over it: the days
    /// away become a past illness, and its way back starts today. Anything else: each plan's way back
    /// for the days it missed, from today.
    func resolve(_ reason: GapReason, fever: Bool, now: Date = Date()) {
        let sick = SickDayStore.shared
        let start = dayAfterLastSeen(now)
        if reason == .ill {
            sick.markUnwell(kind: nil, start: start)
            if !fever {
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
                sick.backToNormal(now: max(start, yesterday))
                sick.applyWayBackIfDue(now: now)
            }
        } else {
            let today = Calendar.current.startOfDay(for: now)
            for plan in ActivePlans.all() {
                let step = SickDays.step(daysMissed: SickDays.daysMissed(plan: plan, episode: nil, now: now), options: sick.options)
                ActivePlans.applier(plan.id)?.applyWayBack(WayBackRecord(step: step, from: today))
            }
        }
        cameBack = now
        comeback = nil
    }

    /// After the first session back: once, on the day you came back.
    var firstSessionBackDone: Bool {
        guard let cameBack, Calendar.current.isDateInToday(cameBack) else { return false }
        return ActivePlans.day().plans.contains { $0.status == .done }
    }

    private func dayAfterLastSeen(_ now: Date) -> Date {
        guard let lastSeen else { return now }
        return min(now, Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: lastSeen)) ?? now)
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}
