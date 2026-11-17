import Foundation

/// A conservative TOML reader for agent configs. Unsupported syntax fails closed; edits are an appended marker
/// block, so every existing byte (including comments and ordering) stays intact.
enum TOMLConfig {
    static let begin = "# >>> skreenrek >>>"
    static let end = "# <<< skreenrek <<<"

    static func validate(_ text: String) throws {
        guard !text.unicodeScalars.contains(where: { ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127 }) else {
            throw AgentSetupError("The TOML config contains a control character. Remove it before connecting.")
        }
        var parser = Reader(text)
        try parser.document()
    }

    static func block(in text: String) throws -> Range<String.Index>? {
        try validate(text)
        let starts = text.ranges(of: begin)
        let ends = text.ranges(of: end)
        guard !starts.isEmpty || !ends.isEmpty else { return nil }
        guard starts.count == 1, ends.count == 1, let start = starts.first, let end = ends.first,
              start.upperBound < end.lowerBound,
              (start.lowerBound == text.startIndex || text[text.index(before: start.lowerBound)] == "\n"),
              (end.upperBound == text.endIndex || text[end.upperBound] == "\n"),
              text[start.upperBound] == "\n"
        else { throw AgentSetupError("The Codex config has invalid Skreenrek markers. Fix them before connecting.") }
        let after = end.upperBound < text.endIndex ? text.index(after: end.upperBound) : end.upperBound
        return start.lowerBound..<after
    }

    static func hasServer(_ text: String) throws -> Bool {
        var parser = Reader(text)
        try parser.document()
        return parser.paths.contains { $0.starts(with: ["mcp_servers", "skreenrek"]) }
    }

    static func server(command: String) throws -> String {
        // JSON basic strings are TOML basic strings too (slashes are not escaped).
        let quoted = try SkreenrekJSON.string(command)
        return "\(begin)\n[mcp_servers.skreenrek]\ncommand = \(quoted)\nargs = [\"mcp\"]\n\(end)\n"
    }

