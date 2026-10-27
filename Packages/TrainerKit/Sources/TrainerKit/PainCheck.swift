import Foundation

/// Where something hurts (D38).
public enum BodyArea: String, CaseIterable, Codable, Sendable {
    case shins, calves, knees, feet, hips

    public var label: String {
        switch self {
        case .shins: return "Shins"
        case .calves: return "Calves / Achilles"
        case .knees: return "Knees"
        case .feet: return "Feet"
        case .hips: return "Hips"
        }
    }
}

/// How it hurts when reported, after a run or by hand (D49).
public enum PainLevel: String, CaseIterable, Codable, Sendable {
    case mild, worsening, sharp

    public var label: String {
        switch self {
        case .mild: return "Mild"
        case .worsening: return "Getting worse"
        case .sharp: return "Sharp, one spot"
        }
    }
}

/// The next-morning answer for an area reported earlier (D49).
public enum PainTrend: String, CaseIterable, Codable, Sendable {
    case gone, less, same, worse

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
        case report(PainLevel)
        case trend(PainTrend)
    }

    public let area: BodyArea
    public let date: Date
    public let kind: Kind

    public init(area: BodyArea, date: Date, kind: Kind) {
        self.area = area
        self.date = date
        self.kind = kind
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
        for area in BodyArea.allCases {
            guard let e = latest[area], e.kind != .trend(.gone) else { continue }
            active.append(area)
            let isToday = calendar.startOfDay(for: e.date) == today
            if !isToday { needsCheck.append(area) }
            switch e.kind {
            case .report(.sharp):
                holds.append(Hold(area: area, reason: "\(area.label): sharp pain"))
                redFlags = true
            case .trend(.same) where isToday:
                holds.append(Hold(area: area, reason: "\(area.label): same as yesterday"))
            case .trend(.worse) where isToday:
                holds.append(Hold(area: area, reason: "\(area.label): worse than yesterday"))
                redFlags = true
            default:
                break
            }
        }
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        self.active = active
        self.needsCheck = needsCheck
        self.holds = holds
        self.showRedFlags = redFlags
        self.suggestRepeatingWeek = entries.contains { $0.kind == .trend(.worse) && $0.date >= weekAgo }
        self.latest = latest
    }

    /// "Mild" / "Less than yesterday". Nil for an area that isn't active.
    public func summary(_ area: BodyArea) -> String? {
        guard active.contains(area), let e = latest[area] else { return nil }
        switch e.kind {
        case .report(let level): return level.label
        case .trend(.less): return "Less than yesterday"
        case .trend(.same): return "Same as yesterday"
        case .trend(.worse): return "Worse than yesterday"
        case .trend(.gone): return nil
        }
    }
}
