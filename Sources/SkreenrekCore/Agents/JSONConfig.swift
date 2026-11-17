import Foundation

/// Edits only the requested JSON member. Other keys, values, order and whitespace keep their original bytes.
/// Foundation validates the full document; the small range walker also rejects duplicate keys before any edit.
enum JSONConfig {
    struct Member {
        let key: String
        let start: Int
        let value: Range<Int>
    }

    static func server(in text: String) throws -> String? {
        let bytes = Array(text.utf8)
        let root = try object(bytes, range: 0..<bytes.count)
        guard let servers = root.first(where: { $0.key == "mcpServers" }) else { return nil }
        let entries = try object(bytes, range: servers.value)
        return entries.first(where: { $0.key == "skreenrek" }).map { string(bytes[$0.value]) }
    }

    static func edit(_ text: String, server: String?) throws -> String {
        var bytes = Array(text.utf8)
        let root = try object(bytes, range: 0..<bytes.count)
        if let servers = root.first(where: { $0.key == "mcpServers" }) {
            try editObject(&bytes, range: servers.value, key: "skreenrek", value: server)
        } else if let server {
            try editObject(&bytes, range: 0..<bytes.count, key: "mcpServers", value: "{\"skreenrek\": \(server)}")
        }
        return string(bytes[...])
    }

    static func equal(_ a: String, _ b: String) -> Bool {
        guard let a = try? JSONSerialization.jsonObject(with: Data(a.utf8)) as? NSDictionary,
              let b = try? JSONSerialization.jsonObject(with: Data(b.utf8)) as? NSDictionary else { return false }
        return a == b
    }

    private static func editObject(_ bytes: inout [UInt8], range: Range<Int>, key: String, value: String?) throws {
        let members = try object(bytes, range: range)
        if let index = members.firstIndex(where: { $0.key == key }) {
            let member = members[index]
            if let value {
                bytes.replaceSubrange(member.value, with: value.utf8)
            } else {
                let remove: Range<Int>
                if index + 1 < members.count {
                    remove = member.start..<members[index + 1].start
                } else if index > 0 {
                    remove = members[index - 1].value.upperBound..<member.value.upperBound
                } else {
                    remove = member.start..<member.value.upperBound
                }
                bytes.removeSubrange(remove)
            }
        } else if let value {
            var end = range.upperBound - 1
            while whitespace(bytes[end]) { end -= 1 }
            let addition = (members.isEmpty ? "" : ",") + "\n    \"\(key)\": \(value)\n"
            bytes.insert(contentsOf: addition.utf8, at: end)
        }
    }

    private static func object(_ bytes: [UInt8], range: Range<Int>) throws -> [Member] {
        let data = Data(bytes[range])
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw AgentSetupError("Couldn't parse the JSON config. Leave it unchanged and fix its syntax before connecting.")
        }
        var index = range.lowerBound
        // Foundation accepts a leading UTF-8 BOM; keep it in the document, but don't read it as a key.
        if bytes[range].starts(with: [0xef, 0xbb, 0xbf]) { index += 3 }
        skip(bytes, &index)
        guard index < range.upperBound, bytes[index] == 123 else {
            throw AgentSetupError("Couldn't parse the JSON config. Leave it unchanged and fix its syntax before connecting.")
        }
        return try members(bytes, &index)
    }

    private static func members(_ bytes: [UInt8], _ index: inout Int) throws -> [Member] {
        index += 1 // {
        skip(bytes, &index)
        var result: [Member] = []
        while bytes[index] != 125 {
            let start = index
            consumeString(bytes, &index)
            let key = try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
            guard !result.contains(where: { $0.key == key }) else {
                throw AgentSetupError("The JSON config has duplicate keys. Fix them before connecting.")
            }
            skip(bytes, &index)
            index += 1 // :
            skip(bytes, &index)
            let valueStart = index
            try consumeValue(bytes, &index)
            result.append(Member(key: key, start: start, value: valueStart..<index))
            skip(bytes, &index)
            if bytes[index] == 44 { index += 1; skip(bytes, &index) }
        }
        index += 1
        return result
    }

    private static func consumeValue(_ bytes: [UInt8], _ index: inout Int) throws {
        switch bytes[index] {
        case 34: consumeString(bytes, &index)
        case 123: _ = try members(bytes, &index)
        case 91:
            index += 1
            skip(bytes, &index)
            while bytes[index] != 93 {
                try consumeValue(bytes, &index)
                skip(bytes, &index)
                if bytes[index] == 44 { index += 1; skip(bytes, &index) }
            }
            index += 1
        default:
            while index < bytes.count && ![UInt8(44), 93, 125, 32, 9, 10, 13].contains(bytes[index]) { index += 1 }
        }
    }

    private static func consumeString(_ bytes: [UInt8], _ index: inout Int) {
        index += 1
        while bytes[index] != 34 {
            if bytes[index] == 92 { index += 1 }
            index += 1
        }
        index += 1
    }

    private static func skip(_ bytes: [UInt8], _ index: inout Int) {
        while index < bytes.count && whitespace(bytes[index]) { index += 1 }
    }

    private static func whitespace(_ byte: UInt8) -> Bool { [9, 10, 13, 32].contains(byte) }
    private static func string(_ bytes: ArraySlice<UInt8>) -> String { String(decoding: bytes, as: UTF8.self) }
}
