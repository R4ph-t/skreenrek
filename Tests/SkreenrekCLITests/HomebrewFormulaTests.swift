import Darwin
import Foundation
import Synchronization
import Testing

@Suite struct HomebrewFormulaTests {
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/ruby"), "Ruby isn't installed"))
    func rubySyntax() async throws {
        let temp = ShortTemp()
        defer { temp.cleanUp() }
        let formula = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Formula/skreenrek.rb")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = ["-c", formula.path]
        process.environment = ["HOME": temp.root.path, "PATH": "/usr/bin:/bin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = Mutex(false)
        let status: Int32 = try await within("ruby -c Formula/skreenrek.rb", seconds: 10) {
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
                DispatchQueue.global().asyncAfter(deadline: .now() + 9) {
                    if !finished.withLock({ $0 }), process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        #expect(status == 0)
    }
}
