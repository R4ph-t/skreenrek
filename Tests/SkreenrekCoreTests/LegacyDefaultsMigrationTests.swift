import Foundation
import SkreenrekCore
import Testing

@Suite struct LegacyDefaultsMigrationTests {
    /// Two throwaway suites standing in for the legacy and the new domain.
    private struct Domains {
        let oldName = "skreenrek-migration-old.\(UUID().uuidString)"
        let newName = "skreenrek-migration-new.\(UUID().uuidString)"
        let old: UserDefaults
        let new: UserDefaults

        init() {
            old = UserDefaults(suiteName: oldName)!
            new = UserDefaults(suiteName: newName)!
        }

        func cleanUp() {
            old.removePersistentDomain(forName: oldName)
            new.removePersistentDomain(forName: newName)
        }

        @discardableResult
        func migrate(excluding: Set<String> = []) -> Int {
            LegacyDefaultsMigration.run(
                old: old, oldDomain: oldName, new: new, newDomain: newName, excluding: excluding)
        }

        var oldSnapshot: NSDictionary { (old.persistentDomain(forName: oldName) ?? [:]) as NSDictionary }
        var newSnapshot: NSDictionary { (new.persistentDomain(forName: newName) ?? [:]) as NSDictionary }
    }

    private static let marker = LegacyDefaultsMigration.markerKey

    @Test func theBundleIDIsTheShippedOne() {
        #expect(SkreenrekIdentity.bundleID == "com.raphaelterrier.skreenrek")
    }

    @Test func copiesTheKeysAndSetsTheMarker() {
        let domains = Domains()
        defer { domains.cleanUp() }
        domains.old.set("/Volumes/Clips", forKey: "outputFolder")
        domains.old.set(60, forKey: "fps")
        domains.old.set(false, forKey: "cursor")
        domains.old.set([12.0, 34.0], forKey: "hud.position.1")

        #expect(domains.migrate() == 4)
        #expect(domains.new.string(forKey: "outputFolder") == "/Volumes/Clips")
        #expect(domains.new.integer(forKey: "fps") == 60)
        #expect(domains.new.object(forKey: "cursor") as? Bool == false)
        #expect(domains.new.array(forKey: "hud.position.1") as? [Double] == [12, 34])
        #expect(domains.new.bool(forKey: Self.marker))
    }

    @Test func keepsAValueTheNewDomainAlreadyHas() {
        let domains = Domains()
        defer { domains.cleanUp() }
        domains.old.set(30, forKey: "fps")
        domains.old.set(true, forKey: "hud")
        domains.new.set(60, forKey: "fps")

        #expect(domains.migrate() == 1)
        #expect(domains.new.integer(forKey: "fps") == 60)
        #expect(domains.new.bool(forKey: "hud"))
    }

    @Test func aSecondRunChangesNothing() {
        let domains = Domains()
        defer { domains.cleanUp() }
        domains.old.set(30, forKey: "fps")
        domains.migrate()
        // The user changes one setting and clears another after migrating. Neither comes back from the old domain.
        domains.new.set(60, forKey: "fps")
        domains.old.set(true, forKey: "addedLater")
        let before = domains.newSnapshot

        #expect(domains.migrate() == 0)
        #expect(domains.newSnapshot == before)
        #expect(domains.new.integer(forKey: "fps") == 60)
        #expect(domains.new.object(forKey: "addedLater") == nil)
    }

    @Test func doesNothingWhenTheOldDomainIsEmptyOrMissing() {
        let domains = Domains()
        defer { domains.cleanUp() }
        domains.new.set(60, forKey: "fps")
        let before = domains.newSnapshot

        #expect(domains.migrate() == 0)
        #expect(domains.newSnapshot == before)
        #expect(LegacyDefaultsMigration.run(
            old: nil, oldDomain: domains.oldName, new: domains.new, newDomain: domains.newName) == 0)
        #expect(domains.newSnapshot == before)
    }

    @Test func leavesTheOldDomainUntouched() {
        let domains = Domains()
        defer { domains.cleanUp() }
        domains.old.set(30, forKey: "fps")
        domains.old.set("/Volumes/Clips", forKey: "outputFolder")
        let before = domains.oldSnapshot

        domains.migrate()
        domains.new.set(60, forKey: "fps")
        domains.migrate()
        #expect(domains.oldSnapshot == before)
        #expect(domains.old.object(forKey: Self.marker) == nil)
    }

    @Test func skipsExcludedKeys() {
        let domains = Domains()
        defer { domains.cleanUp() }
        domains.old.set(30, forKey: "fps")
        domains.old.set(Date(), forKey: DirectCaptureApproval.key)

        #expect(domains.migrate(excluding: [DirectCaptureApproval.key]) == 1)
        #expect(domains.new.object(forKey: DirectCaptureApproval.key) == nil)
        #expect(domains.new.integer(forKey: "fps") == 30)
    }
}
