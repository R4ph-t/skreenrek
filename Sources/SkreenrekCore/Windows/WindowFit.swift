import CoreGraphics
import Foundation

/// A named clip size from spec 13: the video you get, in exact pixels.
public enum SizePreset: String, CaseIterable, Sendable, Hashable, Codable {
    case p720 = "720p"
    case p1080 = "1080p"
    case p1440 = "1440p"
    case uhd4k = "4k"
    case square
    case portrait

    /// The menu's title: `720p`, `4K`, `Square`.
    public var title: String {
        switch self {
        case .p720: "720p"
        case .p1080: "1080p"
        case .p1440: "1440p"
        case .uhd4k: "4K"
        case .square: "Square"
        case .portrait: "Portrait"
        }
    }

    public var size: PixelSize {
        switch self {
        case .p720: PixelSize(width: 1280, height: 720)
        case .p1080: PixelSize(width: 1920, height: 1080)
        case .p1440: PixelSize(width: 2560, height: 1440)
        case .uhd4k: PixelSize(width: 3840, height: 2160)
        case .square: PixelSize(width: 1080, height: 1080)
        case .portrait: PixelSize(width: 1080, height: 1920)
        }
    }

    /// The smaller preset a tooltip or hint suggests when this one doesn't fit.
    public var fallback: SizePreset? {
        switch self {
        case .p720: nil
        case .p1080: .p720
        case .p1440: .p1080
        case .uhd4k: .p1440
        case .square: .p720
        case .portrait: .square
        }
    }

    /// The preset whose clip is exactly `size`, if any.
    public init?(size: PixelSize) {
        guard let match = Self.allCases.first(where: { $0.size == size }) else { return nil }
        self = match
    }

    /// The `--size` and MCP `size` value: `720p`, `1080p`, `1440p`, `4k`, `square`, `portrait` (any case).
    public init?(name: String) {
        self.init(rawValue: name.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// `720p|1080p|1440p|4k|square|portrait`.
    public static var names: String { allCases.map(\.rawValue).joined(separator: "|") }
}

/// A clip size as `--size` and MCP `size` spell it: a preset name, `WxH` (pixels), or `WxHpx` (the same).
public enum SizeSpec {
    public static func parse(_ text: String) throws(SkreenrekError) -> PixelSize {
        if let preset = SizePreset(name: text) { return preset.size }
        var body = text.trimmingCharacters(in: .whitespaces)
        if body.lowercased().hasSuffix("px") { body = String(body.dropLast(2)) }
        let parts = body.split(omittingEmptySubsequences: false) { $0 == "x" || $0 == "X" || $0 == "×" }
        guard parts.count == 2,
            let width = Int(parts[0].trimmingCharacters(in: .whitespaces)), width > 0,
            let height = Int(parts[1].trimmingCharacters(in: .whitespaces)), height > 0
        else {
            throw .usage(
                message: "\"\(text)\" isn't a size.",
                hint: "Pass --size \(SizePreset.names), or WxH in pixels, e.g. --size 1920x1080.")
        }
        return PixelSize(width: width, height: height)
    }
}

/// A window size in whole points: `window{width,height}` in the read-back.
public struct WindowPoints: Sendable, Hashable, Codable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// `1440 × 810`.
    public var description: String { "\(width) × \(height)" }
}

/// Where a clip size puts the window on a display: the largest window of the clip's shape that fits the visible
/// frame minus 32 pt on each side, at most the clip size in points and at least half of it (and never so small that
/// the clip would be scaled up). The clip is recorded at the display's native resolution and scaled down to the
/// exact clip size.
public struct WindowPlan: Sendable, Hashable {
    public var clip: PixelSize
    public var window: WindowPoints
    /// Clip px cropped (at most 1 per dimension) when no window of the exact aspect fits; nil when it matches.
    public var cropped: PixelSize?
    public var displayScale: Double

    /// The window's pixels on the display.
    public var native: PixelSize {
        PixelSize(
            width: Int((Double(window.width) * displayScale).rounded()),
            height: Int((Double(window.height) * displayScale).rounded()))
    }

    /// Native pixels per clip pixel: 1.5 for 1080p from a 1440 × 810 pt window at 2×. Never below 1.
    public var nativeToClip: Double { WindowFit.nativeToClip(window: window, clip: clip, scale: displayScale) }
}

/// Why a clip size doesn't fit a display: the smallest window it needs and the room the display has, in points.
public struct WindowFitFailure: Error, Sendable, Hashable {
    public var clip: PixelSize
    public var needs: WindowPoints
    public var fits: WindowPoints
}

public enum WindowFit {
    /// Points kept clear on each side of the visible frame.
    public static let margin = 32.0

