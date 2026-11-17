import Foundation

/// A permission Skreenrek needs.
public enum Permission: String, Sendable, Hashable, Codable, CaseIterable {
    case screenRecording
    case accessibility
}

/// Why a resize didn't reach the requested size.
public enum NotExactReason: Sendable, Hashable {
    /// The app won't go narrower than this width (px).
    case minWidth(Int)
    /// The app won't go shorter than this height (px).
    case minHeight(Int)
    /// The app won't go wider than this width (px).
    case maxWidth(Int)
    /// The app won't go taller than this height (px).
    case maxHeight(Int)
    /// The app resizes in steps (e.g. character cells), so the requested size isn't possible.
    case steps
}

/// One window in an ambiguous-match list.
public struct WindowCandidate: Sendable, Hashable, Codable {
    public var id: WindowID
    public var app: String
    public var title: String
    public var size: PixelSize

    public init(id: WindowID, app: String, title: String, size: PixelSize) {
        self.id = id
        self.app = app
        self.title = title
        self.size = size
    }
}

/// Which state rule a command broke.
public enum WrongStateReason: Sendable, Hashable {
    case alreadyRecording
    case notRecording
    case stillWriting
}

/// Why a recording stopped early. A partial clip may exist.
public enum RecordingFailure: Sendable, Hashable {
    /// The window closed at this clip time (seconds).
    case windowClosed(at: TimeInterval)
    /// Free space fell below 2 GB at this clip time (seconds).
    case diskLow(at: TimeInterval)
    /// The output folder isn't writable.
    case notWritable
    /// Any other capture or writer failure, as one sentence.
    case other(String)
}

/// Every error Skreenrek reports, one case per row of the design spec's exit-code table.
public enum SkreenrekError: Error, Sendable, Hashable {
    /// Exit 1.
    case `internal`(message: String)
    /// Exit 2: a bad flag or value.
    case usage(message: String, hint: String)
    /// Exit 3.
    case permissionDenied(Permission)
    /// Exit 4: the size read back isn't the size asked for.
    case notExact(app: String, requested: PixelSize, actual: PixelSize, reason: NotExactReason)
    /// Exit 5: `query` is how the window was named, e.g. `--app Safari` or `4127`.
    case windowNotFound(query: String)
    /// Exit 5: candidates are front to back.
    case windowAmbiguous(query: String, candidates: [WindowCandidate])
    /// Exit 6.
    case wrongState(WrongStateReason)
    /// Exit 7: a partial clip may exist.
    case recordingFailed(RecordingFailure)
    /// Exit 130: Ctrl-C during `--wait`; the clip is saved.
    case interrupted

    public var exitCode: Int32 {
        switch self {
        case .internal: 1
        case .usage: 2
        case .permissionDenied: 3
        case .notExact: 4
        case .windowNotFound, .windowAmbiguous: 5
        case .wrongState: 6
        case .recordingFailed: 7
        case .interrupted: 130
        }
    }

    /// The machine-readable code from the design spec.
    public var code: String {
        switch self {
        case .internal: "internal"
        case .usage: "usage"
        case .permissionDenied: "permission_denied"
        case .notExact: "not_exact"
        case .windowNotFound: "window_not_found"
        case .windowAmbiguous: "window_ambiguous"
        case .wrongState: "wrong_state"
        case .recordingFailed: "recording_failed"
        case .interrupted: "interrupted"
        }
    }

    /// What happened, in one sentence. For `windowAmbiguous` the candidate lines follow the sentence.
    public var message: String {
        switch self {
        case .internal(let message):
            return message
        case .usage(let message, _):
            return message
        case .permissionDenied(.screenRecording):
            return "Screen Recording isn't allowed for Skreenrek."
        case .permissionDenied(.accessibility):
            return "Accessibility isn't allowed for Skreenrek."
        case .notExact(let app, let requested, let actual, let reason):
            switch reason {
            case .minWidth(let px): return "\(app) can't be narrower than \(px) px. It is \(actual) now."
            case .minHeight(let px): return "\(app) can't be shorter than \(px) px. It is \(actual) now."
            case .maxWidth(let px): return "\(app) can't be wider than \(px) px. It is \(actual) now."
            case .maxHeight(let px): return "\(app) can't be taller than \(px) px. It is \(actual) now."
            case .steps:
                return "\(app) resizes in steps, so \(requested) isn't possible. It is \(actual) now."
            }
        case .windowNotFound(let query):
            return "No window matches \(query)."
        case .windowAmbiguous(let query, let candidates):
            return (["\(candidates.count) windows match \(query). Pass a window ID:"]
                + Self.candidateLines(candidates)).joined(separator: "\n")
        case .wrongState(.alreadyRecording):
            return "A recording is already running."
        case .wrongState(.notRecording):
            return "No recording is running."
        case .wrongState(.stillWriting):
            return "Skreenrek is still saving the last clip."
        case .recordingFailed(.windowClosed(let at)):
            return "The window closed at \(TimeFormat.minutesSeconds(at)). The clip up to that point was saved."
        case .recordingFailed(.diskLow(let at)):
            return "Less than 2 GB free. The clip up to \(TimeFormat.minutesSeconds(at)) was saved."
        case .recordingFailed(.notWritable):
            return "The output folder isn't writable."
        case .recordingFailed(.other(let message)):
            return message
        case .interrupted:
            return "Recording stopped with Ctrl-C. The clip was saved."
        }
    }

