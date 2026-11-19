import Foundation

/// A release body (the CHANGELOG section `make release` publishes) as the lines What's new shows. SwiftUI `Text`
/// drops Markdown's block structure (headings, list items and paragraphs run together on one line), so the blocks are
/// split here and only inline Markdown is left to `Text`. Pure, so tests cover it.
public enum ReleaseNotes {
    public enum Block: Sendable, Hashable {
        /// A section heading, such as Added or Fixed.
        case heading(String)
        /// One list item.
        case bullet(String)
        /// A plain paragraph.
        case paragraph(String)
    }

    public static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        // A line right after text continues it (a wrapped paragraph or list item); a blank line ends it.
        var continues = false
        let text = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || isRule(line) {
                continues = false
                continue
            }
            if let (level, title) = heading(line) {
                continues = false
                // The version line (the update row already names the version) and a title before any notes.
                if isVersion(title) || (level == 1 && blocks.isEmpty) || title.isEmpty { continue }
                blocks.append(.heading(title))
            } else if let item = bullet(line) {
                blocks.append(.bullet(item))
                continues = true
            } else if continues, let last = blocks.last {
                switch last {
                case .bullet(let item): blocks[blocks.count - 1] = .bullet(item + " " + line)
                case .paragraph(let item): blocks[blocks.count - 1] = .paragraph(item + " " + line)
                case .heading: blocks.append(.paragraph(line))
                }
            } else {
                blocks.append(.paragraph(line))
                continues = true
            }
        }
        return blocks
    }

    /// `## Title` (1 to 6 `#`, then a space), without closing `#`s.
    private static func heading(_ line: String) -> (Int, String)? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var title = rest.trimmingCharacters(in: .whitespaces)
        while title.hasSuffix("#") { title.removeLast() }
        return (level, title.trimmingCharacters(in: .whitespaces))
    }

    /// `- item`, `* item` or `+ item`, at any indent.
    private static func bullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// `---`, `***` or `___`.
    private static func isRule(_ line: String) -> Bool {
        let compact = line.filter { $0 != " " }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    /// `[1.0.6] - 2026-11-19`, `1.0.6`, `v1.0.6 (2026-11-19)`: a heading that starts with a version number.
    private static func isVersion(_ title: String) -> Bool {
        var rest = Substring(title)
        if rest.hasPrefix("[") { rest = rest.dropFirst() }
        if rest.hasPrefix("v") || rest.hasPrefix("V") { rest = rest.dropFirst() }
        let digits = rest.prefix { $0.isNumber }
        return !digits.isEmpty && rest.dropFirst(digits.count).hasPrefix(".")
    }
}
