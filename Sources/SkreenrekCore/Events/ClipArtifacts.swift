import Foundation

/// Writes a finished clip's side files: `events.json` (unless `events` is off) and `hyperframes.html`.
///
/// Called once the clip is finalized, so `stats.stopToFinalizedMs` is known. With `events: false` no `events.json` is
/// written (the stats still reach `stop --json` through the recording result).
public enum ClipArtifacts {
    public struct Written: Sendable, Hashable {
        /// `events.json`, or nil with `events: false`.
        public var eventsFile: URL?
        public var snippetFile: URL
        public var snippet: String
        /// `<assetsDir>/<clip-id>.mp4` when an assets folder was given.
        public var assetCopy: URL?

        public init(eventsFile: URL?, snippetFile: URL, snippet: String, assetCopy: URL?) {
            self.eventsFile = eventsFile
            self.snippetFile = snippetFile
            self.snippet = snippet
            self.assetCopy = assetCopy
        }
    }

    /// - Parameters:
    ///   - log: the `EventRecorder` log; nil (or `events: false`) skips `events.json`.
    ///   - complete: false for a partial clip after a failure.
    public static func write(
        recording: EventsFile.Recording, complete: Bool, log: EventLog?, events: Bool, assetsDir: URL?,
        clipFolder: URL, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> Written {
        var eventsFile: URL?
        if events, let log {
            eventsFile = try EventsFile(recording: recording, complete: complete, log: log).write(to: clipFolder)
        }
        let input = SnippetBuilder.Input(recording: recording, hasEvents: eventsFile != nil)
        let snippet = try SnippetBuilder.write(
            input, clipFolder: clipFolder, assetsDir: assetsDir, homeDirectory: homeDirectory)
        return Written(
            eventsFile: eventsFile, snippetFile: clipFolder.appendingPathComponent(SnippetBuilder.fileName),
            snippet: snippet, assetCopy: assetsDir?.appendingPathComponent("\(recording.id).\(recording.video.container.rawValue)"))
    }
}