    /// The room for a window on `display`: its visible frame minus `margin` on each side, in whole points.
    public static func room(on display: DisplayInfo) -> WindowPoints {
        WindowPoints(
            width: max(0, Int((display.visibleFrame.width - margin * 2).rounded(.down))),
            height: max(0, Int((display.visibleFrame.height - margin * 2).rounded(.down))))
    }

    /// The smallest window that gives `clip` without scaling up: half the clip in points, or the whole clip on a
    /// display below 2×.
    public static func minimumWindow(for clip: PixelSize, scale: Double) -> WindowPoints {
        let divisor = max(1, min(2, scale))
        return WindowPoints(
            width: Int((Double(clip.width) / divisor).rounded(.up)),
            height: Int((Double(clip.height) / divisor).rounded(.up)))
    }

    /// The window for `clip` on `display`. Exact aspect first; otherwise the largest window whose aspect matches the
    /// clip plus one px in width and/or height, which is then cropped by that px. Never letterboxes.
    public static func plan(clip: PixelSize, on display: DisplayInfo) -> Result<WindowPlan, WindowFitFailure> {
        let room = room(on: display)
        var best: WindowPlan?
        for (cw, ch) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
            let target = PixelSize(width: clip.width + cw, height: clip.height + ch)
            let minimum = minimumWindow(for: target, scale: display.scale)
            let g = gcd(target.width, target.height)
            let (a, b) = (target.width / g, target.height / g)
            let k = min(min(clip.width, room.width) / a, min(clip.height, room.height) / b)
            guard k >= 1 else { continue }
            let window = WindowPoints(width: k * a, height: k * b)
            guard window.width >= minimum.width, window.height >= minimum.height else { continue }
            let candidate = WindowPlan(
                clip: clip, window: window, cropped: cw + ch == 0 ? nil : PixelSize(width: cw, height: ch),
                displayScale: display.scale)
            if cw + ch == 0 { return .success(candidate) }
            if best.map({ window.width * window.height > $0.window.width * $0.window.height }) ?? true {
                best = candidate
            }
        }
        if let best { return .success(best) }
        return .failure(
            WindowFitFailure(clip: clip, needs: minimumWindow(for: clip, scale: display.scale), fits: room))
    }

    /// Whether `clip` fits `display` at all.
    public static func fits(_ clip: PixelSize, on display: DisplayInfo) -> Bool {
        if case .success = plan(clip: clip, on: display) { return true }
        return false
    }

    /// The part of a window (in window-local points) that becomes the clip: centred, cropped to the clip's aspect
    /// on the long side, never letterboxed. Nil when the aspects already match.
    public static func sourceRect(window: CGSize, clip: PixelSize) -> CGRect? {
        guard window.width > 0, window.height > 0, clip.width > 0, clip.height > 0 else { return nil }
        let clipAspect = Double(clip.width) / Double(clip.height)
        let windowAspect = window.width / window.height
        if abs(windowAspect - clipAspect) < 1e-9 { return nil }
        if windowAspect > clipAspect {
            let width = window.height * clipAspect
            return CGRect(x: (window.width - width) / 2, y: 0, width: width, height: window.height)
        }
        let height = window.width / clipAspect
        return CGRect(x: 0, y: (window.height - height) / 2, width: window.width, height: height)
    }

    /// Native pixels per clip pixel for a window of `window` pt at `scale`, rounded to 3 places.
    public static func nativeToClip(window: WindowPoints, clip: PixelSize, scale: Double) -> Double {
        let size = CGSize(width: window.width, height: window.height)
        let source = sourceRect(window: size, clip: clip)?.size ?? size
        let ratio = source.width * scale / Double(clip.width)
        return (ratio * 1000).rounded() / 1000
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}

// MARK: - Copy

extension WindowFitFailure {
    /// The clip's name in sentences: `4K`, or `1720 × 1080 px` for a custom size.
    public var name: String { SizePreset(size: clip)?.title ?? clip.description }

    /// The disabled preset's tooltip, e.g. "4K needs room for a 1920 × 1080 pt window. Use a larger display or pick
    /// 1440p."
    public var tooltip: String {
        let fallback = SizePreset(size: clip)?.fallback.map { " or pick \($0.title)" } ?? ""
        return "\(name) needs room for a \(needs) pt window. Use a larger display\(fallback)."
    }

    /// The `usage` error (exit 2) for a size that can't fit without scaling up:
    /// `4K needs a window at least 1920 × 1080 on screen; this display fits 1448 × 870` with the tooltip's sentences
    /// and the flag to use as the hint.
    public var error: SkreenrekError {
        let flag = SizePreset(size: clip)?.fallback.map { "use --size \($0.rawValue), or " } ?? "use a smaller --size, or "
        return .usage(
            message: "\(name) needs a window at least \(needs) on screen; this display fits \(fits)",
            hint: "\(tooltip) \(flag.prefix(1).uppercased() + flag.dropFirst())move the window to a larger display.")
    }
}