    /// The exact next command or action.
    public var hint: String {
        switch self {
        case .internal:
            return "Run: skreenrek doctor"
        case .usage(_, let hint):
            return hint
        case .permissionDenied(.screenRecording):
            return "Allow it in System Settings › Privacy & Security › Screen & System Audio Recording, then run: "
                + "skreenrek doctor"
        case .permissionDenied(.accessibility):
            return "Allow it in System Settings › Privacy & Security › Accessibility, then run: skreenrek doctor"
        case .notExact(_, _, _, let reason):
            switch reason {
            case .minWidth(let px): return "Pick a width of \(px) px or more, or pass --allow-inexact."
            case .minHeight(let px): return "Pick a height of \(px) px or more, or pass --allow-inexact."
            case .maxWidth(let px): return "Pick a width of \(px) px or less, or pass --allow-inexact."
            case .maxHeight(let px): return "Pick a height of \(px) px or less, or pass --allow-inexact."
            case .steps: return "Pick another size, or pass --allow-inexact."
            }
        case .windowNotFound:
            return "List the windows you can record with: skreenrek windows"
        case .windowAmbiguous(_, let candidates):
            let id = candidates.first.map { String($0.id.rawValue) } ?? "<id>"
            return "Pass one of the IDs above, e.g. skreenrek record \(id)"
        case .wrongState(.alreadyRecording):
            return "Stop it with: skreenrek stop"
        case .wrongState(.notRecording):
            return "Start one with: skreenrek record <window>"
        case .wrongState(.stillWriting):
            return "Wait a moment, then run: skreenrek status"
        case .recordingFailed(.notWritable):
            return "Choose another folder with --out DIR, or in Settings."
        case .recordingFailed(.diskLow):
            return "Free up disk space, then find the clip with: skreenrek last"
        case .recordingFailed:
            return "Find the partial clip with: skreenrek last"
        case .interrupted:
            return "Find the clip with: skreenrek last"
        }
    }

    /// `  4127  Safari  localhost:3000  1280 × 800 px`, columns aligned.
    static func candidateLines(_ candidates: [WindowCandidate]) -> [String] {
        let idWidth = candidates.map { String($0.id.rawValue).count }.max() ?? 0
        let appWidth = candidates.map(\.app.count).max() ?? 0
        let titleWidth = candidates.map(\.title.count).max() ?? 0
        return candidates.map { c in
            "  " + pad(String(c.id.rawValue), idWidth) + "  " + pad(c.app, appWidth) + "  " + pad(c.title, titleWidth)
                + "  " + c.size.description
        }
    }

    private static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }

    /// The JSON body: `{ "code", "message", "hint", "exit" }`.
    public var body: ErrorBody {
        ErrorBody(code: code, message: message, hint: hint, exit: exitCode)
    }
}

/// The error body every surface prints or returns.
public struct ErrorBody: Sendable, Hashable, Codable {
    public var code: String
    public var message: String
    public var hint: String
    public var exit: Int32

    public init(code: String, message: String, hint: String, exit: Int32) {
        self.code = code
        self.message = message
        self.hint = hint
        self.exit = exit
    }
}

/// `{ "error": { "code", "message", "hint", "exit" } }`.
public struct ErrorEnvelope: Sendable, Hashable, Codable {
    public var error: ErrorBody

    public init(error: ErrorBody) {
        self.error = error
    }
}

extension SkreenrekError: Encodable {
    /// Encodes as `{ "error": { "code", "message", "hint", "exit" } }`.
    public func encode(to encoder: any Encoder) throws {
        try ErrorEnvelope(error: body).encode(to: encoder)
    }
}
