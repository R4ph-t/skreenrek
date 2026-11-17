import CoreGraphics
import Foundation
import SkreenrekCore
import SkreenrekTesting
import Testing

@Suite struct ExactResizerTests {
    typealias F = WindowFixtures

    static func target(_ window: WindowInfo, on display: DisplayInfo) -> ResolvedWindow {
        var window = window
        window.displayId = display.id
        return ResolvedWindow(window: window, display: display)
    }

    static let safariRetina = target(F.safari, on: F.retina)
    static let terminalExternal = target(F.terminal, on: F.external)

    /// Clip px → the window `WindowFit` picks on the 2× laptop (room 1448 × 885 pt).
    @Test(arguments: [(1280, 800, 1280, 800), (1920, 1080, 1440, 810), (1280, 720, 1280, 720)])
    func exactOnTheFirstAttemptAt2x(width: Int, height: Int, windowWidth: Int, windowHeight: Int) async throws {
        let fake = FakeWindowResizer()
        let size = PixelSize(width: width, height: height)
        let readback = try await ExactResizer(resizer: fake).resize(Self.safariRetina, to: size)
        #expect(readback.exact)
        #expect(readback.attempts == 1)
        #expect(readback.actual == size)
        #expect(readback.requested == size)
        #expect(readback.frame.width == Double(windowWidth))
        #expect(readback.frame.height == Double(windowHeight))
        #expect(readback.cropped == nil)
        #expect(readback.display == Readback.Display(id: 1, name: "Built-in Retina Display", scale: 2))
        #expect(fake.calls.count == 1)
        #expect(fake.readCount == 1)
    }

    @Test(arguments: [(1280, 800), (1280, 720), (800, 600)])
    func exactOnTheFirstAttemptAt1x(width: Int, height: Int) async throws {
        let fake = FakeWindowResizer()
        let size = PixelSize(width: width, height: height)
        let readback = try await ExactResizer(resizer: fake).resize(Self.terminalExternal, to: size)
        #expect(readback.exact)
        #expect(readback.attempts == 1)
        #expect(readback.frame.width == Double(width))
        #expect(readback.frame.height == Double(height))
        #expect(readback.display.scale == 1)
    }

    @Test func keepsTheTopLeftOriginWhenTheFrameFits() async throws {
        let fake = FakeWindowResizer()
        _ = try await ExactResizer(resizer: fake).resize(Self.safariRetina, to: PixelSize(width: 1280, height: 800))
        #expect(fake.calls.first?.requested == PointRect(x: 120, y: 80, width: 1280, height: 800))
    }

    @Test func retriesAnAppThatIgnoresTheFirstAttempt() async throws {
        let fake = FakeWindowResizer(rules: ResizeRules(ignoredAttempts: [1]))
        let readback = try await ExactResizer(resizer: fake)
            .resize(Self.safariRetina, to: PixelSize(width: 1920, height: 1080))
        #expect(readback.exact)
        #expect(readback.attempts == 2)
        #expect(fake.calls.count == 2)
    }

