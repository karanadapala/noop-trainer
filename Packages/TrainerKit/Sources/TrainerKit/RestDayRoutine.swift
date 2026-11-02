import Foundation

/// How the legs feel this morning (D38), anchored on what they let you do rather than on a feeling,
/// since "sore" means different things to different people.
public enum LegFeel: String, CaseIterable, Codable, Sendable {
    case fresh, usual, limiting

    public var label: String {
        switch self {
        case .fresh: return "Fresh"
        case .usual: return "Usual after a run"
        case .limiting: return "Getting in the way"
        }
    }

    public var detail: String {
        switch self {
        case .fresh: return "Nothing to notice."
        case .usual: return "Stiff, heavy or a bit sore, but walking and stairs feel normal."
        case .limiting: return "Walking or stairs feel it, or it's more than your usual."
        }
    }
}

/// The four rest-day routines (D48).
public enum RoutineVariant: String, CaseIterable, Codable, Comparable, Sendable {
    /// The five easy minutes for shins, calves and feet after a run (D110, D118); not a rest-day choice.
    case base
    case protect, restore, steady, build
    /// Back care (D98–D100): the Big 3, and the anti-movement work after lifting. Logged by Back care,
    /// not as rest-day routines.
    case coreA, coreB

    /// The routines a rest day can be swapped between.
    public static let restDay: [RoutineVariant] = [.protect, .restore, .steady, .build]

    public static func < (a: RoutineVariant, b: RoutineVariant) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    public var label: String {
        switch self {
        case .base: return "Base"
        case .build: return "Build"
        case .steady: return "Steady"
        case .restore: return "Restore"
        case .protect: return "Protect"
        case .coreA: return "Big 3"
        case .coreB: return "Core B"
        }
    }

    /// How the coach introduces it.
    public var spokenName: String {
        switch self {
        case .coreA: return "The Big 3"
        case .coreB: return "Core B"
        default: return "\(label) routine"
        }
    }

    /// Back care's sessions, which don't count as rest-day routines.
    public var isBackCare: Bool { self == .coreA || self == .coreB }

