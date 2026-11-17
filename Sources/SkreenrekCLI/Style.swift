/// ANSI styling, applied only when colour is on.
struct Style: Sendable {
    var enabled: Bool

    func green(_ s: String) -> String { wrap(s, "32") }
    func red(_ s: String) -> String { wrap(s, "31") }
    func bold(_ s: String) -> String { wrap(s, "1") }
    func dim(_ s: String) -> String { wrap(s, "2") }

    private func wrap(_ s: String, _ code: String) -> String {
        enabled ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s
    }
}