    @Test func minimumWidthIsNotExactWithTheDesignSpecCopy() async throws {
        // 1280 × 800 asks for a 1280 × 800 pt window (scaled 2:1 to the clip); 1286 pt gives a 1286 px wide clip.
        let fake = FakeWindowResizer(rules: ResizeRules(minimumSize: CGSize(width: 1286, height: 200)))
        let error = await #expect(throws: SkreenrekError.self) {
            try await ExactResizer(resizer: fake).resize(Self.safariRetina, to: PixelSize(width: 1280, height: 800))
        }
        #expect(error?.exitCode == 4)
        #expect(error?.code == "not_exact")
        #expect(error?.message == "Safari can't be narrower than 1286 px. It is 1286 × 800 px now.")
        #expect(error?.hint == "Pick a width of 1286 px or more, or pass --allow-inexact.")
        #expect(fake.calls.count == 3)
    }

    @Test func maximumHeightIsNotExact() async throws {
        // 1280 × 1000 gets a 1120 × 875 pt window (1.75 native px per clip px); 700 pt tall gives an 800 px clip.
        let fake = FakeWindowResizer(rules: ResizeRules(maximumSize: CGSize(width: 5000, height: 700)))
        let error = await #expect(throws: SkreenrekError.self) {
            try await ExactResizer(resizer: fake).resize(Self.safariRetina, to: PixelSize(width: 1280, height: 1000))
        }
        #expect(fake.calls.first?.requested.cgRect.size == CGSize(width: 1120, height: 875))
        #expect(error?.message == "Safari can't be taller than 800 px. It is 1280 × 800 px now.")
        #expect(error?.hint == "Pick a height of 800 px or less, or pass --allow-inexact.")
    }

    @Test func terminalStepsAreNotExact() async throws {
        // 7 × 14 px character cells on a 1× display.
        let fake = FakeWindowResizer(rules: ResizeRules(sizeStep: CGSize(width: 7, height: 14)))
        let error = await #expect(throws: SkreenrekError.self) {
            try await ExactResizer(resizer: fake)
                .resize(Self.terminalExternal, to: PixelSize(width: 1280, height: 800))
        }
        #expect(error?.exitCode == 4)
        #expect(error?.message == "Terminal resizes in steps, so 1280 × 800 px isn't possible. It is 1274 × 798 px now.")
        #expect(error?.hint == "Pick another size, or pass --allow-inexact.")
        #expect(fake.calls.count == 3)
    }

    @Test func allowInexactReturnsTheReadback() async throws {
        let fake = FakeWindowResizer(rules: ResizeRules(sizeStep: CGSize(width: 7, height: 14)))
        let readback = try await ExactResizer(resizer: fake)
            .resize(Self.terminalExternal, to: PixelSize(width: 1280, height: 800), allowInexact: true)
        #expect(!readback.exact)
        #expect(readback.attempts == 3)
        #expect(readback.actual == PixelSize(width: 1274, height: 798))
        #expect(readback.requested == PixelSize(width: 1280, height: 800))
    }

    @Test func oddWidthIsAUsageErrorBeforeAnyResize() async throws {
        let fake = FakeWindowResizer()
        let error = await #expect(throws: SkreenrekError.self) {
            try await ExactResizer(resizer: fake).resize(Self.safariRetina, to: PixelSize(width: 1281, height: 800))
        }
        #expect(error?.exitCode == 2)
        #expect(error?.message == "Width 1281 px is odd. Sizes must be even.")
        #expect(error?.hint == "Use 1280 or 1282 px.")
        #expect(fake.calls.isEmpty)
        #expect(fake.readCount == 0)
    }

    @Test func movesAFrameThatWouldCrossTheVisibleFrame() async throws {
        let fake = FakeWindowResizer()
        let nearCorner = Self.target(
            F.window(10, app: "Notes", frame: PointRect(x: 1200, y: 700, width: 200, height: 200)), on: F.retina)
        let readback = try await ExactResizer(resizer: fake).resize(nearCorner, to: PixelSize(width: 1280, height: 800))
        #expect(readback.exact)
        // The visible frame ends at x 1512, y 982: 1280 × 800 pt must start at 232, 182.
        #expect(readback.frame == PointRect(x: 232, y: 182, width: 1280, height: 800))
    }

    @Test func aFrameLargerThanTheVisibleFrameStartsAtItsTopLeft() {
        let frame = ExactResizer.targetFrame(
            origin: PointRect(x: 300, y: 300, width: 100, height: 100), size: CGSize(width: 2000, height: 1200),
            visibleFrame: F.retina.visibleFrame)
        #expect(frame == PointRect(x: 0, y: 33, width: 2000, height: 1200))
    }

    @Test func aFrameAboveTheVisibleFrameMovesBelowTheMenuBar() {
        let frame = ExactResizer.targetFrame(
            origin: PointRect(x: -50, y: 10, width: 100, height: 100), size: CGSize(width: 640, height: 400),
            visibleFrame: F.retina.visibleFrame)
        #expect(frame == PointRect(x: 0, y: 33, width: 640, height: 400))
    }

    @Test func reasons() {
        let asked = PixelSize(width: 1280, height: 800)
        func reason(_ actuals: [(Int, Int)]) -> NotExactReason {
            ExactResizer.reason(requested: asked, actuals: actuals.map { PixelSize(width: $0.0, height: $0.1) })
        }
        #expect(reason([(1286, 800)]) == .minWidth(1286))
        #expect(reason([(1200, 800)]) == .maxWidth(1200))
        #expect(reason([(1280, 900)]) == .minHeight(900))
        #expect(reason([(1280, 700)]) == .maxHeight(700))
        #expect(reason([(1281, 798)]) == .steps)
        // The first attempt may be ignored; the later ones settle.
        #expect(reason([(1000, 600), (1286, 800), (1286, 800)]) == .minWidth(1286))
        // Alternating between the later attempts.
        #expect(reason([(1286, 800), (1274, 800), (1286, 800)]) == .steps)
    }

    @Test func aPresetThatDoesntFitIsAUsageErrorBeforeAnyResize() async throws {
        let fake = FakeWindowResizer()
        let laptop = Self.target(F.safari, on: WindowFitTests.laptop)
        let error = await #expect(throws: SkreenrekError.self) {
            try await ExactResizer(resizer: fake).resize(laptop, to: SizePreset.uhd4k.size)
        }
        #expect(error?.exitCode == 2)
        #expect(error?.message == "4K needs a window at least 1920 × 1080 on screen; this display fits 1448 × 870")
        #expect(
            error?.hint
                == "4K needs room for a 1920 × 1080 pt window. Use a larger display or pick 1440p. "
                + "Use --size 1440p, or move the window to a larger display.")
        #expect(fake.calls.isEmpty)
    }

    @Test func aCroppedClipReadsBackItsCrop() async throws {
        // On a 1.5× display, 1006 × 900 px has no window of its exact aspect between 2/3 and 1× the clip; a
        // 969 × 867 pt window of 1007:901 is cropped by 1 px each way.
        let fake = FakeWindowResizer()
        let target = Self.target(F.safari, on: WindowFitTests.oneAndAHalf)
        let readback = try await ExactResizer(resizer: fake).resize(target, to: PixelSize(width: 1006, height: 900))
        #expect(readback.exact)
        #expect(readback.cropped == PixelSize(width: 1, height: 1))
        #expect(readback.frame.cgRect.size == CGSize(width: 969, height: 867))
        let json = try SkreenrekJSON.string(readback)
        #expect(json.contains(#""cropped":{"height":1,"unit":"px","width":1}"#))
    }

    @Test func resizerFailuresPassThrough() async throws {
        let fake = FakeWindowResizer()
        fake.failure = SkreenrekError.permissionDenied(.accessibility)
        await #expect(throws: SkreenrekError.permissionDenied(.accessibility)) {
            try await ExactResizer(resizer: fake).resize(Self.safariRetina, to: PixelSize(width: 1280, height: 800))
        }
    }

    @Test func neverExactWithoutAPixelEqualReadback() async throws {
        // Off by a quarter point: 1280.25 pt is 2561 px at 2×, a 1281 px wide clip, not 1280.
        struct Sloppy: WindowResizer {
            func setFrame(_ frame: PointRect, of window: WindowInfo) async throws {}
            func readFrame(of window: WindowInfo) async throws -> PointRect {
                PointRect(x: 120, y: 80, width: 1280.25, height: 800)
            }
        }
        let readback = try await ExactResizer(resizer: Sloppy())
            .resize(Self.safariRetina, to: PixelSize(width: 1280, height: 800), allowInexact: true)
        #expect(!readback.exact)
        #expect(readback.actual == PixelSize(width: 1281, height: 800))
    }

    @Test func goldenReadbackJSON() async throws {
        let readback = try await ExactResizer(resizer: FakeWindowResizer())
            .resize(Self.safariRetina, to: PixelSize(width: 1280, height: 800))
        let json = try SkreenrekJSON.string(readback)
        #expect(
            json == #"{"actual":{"height":800,"unit":"px","width":1280},"attempts":1,"#
                + #""display":{"id":1,"name":"Built-in Retina Display","scale":2},"exact":true,"#
                + #""frame":{"height":800,"unit":"pt","width":1280,"x":120,"y":80},"#
                + #""requested":{"height":800,"unit":"px","width":1280},"#
                + #""window":{"app":"Safari","bundleId":"com.apple.Safari","id":4127,"pid":812,"#
                + #""title":"localhost:3000"}}"#)
    }
}

