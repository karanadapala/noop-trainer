import Foundation

/// The building blocks of a C25K rest day (research 03 §11, D47).
public enum Block: String, CaseIterable, Codable, Sendable {
    case footBalance, lowerLeg, hipThigh, mobility, walk

    public var label: String {
        switch self {
        case .footBalance: return "Feet and balance"
        case .lowerLeg: return "Calves and shins"
        case .hipThigh: return "Hips and thighs"
        case .mobility: return "Stretches"
        case .walk: return "Easy walk"
        }
    }

    /// Blocks whose stage moves up over the 9 weeks (D57).
    public static let progressive: [Block] = [.footBalance, .lowerLeg, .hipThigh]
}

/// Three stages over the 9 weeks: weeks 1–3, 4–6 and 7–9 (D51).
public enum Stage: Int, CaseIterable, Codable, Comparable, Sendable {
    case learn = 1, build, strengthen

    public static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }

    /// The stage the calendar allows in a given C25K week.
    public static func forWeek(_ week: Int) -> Stage {
        switch week {
        case ..<4: return .learn
        case 4...6: return .build
        default: return .strengthen
        }
    }

    public var label: String {
        switch self {
        case .learn: return "Learn"
        case .build: return "Build"
        case .strengthen: return "Strengthen"
        }
    }
}

/// How much of an exercise: sets of reps (tempo-called), sets of holds, or reps that each hold.
public struct Dose: Equatable, Sendable {
    public enum Work: Equatable, Sendable {
        /// Tempo reps: 2 s up, 1 s pause, 3 s down unless the exercise says otherwise.
        case reps(Int)
        /// One hold of this many seconds per set.
        case hold(Int)
        /// Reps that each hold for some seconds (short foot: 8 × 5 s).
        case heldReps(Int, holdSeconds: Int)
    }

    public let sets: Int
    public let work: Work
    /// Done on each leg (or side) in turn.
    public let perSide: Bool
    /// What changes at this stage, spoken and shown: "Seated", "Single-leg on the stair edge".
    public let variant: String

    public init(sets: Int, _ work: Work, perSide: Bool = false, variant: String) {
        self.sets = sets
        self.work = work
        self.perSide = perSide
        self.variant = variant
    }

    public func withSets(_ n: Int) -> Dose { Dose(sets: max(1, n), work, perSide: perSide, variant: variant) }

    /// Seconds of work and rest, for estimating a routine's length.
    public var estimatedSeconds: Int {
        let perSet: Int
        switch work {
        case .reps(let n): perSet = n * Exercise.secondsPerRep
        case .hold(let s): perSet = s
        case .heldReps(let n, let hold): perSet = n * (hold + 2)
        }
        let rounds = sets * (perSide ? 2 : 1)
        return rounds * perSet + (rounds - 1) * Exercise.restBetweenSets
    }
}

/// One rest-day exercise with its three stages (D51), fitted to the user's kit (D41): a wall, a chair,
/// the condo stairs, a light band, 1.5 kg dumbbells and a mat. The stool is not used for load (D60).
public struct Exercise: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let block: Block
    /// One line, spoken and shown (D40).
    public let howTo: String
    /// A trusted free source for the first time (D40).
    public let link: URL?
    /// Areas this exercise loads; it's left out while any of them hurts (D48, D56).
    public let loads: Set<BodyArea>
    /// Optional comfort work (stretches), dropped first when time is short.
    public let optional: Bool
    private let doses: [Stage: Dose]

    public func dose(_ stage: Stage) -> Dose { doses[stage] ?? doses[.learn]! }

    static let secondsPerRep = 6       // 2 up, 1 pause, 3 down
    static let restBetweenSets = 20
    static let changeover = 15         // between exercises

    init(_ id: String, _ name: String, _ block: Block, howTo: String, link: String?, loads: Set<BodyArea>,
         optional: Bool = false, _ doses: [Stage: Dose]) {
        self.id = id
        self.name = name
        self.block = block
        self.howTo = howTo
        self.link = link.flatMap(URL.init(string:))
        self.loads = loads
        self.optional = optional
        self.doses = doses
    }
}

public enum RestDayCatalogue {
    static let nhsStrength = "https://www.nhs.uk/live-well/exercise/strength-exercises/"
    static let nhsKnee = "https://www.nhs.uk/live-well/exercise/knee-exercises-for-runners/"
    static let nhsFlex = "https://www.nhs.uk/live-well/exercise/flexibility-exercises/"

