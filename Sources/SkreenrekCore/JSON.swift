import Foundation

/// Shared JSON coding so goldens stay stable: sorted keys, unescaped slashes.
public enum SkreenrekJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder().encode(value)
    }

    public static func string<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encode(value), as: UTF8.self)
    }
}
