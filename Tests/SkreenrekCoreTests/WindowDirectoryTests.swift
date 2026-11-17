import CoreGraphics
import SkreenrekCore
import SkreenrekTesting
import Testing

@Suite struct WindowDirectoryTests {
    typealias F = WindowFixtures

    static func directory(_ windows: [WindowInfo], displays: [DisplayInfo] = F.displays) -> WindowDirectory {
        WindowDirectory(catalog: FakeWindowCatalog(windows: windows, displays: displays), ownPid: F.ownPid)
    }

    @Test func listsOnlyNormalAppWindowsFrontToBack() async throws {
        let windows = [
            F.window(1, app: "Dock", bundleId: "com.apple.dock", pid: 10),
            F.safari,
            F.window(2, app: "Window Server", pid: 11),
            F.window(3, app: "SystemUIServer", bundleId: "com.apple.systemuiserver", pid: 12),
            F.window(4, app: "Notes", bundleId: "com.apple.Notes", layer: 3),
            F.window(5, app: "Notes", bundleId: "com.apple.Notes", onScreen: false),
            F.window(6, app: "Notes", bundleId: "com.apple.Notes", frame: PointRect(x: 0, y: 0, width: 39, height: 300)),
            F.window(7, app: "Skreenrek", bundleId: "it.fraime.skreenrek", pid: F.ownPid),
            F.terminal,
            F.window(8, app: "Notes", bundleId: "com.apple.Notes", frame: PointRect(x: 0, y: 40, width: 40, height: 40)),
            F.safariGitHub,
        ]
        let listed = try await Self.directory(windows).windows()
        #expect(listed.map(\.id.rawValue) == [4127, 5001, 8, 4133])
    }

    @Test func appFilterMatchesNameOrBundleIdCaseInsensitively() async throws {
        let directory = Self.directory([F.safari, F.terminal, F.safariGitHub])
        #expect(try await directory.windows(app: "safari").map(\.id.rawValue) == [4127, 4133])
        #expect(try await directory.windows(app: "COM.APPLE.TERMINAL").map(\.id.rawValue) == [5001])
        #expect(try await directory.windows(app: "Saf").isEmpty)
    }

    @Test func eachWindowGetsTheDisplayHoldingMostOfIt() async throws {
        // 100 pt on the built-in display, 300 pt on the external one.
        let spanning = F.window(9, app: "Notes", frame: PointRect(x: 1412, y: 100, width: 400, height: 300))
        let listed = try await Self.directory([F.safari, spanning, F.terminal]).resolvedWindows()
        #expect(listed.map(\.display.id) == [1, 2, 2])
        #expect(listed.map(\.window.displayId) == [1, 2, 2])
        #expect(listed[0].pixelSize == PixelSize(width: 1280, height: 800))
        #expect(listed[2].pixelSize == PixelSize(width: 800, height: 600))
    }

    @Test func aWindowOnNoDisplayGetsTheNearestOne() {
        let frame = PointRect(x: 4000, y: 100, width: 100, height: 100)
        #expect(WindowDirectory.display(for: frame, in: F.displays)?.id == 2)
        #expect(WindowDirectory.display(for: frame, in: []) == nil)
    }

    @Test func resolvesByIdOrByAppAndTitle() async throws {
        let directory = Self.directory([F.safari, F.terminal, F.safariGitHub])
        #expect(try await directory.resolve(.id(WindowID(5001))).window.id == WindowID(5001))
        #expect(try await directory.resolve(.app(name: "Safari", title: "github")).window.id == WindowID(4133))
        #expect(try await directory.resolve(.app(name: "com.apple.safari", title: "LOCALHOST")).window.id
            == WindowID(4127))
        #expect(try await directory.resolve(.app(name: "terminal", title: nil)).display.id == 2)
    }

    @Test func unknownWindowIsNotFound() async throws {
        let directory = Self.directory([F.safari])
        let byId = await #expect(throws: SkreenrekError.self) { try await directory.resolve(.id(WindowID(1))) }
        #expect(byId == .windowNotFound(query: "1"))
        #expect(byId?.exitCode == 5)
        let byApp = await #expect(throws: SkreenrekError.self) {
            try await directory.resolve(.app(name: "Safari", title: "nope"))
        }
        #expect(byApp == .windowNotFound(query: "--app Safari --title \"nope\""))
        #expect(byApp?.message == "No window matches --app Safari --title \"nope\".")
    }

    @Test func ownWindowsCannotBeResolvedById() async throws {
        let own = F.window(7, app: "Skreenrek", pid: F.ownPid)
        await #expect(throws: SkreenrekError.windowNotFound(query: "7")) {
            try await Self.directory([own]).resolve(.id(WindowID(7)))
        }
    }

    @Test func ambiguousAppListsCandidatesFrontToBack() async throws {
        let directory = Self.directory([F.safari, F.terminal, F.safariGitHub])
        let error = await #expect(throws: SkreenrekError.self) {
            try await directory.resolve(.app(name: "Safari", title: nil))
        }
        #expect(error?.code == "window_ambiguous")
        #expect(error?.exitCode == 5)
        #expect(
            error?.message == """
                2 windows match --app Safari. Pass a window ID:
                  4127  Safari  localhost:3000  1280 × 800 px
                  4133  Safari  GitHub          1512 × 945 px
                """)
    }

    @Test func catalogFailuresPassThrough() async throws {
        let catalog = FakeWindowCatalog(windows: [F.safari], displays: F.displays)
        catalog.failure = SkreenrekError.permissionDenied(.screenRecording)
        let directory = WindowDirectory(catalog: catalog, ownPid: F.ownPid)
        await #expect(throws: SkreenrekError.permissionDenied(.screenRecording)) { try await directory.windows() }
    }

    @Test func ordersByZOrder() {
        let a = F.window(1, app: "A")
        let b = F.window(2, app: "B")
        let c = F.window(3, app: "C")
        let ordered = WindowDirectory.ordered([a, b, c], byZOrder: [WindowID(3), WindowID(9), WindowID(1)])
        #expect(ordered.map(\.id.rawValue) == [3, 1, 2])
    }

    @Test func describesQueries() {
        #expect(WindowDirectory.describe(.id(WindowID(4127))) == "4127")
        #expect(WindowDirectory.describe(.app(name: "Safari", title: nil)) == "--app Safari")
        #expect(WindowDirectory.describe(.app(name: "Safari", title: "localhost")) == "--app Safari --title \"localhost\"")
    }
}

@Suite struct ScreenGeometryTests {
    @Test func convertsBetweenAppKitAndTopLeft() {
        let geometry = ScreenGeometry(primaryHeight: 982)
        // The menu bar strip of the primary display.
        #expect(geometry.topLeft(fromAppKit: CGRect(x: 0, y: 949, width: 1512, height: 33))
            == PointRect(x: 0, y: 0, width: 1512, height: 33))
        // A display above the primary one has a negative top-left y.
        #expect(geometry.topLeft(fromAppKit: CGRect(x: 0, y: 982, width: 1920, height: 1080))
            == PointRect(x: 0, y: -1080, width: 1920, height: 1080))
        let rect = PointRect(x: 120, y: 80, width: 640, height: 400)
        #expect(geometry.appKit(fromTopLeft: rect) == CGRect(x: 120, y: 502, width: 640, height: 400))
        #expect(geometry.topLeft(fromAppKit: geometry.appKit(fromTopLeft: rect)) == rect)
    }
}
