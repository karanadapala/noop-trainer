import Combine
import Foundation
import TrainerKit

/// The Regimen's own settings: your goals, places and the health profile (D90, D132, D136, D191). Kept under `trainer.*`
/// keys, so they travel in the backup with the rest of the Trainer's state (`TrainerBackup`).
@MainActor
final class RegimenStore: ObservableObject {
    static let shared = RegimenStore()

    /// The goals you picked in setup (D191). Starts empty: the rail shows only what your plans serve.
    @Published var goals: [Goal] {
        didSet { Self.save(goals, Self.goalsKey) }
    }
    @Published var places: [Place] {
        didSet { Self.save(places, Self.placesKey) }
    }
    @Published var health: HealthProfile {
        didSet { Self.save(health, Self.healthKey) }
    }

    private static let goalsKey = "trainer.goals"
    private static let placesKey = "trainer.places"
    private static let healthKey = "trainer.health"

    private init() {
        goals = Self.decode([Goal].self, Self.goalsKey) ?? []
        places = Self.decode([Place].self, Self.placesKey) ?? Place.presets
        health = Self.decode(HealthProfile.self, Self.healthKey) ?? HealthProfile()
    }

    func place(id: String) -> Place? { places.first { $0.id == id } }

    func save(_ place: Place) {
        if let i = places.firstIndex(where: { $0.id == place.id }) { places[i] = place } else { places.append(place) }
    }

    func deletePlace(_ id: String) { places.removeAll { $0.id == id } }

    func save(_ injury: Injury) {
        if let i = health.injuries.firstIndex(where: { $0.id == injury.id }) {
            health.injuries[i] = injury
        } else {
            health.injuries.append(injury)
        }
    }

    func deleteInjury(_ id: UUID) { health.injuries.removeAll { $0.id == id } }

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}
