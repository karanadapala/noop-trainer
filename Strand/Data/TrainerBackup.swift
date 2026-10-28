import Foundation

/// NOOP Trainer's own state in the `.noopbak` backup: an extra `trainer.plist` entry holding every
/// `trainer.*` UserDefaults key (the C25K log and progress, the pain log, rest-day sessions and levels,
/// calf-raise tests, restarted weeks). The Trainer keeps these in UserDefaults until it has its own
/// database (B1), and upstream's `settings.json` whitelist only carries upstream's settings, so without
/// this a move to another install (Xcode copy → SideStore copy) loses them.
///
/// A property list keeps each value's type (JSON blobs stay `Data`, the done list stays `[String]`).
/// Importers that don't know the entry skip it, so the backup still restores in upstream NOOP.
enum TrainerBackup {
    static let entryName = "trainer.plist"
    static let keyPrefix = "trainer."

    /// The Trainer's keys as a plist, or nil when there are none (nothing to add to the backup).
    static func snapshot(from defaults: UserDefaults) -> Data? {
        let values = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix(keyPrefix) }
        guard !values.isEmpty else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }

    /// Replaces the Trainer's keys with the backup's: keys the backup doesn't have are removed, so a
    /// restore brings back exactly the state that was saved. Anything that isn't a `trainer.*` key is
    /// ignored. Returns false (and changes nothing) when the entry can't be read.
    @discardableResult
    static func apply(_ data: Data, to defaults: UserDefaults) -> Bool {
        guard let values = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            return false
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in values where key.hasPrefix(keyPrefix) {
            defaults.set(value, forKey: key)
        }
        return true
    }
}
