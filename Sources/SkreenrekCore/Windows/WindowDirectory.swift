import CoreGraphics

/// A window resolved for a command: the window plus the display it is on.
public struct ResolvedWindow: Sendable, Hashable {
    public var window: WindowInfo
    public var display: DisplayInfo

    public init(window: WindowInfo, display: DisplayInfo) {
        self.window = window
        self.display = display
    }

    /// The window's size in output pixels on its display.
    public var pixelSize: PixelSize { window.pixelSize(on: display) }
}

/// The windows Skreenrek can record, from a `WindowCatalog`: normal app windows only, front to back, each assigned to
/// the display that holds most of it.
public struct WindowDirectory: Sendable {
    /// Windows smaller than this (pt, either side) aren't listed.
    public static let minimumSide: Double = 40
    /// Owners that are never recordable: the Dock, the menu bar and Window Server.
    public static let systemBundleIds: Set<String> = [
        "com.apple.dock", "com.apple.systemuiserver", "com.apple.controlcenter", "com.apple.WindowServer",
    ]
    public static let systemAppNames: Set<String> = ["Dock", "SystemUIServer", "Control Center", "Window Server"]

    public let catalog: any WindowCatalog
    /// Skreenrek's own pid: its windows (menus, HUD, picker) are never listed.
    public let ownPid: Int32

    public init(catalog: any WindowCatalog, ownPid: Int32) {
        self.catalog = catalog
        self.ownPid = ownPid
    }

    /// Recordable windows, front to back. `app` matches the app name or bundle ID, case-insensitively.
    public func windows(app: String? = nil) async throws -> [WindowInfo] {
        try await resolvedWindows(app: app).map(\.window)
    }

    /// Recordable windows with their displays, front to back.
    public func resolvedWindows(app: String? = nil) async throws -> [ResolvedWindow] {
        let displays = try await catalog.displays()
        return try await catalog.windows()
            .filter { window in isRecordable(window) && (app.map { Self.matchesApp(window, $0) } ?? true) }
            .compactMap { window in
                guard let display = Self.display(for: window.frame, in: displays) else { return nil }
                var window = window
                window.displayId = display.id
                return ResolvedWindow(window: window, display: display)
            }
    }

    /// Finds the one window a query names. `window_not_found` or `window_ambiguous` (exit 5) otherwise.
    public func resolve(_ query: WindowQuery) async throws -> ResolvedWindow {
        let all = try await resolvedWindows()
        let matches: [ResolvedWindow]
        switch query {
        case .id(let id):
            matches = all.filter { $0.window.id == id }
        case .app(let name, let title):
            matches = all.filter { candidate in
                Self.matchesApp(candidate.window, name)
                    && (title.map { candidate.window.title.localizedCaseInsensitiveContains($0) } ?? true)
            }
        }
        guard let first = matches.first else {
            throw SkreenrekError.windowNotFound(query: Self.describe(query))
        }
        guard matches.count == 1 else {
            throw SkreenrekError.windowAmbiguous(
                query: Self.describe(query),
                candidates: matches.map {
                    WindowCandidate(id: $0.window.id, app: $0.window.app, title: $0.window.title, size: $0.pixelSize)
                })
        }
        return first
    }

    func isRecordable(_ window: WindowInfo) -> Bool {
        window.layer == 0 && window.onScreen
            && window.frame.width >= Self.minimumSide && window.frame.height >= Self.minimumSide
            && window.pid != ownPid
            && !Self.isSystemOwner(window)
    }

    static func isSystemOwner(_ window: WindowInfo) -> Bool {
        if systemAppNames.contains(window.app) { return true }
        guard let bundleId = window.bundleId?.lowercased() else { return false }
        return systemBundleIds.contains { $0.lowercased() == bundleId }
    }

    static func matchesApp(_ window: WindowInfo, _ name: String) -> Bool {
        window.app.caseInsensitiveCompare(name) == .orderedSame
            || window.bundleId?.caseInsensitiveCompare(name) == .orderedSame
    }

    /// How a query reads in messages: `4127`, `--app Safari` or `--app Safari --title "localhost"`.
    public static func describe(_ query: WindowQuery) -> String {
        switch query {
        case .id(let id): return String(id.rawValue)
        case .app(let name, nil): return "--app \(name)"
        case .app(let name, let title?): return "--app \(name) --title \"\(title)\""
        }
    }

    /// `windows` in the order of `zOrder` (front to back). Windows missing from it keep their order, at the back.
    public static func ordered(_ windows: [WindowInfo], byZOrder zOrder: [WindowID]) -> [WindowInfo] {
        var rank: [WindowID: Int] = [:]
        for (index, id) in zOrder.enumerated() where rank[id] == nil { rank[id] = index }
        return windows.enumerated().sorted { a, b in
            (rank[a.element.id] ?? Int.max, a.offset) < (rank[b.element.id] ?? Int.max, b.offset)
        }.map(\.element)
    }

    /// The display holding the largest part of `frame`. A frame on no display gets the nearest one; nil only when
    /// there are no displays.
    public static func display(for frame: PointRect, in displays: [DisplayInfo]) -> DisplayInfo? {
        let rect = frame.cgRect
        var best: (display: DisplayInfo, area: Double)?
        for display in displays {
            let overlap = rect.intersection(display.frame.cgRect)
            let area = overlap.isNull ? 0 : Double(overlap.width * overlap.height)
            if area > (best?.area ?? 0) { best = (display, area) }
        }
        if let best { return best.display }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return displays.min { distance(center, $0.frame.cgRect) < distance(center, $1.frame.cgRect) }
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> Double {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return Double(dx * dx + dy * dy)
    }
}
