import Foundation
import SkreenrekCore

/// What the menu-bar icon shows in one moment.
public struct StatusIcon: Sendable, Hashable {
    /// The SF Symbol name.
    public var symbol: String
    /// System red (recording only); otherwise a template image that follows the menu bar.
    public var tinted: Bool
    /// `0:12` in SF Mono 12 pt beside the symbol while recording.
    public var elapsed: String?
    /// The tooltip and the VoiceOver label, word for word from the design spec.
    public var sentence: String
    /// Changes when the tooltip and VoiceOver text should be pushed again: on every state change, and every 10 s while
    /// recording (never every second, to avoid chatter).
    public var accessibilityKey: String
}

/// Maps the controller's state to the design spec's five icon states. Pure.
public enum StatusIconModel {
    public enum Symbol {
        public static let idle = "record.circle"
        public static let armed = "viewfinder"
        public static let recording = "record.circle.fill"
        public static let writing = "arrow.down.circle"
        public static let error = "exclamationmark.triangle"
    }

    /// How often the VoiceOver value changes while recording, in seconds.
    public static let spokenInterval = 10

    public static func icon(for context: MenuContext) -> StatusIcon {
        let state = context.displayState
        switch state {
        case .idle:
            return StatusIcon(
                symbol: Symbol.idle, tinted: false, elapsed: nil, sentence: UIStrings.Icon.idle, accessibilityKey: "idle")
        case .armed:
            let sentence = UIStrings.Icon.armed(target: context.spokenTarget, size: context.snapshot.size)
            return StatusIcon(
                symbol: Symbol.armed, tinted: false, elapsed: nil, sentence: sentence, accessibilityKey: sentence)
        case .recording:
            let seconds = context.elapsedSeconds
            let sentence = UIStrings.Icon.recording(target: context.spokenTarget, seconds: seconds)
            return StatusIcon(
                symbol: Symbol.recording, tinted: true, elapsed: TimeFormat.minutesSeconds(Double(seconds)),
                sentence: sentence,
                accessibilityKey: "recording \(context.spokenTarget) \(seconds / spokenInterval)")
        case .writing:
            return StatusIcon(
                symbol: Symbol.writing, tinted: false, elapsed: nil, sentence: UIStrings.Icon.writing,
                accessibilityKey: "writing")
        case .error:
            let reason = context.error.map(UIStrings.Icon.reason) ?? ""
            let sentence = UIStrings.Icon.error(reason: reason)
            return StatusIcon(
                symbol: Symbol.error, tinted: false, elapsed: nil, sentence: sentence, accessibilityKey: sentence)
        }
    }
}
