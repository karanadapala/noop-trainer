import Combine
import Foundation
import TrainerKit
import WhoopStore

/// The morning time budget (D229–D234): once the strap's sleep shows you're up (at once on a smart-alarm
/// morning), one notification says how long today's regimen takes, before anything starts, and asks
/// when suits. If the strap hasn't synced by your usual wake time + 45 min, a copy booked the night
/// before goes instead. Under `trainer.morning.*`.
@MainActor
final class MorningBudget: ObservableObject {
    static let shared = MorningBudget()

    @Published var options: MorningOptions { didSet { Self.save(options, Self.optionsKey) } }
    @Published private(set) var lastSent: Date? { didSet { UserDefaults.standard.set(lastSent, forKey: Self.sentKey) } }
    @Published private(set) var lastReply: Date? { didSet { UserDefaults.standard.set(lastReply, forKey: Self.replyKey) } }
    /// Mornings in a row with no tap and no open that day.
    @Published private(set) var ignored: Int { didSet { UserDefaults.standard.set(ignored, forKey: Self.ignoredKey) } }
    /// The usual wake time, minutes after midnight, from the last two weeks of sleep.
    @Published private(set) var usualWake: Int?

    private var watching: AnyCancellable?

    private static let optionsKey = "trainer.morning.options"
    private static let sentKey = "trainer.morning.lastSent"
    private static let replyKey = "trainer.morning.lastReply"
    private static let ignoredKey = "trainer.morning.ignored"
    private static let todayID = "trainer.morning.today"
    private static let fallbackID = "trainer.morning.fallback"

    private init() {
        let d = UserDefaults.standard
        options = d.data(forKey: Self.optionsKey).flatMap { try? JSONDecoder().decode(MorningOptions.self, from: $0) } ?? MorningOptions()
        lastSent = d.object(forKey: Self.sentKey) as? Date
        lastReply = d.object(forKey: Self.replyKey) as? Date
        ignored = d.integer(forKey: Self.ignoredKey)
    }

    var paused: Bool { ignored >= options.pauseAfterIgnored }

    func watch(_ model: AppModel) {
        guard watching == nil else { return }
        watching = model.repo.$sleeps.sink { [weak self] sleeps in
            Task { @MainActor in self?.sleepsChanged(sleeps) }
        }
        model.onSmartAlarmWake = { [weak self] in Task { @MainActor in self?.wokeUp() } }
    }

    // MARK: Waking

    private func sleepsChanged(_ sleeps: [CachedSleepSession], now: Date = Date()) {
        let cal = Calendar.current
        let ends = sleeps.map { Date(timeIntervalSince1970: TimeInterval($0.endTs)) }
        // Back care and Mobility read the wake time too; keep it fresh even with the app closed.
        BackCareStore.shared.updateWake(from: sleeps)
        let recent = ends.filter { now.timeIntervalSince($0) < 14 * 86400 }
            .map { cal.component(.hour, from: $0) * 60 + cal.component(.minute, from: $0) }
            .filter { (180...780).contains($0) }
            .sorted()
        usualWake = recent.isEmpty ? nil : recent[recent.count / 2]
        if let latest = ends.max(), cal.isDateInToday(latest), now.timeIntervalSince(latest) < 3 * 3600 { wokeUp(now: now) }
    }

    /// The strap says you're up: send today's note, once.
    func wokeUp(now: Date = Date()) {
        guard options.enabled, !paused else { return }
        if let lastSent, Calendar.current.isDate(lastSent, inSameDayAs: now) { return }
        guard let body = message(now: now) else { return }
        if let lastSent, (lastReply ?? .distantPast) < lastSent { ignored += 1 } else { ignored = 0 }
        guard !paused else { return }
        TrainerNotifications.cancel(prefix: Self.fallbackID)
        TrainerNotifications.registerCategories(slots: options.slots)
        TrainerNotifications.schedule(id: Self.todayID, at: now.addingTimeInterval(1), body: body,
                                      category: TrainerNotifications.morningCategory)
        lastSent = now
    }

    /// Books tomorrow's copy for usual wake + the fallback, in case the strap doesn't sync in time.
    func bookFallback(now: Date = Date()) {
        TrainerNotifications.cancel(prefix: Self.fallbackID)
        guard options.enabled, !paused, let wake = usualWake else { return }
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)),
              let at = cal.date(byAdding: .minute, value: wake + options.fallbackAfterUsualWake, to: tomorrow),
              let body = message(now: cal.date(byAdding: .minute, value: wake, to: tomorrow) ?? tomorrow) else { return }
        TrainerNotifications.registerCategories(slots: options.slots)
        TrainerNotifications.schedule(id: Self.fallbackID, at: at, body: body, category: TrainerNotifications.morningCategory)
    }

    /// Opening the app counts as a reply.
    func appBecameActive(now: Date = Date()) { lastReply = now }

    func keepSending() { ignored = 0 }

    // MARK: The note

    /// "Today: about 45 min (C25K 31 · Back care 8 · Mobility 12). Keep an hour free." The length comes
    /// first (D234), then the short start; nil when there's nothing to say.
    func message(now: Date) -> String? {
        if SickDayStore.shared.current != nil { return "Morning. How are you today? Your check is on the Regimen." }
        let budget = ActivePlans.budget(now: now)
        if budget.clear {
            return options.restDays ? "Rest day: nothing planned today. Recovery counts too." : nil
        }
        let parts = budget.items.compactMap { item in item.minutes.map { "\(item.title) \($0)" } }
        var text = "Today: about \(DayBudget.spoken(budget.minutes)) (\(parts.joined(separator: " · "))). Keep \(DayBudget.spoken(budget.keepFree)) free. When suits?"
        let pending = budget.items.filter { !$0.done }
        if pending.count > 1, let short = pending.min(by: { ($0.minutes ?? 0) < ($1.minutes ?? 0) }), let m = short.minutes {
            text += " Short on time? Start with \(short.title), \(m) min."
        }
        return text
    }

    func handle(_ action: TrainerNotifications.Action?) {
        lastReply = Date()
        let index: Int?
        switch action {
        case .slot0?: index = 0
        case .slot1?: index = 1
        case .slot2?: index = 2
        case .ill?: SickDayStore.shared.markUnwell(kind: nil); index = nil
        default: index = nil
        }
        if let index, options.slots.indices.contains(index) { remind(at: options.slots[index]) }
    }

    /// "When suits?": a reminder `leadMinutes` before the chosen time.
    func remind(at minuteOfDay: Int, now: Date = Date()) {
        let budget = ActivePlans.budget(now: now)
        TrainerNotifications.remind(atMinuteOfDay: minuteOfDay, lead: options.leadMinutes,
                                    body: "In \(options.leadMinutes) min: today's regimen, about \(DayBudget.spoken(budget.minutes)).",
                                    now: now)
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}
