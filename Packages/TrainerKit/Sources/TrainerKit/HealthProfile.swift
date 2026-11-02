import Foundation

/// A part of the body an injury belongs to. Wider than `BodyArea`, which only lists what a run can
/// make sore; the back has no pain check yet (that comes with Back care, D104).
public enum BodyRegion: String, CaseIterable, Codable, Sendable {
    case lowerBack, hips, knees, shins, calves, feet, shoulders, other

    public var label: String {
        switch self {
        case .lowerBack: return "Lower back"
        case .hips: return "Hips"
        case .knees: return "Knees"
        case .shins: return "Shins"
        case .calves: return "Calves / Achilles"
        case .feet: return "Feet"
        case .shoulders: return "Shoulders"
        case .other: return "Somewhere else"
        }
    }

    /// The area the morning check asks about, where there is one.
    public var bodyArea: BodyArea? {
        switch self {
        case .hips: return .hips
        case .knees: return .knees
        case .shins: return .shins
        case .calves: return .calves
        case .feet: return .feet
        case .lowerBack: return .back
        case .shoulders, .other: return nil
        }
    }
}

/// Signs that mean stop and get checked, grouped by how soon (D104, D113, research 03 and 05).
/// Advice to show, not a diagnosis.
public struct RedFlags: Equatable, Sendable {
    public let urgent: [String]
    public let soon: [String]

    public static func `for`(_ region: BodyRegion) -> RedFlags {
        switch region {
        case .lowerBack:
            return RedFlags(
                urgent: ["Numbness around the groin, inner thighs or buttocks",
                         "New trouble passing urine, or with bladder or bowel control",
                         "Weakness or numbness in both legs"],
                soon: ["Leg weakness that's getting worse, or the foot catching or slapping when you walk",
                       "Pain after a hard fall",
                       "Back pain with a fever or weight loss you can't explain",
                       "Pain that's there all night, whatever position you're in",
                       "Tingling or numbness down one leg that doesn't settle within a few days"])
        case .shins, .feet:
            return RedFlags(
                urgent: ["Unable to put weight on the leg after a fall or twist",
                         "Numbness on top of the foot during a run, or pain that doesn't ease with rest"],
                soon: ["Pain in one small spot on a bone that hurts to press with a fingertip",
                       "Pain that starts sooner each run, or hurts at rest or at night",
                       "Pain that's worse each morning"])
        case .calves:
            return RedFlags(
                urgent: ["A hot, red, swollen calf",
                         "A sudden snap or kick at the back of the ankle"],
                soon: ["Achilles or heel stiffness on your first steps in the morning, getting worse week by week"])
        case .knees, .hips:
            return RedFlags(
                urgent: ["Unable to put weight on the leg, or the joint locks or gives way",
                         "A hot, swollen joint with a fever"],
                soon: ["Pain that wakes you at night",
                       "Swelling that comes back after each session"])
        case .shoulders:
            return RedFlags(
                urgent: ["Shoulder or arm pain with chest pain or breathlessness",
                         "Unable to lift the arm after a fall"],
                soon: ["Pain that wakes you at night", "Weakness lifting the arm to the side"])
        case .other:
            return RedFlags(urgent: ["Chest pain, fainting or severe breathlessness while exercising"],
                            soon: ["Pain that's getting worse week by week"])
        }
    }
}

/// One injury, past or present, in the user's own words (D136). Every plan reads the same profile
/// instead of carrying its own injury notes.
public struct Injury: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, CaseIterable, Codable, Sendable {
        case active, settled

        public var label: String { self == .active ? "Still bothers me" : "Settled" }
    }

    public var id: UUID
    public var region: BodyRegion
    public var side: PainSide?
    public var title: String
    /// When it started, as the user says it ("2019", "Oct 2026").
    public var since: String
    public var status: Status
    /// What a GP, physio or scan said.
    public var cliniciansSaid: String
    /// Anything else: what sets it off, what helps.
    public var notes: String

    public init(id: UUID = UUID(), region: BodyRegion, side: PainSide? = nil, title: String, since: String = "",
                status: Status = .active, cliniciansSaid: String = "", notes: String = "") {
        self.id = id
        self.region = region
        self.side = side
        self.title = title
        self.since = since
        self.status = status
        self.cliniciansSaid = cliniciansSaid
        self.notes = notes
    }

    public var redFlags: RedFlags { .for(region) }
}

public struct HealthProfile: Codable, Equatable, Sendable {
    public var injuries: [Injury]

    public init(injuries: [Injury] = []) {
        self.injuries = injuries
    }

    public var active: [Injury] { injuries.filter { $0.status == .active } }

    /// Regions with an injury on file, active first, for the red-flag sheet.
    public var regions: [BodyRegion] {
        var seen: [BodyRegion] = []
        for i in active + injuries where !seen.contains(i.region) { seen.append(i.region) }
        return seen
    }

    public func injuries(in region: BodyRegion) -> [Injury] { injuries.filter { $0.region == region } }
}
