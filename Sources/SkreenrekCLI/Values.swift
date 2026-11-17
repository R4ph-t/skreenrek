import Foundation
import SkreenrekControl
import SkreenrekCore

/// Parses flag values. Every failure is a `usage` error (exit 2) with the exact fix.
enum Values {
    /// A clip size: `720p|1080p|1440p|4k|square|portrait`, `1920x1080` (also `X` or `×`) in pixels, or
    /// `1920x1080px` (the same).
    static func size(_ text: String) throws -> PixelSize {
        try SizeSpec.parse(text)
    }

    /// `30s`, `2m`, `1m30s`, or plain seconds (`45`, `2.5`). Must be more than 0.
    static func duration(_ text: String) throws -> TimeInterval {
        let invalid = SkreenrekError.usage(
            message: "\"\(text)\" isn't a duration.", hint: "Pass --duration as 30s, 2m, 1m30s or plain seconds.")
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        var seconds: TimeInterval
        if let plain = Double(trimmed), plain.isFinite {
            seconds = plain
        } else {
            let pattern = /^(?:(\d+(?:\.\d+)?)m)?(?:(\d+(?:\.\d+)?)s)?$/
            guard !trimmed.isEmpty, let match = trimmed.wholeMatch(of: pattern),
                match.output.1 != nil || match.output.2 != nil
            else { throw invalid }
            seconds = (match.output.1.flatMap { Double($0) } ?? 0) * 60 + (match.output.2.flatMap { Double($0) } ?? 0)
        }
        guard seconds > 0 else {
            throw SkreenrekError.usage(
                message: "The duration must be more than 0 seconds.", hint: "Pass a --duration such as 30s.")
        }
        return seconds
    }

    /// `X,Y,W,H` in pixels of the display, top-left origin.
    static func region(_ text: String) throws -> RegionParams {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4, let x = Int(parts[0]), let y = Int(parts[1]), let w = positiveInt(parts[2]),
            let h = positiveInt(parts[3])
        else {
            throw SkreenrekError.usage(
                message: "\"\(text)\" isn't a region.",
                hint: "Pass --region X,Y,W,H in pixels of the display, e.g. --region 0,0,1280,800.")
        }
        return RegionParams(x: x, y: y, width: w, height: h)
    }

    /// `30` or `60`.
    static func fps(_ value: Int) throws -> Int {
        guard FrameRate(rawValue: value) != nil else {
            throw SkreenrekError.usage(message: "Frame rate \(value) isn't offered.", hint: "Pass --fps 30 or --fps 60.")
        }
        return value
    }

    /// `h264` or `hevc`.
    static func codec(_ text: String) throws -> String {
        guard let codec = VideoCodec(rawValue: text.lowercased()) else {
            throw SkreenrekError.usage(
                message: "\"\(text)\" isn't a codec Skreenrek can record.", hint: "Use --codec h264, hevc or prores.")
        }
        return codec.rawValue
    }

    /// A display ID.
    static func display(_ text: String) throws -> DisplayID {
        guard let id = DisplayID(text) else {
            throw SkreenrekError.usage(
                message: "\"\(text)\" isn't a display ID.", hint: "Leave out --display to use the main display.")
        }
        return id
    }

    /// An absolute folder path: `~` expands to the home folder, a relative path resolves against `base`.
    static func folder(_ text: String, home: URL, base: URL) -> String {
        if text == "~" { return home.path }
        if text.hasPrefix("~/") { return home.appendingPathComponent(String(text.dropFirst(2))).standardizedFileURL.path }
        if text.hasPrefix("/") { return URL(fileURLWithPath: text).standardizedFileURL.path }
        return base.appendingPathComponent(text).standardizedFileURL.path
    }

    private static func positiveInt(_ text: some StringProtocol) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value
    }
}

/// How a command names its window: `<window>` (an ID) or `--app NAME [--title TEXT]`. Neither means the armed window.
struct WindowRef: Sendable, Hashable {
    var windowId: UInt32?
    var app: String?
    var title: String?

    static func parse(id: String?, app: String?, title: String?) throws -> WindowRef {
        if let id {
            guard let value = UInt32(id) else {
                throw SkreenrekError.usage(
                    message: "\"\(id)\" isn't a window ID.",
                    hint: "Pass a numeric ID from: skreenrek windows, or use --app NAME.")
            }
            guard app == nil else {
                throw SkreenrekError.usage(
                    message: "Pass a window ID or --app, not both.", hint: "Drop the window ID, or drop --app.")
            }
            guard title == nil else {
                throw SkreenrekError.usage(
                    message: "--title only works with --app.", hint: "Drop --title, or replace the ID with --app NAME.")
            }
            return WindowRef(windowId: value)
        }
        if title != nil, app == nil {
            throw SkreenrekError.usage(message: "--title only works with --app.", hint: "Add --app NAME.")
        }
        return WindowRef(app: app, title: title)
    }

    var isEmpty: Bool { windowId == nil && app == nil }
}
