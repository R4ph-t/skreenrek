import AppKit
import Foundation
import SkreenrekCore
import SkreenrekUI
import Synchronization
import Testing
import Vision

/// `skreenrek debug render-ui` writes non-empty PNGs of the expected sizes in both appearances.
///
/// It runs the built `skreenrek` binary as a child process with a hard timeout, so AppKit's offscreen windows and
/// drawing never occupy this test process's main thread or concurrency pool, and a stuck render fails the test
/// instead of hanging `swift test`.
@Suite struct RenderUITests {
    static let timeoutSeconds = 120.0

    @Test func rendersEverySurfaceInBothAppearances() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-render-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let status = try await Self.run(["debug", "render-ui", "--out", folder.path])
        #expect(status == 0)

        var expected: [String] = []
        for appearance in ["light", "dark"] {
            for state in RenderSamples.states.map(\.name) {
                for surface in ["dropdown", "menubaricon"] {
                    expected.append("\(surface)-\(state)-\(appearance)@2x.png")
                }
            }
            expected += [
                "picker-label-\(appearance)@2x.png", "picker-hint-\(appearance)@2x.png",
                "picker-chip-\(appearance)@2x.png",
                "picker-window-\(appearance)@2x.png", "picker-region-\(appearance)@2x.png",
                "submenu-size-\(appearance)@2x.png", "submenu-framerate-\(appearance)@2x.png",
                "screen-outline-\(appearance)@2x.png", "screen-outline-contrast-\(appearance)@2x.png",
            ]
            for state in [
                "default", "general", "general-control-bar", "updates-checking", "general-devbuild", "agents", "permissions",
                "permissions-notallowed",
            ] {
                expected.append("settings-\(state)-\(appearance)@2x.png")
            }
            expected.append("surface-panel-settings-general-\(appearance)@2x.png")
            expected.append("picker-empty-\(appearance)@2x.png")
            for state in ["keyboard", "window-contrast", "region-contrast"] {
                expected.append("picker-\(state)-\(appearance)@2x.png")
            }
            expected.append("hud-regionoutline-\(appearance)@2x.png")
            expected.append("hud-regionoutline-contrast-\(appearance)@2x.png")
            expected += CaptureRenderSamples.hudStates.map { "hud-\($0.name)-\(appearance)@2x.png" }
            expected += CaptureRenderSamples.onboardingStates.map { "onboarding-\($0.name)-\(appearance)@2x.png" }
            for state in [
                "idle", "picked", "control-bar-row", "clear-hover", "clear-pressed", "lastclip-hover",
                "lastclip-pressed", "recording", "nowindow", "loading", "loading-slow",
                "capture-failed", "permission-missing", "window-closed", "aspect-16x10", "aspect-21x9", "aspect-9x16",
            ] {
                expected.append("panel-\(state)-\(appearance)@2x.png")
            }
            for state in [
                "below", "above", "docked", "narrow", "size-menu", "recording", "recording-hour", "saving",
                "saving-reducedmotion", "disabled", "disabled-size", "custom", "resizing", "not-exact", "refused",
                "saved", "saved-compact", "saved-copied",
            ] {
                expected.append("control-bar-\(state)-\(appearance)@2x.png")
            }
            for state in ["window-recording", "region-recording", "saving-bar"] {
                expected.append("red-outline-\(state)-\(appearance)@2x.png")
            }
        }
        let written = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(Set(written) == Set(expected))

