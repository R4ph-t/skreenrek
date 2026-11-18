import Darwin
import Foundation
import SkreenrekCore
import Synchronization
import Testing

/// `scripts/release-notes.sh` extracts one Keep a Changelog section. These tests run that script against a fixture
/// and against `CHANGELOG.md`. They never touch the network, the Keychain, or the app.
@Suite(.timeLimit(.minutes(1))) struct ChangelogTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let fixture = """
        # Changelog

        ## [Unreleased]

        ### Added

        - not yet

        ## [1.0.10] - 2026-11-17

        ### Added

        - ten

        ## [1.0.3] - 2026-11-17

        ### Added

        - three

        ## [1.0.2] - 2026-11-17

        ### Changed

        - two

        ## [1.0.1] - 2026-11-17

        ### Added

        - one
        - end of changelog
        """

    struct Output: Sendable {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    /// Runs the notes script. `file` nil reads the repo changelog.
    static func notes(_ version: String, file: URL? = nil) async throws -> Output {
        var arguments = [Self.root.appendingPathComponent("scripts/release-notes.sh").path, version]
        if let file { arguments.append(file.path) }
        return try await run("/bin/bash", arguments)
    }

    @Test func extractsASectionAndStopsAtTheNextHeader() async throws {
        let file = try Self.writeFixture()
        defer { try? FileManager.default.removeItem(at: file) }
        let three = try await Self.notes("1.0.3", file: file)
        #expect(three.status == 0, three.stderr)
        #expect(three.stdout.hasPrefix("## [1.0.3] - 2026-11-17\n"))
        #expect(three.stdout.contains("- three"))
        #expect(!three.stdout.contains("- ten"))
        #expect(!three.stdout.contains("- two"))
        #expect(!three.stdout.contains("not yet"))
        // `1.0.1` must not take the `1.0.10` section.
        let ten = try await Self.notes("1.0.10", file: file)
        #expect(ten.status == 0, ten.stderr)
        #expect(ten.stdout.contains("- ten"))
        #expect(!ten.stdout.contains("- one"))
        #expect(!ten.stdout.contains("- three"))
    }

    /// The oldest section has no heading after it, so the extract runs through the end of the file.
    @Test func extractsTheLastSectionWhenNoHeaderFollows() async throws {
        let file = try Self.writeFixture()
        defer { try? FileManager.default.removeItem(at: file) }
        let one = try await Self.notes("1.0.1", file: file)
        #expect(one.status == 0, one.stderr)
        #expect(one.stdout.hasPrefix("## [1.0.1] - 2026-11-17\n"))
        #expect(one.stdout.contains("- one"))
        #expect(one.stdout.contains("- end of changelog"))
        #expect(!one.stdout.contains("- two"))
        #expect(!one.stdout.contains("## [1.0.2]"))
        #expect(one.stdout.hasSuffix("- end of changelog\n"))
    }

    @Test func missingVersionFails() async throws {
        let file = try Self.writeFixture()
        defer { try? FileManager.default.removeItem(at: file) }
        let missing = try await Self.notes("9.9.9", file: file)
        #expect(missing.status != 0)
        #expect(missing.stderr.contains("no ## [9.9.9] section"))
        #expect(missing.stdout.isEmpty)
        let notAVersion = try await Self.notes("1.0", file: file)
        #expect(notAVersion.status != 0)
        #expect(notAVersion.stderr.contains("isn't x.y.z"))
        let absent = try await Self.notes("1.0.3", file: file.deletingLastPathComponent().appendingPathComponent("nope.md"))
        #expect(absent.status != 0)
        #expect(absent.stderr.contains("no changelog"))
    }

    /// The version the app reports has its own section, and that section stops before the next heading.
    @Test func changelogHasASectionForTheCurrentVersion() async throws {
        let current = try await Self.notes(SkreenrekVersion.current)
        #expect(current.status == 0, current.stderr)
        #expect(current.stdout.hasPrefix("## [\(SkreenrekVersion.current)]"))
        #expect(!current.stdout.contains("## [Unreleased]"))
        let body = current.stdout.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
        #expect(!body.contains("## ["))
    }

    /// The backfilled releases stay in their own sections: each one has its own lines and not the neighbours'.
    @Test func backfilledReleasesStayInTheirOwnSections() async throws {
        let newest = try await Self.notes("1.0.3")
        #expect(newest.status == 0, newest.stderr)
        #expect(newest.stdout.contains("Show in Finder"))
        #expect(newest.stdout.contains("Quit & Reopen"))
        #expect(!newest.stdout.contains("What's new"))
        #expect(!newest.stdout.contains("Developer ID"))
        #expect(!newest.stdout.contains("new mark"))
        let middle = try await Self.notes("1.0.2")
        #expect(middle.status == 0, middle.stderr)
        #expect(middle.stdout.contains("new mark"))
        #expect(middle.stdout.contains("deprecated"))
        #expect(!middle.stdout.contains("Show in Finder"))
        let first = try await Self.notes("1.0.1")
        #expect(first.status == 0, first.stderr)
        #expect(first.stdout.contains("Developer ID"))
        #expect(first.stdout.contains("Permissions needed"))
        #expect(!first.stdout.contains("new mark"))
        #expect(!first.stdout.contains("## [1.0.2]"))
        #expect(!first.stdout.contains("## [1.0.3]"))
    }

    /// `make release` reads the section before it builds, and `make release-notes` prints it.
    @Test func releaseReadsTheChangelogBeforeBuilding() throws {
        let script = try String(contentsOf: Self.root.appendingPathComponent("scripts/release.sh"), encoding: .utf8)
        let read = try #require(script.range(of: "scripts/release-notes.sh"))
        let build = try #require(script.range(of: "swift build -c release"))
        #expect(read.lowerBound < build.lowerBound)
        #expect(script.contains("CHANGELOG.md has no section for"))
        #expect(script.contains("Skreenrek-$version-notes.md"))
        #expect(script.contains("--notes-file"))
        let makefile = try String(contentsOf: Self.root.appendingPathComponent("Makefile"), encoding: .utf8)
        #expect(makefile.contains("release-notes:"))
        #expect(makefile.contains("bash scripts/release-notes.sh \"$(VERSION)\""))
        #expect(makefile.contains("--notes-file dist/Skreenrek-X.Y.Z-notes.md"))
    }

    private static func writeFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-changelog-\(UUID().uuidString).md")
        try Data(fixture.utf8).write(to: url)
        return url
    }

    /// Stdout and stderr go to files, so a chatty script can't fill a pipe and stall the test.
    private static func run(_ executable: String, _ arguments: [String], seconds: Double = 10) async throws -> Output {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-notes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outURL = directory.appendingPathComponent("out")
        let errURL = directory.appendingPathComponent("err")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)
        // The handles have to outlive the process: dropping them closes the descriptors the child writes to.
        defer {
            withExtendedLifetime(outHandle) {}
            withExtendedLifetime(errHandle) {}
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardOutput = outHandle
        process.standardError = errHandle
        let finished = Mutex(false)
        let output = try await within(executable, seconds: seconds) {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { child in
                    let first = finished.withLock { value in
                        guard !value else { return false }
                        value = true
                        return true
                    }
                    guard first else { return }
                    let stdout = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
                    let stderr = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
                    continuation.resume(
                        returning: Output(status: child.terminationStatus, stdout: stdout, stderr: stderr))
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
        return output
    }
}
