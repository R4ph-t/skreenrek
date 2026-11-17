import Foundation
import SkreenrekControl
import SkreenrekCore
import SkreenrekUI
import Testing

@Suite struct StatusIconModelTests {
    func icon(_ snapshot: ControllerSnapshot, actionError: SkreenrekError? = nil) -> StatusIcon {
        StatusIconModel.icon(for: UIFixtures.context(snapshot, actionError: actionError))
    }

    @Test func idle() {
        let icon = icon(UIFixtures.idle)
        #expect(icon.symbol == "record.circle")
        #expect(!icon.tinted)
        #expect(icon.elapsed == nil)
        #expect(icon.sentence == "Skreenrek is ready. No window picked.")
    }

    @Test func armed() {
        let icon = icon(UIFixtures.armed)
        #expect(icon.symbol == "viewfinder")
        #expect(!icon.tinted)
        #expect(icon.sentence == "Skreenrek is ready to record Safari at 1280 × 800 pixels.")
    }

    @Test func recording() {
        let icon = icon(UIFixtures.recording(.mcp, client: "Claude Code", elapsed: 12.9))
        #expect(icon.symbol == "record.circle.fill")
        #expect(icon.tinted)
        #expect(icon.elapsed == "0:12")
        #expect(icon.sentence == "Skreenrek is recording Safari. 12 seconds.")
    }

    @Test func writing() {
        var snapshot = UIFixtures.recording(.cli)
        snapshot.state = .writing
        let icon = icon(snapshot)
        #expect(icon.symbol == "arrow.down.circle")
        #expect(!icon.tinted)
        #expect(icon.elapsed == nil)
        #expect(icon.sentence == "Skreenrek is saving the clip.")
    }

    @Test func error() {
        var snapshot = UIFixtures.idle
        snapshot.state = .error
        snapshot.error = .recordingFailed(.windowClosed(at: 31))
        let icon = icon(snapshot)
        #expect(icon.symbol == "exclamationmark.triangle")
        #expect(!icon.tinted)
        #expect(icon.sentence == "Skreenrek stopped recording: the window closed.")
    }

    @Test func errorSentenceCarriesTheActualReason() {
        #expect(
            icon(UIFixtures.idle, actionError: .recordingFailed(.diskLow(at: 3))).sentence
                == "Skreenrek stopped recording: less than 2 GB free.")
        #expect(
            icon(UIFixtures.idle, actionError: .recordingFailed(.notWritable)).sentence
                == "Skreenrek stopped recording: the output folder isn't writable.")
        #expect(
            icon(UIFixtures.idle, actionError: .permissionDenied(.screenRecording)).sentence
                == "Skreenrek stopped recording: Screen Recording is off.")
        #expect(
            icon(UIFixtures.idle, actionError: .recordingFailed(.other("No frames arrived from the window."))).sentence
                == "Skreenrek stopped recording: no frames arrived from the window.")
    }

    @Test func onlyRecordingIsTinted() {
        var writing = UIFixtures.recording(.cli)
        writing.state = .writing
        let states = [
            icon(UIFixtures.idle), icon(UIFixtures.armed), icon(UIFixtures.recording(.cli)), icon(writing),
            icon(UIFixtures.idle, actionError: .recordingFailed(.notWritable)),
        ]
        #expect(states.map(\.tinted) == [false, false, true, false, false])
        #expect(Set(states.map(\.symbol)).count == 5)
    }

    @Test func elapsedEverySecondVoiceOverEveryTenSeconds() {
        let at = { (seconds: Double) in self.icon(UIFixtures.recording(.cli, elapsed: seconds)) }
        #expect(at(1).elapsed != at(2).elapsed)
        #expect(at(10).accessibilityKey == at(19.9).accessibilityKey)
        #expect(at(19.9).accessibilityKey != at(20).accessibilityKey)
        #expect(at(65).elapsed == "1:05")
        #expect(at(65).sentence == "Skreenrek is recording Safari. 1 minute 5 seconds.")
    }

    @Test func spokenDurations() {
        #expect(UIStrings.Icon.spokenDuration(1) == "1 second")
        #expect(UIStrings.Icon.spokenDuration(12) == "12 seconds")
        #expect(UIStrings.Icon.spokenDuration(60) == "1 minute")
        #expect(UIStrings.Icon.spokenDuration(125) == "2 minutes 5 seconds")
    }

    @Test func regionTarget() {
        var snapshot = UIFixtures.armed
        snapshot.window = nil
        snapshot.readback = nil
        snapshot.region = PixelRect(x: 0, y: 0, width: 1280, height: 800)
        #expect(icon(snapshot).sentence == "Skreenrek is ready to record a screen region at 1280 × 800 pixels.")
    }
}
