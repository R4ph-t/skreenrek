import Foundation

/// Builds `hyperframes.html`: one comment line, an optional copy-command comment, and a single HyperFrames clip
/// element whose `src` is always `assets/<clip-id>.mp4`.
///
/// The text never holds an absolute path inside the home folder or a user name: the copy command uses `~/…`.
public enum SnippetBuilder {
    public static let fileName = "hyperframes.html"

    public struct Input: Sendable, Hashable {
        public var clipId: String
        public var source: EventsFile.Source
        public var width: Int
        public var height: Int
        public var fps: Int
        public var duration: Double
        /// Whether `events.json` was written (adds `· clicks: events.json`).
        public var hasEvents: Bool

        public init(
            clipId: String, source: EventsFile.Source, width: Int, height: Int, fps: Int, duration: Double,
            hasEvents: Bool
        ) {
            self.clipId = clipId
            self.source = source
            self.width = width
            self.height = height
            self.fps = fps
            self.duration = duration
            self.hasEvents = hasEvents
        }

        public init(recording: EventsFile.Recording, hasEvents: Bool) {
            self.init(
                clipId: recording.id, source: recording.source, width: recording.video.width,
                height: recording.video.height, fps: recording.fps, duration: recording.duration,
                hasEvents: hasEvents)
        }
    }

    /// Where the copy-command comment points, or nothing when the clip was already copied into an assets folder.
    public enum CopyHint: Sendable, Hashable {
        /// The clip was copied to `<assetsDir>/<clip-id>.mp4`: no copy command.
        case none
        /// `cp <clipFolder>/clip.mp4 assets/<clip-id>.mp4`, with `homeDirectory` written as `~`.
        case copyCommand(clipFolder: URL, homeDirectory: URL)
    }

    /// The snippet text (pure). Ends with a newline.
    public static func text(_ input: Input, copy: CopyHint) -> String {
        var parts = [
            "Skreenrek", label(input.source, width: input.width, height: input.height),
            "\(input.width)×\(input.height) px", "\(input.fps) fps", "\(oneDecimal(input.duration)) s",
        ]
        if input.hasEvents { parts.append("clicks: events.json") }
        var lines = ["<!-- \(parts.joined(separator: " · ")) -->"]
        let asset = "assets/\(input.clipId).mp4"
        if case .copyCommand(let folder, let home) = copy {
            let clip = displayPath(folder.appendingPathComponent("clip.mp4"), home: home)
            lines.append("<!-- Copy the clip first: cp \(clip) \(asset) -->")
        }
        lines.append("<video class=\"clip\" src=\"\(asset)\"")
        lines.append(
            "       data-start=\"0\" data-duration=\"\(oneDecimal(input.duration))\" data-track-index=\"0\" muted playsinline></video>"
        )
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the snippet into `clipFolder` and returns the same text. With `assetsDir`, first copies `clip.mp4` to
    /// `<assetsDir>/<clip-id>.mp4` (creating the folder, replacing an older copy) and leaves the copy command out.
    @discardableResult
    public static func write(
        _ input: Input, clipFolder: URL, assetsDir: URL?, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> String {
        let copy: CopyHint
        if let assetsDir {
            try copyClip(from: clipFolder, clipId: input.clipId, to: assetsDir)
            copy = .none
        } else {
            copy = .copyCommand(clipFolder: clipFolder, homeDirectory: homeDirectory)
        }
        let snippet = text(input, copy: copy)
        try Data(snippet.utf8).write(to: clipFolder.appendingPathComponent(fileName), options: .atomic)
        return snippet
    }

    /// Copies `clip.mp4` to `<assetsDir>/<clip-id>.mp4` and returns the destination.
    @discardableResult
    public static func copyClip(from clipFolder: URL, clipId: String, to assetsDir: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        let destination = assetsDir.appendingPathComponent("\(clipId).mp4")
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.copyItem(at: clipFolder.appendingPathComponent("clip.mp4"), to: destination)
        return destination
    }

    // MARK: - pieces

    /// `App — Title` (just `App` without a title), or `Region 1280×800 px`.
    static func label(_ source: EventsFile.Source, width: Int, height: Int) -> String {
        switch source {
        case .window(let app, _, let title, _, _):
            let app = commentSafe(app)
            let title = commentSafe(title)
            return title.isEmpty ? app : "\(app) — \(title)"
        case .region:
            return "Region \(width)×\(height) px"
        }
    }

    /// Keeps text valid inside an HTML comment on one line: `--` becomes `—`, `>` becomes `›`, `<` becomes `‹`, and
    /// line breaks become spaces.
    static func commentSafe(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: ">", with: "›")
            .replacingOccurrences(of: "<", with: "‹")
        while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "—") }
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value.isFinite ? value : 0)
    }

    /// The path with the home folder written as `~`.
    static func displayPath(_ url: URL, home: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        let trimmedHome = homePath.hasSuffix("/") ? String(homePath.dropLast()) : homePath
        if !trimmedHome.isEmpty, path.hasPrefix(trimmedHome + "/") {
            return "~" + path.dropFirst(trimmedHome.count)
        }
        return path
    }
}
