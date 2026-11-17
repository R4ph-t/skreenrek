import AppKit
import SkreenrekCore
import SwiftUI

/// What `skreenrek debug render-ui` was asked for.
public enum RenderUIRequest: Sendable, Equatable {
    /// No `--direction`: today's shipping UI and file names.
    case shipping(out: URL)
    /// `--direction a|b|c` writes that direction into `out`; `--direction all` writes `out/a`, `out/b` and `out/c`.
    case directions([UIDirection], out: URL, nested: Bool)

    /// Parses the arguments after the executable: `debug render-ui --out DIR [--direction a|b|c|all]`, flags in any
    /// order. Nil for anything else (the CLI handles it).
    public static func parse(_ arguments: [String]) -> RenderUIRequest? {
        guard arguments.count >= 2, arguments[0] == "debug", arguments[1] == "render-ui" else { return nil }
        var out: String?
        var direction: String?
        var rest = arguments.dropFirst(2)[...]
        while let flag = rest.popFirst() {
            guard let value = rest.popFirst() else { return nil }
            switch flag {
            case "--out" where out == nil: out = value
            case "--direction" where direction == nil: direction = value.lowercased()
            default: return nil
            }
        }
        guard let out else { return nil }
        let folder = URL(fileURLWithPath: (out as NSString).expandingTildeInPath, isDirectory: true)
        switch direction {
        case nil: return .shipping(out: folder)
        case "all": return .directions(UIDirection.allCases, out: folder, nested: true)
        case let name?:
            guard let one = UIDirection(rawValue: name) else { return nil }
            return .directions([one], out: folder, nested: false)
        }
    }
}

/// Renders the v2 direction mockups (A, B, C) as PNGs at 2× in light and dark:
/// `dropdown-<state>-<light|dark>@2x.png` for each state and `settings-default-<light|dark>@2x.png`.
@MainActor
public enum DirectionRenderer {
    /// File state name → `RenderSamples` sample name.
    public static let states: [(file: String, sample: String)] = [
        ("idle", "idle"),
        ("armednotexact", "armednotexact"),
        ("recording", "recording"),
        ("saving", "writing"),
        ("error-windowclosed", "errorwindowclosed"),
        ("lastclip-mp4", "lastclip"),
        ("lastclip-prores", "lastclipprores"),
    ]

    /// Every file name one direction writes.
    public static var fileNames: [String] {
        UIRenderer.Appearance.allCases.flatMap { appearance in
            states.map { "dropdown-\($0.file)-\(appearance.rawValue)@2x.png" }
                + ["settings-default-\(appearance.rawValue)@2x.png"]
        }
    }

    @discardableResult
    public static func render(_ request: RenderUIRequest) throws -> [UIRenderer.Rendered] {
        switch request {
        case .shipping(let out):
            return try UIRenderer.renderAll(to: out)
        case .directions(let directions, let out, let nested):
            return try directions.flatMap { direction in
                try render(direction, to: nested ? out.appendingPathComponent(direction.rawValue) : out)
            }
        }
    }

    @discardableResult
    public static func render(_ direction: UIDirection, to folder: URL) throws -> [UIRenderer.Rendered] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let thumbnail = SampleFrame.image()
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-preview-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        // Claude Code and Codex found, Cursor not installed: every agent row form shows.
        for agent in [".claude", ".codex"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(agent), withIntermediateDirectories: true)
        }
        var written: [UIRenderer.Rendered] = []
        for appearance in UIRenderer.Appearance.allCases {
            for state in states {
                guard let sample = RenderSamples.states.first(where: { $0.name == state.sample }) else { continue }
                let view = dropdown(direction, context: sample.context, thumbnail: thumbnail)
                let url = folder.appendingPathComponent("dropdown-\(state.file)-\(appearance.rawValue)@2x.png")
                written.append(try UIRenderer.write(view, appearance: appearance, active: true, to: url))
            }
            let url = folder.appendingPathComponent("settings-default-\(appearance.rawValue)@2x.png")
            written.append(
                try UIRenderer.write(settings(direction, home: home), appearance: appearance, active: true, to: url))
        }
        return written
    }

    static func dropdown(_ direction: UIDirection, context: MenuContext, thumbnail: NSImage?) -> NSView {
        switch direction {
        case .a, .c:
            RefitHostingView.fitted(
                DirectionDropdownView(context: context, branded: direction == .c, thumbnail: thumbnail)
                    .environment(\.controlActiveState, .key).environment(\.drawsActiveControls, true))
        case .b:
            RefitHostingView.fitted(
                DirectionPanelView(context: context, thumbnail: thumbnail).environment(\.controlActiveState, .key).environment(\.drawsActiveControls, true))
        }
    }

    static func settings(_ direction: UIDirection, home: URL) -> NSView {
        let defaults = UserDefaults(suiteName: "skreenrek.render-ui.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults, home: URL(fileURLWithPath: "/Users/you", isDirectory: true))
        store.outputFolder = URL(fileURLWithPath: "/Users/you/Movies/Skreenrek", isDirectory: true)
        let panel = SettingsPanelState(
            permissions: StaticPermissions(screenRecording: .allowed, accessibility: .missing),
            loginItem: StaticLoginItem(),
            agents: AgentsPanelState(
                installer: AgentInstaller(home: home, executablePath: "/unused/skreenrek", path: "")))
        return RefitHostingView.fitted(
            DirectionSettingsView(
                direction: direction, store: store, panel: panel, actions: .none, version: SkreenrekVersion.current
            )
            .environment(\.controlActiveState, .key).environment(\.drawsActiveControls, true))
    }
}

/// A hosting view the offscreen render re-measures once it sits in a window (grouped forms and wrapping text only
/// settle there).
protocol RenderRefitting: NSView {}

final class RefitHostingView<Content: View>: NSHostingView<Content>, RenderRefitting {}
