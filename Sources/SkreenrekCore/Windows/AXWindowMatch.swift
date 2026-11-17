/// One Accessibility window of an app, as read by the real resizer: its title and frame (top-left global pt).
public struct AXWindowSnapshot: Sendable, Hashable {
    public var title: String?
    public var frame: PointRect?

    public init(title: String?, frame: PointRect?) {
        self.title = title
        self.frame = frame
    }
}

/// Picks the Accessibility window that is a listed window, with public API only: by title and frame within the
/// window's own app (the caller filters by pid). It never guesses between equal matches.
public enum AXWindowMatch {
    /// How far (pt) an AX frame edge may be from the listed frame and still match.
    public static let frameTolerance: Double = 1

    /// The index of the matching snapshot. Tries title and frame, then title alone, then frame alone; the first rule
    /// with any match decides. `window_not_found` when nothing matches, `window_ambiguous` when a rule matches more
    /// than one window.
    public static func pick(_ window: WindowInfo, among snapshots: [AXWindowSnapshot], scale: Double = 1) throws
        -> Int
    {
        let titled = snapshots.indices.filter { snapshots[$0].title == window.title }
        let framed = snapshots.indices.filter { snapshots[$0].frame.map { sameFrame($0, window.frame) } ?? false }
        let rules = [titled.filter(framed.contains), titled, framed]
        for matches in rules where !matches.isEmpty {
            guard matches.count == 1 else {
                throw SkreenrekError.windowAmbiguous(
                    query: String(window.id.rawValue),
                    candidates: matches.map { index in
                        WindowCandidate(
                            id: window.id, app: window.app, title: snapshots[index].title ?? window.title,
                            size: (snapshots[index].frame ?? window.frame).pixelSize(scale: scale))
                    })
            }
            return matches[0]
        }
        throw SkreenrekError.windowNotFound(query: String(window.id.rawValue))
    }

    static func sameFrame(_ a: PointRect, _ b: PointRect) -> Bool {
        abs(a.x - b.x) <= frameTolerance && abs(a.y - b.y) <= frameTolerance
            && abs(a.width - b.width) <= frameTolerance && abs(a.height - b.height) <= frameTolerance
    }
}
