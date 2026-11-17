import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekUI
import Testing

/// The v2 direction mockups' pure pieces: header states, menu icons, Last Clip, B's keyboard model, and the
/// `render-ui` arguments.
@Suite struct DirectionModelTests {
    static func sample(_ name: String) throws -> MenuContext {
        try #require(RenderSamples.states.first { $0.name == name }).context
    }

    // MARK: - Header

    @Test func headerFollowsTheDisplayState() throws {
        let idle = DirectionModel.header(for: try Self.sample("idle"))
        #expect(idle.kind == .idle)
        #expect(idle.symbol == "record.circle")
        #expect(idle.title == "Ready")
        #expect(idle.detail == "No window picked")

        let armed = DirectionModel.header(for: try Self.sample("armed"))
        #expect(armed.kind == .armed)
        #expect(armed.symbol == "viewfinder")
        #expect(armed.detail == "1280 × 800 px · exact size")

        let notExact = DirectionModel.header(for: try Self.sample("armednotexact"))
        #expect(notExact.kind == .notExact)
        #expect(notExact.detail == "1286 × 800 px · not exact (min width 1286 px)")

        let recording = DirectionModel.header(for: try Self.sample("recording"))
        #expect(recording.kind == .recording)
        #expect(recording.title == "Recording Safari — localhost:3000")
        #expect(recording.elapsed == "0:12")
        #expect(recording.detail == "1280 × 800 px · 60 fps")

        let saving = DirectionModel.header(for: try Self.sample("writing"))
        #expect(saving.kind == .saving)
        #expect(saving.title == "Saving clip…")

        let error = DirectionModel.header(for: try Self.sample("errorwindowclosed"))
        #expect(error.kind == .error)
        #expect(error.symbol == "exclamationmark.triangle.fill")
        #expect(error.title == "Recording stopped")
        #expect(error.fixes.map(\.title) == ["Show in Finder", "Copy Error Details"])
    }

