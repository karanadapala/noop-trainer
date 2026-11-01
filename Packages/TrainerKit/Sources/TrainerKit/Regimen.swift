import Foundation

/// What a plan is for (D124). Insights and the weekly review are per goal; food comes later.
public enum Goal: String, CaseIterable, Codable, Sendable {
    case cardio, strength, mobility, combat

    public var label: String {
        switch self {
        case .cardio: return "Cardio"
        case .strength: return "Strength"
        case .mobility: return "Mobility"
        case .combat: return "Combat"
        }
    }
}

/// How much of the phone a place allows during a session (D132).
public enum PhoneAccess: String, CaseIterable, Codable, Sendable {
    /// Taps between sets and during holds are fine.
    case full
    /// A look at the screen now and then; no taps mid-set. The voice carries the session.
    case glance
    /// The phone stays in a bag: a brief before, a log after.
    case none

    public var label: String {
        switch self {
        case .full: return "Full"
        case .glance: return "A glance"
        case .none: return "None"
        }
    }

    public var detail: String {
        switch self {
        case .full: return "Taps between sets are fine."
        case .glance: return "Voice-led; the log waits until the end."
        case .none: return "A brief before, a log after."
        }
    }
}

public enum WeightUnit: String, CaseIterable, Codable, Sendable {
    case kg, lb

    public var label: String { rawValue }
}

/// One piece of kit at a place (D90, D107–D109). Weights are in the place's unit. The lightest, the
/// heaviest and the step are known up front (dumbbells) or learned from a "Not on this machine" tap.
public struct Equipment: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case dumbbells, bench, pressMachine, legExtensionCurl, legPress, cableColumn, pulldownRow,
             cableCrossover, treadmill, elliptical, bike, floor, pullUpBar, resistanceBand, heavyBag

        public var label: String {
            switch self {
            case .dumbbells: return "Dumbbells"
            case .bench: return "Flat bench"
            case .pressMachine: return "Chest / incline / shoulder press machine"
            case .legExtensionCurl: return "Leg extension / leg curl machine"
            case .legPress: return "Seated leg press"
            case .cableColumn: return "Cable column (top and bottom pulley)"
            case .pulldownRow: return "Lat pulldown and seated row"
            case .cableCrossover: return "Dual cable crossover"
            case .treadmill: return "Treadmill"
            case .elliptical: return "Elliptical"
            case .bike: return "Exercise bike"
            case .floor: return "Floor space and a mat"
            case .pullUpBar: return "Pull-up bar"
            case .resistanceBand: return "Resistance band"
            case .heavyBag: return "Heavy bag"
            }
        }

        /// Kit whose load is set in steps of weight (so suggestions round to it).
        public var isWeighted: Bool {
            switch self {
            case .dumbbells, .pressMachine, .legExtensionCurl, .legPress, .cableColumn, .pulldownRow,
                 .cableCrossover: return true
            default: return false
            }
        }
    }

    public var id: Kind { kind }
    public let kind: Kind
    public var lightest: Double?
    public var heaviest: Double?
    public var step: Double?

    public init(_ kind: Kind, lightest: Double? = nil, heaviest: Double? = nil, step: Double? = nil) {
        self.kind = kind
        self.lightest = lightest
        self.heaviest = heaviest
        self.step = step
    }

    /// The nearest weight this kit has, when its steps are known; otherwise the weight itself.
    public func rounded(_ weight: Double) -> Double {
        var w = weight
        if let step, step > 0 {
            let base = lightest ?? 0
            w = base + ((w - base) / step).rounded() * step
        }
        if let lightest { w = max(w, lightest) }
        if let heaviest { w = min(w, heaviest) }
        return w
    }
}

/// Where a session happens (D90, D91, D132): its unit, its kit and how much phone it allows. Plans and
/// places only meet through this, so a new place needs no plan changes (D97).
public struct Place: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var unit: WeightUnit
    public var phone: PhoneAccess
    public var equipment: [Equipment]

    public init(id: String, name: String, unit: WeightUnit, phone: PhoneAccess, equipment: [Equipment]) {
        self.id = id
        self.name = name
        self.unit = unit
        self.phone = phone
        self.equipment = equipment
    }

    public func has(_ kind: Equipment.Kind) -> Bool { equipment.contains { $0.kind == kind } }

    public func equipment(_ kind: Equipment.Kind) -> Equipment? { equipment.first { $0.kind == kind } }

    /// Starting points the user edits (D91). Only the dumbbells' range is known; machine limits are
    /// learned during sets (D109).
    public static let presets: [Place] = [
        Place(id: "gym", name: "Gym", unit: .lb, phone: .full, equipment: [
            Equipment(.dumbbells, lightest: 5, heaviest: 40, step: 5),
            Equipment(.bench), Equipment(.pressMachine), Equipment(.legExtensionCurl), Equipment(.legPress),
            Equipment(.cableColumn), Equipment(.pulldownRow), Equipment(.cableCrossover),
            Equipment(.treadmill), Equipment(.elliptical), Equipment(.bike), Equipment(.floor),
        ]),
        Place(id: "home", name: "Home", unit: .lb, phone: .full, equipment: [Equipment(.floor)]),
        Place(id: "outdoors", name: "Outdoors", unit: .lb, phone: .glance, equipment: []),
    ]
}
