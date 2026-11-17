import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekTesting
import Testing

/// Which bundle a client launches when the app isn't running: the one its own executable lives in, by URL. Fixtures
/// are real files and symlinks in a temp folder; nothing is ever launched.
@Suite struct AppBundleLocatorTests {
    /// A temp folder with its own symlinks (`/var` → `/private/var`) already resolved, so expected paths are exact.
    final class Tree {
        let root: URL

        init() throws {
            let raw = FileManager.default.temporaryDirectory
                .appendingPathComponent("skl-\(UUID().uuidString.prefix(8))", isDirectory: true)
            try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
            guard let real = realpath(raw.path, nil) else { throw CocoaError(.fileNoSuchFile) }
            defer { free(real) }
            root = URL(fileURLWithPath: String(cString: real), isDirectory: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func path(_ relative: String) -> String { root.path + "/" + relative }

        /// `<relative>/Contents/MacOS/skreenrek` as an empty executable file; returns the executable's path.
        @discardableResult
        func bundle(_ relative: String) throws -> String {
            try file("\(relative)/Contents/MacOS/skreenrek")
        }

        @discardableResult
        func file(_ relative: String) throws -> String {
            let path = path(relative)
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: path, contents: Data(), attributes: [.posixPermissions: 0o755])
            return path
        }

        /// A symlink at `relative` whose stored target is `target` exactly (absolute or relative).
        @discardableResult
        func link(_ relative: String, to target: String) throws -> String {
            let path = path(relative)
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
            return path
        }
    }

    let locator = AppBundleLocator.live

    @Test func theHomebrewCaskLinkInBinFindsTheAppInApplications() throws {
        let t = try Tree()
        let executable = try t.bundle("Applications/Skreenrek.app")
        let link = try t.link("opt/homebrew/bin/skreenrek", to: executable)
        #expect(locator.appBundle(executablePath: link)?.path == t.path("Applications/Skreenrek.app"))
    }

    @Test func aLocalBinLinkFindsTheApp() throws {
        let t = try Tree()
        let executable = try t.bundle("Applications/Skreenrek.app")
        let link = try t.link("home/.local/bin/skreenrek", to: executable)
        #expect(locator.appBundle(executablePath: link)?.path == t.path("Applications/Skreenrek.app"))
    }

    @Test func aDirectPathInsideABundleIsThatBundle() throws {
        let t = try Tree()
        let executable = try t.bundle("lane/build/Skreenrek.app")
        #expect(locator.appBundle(executablePath: executable)?.path == t.path("lane/build/Skreenrek.app"))
    }

