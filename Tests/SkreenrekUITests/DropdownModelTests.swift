import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekUI
import Testing

/// The dropdown's pure pieces: header states, menu icons and their tints, the Last Clip row, the in-place header
/// update, and the `render-ui` arguments.
@Suite struct DropdownModelTests {
    static func sample(_ name: String) throws -> MenuContext {
        try #require(RenderSamples.states.first { $0.name == name }).context
    }

    // MARK: - Header

    @Test func headerFollowsTheDisplayState() throws {
        let idle = DropdownModel.header(for: try Self.sample("idle"))
        #expect(idle.kind == .idle)
        #expect(idle.symbol == "record.circle")
        #expect(idle.title == "Ready")
        #expect(idle.detail == "No window picked")

        let armed = DropdownModel.header(for: try Self.sample("armed"))
        #expect(armed.kind == .armed)
        #expect(armed.symbol == "viewfinder")
        #expect(armed.detail == "1280 × 800 px · 60 fps")

        let notExact = DropdownModel.header(for: try Self.sample("armednotexact"))
        #expect(notExact.kind == .notExact)
        #expect(notExact.detail == "1286 × 800 px · not exact")

        let recording = DropdownModel.header(for: try Self.sample("recording"))
        #expect(recording.kind == .recording)
        #expect(recording.title == "Recording Safari — localhost:3000")
        #expect(recording.accessibilityLabel == "Recording Safari — localhost:3000, 12 seconds")
        #expect(recording.elapsed == "0:12")
        #expect(recording.detail == "1280 × 800 px · 60 fps")

        let saving = DropdownModel.header(for: try Self.sample("writing"))
        #expect(saving.kind == .saving)
        #expect(saving.title == "Saving clip…")

        let error = DropdownModel.header(for: try Self.sample("errorwindowclosed"))
        #expect(error.kind == .error)
        #expect(error.symbol == "exclamationmark.triangle.fill")
        #expect(error.title == "Recording stopped")
        #expect(error.fixes.map(\.title) == ["Show in Finder", "Copy Error Details"])
    }