    public var summary: String {
        switch self {
        case .base: return "Five easy minutes for shins, calves and feet."
        case .build: return "Feet, calves, hips and a stretch. The week's main strength session."
        case .steady: return "An easy walk, feet and one strength block, a little lighter."
        case .restore: return "An easy walk, gentle foot drills and stretches. No strength today."
        case .protect: return "Nothing that loads an area with a red flag. Rest is the work today."
        case .coreA: return "Curl-up, side plank and bird dog: short holds, never to failure."
        case .coreB: return "Resist twisting, leaning and arching, after the lifts."
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
    /// Areas left out because of a red flag (D113).
    public let skippedAreas: [BodyArea]
    /// Sore areas trained first with easy work (D113, D118).
    public let focusAreas: [BodyArea]

    /// Spoken at the start whenever a sore area is trained (D115).
    public var painRule: String? {
        focusAreas.isEmpty ? nil
            : "Keep it at 3 out of 10 or less. If it climbs during a set, stop that exercise. It should be no worse tomorrow morning."
    }
    /// The stage each progressive block in it is done at (logged for D57).
    public let stages: [Block: Stage]

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
        /// Areas with a focused block from `FocusAreas` (D118); sore areas join them.
        public var focus: [BodyArea]
        /// A walk is already done today (the getting-back-to-running walk), so the routine skips its own.
        public var walkedToday: Bool
        /// Exercises another plan covers today (Back care's side plank replaces this one, D99).
        public var leaveOut: Set<String>

        public init(charge: Double?, legs: LegFeel, pain: PainState, restDayInARow: Int, programWeek: Int,
                    stages: [Block: Stage] = [:], lastStrengthBlock: Block? = nil, rotation: Int = 0,
                    focus: [BodyArea] = [], walkedToday: Bool = false, leaveOut: Set<String> = []) {
            self.focus = focus
            self.walkedToday = walkedToday
            self.leaveOut = leaveOut
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
    /// most; a red flag means Protect, and a hold without one means Steady at most (D113).
    public static func variant(for input: Input) -> RoutineVariant {
        if input.pain.showRedFlags { return .protect }
        var v: RoutineVariant
        switch input.legs {
        case .fresh: v = .build
        case .usual: v = .steady
        case .limiting: v = .restore
        }
        switch RestAdvice.band(forCharge: input.charge) {
        case .low: v = min(v, .restore)
        case .moderate: v = min(v, .steady)
        case .high, .unknown: break
        }
        if input.restDayInARow <= 1 || input.pain.isOnHold { v = min(v, .steady) }
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
        case .base: return 5 * 60
        case .coreA, .coreB: return 12 * 60
        }
    }

    /// The focused block for sore areas is capped on its own (D118).
    static let focusBudget = 10 * 60

    /// Sore areas (no red flag) plus the focus areas, at most two (D118).
    static func focusAreas(_ input: Input) -> [BodyArea] {
        let flagged = Set(input.pain.redFlagAreas)
        var out: [BodyArea] = []
        for area in input.pain.active + input.focus where !flagged.contains(area) && !out.contains(area) {
            out.append(area)
        }
        return Array(out.prefix(FocusAreas.maxAreas))
    }

    /// Easy work for each focus area, at the first stage's dose (research 06 §7a: these are daily-safe).
    static func focusItems(_ areas: [BodyArea], perArea: Int, avoiding flagged: Set<BodyArea>) -> [RoutineItem] {
        var seen: Set<String> = []
        var out: [RoutineItem] = []
        for area in areas {
            let picks = RestDayCatalogue.easy(for: area)
                .filter { $0.loads.isDisjoint(with: flagged) && !seen.contains($0.id) }
                .prefix(perArea)
            for ex in picks {
                seen.insert(ex.id)
                out.append(RoutineItem(exercise: ex, dose: ex.dose(.learn)))
            }
        }
        return fit(out, within: focusBudget)
    }

    /// The evening of a run stopped for pain (research 06 §7c): foot core only, if it's painless.
    public static func stopDay(pain: PainState) -> RestRoutine {
        let flagged = Set(pain.redFlagAreas)
        let items = ["shortFoot", "toeYoga"]
            .compactMap { id in RestDayCatalogue.all.first { $0.id == id } }
            .filter { $0.loads.isDisjoint(with: flagged) }
            .map { RoutineItem(exercise: $0, dose: $0.dose(.learn)) }
        return RestRoutine(variant: .protect, walkMinutes: 0, items: items, skippedAreas: pain.redFlagAreas,
                           focusAreas: [], stages: [:])
    }

    /// The base block (D118): about five easy minutes of shins, calves and feet after a run, with the
    /// focus areas' easy work first. One set each; nothing loads an area with a red flag.
    public static func base(pain: PainState, focus: [BodyArea], leaveOut: Set<String> = []) -> RestRoutine {
        let input = Input(charge: nil, legs: .usual, pain: pain, restDayInARow: 0, programWeek: 1, focus: focus)
        let areas = focusAreas(input)
        let flagged = Set(pain.redFlagAreas)
        let focused = focusItems(areas, perArea: 2, avoiding: flagged).filter { !leaveOut.contains($0.exercise.id) }
        let taken = Set(focused.map(\.exercise.id))
        let everyday = ["tibRaise", "bentKneeCalf", "shortFoot", "toeYoga", "balance"]
            .compactMap { id in RestDayCatalogue.all.first { $0.id == id } }
            .filter { $0.loads.isDisjoint(with: flagged) && !taken.contains($0.id) && !leaveOut.contains($0.id) }
            .map { RoutineItem(exercise: $0, dose: $0.dose(.learn).withSets(1)) }
        return RestRoutine(variant: .base, walkMinutes: 0, items: focused + fit(everyday, within: exerciseBudget(.base)),
                           skippedAreas: pain.redFlagAreas, focusAreas: areas, stages: [:])
    }

    public static func routine(for input: Input, variant chosen: RoutineVariant? = nil) -> RestRoutine {
        let variant = chosen ?? variant(for: input)
        // Sore areas get easy focused work instead of the everyday rotation's harder items; red-flag
        // areas get nothing that loads them (D113).
        let sore = Set(input.pain.active)
        let flagged = Set(input.pain.redFlagAreas)
        let areas = focusAreas(input)
        let halfVolume = input.programWeek <= 2

        func stage(_ block: Block) -> Stage { input.stages[block] ?? .learn }
        var used: [Block: Stage] = [:]
        /// `count` exercises from the block, rotated so each session brings up the next ones.
        func pick(_ block: Block, _ count: Int, stageOverride: Stage? = nil, setsDelta: Int = 0,
                  excluding: Set<String> = []) -> [RoutineItem] {
            let pool = RestDayCatalogue.exercises(in: block)
                .filter { $0.loads.isDisjoint(with: sore) && !excluding.contains($0.id) && !input.leaveOut.contains($0.id) }
            guard !pool.isEmpty else { return [] }
            let start = input.rotation % pool.count
            let rotated = Array(pool[start...] + pool[..<start])
            if Block.progressive.contains(block) { used[block] = stageOverride ?? stage(block) }
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
        case .base, .coreA, .coreB:
            return base(pain: input.pain, focus: input.focus, leaveOut: input.leaveOut)
        }
        let focused = focusItems(areas, perArea: variant >= .steady ? 3 : 2, avoiding: flagged)
            .filter { !input.leaveOut.contains($0.exercise.id) }
        let focusedIDs = Set(focused.map(\.exercise.id))
        list = fit(list.filter { !focusedIDs.contains($0.exercise.id) }, within: exerciseBudget(variant))
        let kept = Set(list.map(\.exercise.block))
        if input.walkedToday { walk = 0 }
        return RestRoutine(variant: variant, walkMinutes: walk, items: focused + list,
                           skippedAreas: input.pain.redFlagAreas, focusAreas: areas,
                           stages: used.filter { kept.contains($0.key) })
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
