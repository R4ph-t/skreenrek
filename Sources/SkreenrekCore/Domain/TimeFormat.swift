import Foundation

public enum TimeFormat {
    /// `m:ss`, the form the design spec uses for times (`0:31`, `4:12`, `61:05`). Fractions are dropped.
    public static func minutesSeconds(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds.rounded(.down) : 0))
        let s = total % 60
        return "\(total / 60):\(twoDigits(s))"
    }

    /// A running clock: `m:ss` under an hour (`0:12`, `59:59`), `h:mm:ss` from an hour (`1:02:03`).
    public static func elapsed(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 3600 else { return minutesSeconds(seconds) }
        let total = Int(min(seconds, Double(Int32.max)))
        return "\(total / 3600):\(twoDigits(total / 60 % 60)):\(twoDigits(total % 60))"
    }

    private static func twoDigits(_ value: Int) -> String { "\(value < 10 ? "0" : "")\(value)" }
}
