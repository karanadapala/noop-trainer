import Foundation

/// Where something hurts (D38).
public enum BodyArea: String, CaseIterable, Codable, Sendable {
    case shins, calves, knees, feet, hips
    /// The low back, or the big-toe pain that has meant a sciatica flare (D104): the back flare path.
    case back

    public var label: String {
        switch self {
        case .shins: return "Shins"
        case .calves: return "Calves / Achilles"
        case .knees: return "Knees"
        case .feet: return "Feet"
        case .hips: return "Hips"
        case .back: return "Back / big toe"
        }
    }

    /// Areas the rest-day routine can strengthen with a focused block. The back has Back care instead.
    public static let focusable: [BodyArea] = [.shins, .calves, .knees, .feet, .hips]

    /// "shin", "calf", for the coach's voice.
    public var spokenName: String {
        switch self {
        case .shins: return "shin"
        case .calves: return "calf"
        case .knees: return "knee"
        case .feet: return "foot"
        case .hips: return "hip"
        case .back: return "back"
        }
    }
}

/// How it hurts when reported, after a run or by hand (D49). Replaced by the 0–10 scale (D114); kept so
/// older answers still read.
public enum PainLevel: String, CaseIterable, Codable, Sendable {
    case mild, worsening, sharp

    public var label: String {
        switch self {
        case .mild: return "Mild"
        case .worsening: return "Getting worse"
        case .sharp: return "Sharp, one spot"
        }
    }

    /// Where an old word answer sits on the 0–10 scale; nil for sharp, which is a spot now.
    var score: Int? {
        switch self {
        case .mild: return 2
        case .worsening: return 5
        case .sharp: return nil
        }
    }
}

/// The 0–10 pain scale (D114), with words at the points people anchor on.
public enum PainScale {
    public static let range = 0...10
    /// The research's limit for exercise and running (D110, D115): above this, stop.
    public static let limit = 3

    public static func anchor(_ score: Int) -> String? {
        switch score {
        case 0: return "None"
        case 3: return "Noticeable"
        case 5: return "Distracting"
        case 8: return "Can't continue"
        default: return nil
        }
    }
}

public enum PainSide: String, CaseIterable, Codable, Sendable {
    case left, right, both

    public var label: String { rawValue.capitalized }
}

/// What the pain feels like (D119). Tingling points at a nerve rather than the leg itself.
public enum PainFeel: String, CaseIterable, Codable, Sendable {
    case sharp, achy, tight, tingling

    public var label: String {
        switch self {
        case .sharp: return "Sharp"
        case .achy: return "Achy"
        case .tight: return "Tight"
        case .tingling: return "Tingling / numb"
        }
    }
}

/// The next-morning answer for an area reported earlier (D49).
public enum PainTrend: String, CaseIterable, Codable, Sendable {
    case gone, less, same, worse

    /// The trend a 0–10 morning score makes against the last score.
    public static func from(score: Int, previous: Int?) -> PainTrend {
        if score == 0 { return .gone }
        guard let previous else { return .same }
        return score < previous ? .less : score > previous ? .worse : .same
    }

    public var label: String {
        switch self {
        case .gone: return "Gone"
        case .less: return "Less"
        case .same: return "Same"
        case .worse: return "Worse"
        }
    }
}

