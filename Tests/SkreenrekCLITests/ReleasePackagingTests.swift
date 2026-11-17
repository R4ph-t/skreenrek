import Darwin
import Foundation
import Synchronization
import Testing

/// The signed release path: `scripts/release.sh` (Developer ID, hardened runtime, notarized, stapled), the Homebrew
/// cask that installs its zip, and the ad-hoc default that dev builds and `make check` keep. These tests read files
/// and run scripts only up to their argument checks: they never touch the Keychain, sign, notarize or launch the app.
@Suite(.timeLimit(.minutes(1))) struct ReleasePackagingTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The script's commands: comments and `echo` lines dropped, so messages that mention a command don't count.
    static func commands(_ path: String) throws -> [String] {
        try text(path).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("#") && !$0.hasPrefix("echo ") }
    }

    @Test func releaseScriptExistsAndIsExecutable() {
        let path = Self.root.appendingPathComponent("scripts/release.sh").path
        #expect(FileManager.default.isExecutableFile(atPath: path))
    }

    @Test func releaseScriptSignsWithDeveloperIDHardenedRuntimeAndTimestamp() throws {
        let script = try Self.commands("scripts/release.sh").joined(separator: "\n")
        for needle in [
            "--options runtime", "--timestamp", "codesign --verify --deep --strict", "spctl -a -vv",
            "ditto -c -k --keepParent", "notarytool submit", "--wait", "stapler staple", "stapler validate",
            "shasum -a 256", "SKREENREK_SIGN_IDENTITY", "SKREENREK_NOTARY_PROFILE",
            "bundle-app.sh --unsigned",
        ] {
            #expect(script.contains(needle), "release.sh lacks \(needle)")
        }
        let signs = script.split(separator: "\n").filter { $0.contains("codesign --force") }
        #expect(!signs.isEmpty)
        for line in signs {
            #expect(line.contains("--sign \"$identity\""), "\(line)")
            #expect(line.contains("--options runtime") && line.contains("--timestamp"), "\(line)")
        }
    }

    @Test func releaseScriptNeverSignsAdHoc() throws {
        let adHoc = try Regex(#"(--sign|-s)\s+(-|"-"|'-')(\s|$)"#)
        for line in try Self.commands("scripts/release.sh") {
            #expect(line.firstMatch(of: adHoc) == nil, "ad-hoc signing in release.sh: \(line)")
            if line.contains("codesign --force") {
                #expect(!line.contains("--entitlements"), "release.sh signs with an entitlements file: \(line)")
            }
        }
    }

    @Test func releaseScriptNeverTagsOrPublishes() throws {
        for line in try Self.commands("scripts/release.sh") {
            for forbidden in ["gh release", "gh api", "git tag", "git push"] {
                #expect(!line.contains(forbidden), "release.sh runs \(forbidden): \(line)")
            }
        }
    }

    @Test func noEntitlementsFileGrantsGetTaskAllow() throws {
        let fm = FileManager.default
        let enumerator = try #require(fm.enumerator(at: Self.root.appendingPathComponent("packaging"),
                                                    includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "entitlements" {
            #expect(!(try String(contentsOf: url, encoding: .utf8)).contains("get-task-allow"), "\(url.lastPathComponent)")
        }
    }

    /// Dev builds keep the ad-hoc default, and `make check` and `make app` never reach the release script.
    @Test func devBuildsStayAdHoc() throws {
        #expect(try Self.text("scripts/bundle-app.sh").contains("codesign --force --sign - --options runtime"))
        let makefile = try Self.text("Makefile")
        #expect(makefile.contains("release:"))
        #expect(makefile.contains("bash scripts/release.sh \"$(VERSION)\""))
        for target in ["check:", "app:"] {
            let body = makefile.components(separatedBy: "\n\(target)").dropFirst().first?
                .components(separatedBy: "\n\n").first ?? ""
            #expect(!body.isEmpty, "Makefile has no \(target)")
            #expect(!body.contains("release.sh"), "\(target) runs release.sh")
        }
    }

    @Test func caskInstallsTheReleaseZip() throws {
        let cask = try Self.text("Casks/skreenrek.rb")
        #expect(cask.contains(#"cask "skreenrek" do"#))
        #expect(cask.contains(
            #"url "https://github.com/R4ph-t/skreenrek/releases/download/v#{version}/Skreenrek-#{version}.zip""#))
        #expect(cask.firstMatch(of: try Regex(#"(?m)^\s*version "\d+\.\d+\.\d+"$"#)) != nil)
        #expect(cask.firstMatch(of: try Regex(#"(?m)^\s*sha256 "[0-9a-f]{64}"$"#)) != nil)
        #expect(cask.contains(#"app "Skreenrek.app""#))
        #expect(cask.contains(##"binary "#{appdir}/Skreenrek.app/Contents/MacOS/skreenrek""##))
        #expect(cask.contains("depends_on macos: :sequoia"))
        #expect(cask.contains("zap trash:"))
        #expect(cask.contains("~/Library/Application Support/skreenrek"))
    }

    /// The cask's macOS floor matches the app's LSMinimumSystemVersion (15.0 is Sequoia).
    @Test func caskMinimumMatchesInfoPlist() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("packaging/Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["LSMinimumSystemVersion"] as? String == "15.0")
        #expect(try Self.text("Casks/skreenrek.rb").contains(":sequoia"))
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/ruby"), "Ruby isn't installed"))
    func caskRubySyntax() async throws {
        let result = try await Self.run(
            "/usr/bin/ruby", ["-c", Self.root.appendingPathComponent("Casks/skreenrek.rb").path], seconds: 10)
        #expect(result.status == 0, "\(result.stderr)")
    }

    /// release.sh fails loudly, before it touches the Keychain or builds, when the identity or profile is empty or
    /// the identity isn't Developer ID.
    @Test func releaseScriptFailsLoudlyWithoutIdentityOrProfile() async throws {
        let script = Self.root.appendingPathComponent("scripts/release.sh").path
        let cases: [(env: [String: String], args: [String], message: String)] = [
            ([:], [], "usage"),
            ([:], ["1.0"], "isn't x.y.z"),
            (["SKREENREK_SIGN_IDENTITY": ""], ["9.9.9"], "SKREENREK_SIGN_IDENTITY is empty"),
            (["SKREENREK_NOTARY_PROFILE": ""], ["9.9.9"], "SKREENREK_NOTARY_PROFILE is empty"),
            (["SKREENREK_SIGN_IDENTITY": "-"], ["9.9.9"], "must be a 'Developer ID Application"),
            ([:], ["9.9.9"], "bump SkreenrekVersion.current"),
        ]
        for item in cases {
            let result = try await Self.run("/bin/bash", [script] + item.args, environment: item.env, seconds: 10)
            #expect(result.status != 0, "\(item)")
            #expect(result.stderr.contains(item.message), "\(item): \(result.stderr)")
        }
    }

    /// `bundle-app.sh --unsigned` leaves signing to release.sh; the default still signs ad hoc.
    @Test func bundleAppUnsignedLeavesNoSignature() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let products = temp.root.appendingPathComponent("products", isDirectory: true)
        try FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/usr/bin/true"), to: products.appendingPathComponent("skreenrek"))
        let bundle = Self.root.appendingPathComponent("scripts/bundle-app.sh").path

        let unsigned = temp.root.appendingPathComponent("unsigned", isDirectory: true)
        #expect(try await Self.run("/bin/bash", [bundle, "--unsigned", products.path, unsigned.path], seconds: 20)
            .status == 0)
        let app = unsigned.appendingPathComponent("Skreenrek.app").path
        #expect(try await Self.run("/usr/bin/codesign", ["--verify", app], seconds: 10).status != 0)

        let signed = temp.root.appendingPathComponent("signed", isDirectory: true)
        #expect(try await Self.run("/bin/bash", [bundle, products.path, signed.path], seconds: 20).status == 0)
        let details = try await Self.run(
            "/usr/bin/codesign", ["-dv", signed.appendingPathComponent("Skreenrek.app").path], seconds: 10)
        #expect(details.stderr.contains("Signature=adhoc"))
    }

    struct Result: Sendable {
        var status: Int32
        var stderr: String
    }

    /// Runs a process with a hard kill after `seconds`, so a stuck script fails the test instead of hanging it.
    static func run(
        _ executable: String, _ arguments: [String], environment: [String: String] = [:], seconds: Double
    ) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"].merging(environment) { $1 }
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        let finished = Mutex(false)
        return try await within(executable, seconds: seconds) {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { child in
                    let first = finished.withLock { value in
                        guard !value else { return false }
                        value = true
                        return true
                    }
                    guard first else { return }
                    let data = errors.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(
                        returning: Result(status: child.terminationStatus, stderr: String(decoding: data, as: UTF8.self)))
                }
                do { try process.run() }
                catch {
                    finished.withLock { $0 = true }
                    continuation.resume(throwing: error)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds - 1) {
                    if !finished.withLock({ $0 }), process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
    }
}
