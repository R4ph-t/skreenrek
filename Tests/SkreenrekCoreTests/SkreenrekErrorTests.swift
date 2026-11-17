import Foundation
import SkreenrekCore
import Testing

@Suite struct SkreenrekErrorTests {
    static let candidates = [
        WindowCandidate(id: WindowID(4127), app: "Safari", title: "localhost:3000",
                        size: PixelSize(width: 1280, height: 800)),
        WindowCandidate(id: WindowID(4133), app: "Safari", title: "GitHub", size: PixelSize(width: 1512, height: 945)),
    ]

    static let rows: [(SkreenrekError, Int32, String)] = [
        (.internal(message: "Something broke."), 1, "internal"),
        (.usage(message: "Width 1281 px is odd.", hint: "Use 1280 or 1282 px."), 2, "usage"),
        (.permissionDenied(.screenRecording), 3, "permission_denied"),
        (.permissionDenied(.accessibility), 3, "permission_denied"),
        (.notExact(app: "Safari", requested: PixelSize(width: 1280, height: 800),
                   actual: PixelSize(width: 1286, height: 800), reason: .minWidth(1286)), 4, "not_exact"),
        (.windowNotFound(query: "--app Safari"), 5, "window_not_found"),
        (.windowAmbiguous(query: "--app Safari", candidates: candidates), 5, "window_ambiguous"),
        (.wrongState(.alreadyRecording), 6, "wrong_state"),
        (.wrongState(.notRecording), 6, "wrong_state"),
        (.wrongState(.stillWriting), 6, "wrong_state"),
        (.recordingFailed(.windowClosed(at: 31)), 7, "recording_failed"),
        (.recordingFailed(.diskLow(at: 252)), 7, "recording_failed"),
        (.recordingFailed(.notWritable), 7, "recording_failed"),
        (.recordingFailed(.other("The writer failed.")), 7, "recording_failed"),
        (.interrupted, 130, "interrupted"),
    ]

    @Test func everyRowHasItsExitCodeCodeMessageAndHint() {
        for (error, exit, code) in Self.rows {
            #expect(error.exitCode == exit, "\(error)")
            #expect(error.code == code, "\(error)")
            #expect(!error.message.isEmpty && !error.hint.isEmpty, "\(error)")
            #expect(error.body == ErrorBody(code: code, message: error.message, hint: error.hint, exit: exit))
        }
    }

    @Test func theDesignSpecCodesAreAllCovered() {
        let codes = Set(Self.rows.map(\.2))
        for code in ["permission_denied", "not_exact", "window_not_found", "window_ambiguous", "wrong_state",
                     "recording_failed", "usage", "internal"] {
            #expect(codes.contains(code))
        }
    }

    @Test func screenRecordingCopyIsWordForWord() {
        let error = SkreenrekError.permissionDenied(.screenRecording)
        #expect(error.message == "Screen Recording isn't allowed for Skreenrek.")
        #expect(error.hint == "Allow it in System Settings › Privacy & Security › Screen & System Audio Recording, "
            + "then run: skreenrek doctor")
    }

    @Test func notExactCopyIsWordForWord() {
        let error = SkreenrekError.notExact(
            app: "Safari", requested: PixelSize(width: 1280, height: 800),
            actual: PixelSize(width: 1286, height: 800), reason: .minWidth(1286))
        #expect(error.message == "Safari can't be narrower than 1286 px. It is 1286 × 800 px now.")
        #expect(error.hint == "Pick a width of 1286 px or more, or pass --allow-inexact.")
    }

    @Test func notExactInStepsUsesSpec02Copy() {
        let error = SkreenrekError.notExact(
            app: "Terminal", requested: PixelSize(width: 1280, height: 800),
            actual: PixelSize(width: 1281, height: 798), reason: .steps)
        #expect(error.message == "Terminal resizes in steps, so 1280 × 800 px isn't possible. It is 1281 × 798 px now.")
    }

    @Test func ambiguousCopyIsWordForWordWithAlignedCandidates() {
        let error = SkreenrekError.windowAmbiguous(query: "--app Safari", candidates: Self.candidates)
        #expect(error.message == """
            2 windows match --app Safari. Pass a window ID:
              4127  Safari  localhost:3000  1280 × 800 px
              4133  Safari  GitHub          1512 × 945 px
            """)
    }

    @Test func recordingFailedCopyMatchesTheDropdownTable() {
        #expect(SkreenrekError.recordingFailed(.windowClosed(at: 31)).message
            == "The window closed at 0:31. The clip up to that point was saved.")
        #expect(SkreenrekError.recordingFailed(.diskLow(at: 252)).message
            == "Less than 2 GB free. The clip up to 4:12 was saved.")
        #expect(SkreenrekError.recordingFailed(.notWritable).message == "The output folder isn't writable.")
    }

    @Test func encodesAsTheErrorEnvelope() throws {
        let json = try SkreenrekJSON.string(SkreenrekError.permissionDenied(.screenRecording))
        #expect(json == #"{"error":{"code":"permission_denied","exit":3,"#
            + #""hint":"Allow it in System Settings › Privacy & Security › Screen & System Audio Recording, "#
            + #"then run: skreenrek doctor","message":"Screen Recording isn't allowed for Skreenrek."}}"#)
        let envelope = try SkreenrekJSON.decoder().decode(ErrorEnvelope.self, from: Data(json.utf8))
        #expect(envelope.error == SkreenrekError.permissionDenied(.screenRecording).body)
    }

    @Test func noCopyNamesPeople() {
        for (error, _, _) in Self.rows {
            for text in [error.message, error.hint] {
                #expect(!text.contains("Raph") && !text.contains("CTO"))
            }
        }
    }
}
