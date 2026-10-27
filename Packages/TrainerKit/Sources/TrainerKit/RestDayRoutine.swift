import Foundation

/// How the legs feel this morning (D38).
public enum LegFeel: String, CaseIterable, Codable, Sendable {
    case fresh, heavy, sore

    public var label: String {
        switch self {
        case .fresh: return "Fresh"
        case .heavy: return "A bit heavy"
        case .sore: return "Sore"
        }
    }
}

/// The four rest-day routines (D48).
public enum RoutineVariant: String, CaseIterable, Codable, Comparable, Sendable {
    case protect, restore, steady, build

    public static func < (a: RoutineVariant, b: RoutineVariant) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    public var label: String {
        switch self {
        case .build: return "Build"
        case .steady: return "Steady"
        case .restore: return "Restore"
        case .protect: return "Protect"
        }
    }

    public var summary: String {
        switch self {
        case .build: return "Feet, calves, hips and a stretch. The week's main strength session."
        case .steady: return "An easy walk, feet and one strength block, a little lighter."
        case .restore: return "An easy walk, gentle foot drills and stretches. No strength today."
        case .protect: return "Only what doesn't load the sore area. Rest is the work today."
        }
    }
}

/// One exercise at its dose for today.
public struct RoutineItem: Equatable, Sendable {
    public let exercise: Exercise
    public let dose: Dose
}

public struct RestRoutine: Equatable, Sendable {
    public let variant: RoutineVariant
    /// Minutes of easy walking first (0 = none).
    public let walkMinutes: Int
    public let items: [RoutineItem]
    /// Areas left out because they hurt.
    public let skippedAreas: [BodyArea]

    public var estimatedMinutes: Int {
        let work = items.map(\.dose.estimatedSeconds).reduce(0, +)
        let changes = max(0, items.count - 1) * Exercise.changeover
        return walkMinutes + Int((Double(work + changes) / 60).rounded(.up))
    }

    public var blocks: [Block] {
        var seen: [Block] = []
        if walkMinutes > 0 { seen.append(.walk) }
        for item in items where !seen.contains(item.exercise.block) { seen.append(item.exercise.block) }
        return seen
    }
}

/// Picks today's routine (D37, D48, D50) and fills it from the catalogue (D51).
public enum RoutineBuilder {
    public struct Input: Sendable {
        public var charge: Double?
        public var legs: LegFeel
        public var pain: PainState
        /// 1 on the first rest day after a run, 2 on the second in a row, and so on.
        public var restDayInARow: Int
        /// The C25K week of the next run (weeks 1–2 use about half the sets).
        public var programWeek: Int
        /// Each progressive block's current stage (D57).
        public var stages: [Block: Stage]
        /// The strength block done most recently, so Steady days alternate.
        public var lastStrengthBlock: Block?
        /// Rest-day routines done so far; rotates which exercises of each block come up.
        public var rotation: Int

        public init(charge: Double?, legs: LegFeel, pain: PainState, restDayInARow: Int, programWeek: Int,
                    stages: [Block: Stage] = [:], lastStrengthBlock: Block? = nil, rotation: Int = 0) {
            self.charge = charge
            self.legs = legs
            self.pain = pain
            self.restDayInARow = restDayInARow
            self.programWeek = programWeek
            self.stages = stages
            self.lastStrengthBlock = lastStrengthBlock
            self.rotation = rotation
        }
    }

    /// Legs set the routine; Charge only nudges it down; the first rest day after a run is Steady at
    /// most; a hold or a sharp pain means Protect.
    public static func variant(for input: Input) -> RoutineVariant {
        if input.pain.isOnHold || input.pain.showRedFlags { return .protect }
        var v: RoutineVariant
        switch input.legs {
        case .fresh: v = .build
        case .heavy: v = .steady
        case .sore: v = .restore
        }
        switch RestAdvice.band(forCharge: input.charge) {
        case .low: v = min(v, .restore)
        case .moderate: v = min(v, .steady)
        case .high, .unknown: break
        }
        if input.restDayInARow <= 1 { v = min(v, .steady) }
        return v
    }