    public static let all: [Exercise] = [
        Exercise("shortFoot", "Short foot", .footBalance,
                 howTo: "Pull the ball of your foot towards your heel to lift the arch. Toes stay relaxed and flat.",
                 link: nil, loads: [.feet],
                 [.learn: Dose(sets: 2, .heldReps(8, holdSeconds: 5), perSide: true, variant: "Seated"),
                  .build: Dose(sets: 3, .heldReps(8, holdSeconds: 5), perSide: true, variant: "Standing"),
                  .strengthen: Dose(sets: 3, .heldReps(8, holdSeconds: 5), perSide: true, variant: "Standing on one leg")]),
        Exercise("toeYoga", "Toe yoga", .footBalance,
                 howTo: "Lift your big toe while the others stay down, then swap: little toes up, big toe down.",
                 link: nil, loads: [.feet],
                 [.learn: Dose(sets: 2, .reps(8), variant: "Seated"),
                  .build: Dose(sets: 2, .reps(10), variant: "Standing"),
                  .strengthen: Dose(sets: 3, .reps(10), variant: "Standing")]),
        Exercise("balance", "Single-leg balance", .footBalance,
                 howTo: "Stand on one leg next to the wall, knee soft, arch lifted. Touch the wall only if you need to.",
                 link: nhsStrength, loads: [.feet],
                 [.learn: Dose(sets: 3, .hold(30), perSide: true, variant: "Eyes open"),
                  .build: Dose(sets: 3, .hold(30), perSide: true, variant: "Eyes closed, or on the folded mat"),
                  .strengthen: Dose(sets: 3, .hold(30), perSide: true, variant: "With a slow reach forward")]),
        Exercise("bentKneeCalf", "Bent-knee calf raise", .lowerLeg,
                 howTo: "Knees slightly bent, hands on the wall. Rise onto the balls of your feet, then lower slowly.",
                 link: nil, loads: [.calves, .feet],
                 [.learn: Dose(sets: 2, .reps(12), variant: "Both legs"),
                  .build: Dose(sets: 3, .reps(10), perSide: true, variant: "One leg"),
                  .strengthen: Dose(sets: 3, .reps(15), perSide: true, variant: "One leg on the stair edge, holding the dumbbells")]),
        Exercise("straightKneeCalf", "Straight-knee calf raise", .lowerLeg,
                 howTo: "Legs straight, hands on the wall. Rise high onto the balls of your feet, then lower slowly.",
                 link: nil, loads: [.calves, .feet],
                 [.learn: Dose(sets: 2, .reps(12), variant: "Both legs"),
                  .build: Dose(sets: 3, .reps(10), perSide: true, variant: "One leg"),
                  .strengthen: Dose(sets: 3, .reps(12), perSide: true, variant: "One leg on the stair edge, 3-second lowering")]),
        Exercise("tibRaise", "Tibialis raise", .lowerLeg,
                 howTo: "Back against the wall, heels a foot away. Lift your toes towards your shins, then lower.",
                 link: nil, loads: [.shins],
                 [.learn: Dose(sets: 2, .reps(10), variant: "Both feet"),
                  .build: Dose(sets: 2, .reps(15), variant: "Both feet"),
                  .strengthen: Dose(sets: 3, .reps(20), variant: "Both feet")]),
        Exercise("bridge", "Glute bridge", .hipThigh,
                 howTo: "On your back on the mat, knees bent. Squeeze your glutes to lift your hips, hold, lower.",
                 link: nhsStrength, loads: [.hips],
                 [.learn: Dose(sets: 2, .reps(10), variant: "Two-second hold at the top"),
                  .build: Dose(sets: 3, .reps(12), variant: "Two-second hold at the top"),
                  .strengthen: Dose(sets: 3, .reps(10), perSide: true, variant: "One leg")]),
        Exercise("sideLegRaise", "Side-lying leg raise", .hipThigh,
                 howTo: "Lie on your side, bottom knee bent. Lift the top leg, slightly behind you, toes forward.",
                 link: nil, loads: [.hips],
                 [.learn: Dose(sets: 2, .reps(10), perSide: true, variant: "No band"),
                  .build: Dose(sets: 3, .reps(12), perSide: true, variant: "Band around your knees"),
                  .strengthen: Dose(sets: 3, .reps(15), perSide: true, variant: "Band around your knees")]),
        Exercise("sidePlank", "Side plank", .hipThigh,
                 howTo: "On your forearm, body in a straight line from head to knees or feet. Hips stay high.",
                 link: nil, loads: [.hips],
                 [.learn: Dose(sets: 2, .hold(15), perSide: true, variant: "From the knees"),
                  .build: Dose(sets: 3, .hold(25), perSide: true, variant: "From the knees or feet"),
                  .strengthen: Dose(sets: 3, .hold(35), perSide: true, variant: "From the feet")]),
        Exercise("squat", "Sit-to-stand, then split squat", .hipThigh,
                 howTo: "Stand up from the chair without your hands. Later: one foot forward, lower the back knee.",
                 link: nhsKnee, loads: [.knees, .hips],
                 [.learn: Dose(sets: 2, .reps(10), variant: "Sit-to-stand from the chair"),
                  .build: Dose(sets: 2, .reps(8), perSide: true, variant: "Split squat"),
                  .strengthen: Dose(sets: 3, .reps(10), perSide: true, variant: "Split squat holding the dumbbells")]),
        Exercise("calfStretch", "Calf stretch", .mobility,
                 howTo: "Hands on the wall, one leg back, heel down. Straight knee, then bend it slightly.",
                 link: nhsFlex, loads: [.calves], optional: true,
                 [.learn: Dose(sets: 2, .hold(30), perSide: true, variant: "Straight, then bent knee")]),
        Exercise("hipFlexorStretch", "Hip-flexor stretch", .mobility,
                 howTo: "Kneel on the folded mat, one foot forward. Tuck your hips under and lean gently forward.",
                 link: nhsFlex, loads: [.hips, .knees], optional: true,
                 [.learn: Dose(sets: 2, .hold(30), perSide: true, variant: "Kneeling on the folded mat")]),
    ]

    public static func exercises(in block: Block) -> [Exercise] { all.filter { $0.block == block } }
}
