import Foundation

/// Carries settings over from the legacy bundle ID's defaults, once. The legacy domain is only ever read.
///
/// Files need no move: the app's only folder is `~/Library/Application Support/skreenrek`, which isn't keyed by the
/// bundle ID.
public enum LegacyDefaultsMigration {
    public static let markerKey = "skreenrek.migratedFromLegacyBundleID"

    /// Copies each legacy key the new domain doesn't have, then sets the marker. Does nothing when the legacy domain
    /// is empty or the marker is already set. Reads persistent domains, so global defaults are neither copied nor
    /// mistaken for values already set.
    /// - Parameter excluding: keys that must not carry over.
    /// - Returns: the number of keys copied.
    @discardableResult
    public static func run(
        old: UserDefaults?, oldDomain: String = SkreenrekIdentity.legacyBundleID,
        new: UserDefaults, newDomain: String = SkreenrekIdentity.bundleID,
        excluding: Set<String> = []
    ) -> Int {
        guard let legacy = old?.persistentDomain(forName: oldDomain), !legacy.isEmpty else { return 0 }
        let current = new.persistentDomain(forName: newDomain) ?? [:]
        guard current[markerKey] == nil else { return 0 }
        let copied = legacy.filter { !excluding.contains($0.key) && current[$0.key] == nil }
        for (key, value) in copied { new.set(value, forKey: key) }
        new.set(true, forKey: markerKey)
        return copied.count
    }
}
