/// One Accessibility window of an app, as read by the real resizer: its title and frame (top-left global pt).
public struct AXWindowSnapshot: Sendable, Hashable {
    public var title: String?
    /// Nil when the frame couldn't be read; such a window only matches by title.
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
    /// with any match decides. `window_not_found` when nothing matches, `windowIndistinct` (exit 5) when a rule
    /// matches more than one window.
    ///
    /// - Parameter siblings: the listed windows of the same app (any order, `window` may be among them). They give
    ///   each look-alike its own window ID in the error, so the list names real, distinct windows.
    public static func pick(
        _ window: WindowInfo, among snapshots: [AXWindowSnapshot], siblings: [WindowInfo] = [], scale: Double = 1
    ) throws -> Int {
        let titled = snapshots.indices.filter { snapshots[$0].title == window.title }
        let framed = snapshots.indices.filter { snapshots[$0].frame.map { sameFrame($0, window.frame) } ?? false }
        let rules = [titled.filter(framed.contains), titled, framed]
        for matches in rules where !matches.isEmpty {
            guard matches.count == 1 else {
                throw SkreenrekError.windowIndistinct(
                    app: window.app, count: matches.count,
                    candidates: candidates(for: matches.map { snapshots[$0] }, window: window, siblings: siblings,
                                           scale: scale))
            }
            return matches[0]
        }
        throw SkreenrekError.windowNotFound(query: String(window.id.rawValue))
    }

    /// One candidate per look-alike that a listed window accounts for, each with a distinct window ID: `window`
    /// itself first, then the listed siblings that look the same (title and frame), front to back.
    static func candidates(
        for lookAlikes: [AXWindowSnapshot], window: WindowInfo, siblings: [WindowInfo], scale: Double
    ) -> [WindowCandidate] {
        var pool = [window] + siblings.filter { $0.id != window.id && $0.pid == window.pid }
        var result: [WindowCandidate] = []
        for snapshot in lookAlikes {
            guard let index = pool.firstIndex(where: { looksLike(snapshot, $0) }) else { continue }
            let listed = pool.remove(at: index)
            result.append(
                WindowCandidate(
                    id: listed.id, app: listed.app, title: listed.title, size: listed.frame.pixelSize(scale: scale)))
        }
        return result
    }

    static func looksLike(_ snapshot: AXWindowSnapshot, _ window: WindowInfo) -> Bool {
        let titleMatches = snapshot.title.map { $0 == window.title } ?? true
        let frameMatches = snapshot.frame.map { sameFrame($0, window.frame) } ?? true
        return titleMatches && frameMatches
    }

    static func sameFrame(_ a: PointRect, _ b: PointRect) -> Bool {
        abs(a.x - b.x) <= frameTolerance && abs(a.y - b.y) <= frameTolerance
            && abs(a.width - b.width) <= frameTolerance && abs(a.height - b.height) <= frameTolerance
    }
}
