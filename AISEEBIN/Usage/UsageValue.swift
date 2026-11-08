import Foundation

/// A JSON value for event payloads, written as literals at call sites:
/// `["slug": "x", "ms": 12]`. Non-finite numbers encode as `null` and strings
/// lose NUL characters and are cut to `maxStringLength`, so no payload can fail to encode or balloon.
enum UsageValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([UsageValue]), object([String: UsageValue]), null

    static let maxStringLength = 4_000

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(Self.clean(v))
        case .number(let v): if v.isFinite { try c.encode(v) } else { try c.encodeNil() }
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    /// No NUL (Postgres rejects it in text and jsonb), at most `maxStringLength`.
    private static func clean(_ s: String) -> String {
        let s = s.contains("\u{0}") ? s.replacingOccurrences(of: "\u{0}", with: "") : s
        return s.count > maxStringLength ? String(s.prefix(maxStringLength)) : s
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([UsageValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: UsageValue].self)) }
    }
}

extension UsageValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
                      ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral,
                      ExpressibleByNilLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(arrayLiteral elements: UsageValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, UsageValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    init(nilLiteral: ()) { self = .null }
}
