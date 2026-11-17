import CoreGraphics
import Foundation
import SkreenrekCore
import SkreenrekSystem
import Testing

/// Opt-in: runs only with `SKREENREK_LIVE=1` and when Accessibility is already allowed for the test runner. Never
/// prompts. Run with `SKREENREK_LIVE=1 swift test --filter Live`.
enum LiveGate {
    static var resizeEnabled: Bool {
        ProcessInfo.processInfo.environment["SKREENREK_LIVE"] == "1" && AXWindowResizer.isTrusted
    }
}

@Suite(.enabled(if: LiveGate.resizeEnabled, "Set SKREENREK_LIVE=1 and allow Accessibility for the test runner"))
struct LiveResizeTests {
    static let title = "skreenrek live resize"

    /// A resizable window in its own process (osascript with the Cocoa bridge), so Accessibility talks to a process
    /// with a running event loop. It prints `ready <window number>` once the window is on screen.
    static let script = """
        ObjC.import('Cocoa');
        var app = $.NSApplication.sharedApplication;
        app.setActivationPolicy($.NSApplicationActivationPolicyRegular);
        var w = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
            $.NSMakeRect(200, 200, 500, 400), 15, $.NSBackingStoreBuffered, false);
        w.title = '\(title)';
        w.makeKeyAndOrderFront(null);
        console.log('ready ' + w.windowNumber);
        app.run;
        """

    @Test func resizesItsOwnWindowTo800x600Exactly() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", Self.script]
        let output = Pipe()
        process.standardError = output
        try process.run()
        defer { process.terminate() }

        var windowNumber: UInt32?
        for try await line in output.fileHandleForReading.bytes.lines where line.hasPrefix("ready ") {
            windowNumber = UInt32(line.dropFirst("ready ".count))
            break
        }
        let id = try #require(windowNumber)

        // Bounds from the window server list need no permission.
        let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(id)) as? [[String: Any]] ?? []
        let bounds = try #require(list.first?[kCGWindowBounds as String] as? NSDictionary)
        let rect = try #require(CGRect(dictionaryRepresentation: bounds))
        let window = WindowInfo(
            id: WindowID(id), app: "osascript", bundleId: nil, title: Self.title, pid: process.processIdentifier,
            frame: PointRect(rect), displayId: 0, onScreen: true)
        let displays = await AppKitDisplays.current()
        let display = try #require(WindowDirectory.display(for: window.frame, in: displays))

        let readback = try await ExactResizer(resizer: AXWindowResizer())
            .resize(ResolvedWindow(window: window, display: display), to: PixelSize(width: 800, height: 600))
        print("LiveResizeTests: \(try SkreenrekJSON.string(readback))")
        #expect(readback.exact)
        #expect(readback.actual == PixelSize(width: 800, height: 600))
    }
}
