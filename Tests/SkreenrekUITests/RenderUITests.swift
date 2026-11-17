import AppKit
import Foundation
import SkreenrekUI
import Synchronization
import Testing

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
                for surface in ["dropdown", "statusrow", "menubaricon"] {
                    expected.append("\(surface)-\(state)-\(appearance)@2x.png")
                }
            }
            expected += [
                "picker-label-\(appearance)@2x.png", "picker-hint-\(appearance)@2x.png",
                "picker-window-\(appearance)@2x.png", "picker-region-\(appearance)@2x.png",
                "submenu-size-\(appearance)@2x.png", "submenu-framerate-\(appearance)@2x.png",
                "settings-default-\(appearance)@2x.png",
            ]
            expected.append("picker-empty-\(appearance)@2x.png")
            for state in ["keyboard", "window-contrast", "region-contrast"] {
                expected.append("picker-\(state)-\(appearance)@2x.png")
            }
            expected.append("hud-regionoutline-\(appearance)@2x.png")
            expected.append("hud-regionoutline-contrast-\(appearance)@2x.png")
            expected += CaptureRenderSamples.hudStates.map { "hud-\($0.name)-\(appearance)@2x.png" }
            expected += CaptureRenderSamples.onboardingStates.map { "onboarding-\($0.name)-\(appearance)@2x.png" }
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

        // Status rows: 300 pt wide, 48 pt tall (64 pt when the detail wraps) at 2×; dropdowns 300 pt wide.
        for appearance in ["light", "dark"] {
            #expect(sizes["statusrow-idle-\(appearance)@2x.png"] ?? (0, 0) == (600, 96))
            #expect(sizes["statusrow-recording-\(appearance)@2x.png"] ?? (0, 0) == (600, 96))
            #expect(sizes["statusrow-armednotexact-\(appearance)@2x.png"] ?? (0, 0) == (600, 128))
            #expect(sizes["statusrow-lastclipmov-\(appearance)@2x.png"] ?? (0, 0) == (600, 96))
            #expect(sizes["statusrow-lastclipprores-\(appearance)@2x.png"] ?? (0, 0) == (600, 96))
            #expect(sizes["statusrow-errorwindowclosed-\(appearance)@2x.png"] ?? (0, 0) == (600, 128))
            #expect(sizes["settings-default-\(appearance)@2x.png"]?.0 == 960)
            #expect(sizes["picker-label-\(appearance)@2x.png"] ?? (0, 0) == (560, 112))
            #expect(sizes["picker-hint-\(appearance)@2x.png"] ?? (0, 0) == (1280, 88))
            for state in CaptureRenderSamples.hudStates {
                #expect(sizes["hud-\(state.name)-\(appearance)@2x.png"]?.1 == 72)
            }
            #expect(sizes["hud-recording-\(appearance)@2x.png"]?.0 == sizes["hud-recording-tenminutes-\(appearance)@2x.png"]?.0)
            for state in CaptureRenderSamples.onboardingStates {
                #expect(sizes["onboarding-\(state.name)-\(appearance)@2x.png"] ?? (0, 0) == (1040, 992))
            }
        }
        for (name, size) in sizes where name.hasPrefix("dropdown-") || name.hasPrefix("statusrow-") {
            #expect(size.0 == 600, "\(name)")
        }
        // The appearance really was forced.
        let light = try Data(contentsOf: folder.appendingPathComponent("dropdown-idle-light@2x.png"))
        let dark = try Data(contentsOf: folder.appendingPathComponent("dropdown-idle-dark@2x.png"))
        #expect(light != dark)
    }

    @Test func rendersEveryDirectionWithAll() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skreenrek-render-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let status = try await Self.run(["debug", "render-ui", "--direction", "all", "--out", folder.path])
        #expect(status == 0)

        let expected = await MainActor.run { Set(DirectionRenderer.fileNames) }
        #expect(expected.contains("dropdown-idle-light@2x.png"))
        #expect(expected.contains("settings-default-dark@2x.png"))
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["a", "b", "c", "c-menubar"])
        for direction in ["a", "b", "c"] {
            let sub = folder.appendingPathComponent(direction)
            let written = try FileManager.default.contentsOfDirectory(atPath: sub.path)
            #expect(Set(written) == expected, "\(direction)")
            for name in written {
                let data = try Data(contentsOf: sub.appendingPathComponent(name))
                let rep = try #require(NSBitmapImageRep(data: data), "\(direction)/\(name)")
                #expect(Self.hasVisiblePixels(rep), "\(direction)/\(name) is empty")
                // A and C: the 300 pt menu; B: the 320 pt panel; Settings: 480 pt.
                let width = name.hasPrefix("settings-") ? 960 : direction == "b" ? 640 : 600
                #expect(rep.pixelsWide == width, "\(direction)/\(name)")
            }
            let light = try Data(contentsOf: sub.appendingPathComponent("dropdown-recording-light@2x.png"))
            let dark = try Data(contentsOf: sub.appendingPathComponent("dropdown-recording-dark@2x.png"))
            #expect(light != dark)
        }

        // C's V1 menu-bar status item: five states × mono/bichrome × light/dark, 24 pt tall.
        let menubar = folder.appendingPathComponent("c-menubar")
        let menuBarNames = await MainActor.run { Set(DirectionRenderer.menuBarFileNames) }
        #expect(menuBarNames.count == 20)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: menubar.path)) == menuBarNames)
        for name in menuBarNames {
            let data = try Data(contentsOf: menubar.appendingPathComponent(name))
            let rep = try #require(NSBitmapImageRep(data: data), "\(name)")
            #expect(rep.pixelsHigh == 48, "\(name)")
            #expect(Self.hasVisiblePixels(rep), "\(name) is empty")
        }
        // The recording item carries the elapsed time, so it's wider than idle.
        let idle = try #require(
            NSBitmapImageRep(data: try Data(contentsOf: menubar.appendingPathComponent("menubar-idle-mono-light@2x.png"))))
        let recording = try #require(
            NSBitmapImageRep(
                data: try Data(contentsOf: menubar.appendingPathComponent("menubar-recording-mono-light@2x.png"))))
        #expect(recording.pixelsWide > idle.pixelsWide)
        // The template layer follows the appearance; bichrome adds colour.
        let monoLight = try Data(contentsOf: menubar.appendingPathComponent("menubar-recording-mono-light@2x.png"))
        let monoDark = try Data(contentsOf: menubar.appendingPathComponent("menubar-recording-mono-dark@2x.png"))
        let bichrome = try Data(contentsOf: menubar.appendingPathComponent("menubar-recording-bichrome-light@2x.png"))
        #expect(monoLight != monoDark)
        #expect(monoLight != bichrome)
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
