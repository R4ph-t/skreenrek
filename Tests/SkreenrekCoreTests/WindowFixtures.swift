import SkreenrekCore

/// Displays and windows for the spec 02 tests: a 2× built-in display with an external 1× display to its right.
enum WindowFixtures {
    static let retina = Fixtures.retina

    static let external = DisplayInfo(
        id: 2, name: "Studio Display", scale: 1,
        frame: PointRect(x: 1512, y: 0, width: 1920, height: 1080),
        visibleFrame: PointRect(x: 1512, y: 25, width: 1920, height: 1055))

    static let displays = [retina, external]

    static let ownPid: Int32 = 99

    static func window(
        _ id: UInt32, app: String, bundleId: String? = nil, title: String = "", pid: Int32 = 500,
        frame: PointRect = PointRect(x: 120, y: 80, width: 640, height: 400), onScreen: Bool = true, layer: Int = 0
    ) -> WindowInfo {
        WindowInfo(
            id: WindowID(id), app: app, bundleId: bundleId, title: title, pid: pid, frame: frame, displayId: 0,
            onScreen: onScreen, layer: layer)
    }

    static let safari = Fixtures.safari
    static let safariGitHub = window(
        4133, app: "Safari", bundleId: "com.apple.Safari", title: "GitHub", pid: 812,
        frame: PointRect(x: 200, y: 100, width: 756, height: 472.5))
    static let terminal = window(
        5001, app: "Terminal", bundleId: "com.apple.Terminal", title: "zsh", pid: 900,
        frame: PointRect(x: 1600, y: 100, width: 800, height: 600))
}