/// One answer about one area at one moment.
public struct PainEntry: Codable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        /// An old word answer (before the 0–10 scale).
        case report(PainLevel)
        case trend(PainTrend)
        /// A 0–10 report, after a run, a stopped run or by hand.
        case rating(Int)
        /// Sharp pain in one small spot on a bone: a red flag whatever the number.
        case spot
    }

    public let area: BodyArea
    public let date: Date
    public let kind: Kind
    /// The 0–10 score behind a morning trend.
    public var score: Int?
    public var side: PainSide?
    public var feel: PainFeel?
    /// Back or buttock pain along with it (D119): with one side, that points at the nerve.
    public var backPain: Bool?

    public init(area: BodyArea, date: Date, kind: Kind, score: Int? = nil, side: PainSide? = nil,
                feel: PainFeel? = nil, backPain: Bool? = nil) {
        self.area = area
        self.date = date
        self.kind = kind
        self.score = score
        self.side = side
        self.feel = feel
        self.backPain = backPain
    }

    /// The 0–10 value this answer carries, if any.
    public var value: Int? {
        switch kind {
        case .rating(let n): return n
        case .report(let level): return level.score
        case .trend: return score
        case .spot: return nil
        }
    }

    /// Tingling or numbness, or one-sided pain with back pain: a nerve sign (D113), checked before training.
    public var nerveSign: Bool {
        feel == .tingling || (area != .back && backPain == true && side != nil && side != .both)
    }

    /// A morning answer on the 0–10 scale, with its trend against the last score.
    public static func morning(area: BodyArea, date: Date, score: Int, previous: Int?) -> PainEntry {
        PainEntry(area: area, date: date, kind: .trend(.from(score: score, previous: previous)), score: score)
    }
}

/// What the pain answers mean today (D49, D53, D61).
///
/// - An area is **active** from a report until a morning answers "gone".
/// - An active area whose latest answer is from an earlier day **needs a morning check**.
/// - Runs are **on hold** when, today, an area was answered "same" or "worse", or when an area's
///   latest answer is a sharp report. A later "gone" or "less" lifts it. A skipped check doesn't hold.
public struct PainState: Equatable, Sendable {
    public struct Hold: Equatable, Sendable {
        public let area: BodyArea
        public let reason: String
    }

    public let active: [BodyArea]
    public let needsCheck: [BodyArea]
    public let holds: [Hold]
    /// Show the red-flag sheet: a sharp report, or worse than yesterday.
    public let showRedFlags: Bool
    /// An area got worse the morning after, in the last week: repeating the week is worth suggesting.
    public let suggestRepeatingWeek: Bool
    /// Areas with a red flag (spot, nerve sign, worse than yesterday): no exercise loads them (D113).
    public let redFlagAreas: [BodyArea]
    private let latest: [BodyArea: PainEntry]

    public var isOnHold: Bool { !holds.isEmpty }

    public init(entries: [PainEntry], now: Date, calendar: Calendar = .current) {
        var latest: [BodyArea: PainEntry] = [:]
        for e in entries.sorted(by: { $0.date < $1.date }) { latest[e.area] = e }
        let today = calendar.startOfDay(for: now)

        var active: [BodyArea] = []
        var needsCheck: [BodyArea] = []
        var holds: [Hold] = []
        var redFlags = false
        var flagged: [BodyArea] = []
        let flare = BackFlare.current(entries: entries, now: now, calendar: calendar)
        for area in BodyArea.allCases {
            guard let e = latest[area], e.kind != .trend(.gone) else { continue }
            active.append(area)
            let isToday = calendar.startOfDay(for: e.date) == today
            if !isToday { needsCheck.append(area) }
            if e.nerveSign {
                holds.append(Hold(area: area, reason: "\(area.label): tingling or back pain with it"))
                redFlags = true
                flagged.append(area)
                continue
            }
            switch e.kind {
            case .report(.sharp), .spot:
                holds.append(Hold(area: area, reason: "\(area.label): sharp pain in one spot"))
                redFlags = true
                flagged.append(area)
            case .trend(.same) where isToday:
                holds.append(Hold(area: area, reason: "\(area.label): same as yesterday"))
            case .trend(.worse) where isToday:
                holds.append(Hold(area: area, reason: "\(area.label): worse than yesterday"))
                redFlags = true
                flagged.append(area)
            default:
                if area == .back, let flare, flare.easy(now: now) {
                    holds.append(Hold(area: area, reason: "Back flare: easy until \(flare.easyUntil.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"))
                }
            }
        }
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        self.active = active
        self.needsCheck = needsCheck
        self.holds = holds
        self.showRedFlags = redFlags
        self.redFlagAreas = flagged
        self.suggestRepeatingWeek = entries.contains { $0.kind == .trend(.worse) && $0.date >= weekAgo }
        self.latest = latest
    }

