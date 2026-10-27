import Foundation

/// The workout that completed a C25K day: either recorded by the coach, or an existing NOOP / Apple
/// Health workout the user linked afterwards. Sprint 0 keeps this in UserDefaults; it moves into the
/// Trainer's own database (B1/B2) so it rides along in `.noopbak` backups.
struct C25KLogEntry: Codable, Equatable {
    enum Source: String, Codable {
        case coach, noop, appleHealth

        var label: String {
            switch self {
            case .coach: return "C25K Coach"
            case .noop: return "NOOP"
            case .appleHealth: return "Apple Health"
            }
        }
    }

    let startTs: Int
    let durationS: Int
    let avgHr: Int?
    let distanceM: Double?
    let source: Source

    var date: Date { Date(timeIntervalSince1970: TimeInterval(startTs)) }
}

/// Persists `C25KLogEntry` per session key ("w2d1").
struct C25KLogStore {
    private static let key = "trainer.c25k.log"

    static func load() -> [String: C25KLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: C25KLogEntry].self, from: data) else { return [:] }
        return decoded
    }

    static func save(_ log: [String: C25KLogEntry]) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