        var sizes: [String: (Int, Int)] = [:]
        for name in written {
            let data = try Data(contentsOf: folder.appendingPathComponent(name))
            let rep = try #require(NSBitmapImageRep(data: data), "\(name)")
            sizes[name] = (rep.pixelsWide, rep.pixelsHigh)
            #expect(rep.pixelsWide > 0 && rep.pixelsHigh > 0, "\(name)")
            if name.hasPrefix("hud-regionoutline") {
                // A single-colour 1 pt border on a transparent interior intentionally has only one opaque colour.
                #expect(rep.colorAt(x: 0, y: rep.pixelsHigh / 2)?.alphaComponent ?? 0 > 0)
                #expect(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.alphaComponent == 0)
            } else {
                #expect(Self.hasVisiblePixels(rep), "\(name) is empty")
            }
            if name.hasPrefix("picker-window-") {
                // The tint must stay transparent, with a fully transparent desktop outside the candidate.
                let tint = rep.colorAt(x: 300, y: 300)?.alphaComponent ?? 0
                #expect(abs(tint - 0.18) < 0.02)
                #expect(rep.colorAt(x: 20, y: 20)?.alphaComponent == 0)
            }
        }

        // Dropdowns 300 pt wide; the V1 menu-bar item 24 pt tall, wider while it shows the elapsed time.
        for appearance in ["light", "dark"] {
            for state in RenderSamples.states.map(\.name) {
                #expect(sizes["menubaricon-\(state)-\(appearance)@2x.png"]?.1 == 48, "\(state)")
            }
            let idle = sizes["menubaricon-idle-\(appearance)@2x.png"]?.0 ?? 0
            #expect(sizes["menubaricon-recording-\(appearance)@2x.png"]?.0 ?? 0 > idle)
            for state in ["general", "agents", "permissions", "permissions-notallowed"] {
                #expect(sizes["settings-\(state)-\(appearance)@2x.png"]?.0 == 960, "\(state)")
            }
            // The heights Designer measured, at 2×.
            for (state, height) in [
                ("nowindow", 702), ("window-closed", 702), ("picked", 1239), ("control-bar-row", 1239),
                ("clear-hover", 1239), ("clear-pressed", 1239), ("lastclip-hover", 1239),
                ("lastclip-pressed", 1239), ("recording", 915), ("idle", 1295),
            ] {
                #expect(sizes["panel-\(state)-\(appearance)@2x.png"]?.1 == height, "\(state)")
            }
            #expect(sizes["picker-label-\(appearance)@2x.png"] ?? (0, 0) == (560, 112))
            #expect(sizes["picker-hint-\(appearance)@2x.png"] ?? (0, 0) == (1280, 88))
            // Measured from the fitted render: the text plus 8 pt a side and 4 pt top and bottom.
            #expect(sizes["picker-chip-\(appearance)@2x.png"] ?? (0, 0) == (186, 46))
            for state in CaptureRenderSamples.hudStates {
                #expect(sizes["hud-\(state.name)-\(appearance)@2x.png"]?.1 == 72)
            }
            // The time slot fits its string: one monospaced digit wider at 10:00, the same with Increase Contrast.
            let recording = sizes["hud-recording-\(appearance)@2x.png"]?.0 ?? 0
            let tenMinutes = sizes["hud-recording-tenminutes-\(appearance)@2x.png"]?.0 ?? 0
            #expect(recording == 342)
            #expect(tenMinutes == 358)
            #expect(sizes["hud-recording-contrast-\(appearance)@2x.png"]?.0 == recording)
            for state in CaptureRenderSamples.onboardingStates {
                #expect(sizes["onboarding-\(state.name)-\(appearance)@2x.png"] ?? (0, 0) == (1040, 856))
            }
        }
        for (name, size) in sizes where name.hasPrefix("dropdown-") || name.hasPrefix("panel-") {
            #expect(size.0 == 600, "\(name)")
        }
        // The appearance really was forced.
        let light = try Data(contentsOf: folder.appendingPathComponent("dropdown-idle-light@2x.png"))
        let dark = try Data(contentsOf: folder.appendingPathComponent("dropdown-idle-dark@2x.png"))
        #expect(light != dark)
    }

    /// The Size and Frame Rate pop-ups draw their current value on a filled cell. This reads the drawn pixels, because
    /// a `Menu` style can drop a custom label while the model still holds the right value.
    @Test func panelPopupsDrawTheirValueOnAFilledCell() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-render-popups-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let status = try await Self.run(["debug", "render-ui", "--out", folder.path])
        #expect(status == 0)

        // At 2×, the cells are 56 px tall and start 481 px down (16 + 167.5 + 12 + 33 + 12 pt). Each is read on its
        // own, because recognition drops short words when both cells share one image.
        let sizeCell = CGRect(x: 32, y: 481, width: 232, height: 56)
        let frameRateCell = CGRect(x: 280, y: 481, width: 288, height: 56)
        for appearance in ["light", "dark"] {
            let name = "panel-idle-\(appearance)@2x.png"
            let data = try Data(contentsOf: folder.appendingPathComponent(name))
            let rep = try #require(NSBitmapImageRep(data: data), "\(name)")
            let size = try Self.recognizedText(in: try #require(rep.cgImage?.cropping(to: sizeCell), "\(name)"))
            // Only the digits: on the white light cell, Vision reads the p as a Cyrillic letter.
            #expect(size.contains("1080"), "\(name) drew: \(size)")
            let frameRate = try Self.recognizedText(
                in: try #require(rep.cgImage?.cropping(to: frameRateCell), "\(name)"))
            #expect(frameRate.contains("Frame Rate"), "\(name) drew: \(frameRate)")
            #expect(frameRate.contains("60 fps"), "\(name) drew: \(frameRate)")

            // Inside the Size cell's left padding, against the panel background beside the cell.
            let fill = try #require(rep.colorAt(x: 38, y: 509)?.usingColorSpace(.deviceRGB), "\(name)")
            let panel = try #require(rep.colorAt(x: 12, y: 509)?.usingColorSpace(.deviceRGB), "\(name)")
            #expect(abs(fill.brightnessComponent - panel.brightnessComponent) > 0.02, "\(name) has no cell fill")
        }
    }

    /// Reads the drawn pixels: the stroke's colour on the preview edge, and each trailing switch ending at x 284.
    @Test func panelsDrawTheSelectedStateAndTheirEdges() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-render-edges-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try await Self.run(["debug", "render-ui", "--out", folder.path]) == 0)

        func image(_ name: String) throws -> NSBitmapImageRep {
            let data = try Data(contentsOf: folder.appendingPathComponent(name))
            return try #require(NSBitmapImageRep(data: data), "\(name)")
        }
        // Halfway down the preview's left edge, inside the 2 pt stroke.
        let picked = try #require(try image("panel-picked-light@2x.png").colorAt(x: 34, y: 200)?.usingColorSpace(.deviceRGB))
        #expect(picked.blueComponent > 0.8 && picked.redComponent < 0.3, "\(picked)")
        let recording = try #require(
            try image("panel-recording-light@2x.png").colorAt(x: 34, y: 200)?.usingColorSpace(.deviceRGB))
        #expect(recording.redComponent > 0.8 && recording.blueComponent < 0.4, "\(recording)")

        // The compact panel's first switch row: 16 + 33 + 12 + 28 + 12 + 40 + 17 pt down, centred at +14.
        let compact = try image("panel-nowindow-light@2x.png")
        let y = Int((158 + 14) * 2)
        // 1 pt inside the end, past the knob's 2 pt inset.
        let inside = try #require(compact.colorAt(x: 566, y: y)?.usingColorSpace(.deviceRGB))
        let outside = try #require(compact.colorAt(x: 572, y: y)?.usingColorSpace(.deviceRGB))
        #expect(inside.blueComponent - inside.redComponent > 0.3, "\(inside)")
        #expect(outside.blueComponent - outside.redComponent < 0.1, "\(outside)")

        // The outline is 3 pt of accent just outside the sample window, whose left edge is at x 48.
        let outline = try image("screen-outline-light@2x.png")
        let stroke = try #require(outline.colorAt(x: 93, y: 400)?.usingColorSpace(.deviceRGB))
        let window = try #require(outline.colorAt(x: 100, y: 400)?.usingColorSpace(.deviceRGB))
        #expect(stroke.blueComponent - stroke.redComponent > 0.5, "\(stroke)")
        #expect(window.redComponent > 0.9, "\(window)")
    }

    /// Reads the drawn pixels: the surface is the addendum's solid colour right up to its hairline, and the corners
    /// outside the 10 pt radius stay empty, so no SwiftUI shadow or grey halo is drawn on top of the window's shadow.
    @Test func panelsDrawAnOpaqueSurfaceWithCleanCorners() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-render-surface-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try await Self.run(["debug", "render-ui", "--out", folder.path]) == 0)

        for (appearance, red, blue) in [("light", 0xF5, 0xF5), ("dark", 0x1E, 0x1E)] {
            for state in ["idle", "picked", "recording", "nowindow"] {
                let name = "panel-\(state)-\(appearance)@2x.png"
                let data = try Data(contentsOf: folder.appendingPathComponent(name))
                let rep = try #require(NSBitmapImageRep(data: data), "\(name)")
                let (right, bottom) = (rep.pixelsWide - 1, rep.pixelsHigh - 1)
                for (x, y) in [(0, 0), (right, 0), (0, bottom), (right, bottom)] {
                    #expect(rep.colorAt(x: x, y: y)?.alphaComponent == 0, "\(name) corner \(x), \(y)")
                }
                // In the left margin, clear of every control.
                // Raw bytes: the PNG is tagged sRGB, and `colorAt` would convert them again.
                var surface = [Int](repeating: 0, count: 4)
                rep.getPixel(&surface, atX: 12, y: rep.pixelsHigh / 2)
                #expect(surface == [red, red, blue, 255], "\(name)")
                // The hairline sits on the fill, so the edge is opaque too.
                #expect(rep.colorAt(x: 0, y: rep.pixelsHigh / 2)?.alphaComponent == 1, "\(name) edge")
            }
        }
    }

    /// Addendum 3: the panel, Settings and onboarding sample the same base and cell, Settings is one tone from its top
    /// edge through the toolbar, every tab has the same height, and General starts with the name and version.
    @Test func panelAndSettingsShareOneSurface() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-render-shared-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try await Self.run(["debug", "render-ui", "--out", folder.path]) == 0)

        func image(_ name: String) throws -> NSBitmapImageRep {
            let data = try Data(contentsOf: folder.appendingPathComponent(name))
            return try #require(NSBitmapImageRep(data: data), "\(name)")
        }
        // Raw bytes: the PNG is tagged sRGB, and `colorAt` would convert them again.
        func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> [Int] {
            var value = [Int](repeating: 0, count: 4)
            rep.getPixel(&value, atX: x, y: y)
            return Array(value.prefix(3))
        }
        for (appearance, base, cell) in [("dark", 0x1E, 0x2A), ("light", 0xF5, 0xFF)] {
            let both = try image("surface-panel-settings-general-\(appearance)@2x.png")
            // At 2×: the panel at x 40–340 pt, Settings at x 380–860 pt, both 40 pt down.
            let panelBase = pixel(both, 100, 1000)
            let panelCell = pixel(both, 200, 605)
            let settingsBase = pixel(both, 1100, 340)
            let settingsCell = pixel(both, 1300, 420)
            #expect(panelBase == [base, base, base], "\(appearance) panel base \(panelBase)")
            #expect(settingsBase == panelBase, "\(appearance) settings base \(settingsBase)")
            #expect(panelCell == [cell, cell, cell], "\(appearance) panel cell \(panelCell)")
            #expect(settingsCell == panelCell, "\(appearance) settings cell \(settingsCell)")
            // At 2×: the stand-in title bar and toolbar tabs take y 0–160, then 8 pt (16 px) before each tab's content.
            // General starts with the 48 pt identity row and 16 pt of space, so its first section is at y 304 px; the
            // other tabs start with their first section at y 176 px. All three are the same, fixed height.
            var heights: Set<Int> = []
            for (tab, sectionTop) in [("general", 304), ("agents", 176), ("permissions", 176)] {
                let name = "settings-\(tab)-\(appearance)@2x.png"
                let rep = try image(name)
                heights.insert(rep.pixelsHigh)
                // The top edge, the title bar, the toolbar and the gap above the content: one tone, no toolbar band.
                for y in [1, 30, 60, 100, 150, 170] {
                    let value = pixel(rep, 900, y)
                    #expect(value == [base, base, base], "\(name) y \(y): \(value)")
                }
                let section = pixel(rep, 700, sectionTop + 20)
                #expect(section == [cell, cell, cell], "\(name) section \(section)")
                #expect(pixel(rep, 700, sectionTop - 8) == [base, base, base], "\(name) above the section")
            }
            #expect(heights.count == 1, "\(heights)")
            // Onboarding: the same base from the title bar band down, the cards on surface.cell, and the agent card's
            // separators inset 12 pt from its leading edge (the card starts at x 24 pt).
            let agents = try image("onboarding-4-agents-\(appearance)@2x.png")
            for (x, y) in [(520, 10), (20, 500), (520, 740)] {
                let value = pixel(agents, x, y)
                #expect(value == [base, base, base], "\(appearance) onboarding base \(x), \(y): \(value)")
            }
            let agentCard = pixel(agents, 500, 320)
            #expect(agentCard == [cell, cell, cell], "\(appearance) onboarding agents card \(agentCard)")
            #expect(pixel(agents, 60, 376) == [cell, cell, cell], "\(appearance) separator inset")
            #expect(pixel(agents, 500, 376) != [cell, cell, cell], "\(appearance) separator")
            let permission = try image("onboarding-1-screenrecording-\(appearance)@2x.png")
            let permissionCard = pixel(permission, 300, 410)
            #expect(permissionCard == [cell, cell, cell], "\(appearance) onboarding permission card \(permissionCard)")
            #expect(pixel(permission, 20, 600) == [base, base, base], "\(appearance) onboarding permission base")
            // The identity row at the top of General (y 176–272 px): the name and version, and nowhere else below it.
            let general = try image("settings-general-\(appearance)@2x.png")
            let cg = try #require(general.cgImage)
            let identity = try Self.recognizedText(in: try #require(cg.cropping(to: CGRect(x: 0, y: 176, width: 480, height: 96))))
            #expect(identity.contains("Skreenrek"), "\(identity)")
            #expect(identity.contains("Version \(SkreenrekVersion.current)"), "\(identity)")
            let toolbar = try Self.recognizedText(in: try #require(cg.cropping(to: CGRect(x: 0, y: 0, width: 960, height: 160))))
            for tab in ["General", "Agents", "Permissions"] {
                #expect(toolbar.contains(tab), "\(toolbar)")
            }
            // Updates: Sparkle's Check for Updates… and the automatic check switch, and no "Version" line below the
            // identity row.
            let body = try Self.recognizedText(
                in: try #require(cg.cropping(to: CGRect(x: 0, y: 290, width: 960, height: general.pixelsHigh - 290))))
            #expect(body.contains("Check for Updates"), "\(body)")
            #expect(body.contains("Automatically check for updates"), "\(body)")
            #expect(!body.contains("Version"), "\(body)")
        }
    }

    private static func recognizedText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    /// `--direction c` is an alias for the shipping render.
    @Test func directionCIsTheShippingUI() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-render-c-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let status = try await Self.run(["debug", "render-ui", "--direction", "c", "--out", folder.path])
        #expect(status == 0)
        let written = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        #expect(written.contains("dropdown-recording-dark@2x.png"))
        #expect(written.contains("settings-default-light@2x.png"))
        #expect(written.contains("submenu-size-light@2x.png"))
    }

    /// `--direction size13` writes only the spec 13 v2 size previews, by their spec names.
    @Test func rendersTheSize13PreviewsInBothAppearances() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-render-size13-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let status = try await Self.run(["debug", "render-ui", "--direction", "size13", "--out", folder.path])
        #expect(status == 0)

        var expected: Set<String> = []
        for appearance in ["light", "dark"] {
            for name in [
                "size-submenu-laptop", "size-submenu-large", "custom-valid", "custom-toolarge", "dropdown-armed-1080p",
            ] {
                expected.insert("\(name)-\(appearance)@2x.png")
            }
        }
        let written = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(Set(written) == expected)

        var sizes: [String: (Int, Int)] = [:]
        for name in written {
            let data = try Data(contentsOf: folder.appendingPathComponent(name))
            let rep = try #require(NSBitmapImageRep(data: data), "\(name)")
            sizes[name] = (rep.pixelsWide, rep.pixelsHigh)
            #expect(Self.hasVisiblePixels(rep), "\(name) is empty")
        }
        for appearance in ["light", "dark"] {
            // The Custom… panel is 320 pt wide; the main menu keeps the dropdown's 300 pt.
            #expect(sizes["custom-valid-\(appearance)@2x.png"]?.0 == 640)
            #expect(sizes["custom-toolarge-\(appearance)@2x.png"]?.0 == 640)
            #expect(sizes["dropdown-armed-1080p-\(appearance)@2x.png"]?.0 == 600)
            // The laptop render carries the 4K tooltip beside the submenu, so it's wider than the large one.
            let laptop = try #require(sizes["size-submenu-laptop-\(appearance)@2x.png"])
            let large = try #require(sizes["size-submenu-large-\(appearance)@2x.png"])
            #expect(laptop.0 > large.0)
            #expect(laptop.1 == large.1)
        }
        let light = try Data(contentsOf: folder.appendingPathComponent("custom-valid-light@2x.png"))
        let dark = try Data(contentsOf: folder.appendingPathComponent("custom-valid-dark@2x.png"))
        #expect(light != dark)
    }

    /// The `skreenrek` executable from the same build as this test bundle (`swift build` puts both in one products
    /// folder), found from the loaded `.xctest` bundle or the test runner's arguments.
    static func binary() throws -> URL {
        let candidates = (Bundle.allBundles + Bundle.allFrameworks).map(\.bundlePath)
            + ProcessInfo.processInfo.arguments + [Bundle.main.bundlePath]
        for path in candidates {
            guard let range = path.range(of: ".xctest") else { continue }
            let bundle = URL(fileURLWithPath: String(path[..<range.upperBound]))
            let url = bundle.deletingLastPathComponent().appendingPathComponent("skreenrek")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        Issue.record("No skreenrek binary beside the test bundle (checked \(candidates)); run swift build first.")
        throw CancellationError()
    }

    /// Runs the binary and returns its exit status, or throws after `timeoutSeconds` (killing it).
    static func run(_ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = try binary()
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exit = ExitOnce()
        return try await withCheckedThrowingContinuation { continuation in
            exit.set(continuation)
            process.terminationHandler = { exit.finish(.success($0.terminationStatus)) }
            do {
                try process.run()
            } catch {
                exit.finish(.failure(error))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                guard exit.isPending else { return }
                process.terminate()
                exit.finish(.failure(WaitTimedOut(what: "skreenrek debug render-ui", seconds: timeoutSeconds)))
            }
        }
    }

    static func hasVisiblePixels(_ rep: NSBitmapImageRep) -> Bool {
        var colors = Set<UInt32>()
        let stepX = max(1, rep.pixelsWide / 40)
        let stepY = max(1, rep.pixelsHigh / 40)
        for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0 else { continue }
                let key =
                    UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8
                    | UInt32(c.blueComponent * 255)
                colors.insert(key)
                if colors.count > 1 { return true }
            }
        }
        return false
    }
}

/// Resumes the child-process continuation once, from the exit or the watchdog.
private final class ExitOnce: Sendable {
    private let continuation = Mutex<CheckedContinuation<Int32, any Error>?>(nil)

    func set(_ continuation: CheckedContinuation<Int32, any Error>) {
        self.continuation.withLock { $0 = continuation }
    }

    var isPending: Bool { continuation.withLock { $0 != nil } }

    func finish(_ result: Result<Int32, any Error>) {
        continuation.withLock { $0.take() }?.resume(with: result)
    }
}
