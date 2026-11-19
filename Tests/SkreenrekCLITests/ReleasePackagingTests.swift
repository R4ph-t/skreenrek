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

    /// Dev builds keep the ad-hoc default, and `make check` and `make app` never reach the release script. They sign
    /// without the hardened runtime: its library validation refuses an ad-hoc Sparkle.framework (no team to match).
    @Test func devBuildsStayAdHoc() throws {
        let signs = try Self.commands("scripts/bundle-app.sh").filter { $0.contains("codesign --force") }
        #expect(signs.count == 2)
        for line in signs {
            #expect(line.contains("--sign -"), "\(line)")
            #expect(!line.contains("--options runtime") && !line.contains("--entitlements"), "\(line)")
        }
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
        // Sparkle updates the app in place, so Homebrew leaves upgrades to it.
        #expect(cask.contains("\n  auto_updates true\n  depends_on macos: :sequoia\n"))
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
            ([:], ["--dry-run"], "usage"),
            ([:], ["--dry-run", "1.0"], "isn't x.y.z"),
            // A dry run never notarizes, so it doesn't need a notary profile.
            (["SKREENREK_NOTARY_PROFILE": ""], ["--dry-run", "9.9.9"], "bump SkreenrekVersion.current"),
        ]
        for item in cases {
            let result = try await Self.run("/bin/bash", [script] + item.args, environment: item.env, seconds: 10)
            #expect(result.status != 0, "\(item)")
            #expect(result.stderr.contains(item.message), "\(item): \(result.stderr)")
        }
    }

    /// The Sparkle.framework `swift build` unpacked (the xcframework's macOS slice is what it copies into the products).
    static var sparkleFramework: URL {
        root.appendingPathComponent(".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework")
    }

    /// A products folder like `swift build`'s: a stand-in `skreenrek` executable and Sparkle.framework next to it.
    static func products(in temp: ShortTemp, sparkle: Bool = true) async throws -> URL {
        let products = temp.root.appendingPathComponent("products", isDirectory: true)
        try FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/usr/bin/true"), to: products.appendingPathComponent("skreenrek"))
        if sparkle {
            let source = sparkleFramework.path
            #expect(FileManager.default.fileExists(atPath: source), "swift build didn't unpack \(source)")
            let copy = try await run(
                "/usr/bin/ditto", [source, products.appendingPathComponent("Sparkle.framework").path], seconds: 20)
            #expect(copy.status == 0, "\(copy.stderr)")
        }
        return products
    }

    static func plist(_ app: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// `bundle-app.sh --unsigned` leaves signing to release.sh; the default still signs ad hoc.
    @Test func bundleAppUnsignedLeavesNoSignature() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let products = try await Self.products(in: temp)
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

    /// Both bundles embed Sparkle.framework without its XPC services. The release (unsigned) bundle keeps the feed
    /// and the key; the ad-hoc one drops them, so Sparkle stays off, and it verifies with the framework signed inside.
    @Test func bundleAppEmbedsSparkleAndOnlyReleasesKeepTheFeed() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let products = try await Self.products(in: temp)
        let bundle = Self.root.appendingPathComponent("scripts/bundle-app.sh").path
        let fm = FileManager.default

        for signed in [false, true] {
            let out = temp.root.appendingPathComponent(signed ? "signed" : "unsigned", isDirectory: true)
            let result = try await Self.run(
                "/bin/bash", [bundle] + (signed ? [] : ["--unsigned"]) + [products.path, out.path], seconds: 30)
            #expect(result.status == 0, "\(result.stderr)")
            let app = out.appendingPathComponent("Skreenrek.app")
            let sparkle = app.appendingPathComponent("Contents/Frameworks/Sparkle.framework")
            #expect(fm.fileExists(atPath: sparkle.appendingPathComponent("Versions/B/Sparkle").path))
            #expect(fm.fileExists(atPath: sparkle.appendingPathComponent("Versions/B/Autoupdate").path))
            #expect(fm.fileExists(atPath: sparkle.appendingPathComponent("Versions/B/Updater.app").path))
            #expect(!fm.fileExists(atPath: sparkle.appendingPathComponent("Versions/B/XPCServices").path))
            #expect((try? fm.destinationOfSymbolicLink(atPath: sparkle.appendingPathComponent("XPCServices").path)) == nil)
            #expect(try fm.destinationOfSymbolicLink(atPath: sparkle.appendingPathComponent("Versions/Current").path) == "B")

            let info = try Self.plist(app)
            if signed {
                #expect(info["SUFeedURL"] == nil)
                #expect(info["SUPublicEDKey"] == nil)
                let verify = try await Self.run(
                    "/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], seconds: 20)
                #expect(verify.status == 0, "\(verify.stderr)")
                for part in ["Versions/B/Autoupdate", "Versions/B/Updater.app", ""] {
                    let details = try await Self.run(
                        "/usr/bin/codesign", ["-dv", sparkle.appendingPathComponent(part).path], seconds: 10)
                    #expect(details.stderr.contains("Signature=adhoc"), "\(part): \(details.stderr)")
                }
            } else {
                #expect(info["SUFeedURL"] as? String
                    == "https://github.com/R4ph-t/skreenrek/releases/latest/download/appcast.xml")
                #expect(info["SUPublicEDKey"] as? String == "7uv/ca5Plq03VT5kH490hKhCBcLKCsr7rofoiAhLHI8=")
            }
        }
    }

    @Test func bundleAppFailsClearlyWithoutSparkle() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let products = try await Self.products(in: temp, sparkle: false)
        let result = try await Self.run(
            "/bin/bash",
            [Self.root.appendingPathComponent("scripts/bundle-app.sh").path, products.path,
             temp.root.appendingPathComponent("out").path],
            seconds: 20)
        #expect(result.status != 0)
        #expect(result.stderr.contains("Sparkle.framework is missing"), "\(result.stderr)")
    }

    @Test func infoPlistTurnsOnSparkle() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("packaging/Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["SUFeedURL"] as? String
            == "https://github.com/R4ph-t/skreenrek/releases/latest/download/appcast.xml")
        #expect(plist["SUPublicEDKey"] as? String == "7uv/ca5Plq03VT5kH490hKhCBcLKCsr7rofoiAhLHI8=")
        #expect(plist["SUEnableAutomaticChecks"] as? Bool == true)
    }

    /// release.sh signs Sparkle inside-out (Autoupdate, Updater.app, the framework), then the app; never with --deep.
    /// A dry run stops after verifying, before notarization; a real run writes the appcast after the zip check.
    @Test func releaseScriptSignsSparkleInsideOutAndWritesTheAppcast() throws {
        let commands = try Self.commands("scripts/release.sh")
        let script = commands.joined(separator: "\n")
        let parts = try #require(commands.first { $0.hasPrefix("sparkle_parts=(") })
        #expect(parts == #"sparkle_parts=("$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle")"#)
        let signs = commands.enumerated().filter { $0.element.contains("codesign --force") }
        #expect(signs.count == 2)
        #expect(signs.first?.element.hasSuffix(#""$part" || fail "codesign failed for $part""#) == true)
        #expect(signs.last?.element.contains(#"--identifier "$bundle_id" "$app""#) == true)
        let loop = try #require(commands.firstIndex { $0.hasPrefix(#"for part in "${sparkle_parts[@]}""#) })
        #expect(loop < (signs.last?.offset ?? 0))
        #expect(!script.contains("find \"$app"))
        for line in commands where line.contains("codesign --force") || line.contains("codesign --sign") {
            #expect(!line.contains("--deep"), "\(line)")
        }

        func position(_ needle: String) throws -> String.Index {
            try #require(script.range(of: needle), "release.sh lacks \(needle)").lowerBound
        }
        #expect(try position("spctl -a -vv -t exec \"$app\"") < position(#"if [ "$dry_run" -eq 1 ]; then"#))
        #expect(try position(#"if [ "$dry_run" -eq 1 ]; then"#) < position("notarytool submit"))
        #expect(try Self.text("scripts/release.sh").contains(#"echo "dry run: signed app at $app""#))
        #expect(try position(#"stapler validate "$check/Skreenrek.app""#) < position("scripts/make-appcast.sh"))
        #expect(try Self.text("scripts/release.sh")
            .contains(#"gh release create v$version $zip $appcast --notes-file $notes""#))
    }

    /// make-appcast.sh with a stand-in sign_update: a well-formed one-item feed with the signature, the length, the
    /// versions, the floor and the notes as Markdown, even when the notes contain `]]>`.
    @Test func makeAppcastWritesOneSignedItem() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let fm = FileManager.default
        let stub = temp.root.appendingPathComponent("sign_update")
        try "#!/bin/sh\n[ \"$1\" = --account ] && [ \"$2\" = skreenrek ] || exit 9\necho 'sparkle:edSignature=\"AAAA\" length=\"123\"'\n"
            .write(to: stub, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        let zip = temp.root.appendingPathComponent("Skreenrek-9.8.7.zip")
        try Data("zip".utf8).write(to: zip)
        let notes = temp.root.appendingPathComponent("notes.md")
        try """
            ## [9.8.7] - 2026-11-20

            ### Added

            - Check for Updates… in the menu, with `code` and a literal ]]> in it.
            """.write(to: notes, atomically: true, encoding: .utf8)
        let out = temp.root.appendingPathComponent("dist/appcast.xml")

        let script = Self.root.appendingPathComponent("scripts/make-appcast.sh").path
        let result = try await Self.run(
            "/bin/bash", [script, "9.8.7", zip.path, notes.path, out.path],
            environment: ["SPARKLE_SIGN_UPDATE": stub.path], seconds: 20)
        #expect(result.status == 0, "\(result.stderr)")

        let document = try XMLDocument(contentsOf: out)
        let root = try #require(document.rootElement())
        #expect(root.name == "rss")
        #expect(root.attribute(forName: "version")?.stringValue == "2.0")
        let sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
        #expect(root.namespace(forPrefix: "sparkle")?.stringValue == sparkle)
        func values(_ path: String) throws -> [String] {
            try document.nodes(forXPath: path).compactMap(\.stringValue)
        }
        #expect(try values("/rss/channel/title") == ["Skreenrek"])
        #expect(try document.nodes(forXPath: "/rss/channel/item").count == 1)
        #expect(try values("/rss/channel/item/title") == ["Skreenrek 9.8.7"])
        #expect(try values("/rss/channel/item/sparkle:version") == ["9.8.7"])
        #expect(try values("/rss/channel/item/sparkle:shortVersionString") == ["9.8.7"])
        #expect(try values("/rss/channel/item/sparkle:minimumSystemVersion") == ["15.0"])
        #expect(try values("/rss/channel/item/sparkle:fullReleaseNotesLink")
            == ["https://github.com/R4ph-t/skreenrek/releases"])
        let pubDate = try #require(try values("/rss/channel/item/pubDate").first)
        let rfc822 = DateFormatter()
        rfc822.locale = Locale(identifier: "en_US_POSIX")
        rfc822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        #expect(rfc822.date(from: pubDate) != nil, "\(pubDate)")

        let description = try #require(try document.nodes(forXPath: "/rss/channel/item/description").first as? XMLElement)
        #expect(description.attribute(forName: "sparkle:format")?.stringValue == "markdown")
        let markdown = try #require(description.stringValue)
        #expect(markdown.contains("### Added"))
        #expect(markdown.contains("- Check for Updates… in the menu, with `code` and a literal ]]> in it."))
        #expect(!markdown.contains("## [9.8.7]"))

        let enclosure = try #require(try document.nodes(forXPath: "/rss/channel/item/enclosure").first as? XMLElement)
        #expect(enclosure.attribute(forName: "url")?.stringValue
            == "https://github.com/R4ph-t/skreenrek/releases/download/v9.8.7/Skreenrek-9.8.7.zip")
        #expect(enclosure.attribute(forName: "type")?.stringValue == "application/octet-stream")
        #expect(enclosure.attribute(forName: "sparkle:edSignature")?.stringValue == "AAAA")
        #expect(enclosure.attribute(forName: "length")?.stringValue == "123")
    }

    /// No signature, no appcast: a sign_update that fails or prints nothing stops the script.
    @Test func makeAppcastFailsWithoutASignature() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let stub = temp.root.appendingPathComponent("sign_update")
        try "#!/bin/sh\necho 'no key'\n".write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        let zip = temp.root.appendingPathComponent("Skreenrek-9.8.7.zip")
        try Data("zip".utf8).write(to: zip)
        let notes = temp.root.appendingPathComponent("notes.md")
        try "- A change.\n".write(to: notes, atomically: true, encoding: .utf8)
        let script = Self.root.appendingPathComponent("scripts/make-appcast.sh").path
        let out = temp.root.appendingPathComponent("appcast.xml")
        let result = try await Self.run(
            "/bin/bash", [script, "9.8.7", zip.path, notes.path, out.path],
            environment: ["SPARKLE_SIGN_UPDATE": stub.path], seconds: 20)
        #expect(result.status != 0)
        #expect(result.stderr.contains("no sparkle:edSignature"), "\(result.stderr)")
        #expect(!FileManager.default.fileExists(atPath: out.path))
        let usage = try await Self.run("/bin/bash", [script, "9.8.7"], seconds: 10)
        #expect(usage.status != 0)
        #expect(usage.stderr.contains("usage"))
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
