import Foundation
import SkreenrekControl
import SkreenrekCore

/// The design spec's human output, character for character. Pure: tests check it as goldens.
struct HumanFormat: Sendable {
    var style: Style
    /// The home folder, shown as `~`.
    var home: String

    /// `Safari — localhost:3000`, or just `Safari` for an untitled window.
    static func windowName(app: String, title: String) -> String {
        title.isEmpty ? app : "\(app) — \(title)"
    }

    /// `~/Movies/Skreenrek/…` for paths in the home folder.
    func tilde(_ path: String) -> String {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        if path == home { return "~" }
        if !home.isEmpty, path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// `2×`, `1.5×`.
    static func scale(_ scale: Double) -> String {
        "\(number(scale))×"
    }

    /// `640`, `640.5`.
    static func number(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e12 { return String(Int(value)) }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    /// One column-aligned row per window: `<id>  <app>  <title>  <w> × <h> px`.
    func windows(_ body: WindowsBody) -> String {
        table(
            body.windows.map {
                [String($0.id.rawValue), $0.app, $0.title, PixelSize(width: $0.width, height: $0.height).description]
            })
    }

    /// Rows with columns padded to the widest cell, two spaces apart; the last column isn't padded.
    func table(_ rows: [[String]]) -> String {
        guard let columns = rows.map(\.count).max() else { return "" }
        var widths = [Int](repeating: 0, count: columns)
        for row in rows {
            for (i, cell) in row.enumerated() { widths[i] = max(widths[i], cell.count) }
        }
        return rows.map { row in
            row.enumerated().map { i, cell in
                i == row.count - 1 ? cell : cell + String(repeating: " ", count: widths[i] - cell.count)
            }.joined(separator: "  ")
        }.map { $0 + "\n" }.joined()
    }

    /// `resize`: `✓ Safari — localhost:3000 is 1280 × 800 px (640 × 400 pt at 2×)`.
    func resize(_ readback: Readback) -> String {
        let pt = "\(Self.number(readback.frame.width)) × \(Self.number(readback.frame.height)) pt"
        return check() + " \(Self.windowName(app: readback.window.app, title: readback.window.title)) is "
            + "\(readback.actual) (\(pt) at \(Self.scale(readback.display.scale)))\n" + inexactNote(readback)
    }

    /// `record` with a size: `✓ Safari — localhost:3000 is 1280 × 800 px`.
    func recordReadback(_ readback: Readback) -> String {
        check() + " \(Self.windowName(app: readback.window.app, title: readback.window.title)) is \(readback.actual)\n"
            + inexactNote(readback)
    }

    /// `● Recording at 60 fps. Stop with: skreenrek stop`.
    func recording(_ start: StartBody) -> String {
        style.red("●") + " Recording at \(start.fps) fps. Stop with: skreenrek stop\n"
    }

    /// `stop` and `last`: the saved line, the three aligned paths, and the quiet note when the recording wasn't clean
    /// or used the software encoder.
    func saved(_ body: StopBody) -> String {
        let r = body.recording
        var lines = [
            check() + " Saved \(TimeFormat.minutesSeconds(r.duration)) · "
                + "\(PixelSize(width: r.width, height: r.height)) · \(r.fps) fps",
            "  clip    \(tilde(body.files.clip))",
        ]
        if let events = body.files.events { lines.append("  events  \(tilde(events))") }
        lines.append("  snippet \(tilde(body.files.snippet))")
        if let note = Self.statsNote(r.stats) { lines.append(style.dim("  note    \(note)")) }
        return lines.map { $0 + "\n" }.joined()
    }

    /// `3 dropped frames · software encoder`; nil when the recording is clean and used the hardware encoder.
    static func statsNote(_ stats: RecordingStats) -> String? {
        var parts: [String] = []
        if stats.framesDropped > 0 { parts.append(count(stats.framesDropped, "dropped frame")) }
        if stats.sourceFramesSkipped > 0 { parts.append(count(stats.sourceFramesSkipped, "skipped frame")) }
        if stats.encoder == .software { parts.append("software encoder") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `✓ Discarded the recording.`
    func discarded() -> String {
        check() + " Discarded the recording.\n"
    }

    /// `pick`: the chosen window as a `windows` row, the region, or `Pick cancelled.`
    func pick(_ body: PickBody) -> String {
        switch body {
        case .window(let entry):
            return windows(WindowsBody(windows: [entry]))
        case .region(let picked):
            let r = picked.region
            return "region \(r.x),\(r.y),\(r.width),\(r.height) on display \(picked.displayId)  \(r.size)\n"
        case .cancelled:
            return "Pick cancelled.\n"
        }
    }

    /// `status`: the state word, plus the window and elapsed time when recording.
    func status(_ body: StatusBody) -> String {
        var parts = [body.state.rawValue]
        switch body.state {
        case .recording, .writing:
            if let window = body.window {
                parts.append(Self.windowName(app: window.app, title: window.title))
            } else if let r = body.recording {
                parts.append("region \(PixelSize(width: r.width, height: r.height))")
            }
            if let r = body.recording { parts.append(TimeFormat.minutesSeconds(r.elapsed)) }
        case .armed:
            if let window = body.window {
                parts.append(Self.windowName(app: window.app, title: window.title))
                parts.append(PixelSize(width: window.width, height: window.height).description)
            }
        case .error:
            if let error = body.error { parts.append(error.message) }
        case .idle:
            break
        }
        return parts.joined(separator: " · ") + "\n"
    }

    /// A `doctor` line: `✓ Screen Recording   Allowed`.
    func doctorLine(ok: Bool, label: String, detail: String, labelWidth: Int) -> String {
        let mark = ok ? check() : style.red("✗")
        return mark + " " + label + String(repeating: " ", count: max(0, labelWidth - label.count)) + "  " + detail
            + "\n"
    }

    /// `error: …` then `hint:  …`.
    func error(_ body: ErrorBody) -> String {
        style.red("error:") + " \(body.message)\nhint:  \(body.hint)\n"
    }

    private func inexactNote(_ readback: Readback) -> String {
        readback.exact ? "" : style.dim("  note    not exact: \(readback.requested) was asked for") + "\n"
    }

    private func check() -> String { style.green("✓") }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
