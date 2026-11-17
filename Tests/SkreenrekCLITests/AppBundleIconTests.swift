import Darwin
import Foundation
import ImageIO
import Synchronization
import Testing

/// `scripts/bundle-app.sh` ships the V1 app icon: Contents/Resources/AppIcon.icns plus CFBundleIconFile = AppIcon.
/// The bundle is built around a copy of /usr/bin/true standing in for the `skreenrek` executable, so the test needs
/// no release build and never launches anything but the script.
@Suite(.timeLimit(.minutes(1))) struct AppBundleIconTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func bundledAppHasTheIconAndItsInfoPlistKey() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let products = temp.root.appendingPathComponent("products", isDirectory: true)
        try FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/usr/bin/true"), to: products.appendingPathComponent("skreenrek"))

        let status = try await Self.run(
            "/bin/bash", [Self.root.appendingPathComponent("scripts/bundle-app.sh").path, products.path, temp.root.path],
            seconds: 20)
        #expect(status == 0)

        let contents = temp.root.appendingPathComponent("Skreenrek.app/Contents")
        let icon = contents.appendingPathComponent("Resources/AppIcon.icns")
        let committed = Self.root.appendingPathComponent("packaging/AppIcon.icns")
        #expect(try Data(contentsOf: icon) == Data(contentsOf: committed))

        let plist = try #require(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: contents.appendingPathComponent("Info.plist")), format: nil) as? [String: Any])
        #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
    }

    /// Every standard .iconset size, 16 to 1024 px, is in the committed icns.
    @Test func committedIconHasEveryIconsetSize() throws {
        let url = Self.root.appendingPathComponent("packaging/AppIcon.icns")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        var widths = Set<Int>()
        for index in 0..<CGImageSourceGetCount(source) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            if let width = properties?[kCGImagePropertyPixelWidth] as? Int { widths.insert(width) }
        }
        #expect(widths == [16, 32, 64, 128, 256, 512, 1024])
    }

    /// Runs a process with a hard kill after `seconds`, so a stuck script fails the test instead of hanging it.
    static func run(_ executable: String, _ arguments: [String], seconds: Double) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = Mutex(false)
        return try await within("bundle-app.sh", seconds: seconds) {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { child in
                    let first = finished.withLock { value in
                        guard !value else { return false }
                        value = true
                        return true
                    }
                    if first { continuation.resume(returning: child.terminationStatus) }
                }
                do { try process.run() }
                catch {
                    finished.withLock { $0 = true }
                    continuation.resume(throwing: error)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds - 1) {
                    if !finished.withLock({ $0 }), process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
    }
}
