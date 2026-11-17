import Foundation

/// The clip folder: `<parent>/YYYY-MM-DD_HHMMSS_<slug>` in local time, created before recording starts.
public enum OutputFolder {
    /// Longest slug, in characters.
    public static let maxSlugLength = 40
    /// The slug used when the app name has no ASCII letters or digits.
    public static let fallbackSlug = "window"

    /// `~/Movies/Skreenrek/`.
    public static func defaultParent(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Movies", isDirectory: true).appendingPathComponent("Skreenrek", isDirectory: true)
    }

    /// Lowercase ASCII `[a-z0-9-]`: accents folded, every other run of characters becomes one `-`, no leading or
    /// trailing `-`, at most 40 characters. Empty when nothing is left.
    public static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
        var slug = ""
        var pendingDash = false
        for scalar in folded.unicodeScalars {
            let isAllowed = ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
            if isAllowed {
                if pendingDash, !slug.isEmpty { slug.append("-") }
                pendingDash = false
                slug.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        if slug.count > maxSlugLength {
            slug = String(slug.prefix(maxSlugLength))
            while slug.hasSuffix("-") { slug.removeLast() }
        }
        return slug
    }

    /// The slug for a recording: `name` (slugified) when given and non-empty, else `region` for regions, else the
    /// app name (or `window` when that slugifies to nothing).
    public static func slug(for target: CaptureTarget, name: String?) -> String {
        if let name {
            let named = slug(name)
            if !named.isEmpty { return named }
        }
        switch target {
        case .region:
            return "region"
        case .window(let window):
            let app = slug(window.app)
            return app.isEmpty ? fallbackSlug : app
        }
    }

    /// `YYYY-MM-DD_HHMMSS_<slug>` in `timeZone`.
    public static func baseName(date: Date, slug: String, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ value: Int?) -> String {
            let v = value ?? 0
            return v < 10 ? "0\(v)" : "\(v)"
        }
        return "\(c.year ?? 0)-\(two(c.month))-\(two(c.day))_\(two(c.hour))\(two(c.minute))\(two(c.second))_\(slug)"
    }

    /// Creates the clip folder under `parent` (default `~/Movies/Skreenrek/`, created if missing). A name taken in
    /// the same second gets `-2`, `-3`, …. Throws `recording_failed` (`The output folder isn't writable.`) when the
    /// parent can't be created or written.
    public static func create(
        in parent: URL?, target: CaptureTarget, name: String?, date: Date, timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) throws -> URL {
        let parent = parent ?? defaultParent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw SkreenrekError.recordingFailed(.notWritable)
        }
        guard fileManager.isWritableFile(atPath: parent.path) else {
            throw SkreenrekError.recordingFailed(.notWritable)
        }
        let base = baseName(date: date, slug: slug(for: target, name: name), timeZone: timeZone)
        var attempt = 1
        while true {
            let folderName = attempt == 1 ? base : "\(base)-\(attempt)"
            let folder = parent.appendingPathComponent(folderName, isDirectory: true)
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
                return folder
            } catch CocoaError.fileWriteFileExists {
                attempt += 1
            } catch {
                if fileManager.fileExists(atPath: folder.path) {
                    attempt += 1
                    continue
                }
                throw SkreenrekError.recordingFailed(.notWritable)
            }
        }
    }
}