    @Test func headerCarriesACompactRecordOrStopControl() throws {
        // Idle: Record, dimmed until a window is picked (like the Record Window item).
        let idle = try #require(DropdownModel.header(for: try Self.sample("idle")).control)
        #expect(idle.kind == .record && !idle.enabled)
        #expect(idle.title == "Record" && idle.elapsed == nil)
        #expect(idle.action == .record)
        #expect(idle.accessibilityLabel == "Record Window")

        for name in ["armed", "armednotexact", "lastclip"] {
            let control = DropdownModel.header(for: try Self.sample(name)).control
            #expect(control?.kind == .record, "\(name)")
            #expect(control?.enabled == (name != "lastclip"), "\(name)")
        }

        // Recording: Stop with the elapsed time; VoiceOver hears the time in words.
        let stop = try #require(DropdownModel.header(for: try Self.sample("recording")).control)
        #expect(stop.kind == .stop && stop.enabled)
        #expect(stop.title == "Stop" && stop.elapsed == "0:12")
        #expect(stop.action == .stop)
        #expect(stop.accessibilityLabel == "Stop Recording, 12 seconds")

        // Saving and errors have no control.
        for name in ["writing", "errorwindowclosed", "errorscreenrecording"] {
            #expect(DropdownModel.header(for: try Self.sample(name)).control == nil, "\(name)")
        }

        // The menu keeps its Record Window and Stop Recording items with their shortcuts.
        let recordingItems = DropdownModel.rows(for: try Self.sample("recording")).compactMap { row -> MenuItemModel? in
            if case .item(let item) = row { return item }
            return nil
        }
        #expect(recordingItems.first { $0.action == .stop }?.shortcut == .stop)
        #expect(DropdownModel.rows(for: try Self.sample("armed")).contains { row in
            if case .item(let item) = row { return item.action == .record && item.enabled }
            return false
        })
    }

    @Test func stopControlTicksWithTheHeaderInPlace() throws {
        let context = try Self.sample("recording")
        var later = context
        later.snapshot.elapsed = 75.2
        #expect(DropdownModel.header(for: later).control?.elapsed == "1:15")
        #expect(DropdownModel.header(for: later).control?.accessibilityLabel == "Stop Recording, 1 minute 15 seconds")
        #expect(DropdownModel.onlyHeaderDiffers(DropdownModel.rows(for: later), DropdownModel.rows(for: context)))
    }

    @Test func notExactReasonMovesToTheTooltipAndVoiceOver() throws {
        let context = try Self.sample("armednotexact")
        let header = DropdownModel.header(for: context)
        let sentence =
            "Not exact: Safari won't go narrower than 1286 px, so the clip is 1286 × 800 instead of 1280 × 800."
        #expect(header.help == sentence)
        #expect(header.accessibilityLabel == "Safari — localhost:3000. \(sentence)")
        // The Size row keeps the requested size.
        let sizes = DropdownModel.rows(for: context).compactMap { row -> String? in
            if case .submenu(let submenu) = row, submenu.title == "Size" { return submenu.detail }
            return nil
        }
        #expect(sizes == ["1280 × 800"])
        // An exact window has no tooltip.
        #expect(DropdownModel.header(for: try Self.sample("armed")).help == nil)
    }

    @Test func notExactReasonUsesTheRealAppAndSizes() {
        let requested = PixelSize(width: 1920, height: 1080)
        #expect(
            UIStrings.Brand.notExactReason(
                app: "Terminal", reason: .steps, requested: requested, actual: PixelSize(width: 1918, height: 1074))
                == "Not exact: Terminal resizes in steps, so the clip is 1918 × 1074 instead of 1920 × 1080.")
        #expect(
            UIStrings.Brand.notExactReason(
                app: "Notes", reason: .maxHeight(900), requested: requested, actual: PixelSize(width: 1920, height: 900))
                == "Not exact: Notes won't go taller than 900 px, so the clip is 1920 × 900 instead of 1920 × 1080.")
    }

    // MARK: - Dropdown rows

    @Test func dropdownSwapsInTheHeaderAndTheClipRow() throws {
        let rows = DropdownModel.rows(for: try Self.sample("lastclipprores"))
        guard case .header(let header) = rows.first else {
            Issue.record("The first row isn't the header")
            return
        }
        #expect(header.kind == .idle)
        let clips = rows.compactMap { row -> DropdownClip? in
            if case .clip(let clip) = row { return clip }
            return nil
        }
        #expect(clips.count == 1)
        #expect(clips.first?.title == "Safari — localhost:3000")
        #expect(clips.first?.detail == "0:42 · 1280 × 800 px · 60 fps · ProRes MOV")
        #expect(clips.first?.summary == "0:42 · 1280 × 800 px · 60 fps")
        #expect(clips.first?.note == "ProRes MOV")
        #expect(rows.contains(.sectionHeader("Last Clip")))
        // Only one header, and the Last Clip actions stay as menu items.
        #expect(rows.filter { if case .header = $0 { true } else { false } }.count == 1)
        let titles = rows.compactMap { row -> String? in
            if case .item(let item) = row { return item.title }
            return nil
        }
        #expect(titles.contains("Copy HyperFrames Snippet"))
    }

    @Test func defaultClipNoteIsTheStartTime() throws {
        let clip = try #require(DropdownModel.lastClip(for: try Self.sample("lastclip")))
        #expect(clip.summary == "0:42 · 1280 × 800 px · 60 fps")
        #expect(clip.note == "10:24")
        // VoiceOver reads the shipping one-line detail.
        #expect(clip.detail == "0:42 · 1280 × 800 px · 60 fps · 10:24")
        #expect(clip.accessibilityLabel == "Safari — localhost:3000. 0:42 · 1280 × 800 px · 60 fps · 10:24")
        // A clip from this session (its title came from the recording) gets the accent stroke.
        #expect(clip.isNewest)
    }

    @Test func recordingDropdownShowsTheOriginAsAnInfoRow() throws {
        let rows = DropdownModel.rows(for: try Self.sample("recording"))
        #expect(rows.contains(.info("Started by Claude Code over MCP")))
    }

    @Test func menuIconsMatchTheDirectionsDoc() {
        #expect(DropdownModel.symbol(for: .pickWindow) == "macwindow")
        #expect(DropdownModel.symbol(for: .toggleCursor) == "cursorarrow")
        #expect(DropdownModel.symbol(for: .toggleEvents) == "cursorarrow.click")
        #expect(DropdownModel.symbol(for: .record) == "record.circle")
        #expect(DropdownModel.symbol(for: .openOutputFolder) == "folder")
        #expect(DropdownModel.symbol(for: .openSettings) == "gearshape")
        #expect(DropdownModel.symbol(for: .quit) == nil)
        #expect(DropdownModel.symbol(for: .stop) == "stop.fill")
        #expect(DropdownModel.symbol(for: .discard) == "trash")
        #expect(DropdownModel.symbol(for: .showInFinder(path: "/x")) == "folder")
        #expect(DropdownModel.symbol(for: .copyFilePath(path: "/x")) == "doc.on.doc")
        #expect(DropdownModel.symbol(for: .copySnippet("")) == "chevron.left.forwardslash.chevron.right")
        #expect(DropdownModel.symbol(for: .copyErrorDetails("")) == "doc.on.clipboard")
        #expect(DropdownModel.symbol(forSubmenu: "Size") == "aspectratio")
        #expect(DropdownModel.symbol(forSubmenu: "Frame Rate") == "speedometer")
        #expect(DropdownModel.symbol(for: .showPermissions) == "hand.raised")
    }

    @Test func onlyThePrimaryItemAndStopAreTinted() throws {
        func tints(_ name: String) throws -> [String: DropdownModel.IconTint] {
            let context = try Self.sample(name)
            var tints: [String: DropdownModel.IconTint] = [:]
            for case .item(let item) in DropdownModel.rows(for: context) {
                tints[item.title] = DropdownModel.iconTint(for: item, context: context)
            }
            return tints
        }
        let idle = try tints("idle")
        #expect(idle["Pick Window…"] == .accent)
        #expect(idle["Record Window"] == .neutral)  // disabled until a window is picked
        #expect(idle.values.filter { $0 != .neutral }.count == 1)
        let armed = try tints("armed")
        #expect(armed["Record Window"] == .red)
        #expect(armed["Pick Another Window…"] == .neutral)
        #expect(armed.values.filter { $0 != .neutral }.count == 1)
        let recording = try tints("recording")
        #expect(recording["Stop Recording"] == .red)
        #expect(recording["Discard Recording…"] == .neutral)
    }

    @Test func everyStateStartsWithOneHeader() throws {
        for sample in RenderSamples.states {
            let rows = DropdownModel.rows(for: sample.context)
            guard case .header(let header) = rows.first else {
                Issue.record("\(sample.name) doesn't start with the header")
                continue
            }
            #expect(rows.filter(\.isHeaderRow).count == 1, "\(sample.name)")
            #expect(!header.title.isEmpty && !header.accessibilityLabel.isEmpty, "\(sample.name)")
            // The rows keep every action the shipping entries have, in order.
            let actions = rows.compactMap { row -> MenuAction? in
                if case .item(let item) = row { return item.action }
                return nil
            }
            let shipping = MenuModel.entries(for: sample.context).compactMap { entry -> MenuAction? in
                if case .item(let item) = entry { return item.action }
                return nil
            }
            #expect(actions == shipping, "\(sample.name)")
        }
    }

    @Test func onlyTheHeaderChangesWhileRecording() throws {
        let context = try Self.sample("recording")
        var later = context
        later.snapshot.elapsed = 13.2
        let before = DropdownModel.rows(for: context)
        let after = DropdownModel.rows(for: later)
        #expect(before != after)
        #expect(DropdownModel.onlyHeaderDiffers(after, before))
        #expect(!DropdownModel.onlyHeaderDiffers(DropdownModel.rows(for: try Self.sample("idle")), before))
    }

    // MARK: - render-ui arguments

    @Test func renderArgumentsDrawTheShippingUI() {
        let out = URL(fileURLWithPath: "/tmp/r", isDirectory: true)
        #expect(RenderUIRequest.parse(["debug", "render-ui", "--out", "/tmp/r"]) == .shipping(out: out))
        // C is the shipping UI; `--direction c` stays as an alias.
        #expect(RenderUIRequest.parse(["debug", "render-ui", "--direction", "C", "--out", "/tmp/r"]) == .shipping(out: out))
        #expect(RenderUIRequest.parse(["debug", "render-ui", "--out", "/tmp/r", "--direction", "size13"]) == .size13(out: out))
        for retired in ["a", "b", "all", "c-menubar"] {
            #expect(RenderUIRequest.parse(["debug", "render-ui", "--out", "/tmp/r", "--direction", retired]) == nil)
        }
        #expect(RenderUIRequest.parse(["debug", "render-ui", "--direction", "c"]) == nil)
        #expect(RenderUIRequest.parse(["debug", "render-ui", "--out"]) == nil)
        #expect(RenderUIRequest.parse(["record", "--out", "/tmp/r"]) == nil)
    }
}

extension DropdownRow {
    var isHeaderRow: Bool {
        if case .header = self { return true }
        return false
    }
}