    /// "4/10" / "Less than yesterday · 2/10". Nil for an area that isn't active.
    public func summary(_ area: BodyArea) -> String? {
        guard active.contains(area), let e = latest[area] else { return nil }
        let score = e.score.map { " · \($0)/10" } ?? ""
        switch e.kind {
        case .report(let level): return level.label
        case .rating(let n): return "\(n)/10"
        case .spot: return "Sharp, one spot"
        case .trend(.less): return "Less than yesterday" + score
        case .trend(.same): return "Same as yesterday" + score
        case .trend(.worse): return "Worse than yesterday" + score
        case .trend(.gone): return nil
        }
    }

    /// The latest 0–10 value for an area, to compare the next morning against.
    public func lastScore(_ area: BodyArea) -> Int? { latest[area]?.value }
}

/// Corrections to the pain log (D151). Every answer can be changed or deleted; the morning trends
/// after it are worked out again, so a mis-tap never leaves a stale "worse" (and its hold) behind.
public enum PainHistory {
    /// The log with every morning trend recomputed from the 0–10 score before it, oldest first.
    public static func recomputed(_ entries: [PainEntry]) -> [PainEntry] {
        var previous: [BodyArea: Int] = [:]
        return entries.sorted { $0.date < $1.date }.map { e in
            var out = e
            if case .trend = e.kind, let score = e.score {
                out = .morning(area: e.area, date: e.date, score: score, previous: previous[e.area])
                out.side = e.side
                out.feel = e.feel
                out.backPain = e.backPain
            }
            previous[out.area] = out.value
            return out
        }
    }

    /// The log without `entry`, trends recomputed.
    public static func deleting(_ entry: PainEntry, from entries: [PainEntry]) -> [PainEntry] {
        var rest = entries
        if let i = rest.firstIndex(of: entry) { rest.remove(at: i) }
        return recomputed(rest)
    }

    /// The log with `entry`'s 0–10 value changed, trends recomputed. Old word answers become ratings.
    public static func changing(_ entry: PainEntry, to score: Int, in entries: [PainEntry]) -> [PainEntry] {
        var rest = entries
        guard let i = rest.firstIndex(of: entry) else { return recomputed(rest) }
        var changed: PainEntry
        switch entry.kind {
        case .trend: changed = entry; changed.score = score
        case .rating, .report, .spot: changed = PainEntry(area: entry.area, date: entry.date, kind: .rating(score))
        }
        changed.side = entry.side
        changed.feel = entry.feel
        changed.backPain = entry.backPain
        rest[i] = changed
        return recomputed(rest)
    }
}

/// A back flare (D104; research 05 §6): any back or big-toe report starts one. For the first 48 hours
/// runs, lifting and Core B wait; the Big 3 only if it doesn't bring symptoms on. After that the usual
/// morning answers decide. Still going after about a week, or with tingling or numbness, it's worth a
/// GP or physio. A morning "gone" ends it.
public struct BackFlare: Equatable, Sendable {
    public static let easyHours = 48
    public static let clinicianDays = 7

    public let start: Date
    public let easyUntil: Date
    public let days: Int
    public let nerveSign: Bool

    public func easy(now: Date) -> Bool { now < easyUntil }

    public var seeClinician: Bool { nerveSign || days >= Self.clinicianDays }

    public static func current(entries: [PainEntry], now: Date, calendar: Calendar = .current) -> BackFlare? {
        let back = entries.filter { $0.area == .back }.sorted { $0.date < $1.date }
        guard let last = back.last, last.kind != .trend(.gone) else { return nil }
        let lastGone = back.lastIndex { $0.kind == .trend(.gone) }
        let episode = back[(lastGone.map { $0 + 1 } ?? 0)...]
        guard let first = episode.first else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: first.date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return BackFlare(start: first.date,
                         easyUntil: first.date.addingTimeInterval(TimeInterval(easyHours * 3600)),
                         days: days, nerveSign: episode.contains { $0.nerveSign })
    }
}
