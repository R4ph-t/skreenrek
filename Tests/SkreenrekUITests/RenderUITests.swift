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
                "submenu-size-\(appearance)@2x.png", "submenu-framerate-\(appearance)@2x.png",
                "settings-default-\(appearance)@2x.png",
            ]
        }
        let written = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(Set(written) == Set(expected))

        var sizes: [String: (Int, Int)] = [:]
        for name in written {
            let data = try Data(contentsOf: folder.appendingPathComponent(name))
            let rep = try #require(NSBitmapImageRep(data: data), "\(name)")
            sizes[name] = (rep.pixelsWide, rep.pixelsHigh)
            #expect(rep.pixelsWide > 0 && rep.pixelsHigh > 0, "\(name)")
            #expect(Self.hasVisiblePixels(rep), "\(name) is empty")
        }

        // Status rows: 300 pt wide, 48 pt tall (64 pt when the detail wraps) at 2×; dropdowns 300 pt wide.
        for appearance in ["light", "dark"] {
            #expect(sizes["statusrow-idle-\(appearance)@2x.png"] ?? (0, 0) == (600, 96))
            #expect(sizes["statusrow-recording-\(appearance)@2x.png"] ?? (0, 0) == (600, 96))
            #expect(sizes["statusrow-lastclipmov-\(appearance)@2x.png"] ?? (0, 0) == (600, 96))
            #expect(sizes["statusrow-lastclipprores-\(appearance)@2x.png"] ?? (0, 0) == (600, 96))
            #expect(sizes["statusrow-armednotexact-\(appearance)@2x.png"] ?? (0, 0) == (600, 96))
            #expect(sizes["statusrow-errorwindowclosed-\(appearance)@2x.png"] ?? (0, 0) == (600, 128))
            #expect(sizes["settings-default-\(appearance)@2x.png"]?.0 == 960)
        }
        for (name, size) in sizes where name.hasPrefix("dropdown-") || name.hasPrefix("statusrow-") {
            #expect(size.0 == 600, "\(name)")
        }
        // The appearance really was forced.
        let light = try Data(contentsOf: folder.appendingPathComponent("dropdown-idle-light@2x.png"))
        let dark = try Data(contentsOf: folder.appendingPathComponent("dropdown-idle-dark@2x.png"))
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
