import Foundation
import SkreenrekControl
import SkreenrekCore
@testable import SkreenrekUI
import Testing

enum UIFixtures {
    static let size = PixelSize(width: 1280, height: 800)
    static let safari = RenderSamples.armed.context.snapshot.window!
    static let paris = TimeZone(identifier: "Europe/Paris")!
    static let british = Locale(identifier: "en_GB")

    static func readback(actual: PixelSize, requested: PixelSize = size) -> Readback {
        Readback(
            window: Readback.Window(safari),
            display: Readback.Display(id: 1, name: "Built-in Retina Display", scale: 2), requested: requested,
            actual: actual, frame: PointRect(x: 120, y: 80, width: 643, height: 400), exact: actual == requested,
            attempts: 3)
    }

    static func context(
        _ snapshot: ControllerSnapshot, actionError: SkreenrekError? = nil, title: String? = nil,
        sizeChoice: SizeChoice = .default
    ) -> MenuContext {
        MenuContext(
            snapshot: snapshot, actionError: actionError, lastClipTitle: title, sizeChoice: sizeChoice,
            timeZone: paris, locale: british)
    }

    static let idle = ControllerSnapshot(state: .idle, fps: .fps60)
    static let armed = ControllerSnapshot(
        state: .armed, window: safari, displayId: 1, size: size, readback: readback(actual: size), fps: .fps60)
    static func recording(_ startedBy: StartedBy, client: String? = nil, elapsed: Double = 12.6) -> ControllerSnapshot {
        ControllerSnapshot(
            state: .recording, elapsed: elapsed, window: safari, displayId: 1, size: size, fps: .fps60,
            startedBy: startedBy, client: client)
    }
}

extension MenuEntry {
    /// A one-line description for comparing whole menus.
    var line: String {
        switch self {
        case .status(let row): "[\(row.symbol)\(row.tint == .red ? " red" : "")] \(row.title) | \(row.detail)"
        case .separator: "---"
        case .header(let title): "# \(title)"
        case .item(let item):
            (item.checked ? "✓ " : "") + item.title + (item.shortcut.map { " " + $0.display } ?? "")
                + (item.enabled ? "" : " (disabled)") + (item.isDefault ? " (default)" : "")
        case .submenu(let submenu): "\(submenu.title) ▸ \(submenu.detail ?? "")"
        }
    }
}

func lines(_ context: MenuContext) -> [String] { MenuModel.entries(for: context).map(\.line) }

