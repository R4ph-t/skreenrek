import Foundation
import Testing

/// The zero-copy guard from spec 03: nothing in the capture-to-writer path locks base addresses, copies pixels, or
/// renders through Core Image, Core Graphics or vImage.
@Suite struct RecorderGuardrailTests {
    @Test func theCapturePathMakesNoPixelCopies() throws {
        let forbidden = try Regex(#"CVPixelBufferLockBaseAddress|memcpy|vImage|CIContext|CGContext|CVPixelBufferCreate\("#)
        var checked = 0
        for folder in ["Sources/SkreenrekCore/Recording", "Sources/SkreenrekSystem/Capture"] {
            for file in try GuardrailTests.swiftFiles(in: folder) {
                checked += 1
                #expect(file.text.firstMatch(of: forbidden) == nil, "\(folder)/\(file.name)")
            }
        }
        #expect(checked >= 6)
    }
}
