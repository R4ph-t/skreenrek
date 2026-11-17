import CoreGraphics
import Foundation
import SkreenrekCore
import SkreenrekSystem
import Testing

/// How a ScreenCaptureKit stream that stopped on its own ends. Pure: no capture, no permission.
@Suite struct StreamEndTests {
    struct Boom: LocalizedError {
        var errorDescription: String? { "The stream broke." }
    }

    static let permission = NSError(domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain", code: -3801)

    @Test func aWindowThatIsGoneIsWindowClosed() {
        let error = SCStreamFrameSource.endError(stoppedWith: Boom(), windowID: 42, windowExists: { _ in false })
        #expect(error as? FrameSourceError == .windowClosed)
        let stopped = SCStreamFrameSource.endError(stoppedWith: nil, windowID: 42, windowExists: { _ in false })
        #expect(stopped as? FrameSourceError == .windowClosed)
    }

    @Test func aWindowThatStillExistsIsARecordingFailureWithTheReason() {
        let error = SCStreamFrameSource.endError(stoppedWith: Boom(), windowID: 42, windowExists: { _ in true })
        #expect(error as? SkreenrekError == .recordingFailed(.other("Screen capture stopped: The stream broke.")))
        let stopped = SCStreamFrameSource.endError(stoppedWith: nil, windowID: 42, windowExists: { _ in true })
        #expect(stopped as? SkreenrekError == .recordingFailed(.other("Screen capture stopped.")))
    }

    @Test func aRegionIsNeverWindowClosed() {
        let error = SCStreamFrameSource.endError(stoppedWith: Boom(), windowID: nil, windowExists: { _ in false })
        #expect(error as? SkreenrekError == .recordingFailed(.other("Screen capture stopped: The stream broke.")))
    }

    @Test func aPermissionErrorIsPermissionDeniedEvenIfTheWindowIsGone() {
        let error = SCStreamFrameSource.endError(
            stoppedWith: Self.permission, windowID: 42, windowExists: { _ in false })
        #expect(error as? SkreenrekError == .permissionDenied(.screenRecording))
    }

    @Test func theWindowCheckTakesTheID() {
        #expect(SCStreamFrameSource.windowExists(CGWindowID(UInt32.max - 1)) == false)
    }
}