@Suite struct MenuModelTests {
    @Test func idleNoWindowNoClip() {
        #expect(
            lines(UIFixtures.context(UIFixtures.idle)) == [
                "[record.circle] Ready | No window picked",
                "---",
                "Pick Window…",
                "Size ▸ Current Size",
                "Frame Rate ▸ 60 fps",
                "---",
                "✓ Show Cursor",
                "✓ Write Click Events",
                "---",
                "Record Window (disabled)",
                "---",
                "Open Output Folder",
                "Settings… ⌘,",
                "Quit Skreenrek ⌘Q",
            ])
    }

    @Test func armedExact() {
        let menu = lines(UIFixtures.context(UIFixtures.armed))
        #expect(menu[0] == "[viewfinder] Safari — localhost:3000 | 1280 × 800 px · 60 fps")
        #expect(MenuModel.entries(for: UIFixtures.context(UIFixtures.armed)).first?.statusRow?.toolTip == nil)
        #expect(menu.contains("Pick Another Window…"))
        #expect(!menu.contains("Pick Window…"))
        #expect(menu.contains("Record Window"))
    }

    @Test func armedNotExact() throws {
        var snapshot = UIFixtures.armed
        snapshot.size = PixelSize(width: 1286, height: 800)
        snapshot.readback = UIFixtures.readback(actual: PixelSize(width: 1286, height: 800))
        let menu = lines(UIFixtures.context(snapshot))
        #expect(menu[0] == "[viewfinder] Safari — localhost:3000 | 1286 × 800 px · not exact")
        #expect(menu.contains("Record Window"))
        let row = try #require(MenuModel.entries(for: UIFixtures.context(snapshot)).first?.statusRow)
        let reason = "Safari won't go narrower than 1286 px, so the clip is 1286 × 800 instead of 1280 × 800."
        #expect(row.toolTip == reason)
        #expect(row.accessibilityLabel == "Safari — localhost:3000. 1286 × 800 px · not exact. \(reason)")
        // The Size submenu keeps the requested size, not the read-back.
        let size = MenuModel.entries(for: UIFixtures.context(snapshot)).compactMap { entry -> SubmenuModel? in
            if case .submenu(let submenu) = entry, submenu.title == "Size" { return submenu }
            return nil
        }.first
        #expect(size?.detail == "Current Size")
    }

    @Test func notExactReasonsNameTheLimit() {
        let requested = PixelSize(width: 1280, height: 800)
        func reason(_ actual: PixelSize, _ why: NotExactReason) -> String {
            UIStrings.Menu.notExactReason(app: "Terminal", requested: requested, actual: actual, reason: why)
        }
        #expect(
            reason(PixelSize(width: 1280, height: 812), .minHeight(812))
                == "Terminal won't go shorter than 812 px, so the clip is 1280 × 812 instead of 1280 × 800.")
        #expect(
            reason(PixelSize(width: 1200, height: 800), .maxWidth(1200))
                == "Terminal won't go wider than 1200 px, so the clip is 1200 × 800 instead of 1280 × 800.")
        #expect(
            reason(PixelSize(width: 1280, height: 700), .maxHeight(700))
                == "Terminal won't go taller than 700 px, so the clip is 1280 × 700 instead of 1280 × 800.")
        #expect(
            reason(PixelSize(width: 1274, height: 798), .steps)
                == "Terminal resizes in steps, so the clip is 1274 × 798 instead of 1280 × 800.")
    }

    @Test func armedWithoutReadbackShowsTheSizeAlone() {
        var snapshot = UIFixtures.armed
        snapshot.readback = nil
        #expect(
            lines(UIFixtures.context(snapshot))[0] == "[viewfinder] Safari — localhost:3000 | 1280 × 800 px · 60 fps")
    }

    @Test(arguments: [
        (StartedBy.mcp, "Claude Code" as String?, "Started by Claude Code over MCP"),
        (.mcp, nil, "Started over MCP"),
        (.menu, nil, "Started from the menu"),
        (.cli, nil, "Started from the command line"),
    ])
    func recording(startedBy: StartedBy, client: String?, origin: String) {
        let menu = lines(UIFixtures.context(UIFixtures.recording(startedBy, client: client)))
        #expect(
            menu == [
                "[record.circle.fill red] Recording Safari — localhost:3000 | 0:12 · 1280 × 800 px · 60 fps",
                "\(origin) (disabled)",
                "---",
                "Stop Recording ⌃⌘⎋ (default)",
                "Discard Recording…",
                "---",
                "Open Output Folder",
                "Settings… ⌘,",
                "Quit Skreenrek ⌘Q",
            ])
    }

    @Test func sizeFrameRateAndPickingAreHiddenWhileRecording() {
        var snapshot = UIFixtures.recording(.cli)
        snapshot.lastClip = RenderSamples.clip()
        let titles = lines(UIFixtures.context(snapshot))
        for hidden in ["Pick", "Size", "Frame Rate", "Record Window", "Show Cursor", "Last Clip"] {
            #expect(!titles.contains { $0.contains(hidden) }, "\(hidden)")
        }
    }

    @Test func writing() {
        var snapshot = UIFixtures.recording(.menu, elapsed: 42)
        snapshot.state = .writing
        #expect(
            lines(UIFixtures.context(snapshot)) == [
                "[arrow.down.circle] Saving clip… | 0:42 · 1280 × 800 px · 60 fps",
                "Started from the menu (disabled)",
                "---",
                "Open Output Folder",
                "Settings… ⌘,",
                "Quit Skreenrek ⌘Q",
            ])
    }

    @Test func lastClipSection() {
        var snapshot = UIFixtures.idle
        snapshot.lastClip = RenderSamples.clip()
        let menu = lines(UIFixtures.context(snapshot, title: "Safari — localhost:3000"))
        let start = try! #require(menu.firstIndex(of: "# Last Clip"))
        #expect(
            Array(menu[start..<(start + 5)]) == [
                "# Last Clip",
                "[play.rectangle] Safari — localhost:3000 | 0:42 · 1280 × 800 px · 60 fps · 10:24",
                "Show in Finder",
                "Copy File Path",
                "Copy HyperFrames Snippet",
            ])
        let entries = MenuModel.entries(for: UIFixtures.context(snapshot))
        let actions = entries.compactMap { entry -> MenuAction? in
            if case .item(let item) = entry { return item.action }
            return nil
        }
        let clip = RenderSamples.clip()
        #expect(actions.contains(.showInFinder(path: clip.files.clip)))
        #expect(actions.contains(.copyFilePath(path: clip.files.clip)))
        #expect(actions.contains(.copySnippet(clip.snippet)))
    }

    @Test func lastClipTitleFallsBackToTheReadback() {
        var snapshot = UIFixtures.idle
        snapshot.lastClip = RenderSamples.clip()
        #expect(
            lines(UIFixtures.context(snapshot)).contains { $0.hasPrefix("[play.rectangle] Safari — localhost:3000") })
    }

    @Test func lastClipDetailDefaultFormatHasNoSuffix() {
        #expect(
            MenuModel.lastClipDetail(RenderSamples.clip(), timeZone: UIFixtures.paris, locale: UIFixtures.british)
                == "0:42 · 1280 × 800 px · 60 fps · 10:24")
    }

    @Test func lastClipDetailAppendsANonDefaultFormat() {
        let mov = RenderSamples.clip(file: "clip.mov")
        #expect(
            MenuModel.lastClipDetail(mov, timeZone: UIFixtures.paris, locale: UIFixtures.british)
                == "0:42 · 1280 × 800 px · 60 fps · H.264 MOV")
        let hevc = RenderSamples.clip(codec: .hevc)
        #expect(
            MenuModel.lastClipDetail(hevc, timeZone: UIFixtures.paris, locale: UIFixtures.british)
                == "0:42 · 1280 × 800 px · 60 fps · HEVC MP4")
        let prores = RenderSamples.clip(codec: .prores, file: "clip.mov")
        #expect(
            MenuModel.lastClipDetail(prores, timeZone: UIFixtures.paris, locale: UIFixtures.british)
                == "0:42 · 1280 × 800 px · 60 fps · ProRes MOV")
    }

    @Test func formatLabels() {
        #expect(ClipFormatLabel.suffix(codec: "prores", clipPath: "/x/clip.mov") == "ProRes MOV")
        #expect(ClipFormatLabel.suffix(codec: "hevc", clipPath: "/x/clip.mov") == "HEVC MOV")
        #expect(ClipFormatLabel.suffix(codec: "h264", clipPath: "/x/clip.mp4") == nil)
        // No container (a clip from before formats existed, or no extension) counts as mp4.
        #expect(ClipFormatLabel.suffix(codec: "h264", clipPath: "/x/clip") == nil)
    }

    @Test func sizeSubmenu() {
        let submenu = MenuModel.sizeSubmenu(.default)
        #expect(submenu.title == "Size")
        #expect(submenu.detail == "Current Size")
        #expect(
            submenu.entries.map(\.line) == [
                "720p", "1080p", "1440p", "4K", "---", "Square", "Portrait", "---", "✓ Current Size", "Custom…",
            ])
        let custom = MenuModel.sizeSubmenu(.size(PixelSize(width: 1000, height: 600)))
        #expect(custom.entries.last?.line == "✓ Custom…")
        #expect(custom.detail == "1000 × 600")
        #expect(MenuModel.sizeSubmenu(.size(PixelSize(width: 3840, height: 2160))).detail == "4K")
    }

    @Test func frameRateSubmenu() {
        let submenu = MenuModel.frameRateSubmenu(.fps30)
        #expect(submenu.detail == "30 fps")
        #expect(submenu.entries.map(\.line) == ["✓ 30 fps", "60 fps"])
    }
}

