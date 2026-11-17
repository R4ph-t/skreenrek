import Foundation

public enum TimeFormat {
    /// `m:ss`, the form the design spec uses for times (`0:31`, `4:12`, `61:05`). Fractions are dropped.
    public static func minutesSeconds(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds.rounded(.down) : 0))
        let s = total % 60
        return "\(total / 60):\(s < 10 ? "0" : "")\(s)"
    }
}
