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

    @Test(arguments: [(1280, 800), (1920, 1080), (1080, 1920)])
    func exactOnTheFirstAttemptAt2x(width: Int, height: Int) async throws {
        let fake = FakeWindowResizer()
        let size = PixelSize(width: width, height: height)
        let readback = try await ExactResizer(resizer: fake).resize(Self.safariRetina, to: size)
        #expect(readback.exact)
        #expect(readback.attempts == 1)
        #expect(readback.actual == size)
        #expect(readback.requested == size)
        #expect(readback.frame.width == Double(width) / 2)
        #expect(readback.frame.height == Double(height) / 2)
        #expect(readback.display == Readback.Display(id: 1, name: "Built-in Retina Display", scale: 2))
        #expect(fake.calls.count == 1)
        #expect(fake.readCount == 1)
    }

    @Test(arguments: [(1280, 800), (1920, 1080), (1080, 1920)])
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
        #expect(fake.calls.first?.requested == PointRect(x: 120, y: 80, width: 640, height: 400))
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
        // 643 pt at 2× is 1286 px.
        let fake = FakeWindowResizer(rules: ResizeRules(minimumSize: CGSize(width: 643, height: 200)))
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
        let fake = FakeWindowResizer(rules: ResizeRules(maximumSize: CGSize(width: 5000, height: 450)))
        let error = await #expect(throws: SkreenrekError.self) {
            try await ExactResizer(resizer: fake).resize(Self.safariRetina, to: PixelSize(width: 1280, height: 1000))
        }
        #expect(error?.message == "Safari can't be taller than 900 px. It is 1280 × 900 px now.")
        #expect(error?.hint == "Pick a height of 900 px or less, or pass --allow-inexact.")
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

    @Test func oddWidthOn2xIsAUsageErrorBeforeAnyResize() async throws {
        let fake = FakeWindowResizer()
        let error = await #expect(throws: SkreenrekError.self) {
            try await ExactResizer(resizer: fake).resize(Self.safariRetina, to: PixelSize(width: 1281, height: 800))
        }
        #expect(error?.exitCode == 2)
        #expect(error?.message == "Width 1281 px is odd. On a 2× display sizes must be even.")
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
        // The visible frame ends at x 1512, y 982: 640 × 400 pt must start at 872, 582.
        #expect(readback.frame == PointRect(x: 872, y: 582, width: 640, height: 400))
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

    @Test func resizerFailuresPassThrough() async throws {
        let fake = FakeWindowResizer()
        fake.failure = SkreenrekError.permissionDenied(.accessibility)
        await #expect(throws: SkreenrekError.permissionDenied(.accessibility)) {
            try await ExactResizer(resizer: fake).resize(Self.safariRetina, to: PixelSize(width: 1280, height: 800))
        }
    }

    @Test func neverExactWithoutAPixelEqualReadback() async throws {
        // Off by a quarter point: 1280.5 → 1281 px at 2× is not 1280.
        struct Sloppy: WindowResizer {
            func setFrame(_ frame: PointRect, of window: WindowInfo) async throws {}
            func readFrame(of window: WindowInfo) async throws -> PointRect {
                PointRect(x: 120, y: 80, width: 640.25, height: 400)
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
                + #""frame":{"height":400,"unit":"pt","width":640,"x":120,"y":80},"#
                + #""requested":{"height":800,"unit":"px","width":1280},"#
                + #""window":{"app":"Safari","bundleId":"com.apple.Safari","id":4127,"pid":812,"#
                + #""title":"localhost:3000"}}"#)
    }
}

@Suite struct SizeRequestTests {
    @Test func pointsArePixelsOverScale() throws {
        #expect(try SizeRequest(width: 1280, height: 800).points(scale: 2) == CGSize(width: 640, height: 400))
        #expect(try SizeRequest(width: 1281, height: 801).points(scale: 1) == CGSize(width: 1281, height: 801))
    }

    @Test func oddHeightOn2x() {
        #expect(throws: SkreenrekError.usage(
            message: "Height 801 px is odd. On a 2× display sizes must be even.", hint: "Use 800 or 802 px.")
        ) { try SizeRequest(width: 1280, height: 801).points(scale: 2) }
    }

    @Test(arguments: [(1, 800), (0, 800), (16385, 800), (800, -2), (800, 20000)])
    func outOfRangeIsAUsageError(width: Int, height: Int) {
        let error = #expect(throws: SkreenrekError.self) { try SizeRequest(width: width, height: height).points(scale: 1) }
        #expect(error?.exitCode == 2)
        #expect(error?.message.contains("out of range") == true)
    }

    @Test func boundsAreAccepted() throws {
        #expect(try SizeRequest(width: 2, height: 16384).points(scale: 2) == CGSize(width: 1, height: 8192))
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

    @Test func twoEqualMatchesAreAmbiguous() {
        let same = AXWindowSnapshot(title: "localhost:3000", frame: Self.window.frame)
        let error = #expect(throws: SkreenrekError.self) {
            try AXWindowMatch.pick(Self.window, among: [same, same], scale: 2)
        }
        #expect(error?.code == "window_ambiguous")
        #expect(error?.exitCode == 5)
        if case .windowAmbiguous(_, let candidates)? = error {
            #expect(candidates.map(\.size) == [PixelSize(width: 1280, height: 800), PixelSize(width: 1280, height: 800)])
        } else {
            Issue.record("expected window_ambiguous")
        }
    }

    @Test func noMatchIsNotFound() {
        #expect(throws: SkreenrekError.windowNotFound(query: "4127")) {
            try AXWindowMatch.pick(Self.window, among: [AXWindowSnapshot(title: "Other", frame: nil)])
        }
    }
}
