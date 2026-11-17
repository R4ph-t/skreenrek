import Foundation

/// Process exit codes, one per row of the exit-code table.
public enum SkreenrekExitCode: Int32, Sendable, Codable, CaseIterable {
    case success = 0
    case `internal` = 1
    case usage = 2
    case permissionDenied = 3
    case notExact = 4
    case windowNotFoundOrAmbiguous = 5
    case wrongState = 6
    case recordingFailed = 7
    /// Ctrl-C during `record --wait`: the clip is stopped and saved.
    case interrupted = 130
}

/// A permission Skreenrek's app needs.
public enum Permission: String, Sendable, Codable, Hashable, CaseIterable {
    case screenRecording
    case accessibility
}

/// A window in an ambiguity list, with the pixel size shown for it.
public struct WindowCandidate: Sendable, Hashable {
    public var window: WindowInfo
    public var pixelSize: PixelSize

    public init(window: WindowInfo, pixelSize: PixelSize) {
        self.window = window
        self.pixelSize = pixelSize
    }

    /// `<id>  <app>  <title>  <w> × <h> px`
    public var line: String {
        "\(window.id)  \(window.app)  \(window.title)  \(pixelSize.width) × \(pixelSize.height) px"
    }
}

/// Every error Skreenrek reports to a person or an agent. Each has an exit code, a stable `code`, a one-sentence
/// `message` and a `hint` with the next command or action.
public enum SkreenrekError: Error, Sendable, Hashable {
    /// Something that shouldn't happen, or the app isn't reachable. Exit 1.
    case `internal`(message: String, hint: String)
    /// A bad flag, argument or size. Exit 2.
    case usage(message: String, hint: String)
    /// Screen Recording or Accessibility is off for Skreenrek. Exit 3.
    case permissionDenied(Permission)
    /// The window didn't take the exact size. Exit 4. 02 builds the reason and hint from the read-back.
    case notExact(message: String, hint: String)
    /// No window matches. Exit 5.
    case windowNotFound(query: String)
    /// More than one window matches, front to back. Exit 5.
    case windowAmbiguous(query: String, candidates: [WindowCandidate])
    /// The action isn't possible in the controller's current state. Exit 6.
    case wrongState(message: String, hint: String)
    /// Recording stopped early or couldn't write. Exit 7.
    case recordingFailed(message: String, hint: String)

    public var exitCode: SkreenrekExitCode {
        switch self {
        case .internal: .internal
        case .usage: .usage
        case .permissionDenied: .permissionDenied
        case .notExact: .notExact
        case .windowNotFound, .windowAmbiguous: .windowNotFoundOrAmbiguous
        case .wrongState: .wrongState
        case .recordingFailed: .recordingFailed
        }
    }

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
        }
    }

    public var message: String {
        switch self {
        case .internal(let message, _), .usage(let message, _), .notExact(let message, _),
            .wrongState(let message, _), .recordingFailed(let message, _):
            message
        case .permissionDenied(.screenRecording):
            ErrorCopy.screenRecordingOffMessage
        case .permissionDenied(.accessibility):
            ErrorCopy.accessibilityOffMessage
        case .windowNotFound(let query):
            "No window matches \(query)."
        case .windowAmbiguous(let query, let candidates):
            (["\(candidates.count) windows match \(query). Pass a window ID:"] + candidates.map(\.line))
                .joined(separator: "\n")
        }
    }

    public var hint: String {
        switch self {
        case .internal(_, let hint), .usage(_, let hint), .notExact(_, let hint), .wrongState(_, let hint),
            .recordingFailed(_, let hint):
            hint
        case .permissionDenied(.screenRecording):
            ErrorCopy.screenRecordingOffHint
        case .permissionDenied(.accessibility):
            ErrorCopy.accessibilityOffHint
        case .windowNotFound:
            "List windows with: skreenrek windows"
        case .windowAmbiguous(_, let candidates):
            if let first = candidates.first {
                "skreenrek record \(first.window.id)"
            } else {
                "List windows with: skreenrek windows"
            }
        }
    }
}

/// Fixed copy for errors whose wording comes from the design spec.
public enum ErrorCopy {
    public static let screenRecordingOffMessage = "Screen Recording is off for Skreenrek."
    public static let screenRecordingOffHint =
        "Turn on Skreenrek in System Settings › Privacy & Security › Screen Recording, then run: skreenrek doctor"
    public static let accessibilityOffMessage = "Can't resize windows. Accessibility is off for Skreenrek."
    public static let accessibilityOffHint =
        "Turn on Skreenrek in System Settings › Privacy & Security › Accessibility, then run: skreenrek doctor"
}

extension SkreenrekError: LocalizedError {
    public var errorDescription: String? { message }
}

extension SkreenrekError: Encodable {
    private struct Body: Encodable {
        var code: String
        var message: String
        var hint: String
        var exit: Int32
    }

    private enum CodingKeys: String, CodingKey { case error }

    /// `{ "error": { "code", "message", "hint", "exit" } }`
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            Body(code: code, message: message, hint: hint, exit: exitCode.rawValue), forKey: .error)
    }
}