@Suite struct SizeRequestTests {
    @Test func evenSizesInRangeAreValid() throws {
        try SizeRequest(width: 1280, height: 800).validate()
        try SizeRequest(width: 2, height: 16384).validate()
    }

    @Test func oddHeight() {
        #expect(throws: SkreenrekError.usage(message: "Height 801 px is odd. Sizes must be even.", hint: "Use 800 or 802 px.")) {
            try SizeRequest(width: 1280, height: 801).validate()
        }
    }

    @Test(arguments: [(1, 800), (0, 800), (16385, 800), (800, -2), (800, 20000)])
    func outOfRangeIsAUsageError(width: Int, height: Int) {
        let error = #expect(throws: SkreenrekError.self) { try SizeRequest(width: width, height: height).validate() }
        #expect(error?.exitCode == 2)
        #expect(error?.message.contains("out of range") == true)
    }
}

@Suite struct AXWindowMatchTests {
    typealias F = WindowFixtures
    static let window = F.safari

    @Test func titleAndFrameWin() throws {
        let snapshots = [
            AXWindowSnapshot(title: "localhost:3000", frame: PointRect(x: 0, y: 0, width: 100, height: 100)),
            AXWindowSnapshot(title: "localhost:3000", frame: PointRect(x: 120.5, y: 80, width: 640, height: 400)),
            AXWindowSnapshot(title: "GitHub", frame: Self.window.frame),
        ]
        #expect(try AXWindowMatch.pick(Self.window, among: snapshots) == 1)
    }

