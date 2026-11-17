import Foundation
import Testing

/// The spec's guardrails, checked on every `swift test`.
@Suite struct GuardrailTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func swiftFiles(in relativePath: String) throws -> [(name: String, text: String)] {
        let folder = root.appendingPathComponent(relativePath)
        let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        return try enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.map {
            ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8))
        }
    }

    @Test func coreAndTestingImportNoSystemUIFrameworks() throws {
        let forbidden = try Regex(#"import (ScreenCaptureKit|AppKit|ApplicationServices|SwiftUI)"#)
        for folder in ["Sources/SkreenrekCore", "Sources/SkreenrekTesting"] {
            let files = try Self.swiftFiles(in: folder)
            #expect(!files.isEmpty)
            for file in files {
                #expect(file.text.firstMatch(of: forbidden) == nil, "\(folder)/\(file.name)")
            }
        }
    }

    @Test func testsNeverCallAPermissionAPIOrImportScreenCaptureKit() throws {
        let apis = ["CGRequestScreenCaptureAccess", "CGPreflightScreenCaptureAccess", "AXIsProcessTrustedWithOptions",
                    "import ScreenCaptureKit"]
        for file in try Self.swiftFiles(in: "Tests") where file.name != "GuardrailTests.swift" {
            for api in apis {
                #expect(!file.text.contains(api), "\(file.name) uses \(api)")
            }
        }
    }

    @Test func packageHasNoResources() throws {
        let manifest = try String(contentsOf: Self.root.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(!manifest.contains("resources:"))
    }
}