@Suite struct ErrorRowTests {
    static let clip = RenderSamples.clip()

    func rows(_ error: SkreenrekError, armed: Bool = false) -> [String] {
        var snapshot = armed ? UIFixtures.armed : UIFixtures.idle
        snapshot.lastClip = Self.clip
        snapshot.state = .error
        snapshot.error = error
        return lines(UIFixtures.context(snapshot))
    }

    @Test func windowClosed() {
        let menu = rows(.recordingFailed(.windowClosed(at: 31)))
        #expect(
            Array(menu.prefix(4)) == [
                "[exclamationmark.triangle] Recording stopped | The window closed at 0:31. "
                    + "The clip up to that point was saved.",
                "Show in Finder",
                "Copy Error Details",
                "---",
            ])
        // Then the normal idle items.
        #expect(menu[4] == "Pick Window…")
    }

    @Test func screenRecordingOff() {
        #expect(
            Array(rows(.permissionDenied(.screenRecording)).prefix(2)) == [
                "[exclamationmark.triangle] Screen Recording is off | Allow Skreenrek in System Settings › Privacy & "
                    + "Security, then reopen it.",
                "Open Privacy Settings…",
            ])
    }

    @Test func accessibilityOff() {
        #expect(
            Array(rows(.permissionDenied(.accessibility)).prefix(2)) == [
                "[exclamationmark.triangle] Can't resize windows | Allow Skreenrek in Accessibility settings to set "
                    + "exact sizes.",
                "Open Accessibility Settings…",
            ])
    }

    @Test func notExact() {
        let error = SkreenrekError.notExact(
            app: "Safari", requested: UIFixtures.size, actual: PixelSize(width: 1286, height: 800),
            reason: .minWidth(1286))
        let menu = rows(error, armed: true)
        #expect(
            Array(menu.prefix(2)) == [
                "[exclamationmark.triangle] Size isn't exact | Safari can't be narrower than 1286 px. "
                    + "It is 1286 × 800 px now.",
                "Pick Another Size…",
            ])
        #expect(menu.contains("Pick Another Window…"))
    }

    @Test func diskLow() {
        #expect(
            Array(rows(.recordingFailed(.diskLow(at: 252))).prefix(3)) == [
                "[exclamationmark.triangle] Recording stopped | Less than 2 GB free. The clip up to 4:12 was saved.",
                "Show in Finder",
                "---",
            ])
    }

    @Test func writeFailed() {
        #expect(
            Array(rows(.recordingFailed(.notWritable)).prefix(3)) == [
                "[exclamationmark.triangle] Couldn't save the clip | The output folder isn't writable.",
                "Choose Output Folder…",
                "---",
            ])
    }

    @Test func fixActions() {
        let presentation = ErrorPresentation(.permissionDenied(.screenRecording), lastClip: nil)
        #expect(presentation.fixes.map(\.action) == [.openPrivacySettings(.screenRecording)])
        let closed = ErrorPresentation(.recordingFailed(.windowClosed(at: 31)), lastClip: Self.clip)
        #expect(
            closed.fixes.map(\.action) == [
                .showInFinder(path: Self.clip.files.clip),
                .copyErrorDetails(
                    "error: The window closed at 0:31. The clip up to that point was saved.\n"
                        + "hint:  Find the partial clip with: skreenrek last"),
            ])
        #expect(
            ErrorPresentation(
                .notExact(
                    app: "A", requested: UIFixtures.size, actual: UIFixtures.size,
                    reason: .steps), lastClip: nil
            ).fixes.map(\.action) == [.customSize])
        #expect(
            ErrorPresentation(.recordingFailed(.notWritable), lastClip: nil).fixes.map(\.action) == [
                .chooseOutputFolder
            ])
    }

    @Test func anActionErrorShowsOverAnIdleController() {
        let context = UIFixtures.context(UIFixtures.idle, actionError: .permissionDenied(.screenRecording))
        #expect(context.displayState == .error)
        #expect(lines(context)[0].contains("Screen Recording is off"))
    }

    @Test func recordingHidesAnOldError() {
        let context = UIFixtures.context(
            UIFixtures.recording(.cli), actionError: .permissionDenied(.screenRecording))
        #expect(context.displayState == .recording)
        #expect(context.error == nil)
    }
}
