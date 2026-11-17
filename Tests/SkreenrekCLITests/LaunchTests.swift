import Foundation
import SkreenrekCLI
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Testing

/// The app-launch path and the mode dispatch in `main.swift`.
@Suite(.timeLimit(.minutes(2))) struct LaunchTests {
    /// `<root>/Skreenrek.app/Contents/MacOS/skreenrek` plus a `<root>/bin/skreenrek` symlink to it.
    static func makeBundle(in root: URL) throws -> (bundle: URL, link: URL) {
        let fm = FileManager.default
        let bundle = root.appendingPathComponent("Skreenrek.app", isDirectory: true)
        let macOS = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent("skreenrek")
        fm.createFile(atPath: executable.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let link = bin.appendingPathComponent("skreenrek")
        try fm.createSymbolicLink(at: link, withDestinationURL: executable)
        return (bundle, link)
    }

    @Test func insideTheBundleALaunchOpensTheAppHiddenAndTheCallGoesThrough() async throws {
        let h = CLIHarness()
        defer { h.stop() }
        let (bundle, link) = try Self.makeBundle(in: h.temp.root)
        // The fake launch starts the app: the socket appears.
        let host = h.host
        let launcher = FakeAppLauncher { _ in try host.start() }
        let result = try await h.run(["status"], executablePath: link.path, launcher: launcher)
        #expect(result.code == 0, "\(result)")
        #expect(result.out == "idle\n")
        #expect(launcher.launches.map { $0.resolvingSymlinksInPath() } == [bundle.resolvingSymlinksInPath()])

        // Running already: no second launch.
        _ = try await h.run(["status"], executablePath: link.path, launcher: launcher)
        #expect(launcher.launches.count == 1)
    }

    @Test func aLaunchedAppThatNeverAnswersFailsAfterTenSeconds() async throws {
        let h = CLIHarness()
        defer { h.temp.cleanUp() }
        let (_, link) = try Self.makeBundle(in: h.temp.root)
        let clock = ManualClock()
        let launcher = FakeAppLauncher()
        async let run = h.run(["status"], executablePath: link.path, launcher: launcher, launchClock: clock)
        try await within("the launch wait") { await clock.waitForSleepers(1) }
        clock.advance(by: 11)
        let result = try await run
        #expect(result.code == 1)
        #expect(launcher.launches.count == 1)
        #expect(result.err == """
            error: Skreenrek didn't start within 10 seconds.
            hint:  Open Skreenrek.app, then run: skreenrek doctor

            """)
    }

    @Test func theBundleIsFoundThroughSymlinksAndNotOutsideOne() throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let (bundle, link) = try Self.makeBundle(in: temp.root)
        #expect(AppConnector.appBundle(executablePath: link.path)?.resolvingSymlinksInPath()
            == bundle.resolvingSymlinksInPath())
        #expect(AppConnector.appBundle(executablePath: "/usr/local/bin/skreenrek") == nil)
        #expect(AppConnector.appBundle(executablePath: "/Applications/Other.app/Contents/MacOS/skreenrek") == nil)
        #expect(
            AppConnector.appBundle(executablePath: "/Applications/Skreenrek.app/Contents/MacOS/skreenrek")?.path
                == "/Applications/Skreenrek.app")
    }

    @Test func dispatchRule() {
        #expect(LaunchMode.decide(arguments: [], stdinIsTTY: false) == .app)
        #expect(LaunchMode.decide(arguments: ["-psn_0_12345"], stdinIsTTY: false) == .app)
        #expect(LaunchMode.decide(arguments: ["app"], stdinIsTTY: true) == .app)
        #expect(LaunchMode.decide(arguments: ["app"], stdinIsTTY: false) == .app)
        #expect(LaunchMode.decide(arguments: [], stdinIsTTY: true) == .help)
        #expect(LaunchMode.decide(arguments: ["status"], stdinIsTTY: false) == .cli(["status"]))
        #expect(LaunchMode.decide(arguments: ["--version"], stdinIsTTY: true) == .cli(["--version"]))
        #expect(LaunchMode.decide(arguments: ["app", "--json"], stdinIsTTY: true) == .cli(["app", "--json"]))
    }
}