    @Test func relativeLinksAndLinkedFoldersAreFollowed() throws {
        // The formula layout: bin/skreenrek → ../opt/skreenrek/…, and opt/skreenrek → ../Cellar/skreenrek/1.0.1.
        let t = try Tree()
        try t.bundle("homebrew/Cellar/skreenrek/1.0.1/Skreenrek.app")
        try t.link("homebrew/opt/skreenrek", to: "../Cellar/skreenrek/1.0.1")
        let link = try t.link(
            "homebrew/bin/skreenrek", to: "../opt/skreenrek/Skreenrek.app/Contents/MacOS/skreenrek")
        #expect(
            locator.appBundle(executablePath: link)?.path
                == t.path("homebrew/Cellar/skreenrek/1.0.1/Skreenrek.app"))
        // A relative executable path starts at the current directory.
        let relative = AppBundleLocator(readLink: locator.readLink, currentDirectory: t.path("homebrew"))
        #expect(
            relative.appBundle(executablePath: "./bin/skreenrek")?.path
                == t.path("homebrew/Cellar/skreenrek/1.0.1/Skreenrek.app"))
    }

    @Test func aBareExecutableOutsideAnyBundleHasNoBundle() throws {
        let t = try Tree()
        let bare = try t.file("bin/skreenrek")
        #expect(locator.appBundle(executablePath: bare) == nil)
        let link = try t.link("home/.local/bin/skreenrek", to: bare)
        #expect(locator.appBundle(executablePath: link) == nil)
        #expect(locator.resolve(link) == bare)
        // `Contents/MacOS` without an `.app` around it isn't a bundle either.
        let fake = try t.file("Skreenrek/Contents/MacOS/skreenrek")
        #expect(locator.appBundle(executablePath: fake) == nil)
    }

    @Test func aSymlinkLoopStopsAndHasNoBundle() throws {
        let t = try Tree()
        try t.link("a", to: "b")
        let b = try t.link("b", to: "a")
        #expect(locator.appBundle(executablePath: b) == nil)
    }

    @Test func resolutionIsPureOverTheInjectedLinks() {
        let links = [
            "/opt/homebrew/bin/skreenrek": "/Applications/Skreenrek.app/Contents/MacOS/skreenrek",
            "/Users/me/.local/bin/skreenrek": "../../dev/lane/build/Skreenrek.app/Contents/MacOS/skreenrek",
        ]
        let fake = AppBundleLocator(readLink: { links[$0] }, currentDirectory: "/Users/me")
        #expect(fake.appBundle(executablePath: "/opt/homebrew/bin/skreenrek")?.path == "/Applications/Skreenrek.app")
        #expect(
            fake.appBundle(executablePath: ".local/bin/skreenrek")?.path == "/Users/me/dev/lane/build/Skreenrek.app")
        #expect(fake.appBundle(executablePath: "/usr/local/bin/skreenrek") == nil)
    }

    // MARK: - The launch

    func connector(_ executable: String, _ launcher: FakeAppLauncher, _ t: Tree) -> ControlConnector {
        // Nothing listens on the socket; a zero timeout gives up right after the launch, with no waiting.
        ControlConnector(
            socketPath: URL(fileURLWithPath: t.path("c.sock")), executablePath: executable, launcher: launcher,
            clock: ManualClock(), launchTimeout: 0)
    }

    func connectError(_ connector: ControlConnector) async -> ErrorBody? {
        do {
            _ = try await connector.connect(as: ClientInfo(kind: .cli))
            return nil
        } catch let error as ControlConnectError {
            return error.body
        } catch {
            return nil
        }
    }

    @Test func theLauncherIsGivenTheEnclosingBundleURL() async throws {
        let t = try Tree()
        let executable = try t.bundle("Applications/Skreenrek.app")
        let link = try t.link("opt/homebrew/bin/skreenrek", to: executable)
        let launcher = FakeAppLauncher()
        let body = await connectError(connector(link, launcher, t))
        #expect(launcher.launches.map(\.path) == [t.path("Applications/Skreenrek.app")])
        #expect(body?.message == "Skreenrek didn't start within 0 seconds.")
    }

    @Test func aFailedLaunchNamesTheBundleAndTheMacOSError() async throws {
        let t = try Tree()
        let executable = try t.bundle("Applications/Skreenrek.app")
        let launcher = FakeAppLauncher { _ in
            throw NSError(
                domain: NSOSStatusErrorDomain, code: -10827,
                userInfo: [NSLocalizedDescriptionKey: "The application “Skreenrek” can’t be opened."])
        }
        let body = try #require(await connectError(connector(executable, launcher, t)))
        let bundle = t.path("Applications/Skreenrek.app")
        #expect(
            body.message
                == "Skreenrek couldn't be opened at \(bundle): The application “Skreenrek” can’t be opened. "
                + "(NSOSStatusErrorDomain error -10827)")
        #expect(body.hint == "Reinstall Skreenrek, or open \(bundle) by hand, then run: skreenrek doctor")
        #expect(body.code == "internal")
        #expect(body.exit == 1)
    }

    @Test func outsideABundleTheErrorNamesThePathTriedAndNothingLaunches() async throws {
        let t = try Tree()
        let bare = try t.file("bin/skreenrek")
        let link = try t.link("home/.local/bin/skreenrek", to: bare)
        let launcher = FakeAppLauncher()
        let body = try #require(await connectError(connector(link, launcher, t)))
        #expect(launcher.launches.isEmpty)
        #expect(
            body.message
                == "Skreenrek isn't running, and \(link) (resolved to \(bare)) isn't inside an app bundle, so it "
                + "can't be opened.")
        #expect(body.hint == "Open Skreenrek.app, or run: skreenrek app")
    }
}