    @Test func fallsBackToTitleThenFrame() throws {
        let byTitle = [
            AXWindowSnapshot(title: "Other", frame: nil),
            AXWindowSnapshot(title: "localhost:3000", frame: PointRect(x: 0, y: 0, width: 10, height: 10)),
        ]
        #expect(try AXWindowMatch.pick(Self.window, among: byTitle) == 1)
        let byFrame = [
            AXWindowSnapshot(title: nil, frame: Self.window.frame),
            AXWindowSnapshot(title: "Other", frame: PointRect(x: 0, y: 0, width: 10, height: 10)),
        ]
        #expect(try AXWindowMatch.pick(Self.window, among: byFrame) == 0)
    }

    @Test func twoEqualMatchesAreAmbiguousWithDistinctListedIDs() {
        let same = AXWindowSnapshot(title: "localhost:3000", frame: Self.window.frame)
        var twin = Self.window
        twin.id = WindowID(4199)
        var otherApp = Self.window
        otherApp.id = WindowID(5000)
        otherApp.pid = 1
        let error = #expect(throws: SkreenrekError.self) {
            try AXWindowMatch.pick(Self.window, among: [same, same], siblings: [otherApp, twin, Self.window], scale: 2)
        }
        #expect(error?.code == "window_ambiguous")
        #expect(error?.exitCode == 5)
        guard case .windowIndistinct(let app, let count, let candidates)? = error else {
            Issue.record("expected windowIndistinct, got \(String(describing: error))")
            return
        }
        #expect(app == "Safari" && count == 2)
        // Every candidate is a real listed window with its own ID: the window asked for first, then its twin.
        #expect(candidates.map(\.id) == [WindowID(4127), WindowID(4199)])
        #expect(Set(candidates.map(\.id)).count == candidates.count)
        #expect(candidates.map(\.size) == [PixelSize(width: 1280, height: 800), PixelSize(width: 1280, height: 800)])
        #expect(error?.message == """
            Safari has 2 windows with the same title and size, so Skreenrek can't tell them apart:
              4127  Safari  localhost:3000  1280 × 800 px
              4199  Safari  localhost:3000  1280 × 800 px
            """)
        #expect(error?.hint == "Move or resize one of them by hand so they differ, then try again.")
    }

    @Test func lookAlikesNoListedWindowAccountsForNeverReuseAnID() {
        let same = AXWindowSnapshot(title: "localhost:3000", frame: Self.window.frame)
        let error = #expect(throws: SkreenrekError.self) {
            try AXWindowMatch.pick(Self.window, among: [same, same, same], scale: 2)
        }
        guard case .windowIndistinct(_, let count, let candidates)? = error else {
            Issue.record("expected windowIndistinct")
            return
        }
        #expect(count == 3)
        #expect(candidates.map(\.id) == [WindowID(4127)])
    }

    @Test func anUnreadableWindowIsSkippedNotFatal() throws {
        // The resizer reports a window whose frame can't be read as a nil frame: it can't match by frame, and the
        // readable window still matches.
        let snapshots = [
            AXWindowSnapshot(title: nil, frame: nil),
            AXWindowSnapshot(title: "localhost:3000", frame: Self.window.frame),
        ]
        #expect(try AXWindowMatch.pick(Self.window, among: snapshots) == 1)
    }

    @Test func noMatchIsNotFound() {
        #expect(throws: SkreenrekError.windowNotFound(query: "4127")) {
            try AXWindowMatch.pick(Self.window, among: [AXWindowSnapshot(title: "Other", frame: nil)])
        }
    }
}
