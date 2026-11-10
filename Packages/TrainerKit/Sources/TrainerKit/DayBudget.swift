import Foundation

/// The buffers and rounding behind today's time (D230, D235). Decoded key by key, so a stored copy keeps
/// working when a setting is added.
public struct DayBudgetOptions: Codable, Equatable, Sendable {
    /// Minutes to get going at each place (changing, the walk there, setting up), counted once per place
    /// on the day. Keys are Places ids.
    public var buffers: [String: Int] = ["home": 5, "gym": 10, "outdoors": 5]
    /// For a place with no buffer of its own, or a plan that doesn't say where.
    public var otherBuffer = 5
    /// "Keep … free" rounds up to this many minutes.
    public var roundTo = 15

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DayBudgetOptions()
        buffers = try c.decodeIfPresent([String: Int].self, forKey: .buffers) ?? d.buffers
        otherBuffer = try c.decodeIfPresent(Int.self, forKey: .otherBuffer) ?? d.otherBuffer
        roundTo = try c.decodeIfPresent(Int.self, forKey: .roundTo) ?? d.roundTo
    }

    public func buffer(at placeID: String?) -> Int { placeID.flatMap { buffers[$0] } ?? otherBuffer }
}

/// How long today's regimen takes, so you know before you start (D235): every active plan's sessions
/// still to do today, plus getting going at each place.
public struct DayBudget: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public let planID: String
        public let title: String
        /// Nil once it's done.
        public let minutes: Int?
        public var done: Bool { minutes == nil }
    }

    /// One per plan with something today, done or still to do, in plan order.
    public let items: [Item]
    /// Minutes of training still to do.
    public let minutes: Int
    /// Getting going, once per place still to visit today.
    public let buffer: Int
    /// `minutes + buffer`, rounded up.
    public let keepFree: Int

    public init(plans: [any TrainingPlan], day: RegimenDay, options: DayBudgetOptions) {
        var items: [Item] = []
        var places: [String?] = []
        for (plan, today) in zip(plans, day.plans) {
            if today.status == .done {
                items.append(Item(planID: plan.id, title: plan.title, minutes: nil))
            } else if let m = today.minutes, today.status == .session || today.laterToday {
                items.append(Item(planID: plan.id, title: plan.title, minutes: m))
                if !places.contains(plan.placeID) { places.append(plan.placeID) }
            }
        }
        self.items = items
        minutes = items.compactMap(\.minutes).reduce(0, +)
        buffer = minutes == 0 ? 0 : places.map(options.buffer(at:)).reduce(0, +)
        let step = max(1, options.roundTo)
        keepFree = (minutes + buffer + step - 1) / step * step
    }

    /// Nothing left to do today.
    public var clear: Bool { minutes == 0 }

    /// "45 min", "an hour", "1 h 15", "2 hours".
    public static func spoken(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return h == 1 ? "an hour" : "\(h) hours" }
        return "\(h) h \(m)"
    }
}