    /// Minutes of exercise (after any walk) each routine aims for (D42: about 20 / 15 / 10–15 / 5–10
    /// in total). The research's full doses run to an hour if every exercise is done every time, so each
    /// session takes a few exercises per block and rotates through the rest; weekly volume matters more
    /// than frequency (research 03 §8, Grgic 2018).
    static func exerciseBudget(_ v: RoutineVariant) -> Int {
        switch v {
        case .build: return 20 * 60
        case .steady: return 10 * 60
        case .restore: return 6 * 60
        case .protect: return 8 * 60
        }
    }

    public static func routine(for input: Input, variant chosen: RoutineVariant? = nil) -> RestRoutine {
        let variant = chosen ?? variant(for: input)
        let sore = Set(input.pain.active)
        let halfVolume = input.programWeek <= 2

        func stage(_ block: Block) -> Stage { input.stages[block] ?? .learn }
        /// `count` exercises from the block, rotated so each session brings up the next ones.
        func pick(_ block: Block, _ count: Int, stageOverride: Stage? = nil, setsDelta: Int = 0,
                  excluding: Set<String> = []) -> [RoutineItem] {
            let pool = RestDayCatalogue.exercises(in: block)
                .filter { $0.loads.isDisjoint(with: sore) && !excluding.contains($0.id) }
            guard !pool.isEmpty else { return [] }
            let start = input.rotation % pool.count
            let rotated = Array(pool[start...] + pool[..<start])
            return rotated.prefix(count).map { ex in
                var dose = ex.dose(stageOverride ?? stage(block))
                if halfVolume { dose = dose.withSets((dose.sets + 1) / 2) }
                if setsDelta != 0 { dose = dose.withSets(dose.sets + setsDelta) }
                return RoutineItem(exercise: ex, dose: dose)
            }
        }

        var walk = 0
        var list: [RoutineItem] = []
        switch variant {
        case .build:
            list = pick(.footBalance, 1) + pick(.lowerLeg, 2) + pick(.hipThigh, 2) + pick(.mobility, 1)
        case .steady:
            let strength: Block = input.lastStrengthBlock == .lowerLeg ? .hipThigh : .lowerLeg
            walk = 5
            list = pick(.footBalance, 1) + pick(strength, 2, setsDelta: -1) + pick(.mobility, 1)
        case .restore:
            walk = 10
            list = pick(.footBalance, 1, stageOverride: .learn, excluding: ["balance"]) + pick(.mobility, 2)
        case .protect:
            list = pick(.footBalance, 1, stageOverride: .learn, excluding: ["balance"]) + pick(.mobility, 2)
        }
        list = fit(list, within: exerciseBudget(variant))
        let skipped = BodyArea.allCases.filter { area in
            sore.contains(area) && RestDayCatalogue.all.contains { $0.loads.contains(area) }
        }
        return RestRoutine(variant: variant, walkMinutes: walk, items: list, skippedAreas: skipped)
    }

    /// Trims to the time budget: a set off the longest strength item first (never below 2 sets while
    /// any item has more), then stretches go, then whole items from the end.
    static func fit(_ items: [RoutineItem], within budget: Int) -> [RoutineItem] {
        var list = items
        func total() -> Int {
            list.map(\.dose.estimatedSeconds).reduce(0, +) + max(0, list.count - 1) * Exercise.changeover
        }
        while total() > budget {
            if let i = list.indices.filter({ list[$0].dose.sets > 2 })
                .max(by: { list[$0].dose.estimatedSeconds < list[$1].dose.estimatedSeconds }) {
                list[i] = RoutineItem(exercise: list[i].exercise, dose: list[i].dose.withSets(list[i].dose.sets - 1))
            } else if let i = list.lastIndex(where: { $0.exercise.optional }), list.count > 1 {
                list.remove(at: i)
            } else if let i = list.indices.filter({ list[$0].dose.sets > 1 })
                .max(by: { list[$0].dose.estimatedSeconds < list[$1].dose.estimatedSeconds }) {
                list[i] = RoutineItem(exercise: list[i].exercise, dose: list[i].dose.withSets(list[i].dose.sets - 1))
            } else if list.count > 1 {
                list.removeLast()
            } else {
                break
            }
        }
        return list
    }
}