    @Test func panelRecordingLineNamesWhoStartedIt() throws {
        #expect(
            DirectionModel.panelRecordingDetail(try Self.sample("recording"))
                == "1280 × 800 px · 60 fps · started by Claude Code")
        #expect(
            DirectionModel.panelRecordingDetail(try Self.sample("writing"))
                == "1280 × 800 px · 60 fps · started from the menu")
    }

    // MARK: - Dropdown rows (A and C)

    @Test func dropdownSwapsInTheHeaderAndTheClipRow() throws {
        let rows = DirectionModel.dropdownRows(for: try Self.sample("lastclipprores"))
        guard case .header(let header) = rows.first else {
            Issue.record("The first row isn't the header")
            return
        }
        #expect(header.kind == .idle)
        let clips = rows.compactMap { row -> DirectionClip? in
            if case .clip(let clip) = row { return clip }
            return nil
        }
        #expect(clips.count == 1)
        #expect(clips.first?.title == "Safari — localhost:3000")
        #expect(clips.first?.detail == "0:42 · 1280 × 800 px · 60 fps · ProRes MOV")
        #expect(rows.contains(.sectionHeader("Last Clip")))
        // Only one header, and the Last Clip actions stay as menu items.
        #expect(rows.filter { if case .header = $0 { true } else { false } }.count == 1)
        let titles = rows.compactMap { row -> String? in
            if case .item(let item) = row { return item.title }
            return nil
        }
        #expect(titles.contains("Copy HyperFrames Snippet"))
    }

    @Test func recordingDropdownShowsTheOriginAsAnInfoRow() throws {
        let rows = DirectionModel.dropdownRows(for: try Self.sample("recording"))
        #expect(rows.contains(.info("Started by Claude Code over MCP")))
    }

    @Test func menuIconsMatchTheDirectionsDoc() {
        #expect(DirectionModel.symbol(for: .pickWindow) == "macwindow")
        #expect(DirectionModel.symbol(for: .toggleCursor) == "cursorarrow")
        #expect(DirectionModel.symbol(for: .toggleEvents) == "cursorarrow.click")
        #expect(DirectionModel.symbol(for: .record) == "record.circle")
        #expect(DirectionModel.symbol(for: .openOutputFolder) == "folder")
        #expect(DirectionModel.symbol(for: .openSettings) == "gearshape")
        #expect(DirectionModel.symbol(for: .quit) == nil)
        #expect(DirectionModel.symbol(for: .stop) == "stop.fill")
        #expect(DirectionModel.symbol(for: .discard) == "trash")
        #expect(DirectionModel.symbol(for: .showInFinder(path: "/x")) == "folder")
        #expect(DirectionModel.symbol(for: .copyFilePath(path: "/x")) == "doc.on.doc")
        #expect(DirectionModel.symbol(for: .copySnippet("")) == "chevron.left.forwardslash.chevron.right")
        #expect(DirectionModel.symbol(forSubmenu: "Size") == "aspectratio")
        #expect(DirectionModel.symbol(forSubmenu: "Frame Rate") == "speedometer")
    }

    // MARK: - Panel keyboard (B)

    @Test func focusRunsPrimaryTilesTogglesThenClipButtons() throws {
        #expect(
            DirectionModel.focusOrder(for: try Self.sample("lastclip")) == [
                .primary, .sizeTile, .frameRateTile, .cursorToggle, .eventsToggle, .clipFinder, .clipCopyPath,
                .clipSnippet, .settings, .more,
            ])
        #expect(DirectionModel.initialFocus(for: try Self.sample("idle")) == .primary)
        let armed = DirectionModel.focusOrder(for: try Self.sample("armed"))
        #expect(Array(armed.prefix(3)) == [.primary, .pickAnother, .sizeTile])
        let error = DirectionModel.focusOrder(for: try Self.sample("errorwindowclosed"))
        #expect(Array(error.prefix(4)) == [.primary, .fix(0), .fix(1), .sizeTile])
        #expect(DirectionModel.focusOrder(for: try Self.sample("recording")) == [.primary, .discard, .settings, .more])
    }

    @Test func returnTriggersThePrimaryButtonWhereverFocusIs() throws {
        let idle = try Self.sample("idle")
        #expect(DirectionModel.command(for: .returnKey, focus: .eventsToggle, context: idle) == .perform(.pickWindow))
        let armed = try Self.sample("armed")
        #expect(DirectionModel.command(for: .returnKey, focus: .sizeTile, context: armed) == .perform(.record))
        let recording = try Self.sample("recording")
        #expect(DirectionModel.command(for: .returnKey, focus: .discard, context: recording) == .perform(.stop))
        #expect(DirectionModel.command(for: .returnKey, focus: nil, context: try Self.sample("writing")) == nil)
    }

    @Test func escapeClosesAndTabWraps() throws {
        let context = try Self.sample("idle")
        #expect(DirectionModel.command(for: .escape, focus: .primary, context: context) == .close)
        #expect(DirectionModel.command(for: .tab, focus: .primary, context: context) == .focus(.sizeTile))
        #expect(DirectionModel.command(for: .tab, focus: .more, context: context) == .focus(.primary))
        #expect(DirectionModel.command(for: .backTab, focus: .primary, context: context) == .focus(.more))
        #expect(DirectionModel.command(for: .tab, focus: nil, context: context) == .focus(.primary))
        // A clip button that isn't on screen (no clip) restarts the walk.
        #expect(DirectionModel.command(for: .tab, focus: .clipSnippet, context: context) == .focus(.primary))
    }

    // MARK: - render-ui arguments

    @Test func renderArgumentsKeepTheShippingDefault() {
        let out = URL(fileURLWithPath: "/tmp/r", isDirectory: true)
        #expect(RenderUIRequest.parse(["debug", "render-ui", "--out", "/tmp/r"]) == .shipping(out: out))
        #expect(
            RenderUIRequest.parse(["debug", "render-ui", "--direction", "b", "--out", "/tmp/r"])
                == .directions([.b], out: out, nested: false))
        #expect(
            RenderUIRequest.parse(["debug", "render-ui", "--out", "/tmp/r", "--direction", "ALL"])
                == .directions([.a, .b, .c], out: out, nested: true))
        #expect(RenderUIRequest.parse(["debug", "render-ui", "--out", "/tmp/r", "--direction", "d"]) == nil)
        #expect(RenderUIRequest.parse(["debug", "render-ui", "--direction", "a"]) == nil)
        #expect(RenderUIRequest.parse(["debug", "render-ui", "--out"]) == nil)
        #expect(RenderUIRequest.parse(["record", "--out", "/tmp/r"]) == nil)
    }
}
