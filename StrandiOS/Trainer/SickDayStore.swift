import Combine
import Foundation
import StrandAnalytics
import TrainerKit

/// Sick days in the app (D214, D219–D224): illnesses under `trainer.sick.*`, the strap's illness watch,
/// and the one funnel every screen reads today's plans through, so the Regimen, the Today card and each
/// plan's own screen can't disagree about what's paused.
@MainActor
final class SickDayStore: ObservableObject {
    static let shared = SickDayStore()

    @Published var options: SickDayOptions { didSet { Self.save(options, Self.optionsKey) } }
    @Published private(set) var episodes: [SickEpisode] { didSet { Self.save(episodes, Self.episodesKey) } }
    /// "A bit off" on the strap's question: gentle plans only, for that day.
    @Published private(set) var easyDay: Date? { didSet { UserDefaults.standard.set(easyDay, forKey: Self.easyKey) } }
    /// "Fine" or "I'm fine, keep the plan": the strap's card stays quiet for that day.
    @Published private(set) var strapAnswered: Date? {
        didSet { UserDefaults.standard.set(strapAnswered, forKey: Self.answeredKey) }
    }
    /// NOOP's illness watch (D222), mirrored from the app model; nil when it's off or still learning.
    @Published private(set) var strapLevel: IllnessSignalEngine.Level?

    private var watching: AnyCancellable?

    private static let optionsKey = "trainer.sick.options"
    private static let episodesKey = "trainer.sick.episodes"
    private static let easyKey = "trainer.sick.easyDay"
    private static let answeredKey = "trainer.sick.strapAnswered"

    private init() {
        let d = UserDefaults.standard
        options = Self.decode(SickDayOptions.self, Self.optionsKey) ?? SickDayOptions()
        episodes = Self.decode([SickEpisode].self, Self.episodesKey) ?? []
        easyDay = d.object(forKey: Self.easyKey) as? Date
        strapAnswered = d.object(forKey: Self.answeredKey) as? Date
    }

    func watch(_ model: AppModel) {
        guard watching == nil else { return }
        watching = model.$illnessSignal.sink { [weak self] result in
            Task { @MainActor in self?.strapLevel = result?.level }
        }
    }

    // MARK: Today

    /// The illness that's on now.
    var current: SickEpisode? { episodes.last.flatMap { $0.isOn ? $0 : nil } }

    /// The last illness while it, or its way back, still shapes today.
    func context(now: Date = Date(), calendar: Calendar = .current) -> IllnessContext? {
        guard let last = episodes.last else { return nil }
        if last.isOn { return IllnessContext(episode: last, options: options) }
        guard let back = wayBackEnds(last, calendar: calendar), calendar.startOfDay(for: now) <= back else { return nil }
        return IllnessContext(episode: last, options: options)
    }

    /// The day the last plan comes back after `episode`.
    func wayBackEnds(_ episode: SickEpisode, calendar: Calendar = .current) -> Date? {
        SickDays.resumes(after: episode, options: options, calendar: calendar).values.max()
    }

    /// Only gentle plans today: "A bit off", or the strap's "raised" unless you said you're fine.
    func easyToday(now: Date = Date()) -> Bool {
        let cal = Calendar.current
        if current != nil { return false }
        if let easyDay, cal.isDate(easyDay, inSameDayAs: now) { return true }
        let answered = strapAnswered.map { cal.isDate($0, inSameDayAs: now) } ?? false
        return strapLevel == .raised && !answered
    }

    /// The strap's question shows: mild or raised, not ill already, not answered today.
    func strapAsks(now: Date = Date()) -> Bool {
        guard current == nil, strapLevel == .mild || strapLevel == .raised else { return false }
        let cal = Calendar.current
        if let easyDay, cal.isDate(easyDay, inSameDayAs: now) { return false }
        return !(strapAnswered.map { cal.isDate($0, inSameDayAs: now) } ?? false)
    }

    func regimenDay(plans: [any TrainingPlan], now: Date = Date()) -> RegimenDay {
        RegimenDay(plans: plans, now: now, illness: context(now: now), easyDay: easyToday(now: now))
    }

    // MARK: Changes

    /// "I'm unwell" (D219). `start` is earlier when answering the gap check for days already gone.
    func markUnwell(kind: IllnessKind?, start: Date = Date()) {
        guard current == nil else { setKind(kind); return }
        episodes.append(SickEpisode(start: start, kind: kind))
    }

    func setKind(_ kind: IllnessKind?) {
        guard let i = openIndex else { return }
        episodes[i].kind = kind
    }

    /// The morning check (D223). "Back to normal" ends the illness today; the way back starts tomorrow.
    func check(_ feel: SickFeel, fever: Bool, now: Date = Date()) {
        guard let i = openIndex else { return }
        episodes[i].checks.removeAll { Calendar.current.isDate($0.date, inSameDayAs: now) }
        episodes[i].checks.append(SickCheck(date: now, feel: feel, fever: fever))
        if feel == .normal { episodes[i].end = now }
    }

    /// "Change" on this morning's answer: the question shows again.
    func clearTodaysCheck(now: Date = Date()) {
        guard let i = openIndex else { return }
        episodes[i].checks.removeAll { Calendar.current.isDate($0.date, inSameDayAs: now) }
    }

    func todaysCheck(now: Date = Date()) -> SickCheck? {
        current?.checks.last { Calendar.current.isDate($0.date, inSameDayAs: now) }
    }

    func backToNormal(now: Date = Date()) {
        guard let i = openIndex else { return }
        episodes[i].end = now
    }

    /// Undo "Back to normal" on the day it was tapped.
    func stillUnwell() {
        guard let last = episodes.indices.last, let end = episodes[last].end,
              Calendar.current.isDateInToday(end) else { return }
        episodes[last].end = nil
        episodes[last].checks.removeAll { $0.feel == .normal && Calendar.current.isDateInToday($0.date) }
    }

    enum StrapAnswer { case fine, bitOff, ill }

    func answerStrap(_ answer: StrapAnswer, now: Date = Date()) {
        switch answer {
        case .fine: strapAnswered = now
        case .bitOff: easyDay = now; strapAnswered = now
        case .ill: markUnwell(kind: nil, start: now)
        }
    }

    private var openIndex: Int? { episodes.indices.last.flatMap { episodes[$0].isOn ? $0 : nil } }

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}

extension ActivePlans {
    /// Today across every active plan, through sick days and the strap: the one funnel for every screen.
    static func day(now: Date = Date()) -> RegimenDay { SickDayStore.shared.regimenDay(plans: all(), now: now) }
}