    /// A user can add keys to our table after the marker. Removing its header would silently move those keys
    /// into a different table. Only comments, blank lines or a new table may follow a removable block.
    static func canRemove(_ text: String, range: Range<String.Index>) -> Bool {
        for line in text[range.upperBound...].split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            return trimmed.hasPrefix("[")
        }
        return true
    }

    private struct Reader {
        let chars: [Character]
        var index = 0
        var table: [String] = []
        var paths: Set<[String]> = []
        var tables: Set<[String]> = []
        var arrayTables: Set<[String]> = []
        var keys: Set<[String]> = []
        var arraySerial = 0
        var scope: [String] = []

        init(_ text: String) { chars = Array(text) }
        var current: Character? { index < chars.count ? chars[index] : nil }
        mutating func take(_ char: Character) -> Bool {
            guard current == char else { return false }
            index += 1
            return true
        }
        func fail() -> AgentSetupError {
            AgentSetupError("Couldn't parse the TOML config. Leave it unchanged and fix its syntax before connecting.")
        }
        mutating func require(_ char: Character) throws { guard take(char) else { throw fail() } }
        mutating func spaces() { while current == " " || current == "\t" { index += 1 } }
        mutating func comment() {
            if take("#") { while current != nil && current != "\n" && current != "\r\n" { index += 1 } }
        }
        mutating func newlines() {
            while true {
                spaces(); comment()
                if !take("\n") && !take("\r\n") { break }
            }
        }
        mutating func document() throws {
            newlines()
            while current != nil {
                if take("[") {
                    let array = take("[")
                    let path = try key()
                    try require("]")
                    if array { try require("]") }
                    guard !keys.contains(where: { path.starts(with: $0) }) else { throw fail() }
                    if array {
                        guard !tables.contains(path) else { throw fail() }
                        arrayTables.insert(path)
                    } else {
                        guard !arrayTables.contains(path), tables.insert(path).inserted else { throw fail() }
                    }
                    table = path
                    scope = array ? ["#array\(arraySerial)"] : []
                    if array { arraySerial += 1 }
                    paths.insert(path)
                } else {
                    let path = try key()
                    try require("=")
                    spaces()
                    try value()
                    let full = table + path
                    let scoped = scope + full
                    guard !keys.contains(where: { scoped.starts(with: $0) || $0.starts(with: scoped) }),
                          !tables.contains(full) else { throw fail() }
                    keys.insert(scoped)
                    paths.insert(full)
                }
                spaces(); comment()
                guard current == nil || take("\n") || take("\r\n") else { throw fail() }
                newlines()
            }
        }
        mutating func key() throws -> [String] {
            var parts: [String] = []
            repeat {
                spaces()
                if current == "\"" || current == "'" {
                    parts.append(try string(multiline: false))
                } else {
                    let start = index
                    while let c = current, c.isASCII && (c.isLetter || c.isNumber || c == "_" || c == "-") {
                        index += 1
                    }
                    guard index > start else { throw fail() }
                    parts.append(String(chars[start..<index]))
                }
                spaces()
            } while take(".")
            return parts
        }
        mutating func value() throws {
            if current == "\"" || current == "'" { _ = try string(multiline: true); return }
            if take("[") {
                newlines()
                if take("]") { return }
                while true {
                    try value(); newlines()
                    if take("]") { return }
                    try require(","); newlines()
                    if take("]") { return }
                }
            }
            if take("{") {
                spaces()
                var names: Set<[String]> = []
                if take("}") { return }
                while true {
                    let path = try key()
                    guard !names.contains(where: { path.starts(with: $0) || $0.starts(with: path) }) else { throw fail() }
                    names.insert(path)
                    try require("="); spaces(); try value(); spaces()
                    if take("}") { return }
                    try require(","); spaces()
                }
            }
            let start = index
            while let c = current, ![" ", "\t", "\n", "\r\n", ",", "]", "}", "#"].contains(c) { index += 1 }
            let token = String(chars[start..<index])
            let patterns = [
                #"^(true|false|[+-]?(inf|nan))$"#,
                #"^[+-]?(0|[1-9](_?[0-9])*)(\.[0-9](_?[0-9])*)?([eE][+-]?[0-9](_?[0-9])*)?$"#,
                #"^0x[0-9a-fA-F](_?[0-9a-fA-F])*$"#, #"^0o[0-7](_?[0-7])*$"#, #"^0b[01](_?[01])*$"#,
            ]
            guard patterns.contains(where: { token.range(of: $0, options: .regularExpression) != nil }) else {
                throw fail()
            }
        }
        mutating func string(multiline: Bool) throws -> String {
            guard let quote = current else { throw fail() }
            index += 1
            let triple = multiline && index + 1 < chars.count && chars[index] == quote && chars[index + 1] == quote
            if triple { index += 2 }
            var result = ""
            while let c = current {
                index += 1
                if c == quote {
                    if !triple { return result }
                    if index + 1 < chars.count && chars[index] == quote && chars[index + 1] == quote {
                        index += 2
                        return result
                    }
                }
                if !triple && (c == "\n" || c == "\r\n") { throw fail() }
                if c == "\\" && quote == "\"" {
                    guard let escaped = current else { throw fail() }
                    index += 1
                    if escaped == "u" || escaped == "U" {
                        let count = escaped == "u" ? 4 : 8
                        guard index + count <= chars.count else { throw fail() }
                        let hex = String(chars[index..<index + count])
                        guard hex.allSatisfy(\.isHexDigit), let value = UInt32(hex, radix: 16),
                              let scalar = UnicodeScalar(value) else { throw fail() }
                        result.append(Character(scalar)); index += count
                    } else if triple && (escaped == "\n" || escaped == "\r\n" || escaped == " " || escaped == "\t") {
                        while current?.isWhitespace == true { index += 1 }
                    } else {
                        let escapes: [Character: Character] = ["b": "\u{8}", "t": "\t", "n": "\n", "f": "\u{c}",
                                                                "r": "\r", "\"": "\"", "\\": "\\"]
                        guard let decoded = escapes[escaped] else { throw fail() }
                        result.append(decoded)
                    }
                } else {
                    guard !c.unicodeScalars.contains(where: { $0.value < 32 && c != "\t" && !(triple && c.isNewline) })
                    else { throw fail() }
                    result.append(c)
                }
            }
            throw fail()
        }
    }
}

private extension String {
    func ranges(of value: String) -> [Range<Index>] {
        var result: [Range<Index>] = []
        var start = startIndex
        while let range = range(of: value, range: start..<endIndex) { result.append(range); start = range.upperBound }
        return result
    }
}
