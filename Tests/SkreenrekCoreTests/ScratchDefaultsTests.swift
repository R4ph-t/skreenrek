import Foundation
import SkreenrekCore
import Testing

/// Tests and renders once left ~31,000 empty plists in ~/Library/Preferences: a named suite leaves `<name>.plist`
/// behind even after `removePersistentDomain`. These keep it from coming back.
@Suite struct ScratchDefaultsTests {
    static let preferences = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences", isDirectory: true)
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Preference files whose name mentions the scratch directory (other apps may write there meanwhile).
    static func preferenceFiles(mentioning scratch: ScratchDefaults) -> [String] {
        let token = scratch.directory.lastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: preferences.path)) ?? []
        return names.filter { $0.contains(token) }
    }

    @Test func readsAndWritesAndLeavesNothingBehind() {
        let scratch = ScratchDefaults()
        #expect(scratch.suiteName.hasPrefix(scratch.directory.path))
        scratch.defaults.set(42, forKey: "fps")
        scratch.defaults.synchronize()
        // A second instance on the same suite sees the value, and the migration can read it as a domain.
        #expect(UserDefaults(suiteName: scratch.suiteName)?.integer(forKey: "fps") == 42)
        #expect(scratch.defaults.persistentDomain(forName: scratch.suiteName)?["fps"] as? Int == 42)
        #expect(Self.preferenceFiles(mentioning: scratch).isEmpty)

        scratch.remove()
        #expect(!FileManager.default.fileExists(atPath: scratch.directory.path))
        #expect(Self.preferenceFiles(mentioning: scratch).isEmpty)
        scratch.remove()  // A second call is harmless.
    }

    /// Both closure forms run the body on a fresh suite and return its result; removal is `remove()`, tested above.
    @Test func theClosureFormsHandOutAFreshSuite() async {
        let flag = withScratchDefaults { defaults in
            let fresh = defaults.object(forKey: "flag") == nil
            defaults.set(true, forKey: "flag")
            return fresh && defaults.bool(forKey: "flag")
        }
        #expect(flag)

        let value = await withScratchDefaults { defaults in
            await Task.yield()
            defaults.set(7, forKey: "n")
            return defaults.integer(forKey: "n")
        }
        #expect(value == 7)
    }

    /// Only `ScratchDefaults` and the real legacy-bundle-ID migration may open a suite by name.
    @Test func noOtherCodeOpensASuiteByName() throws {
        let call = "UserDefaults" + "(suiteName:"
        let allowed: Set<String> = [
            "Sources/SkreenrekCore/ScratchDefaults.swift",
            "Sources/SkreenrekUI/MenuBarApp.swift",
            "Tests/SkreenrekCoreTests/ScratchDefaultsTests.swift",
        ]
        var offenders: [String] = []
        for folder in ["Sources", "Tests"] {
            let base = Self.root.appendingPathComponent(folder)
            let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
            #expect(!files.isEmpty, "no Swift files under \(folder)")
            for file in files {
                let relative = String(file.path.dropFirst(Self.root.path.count + 1))
                guard !allowed.contains(relative) else { continue }
                if try String(contentsOf: file, encoding: .utf8).contains(call) { offenders.append(relative) }
            }
        }
        #expect(offenders.isEmpty, "use ScratchDefaults instead of a named suite in \(offenders)")
    }
}
