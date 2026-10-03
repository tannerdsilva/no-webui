// MARK: - JSONValue
//
// a minimal rfc 8259 json value — the data-free replacement for Foundation's
// `Data`-backed JSON decode/encode inside the framework. `parse` is strict
// (rejects trailing tokens, unescaped control characters, malformed numbers);
// `serialize` emits compact json with an integral-friendly number form
// (whole values are written without a trailing `.0`).
//
// scalar-clean by design: the parser walks `unicodeScalars`, never
// `Character` grapheme clusters — the embedded wasm runtime omits the
// grapheme-break tables, so a Character-level parser would not link there.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// parse a complete json document; anything after the value is an error.
    public static func parse(_ text: String) throws -> JSONValue {
        var parser = JSONParser(text)
        let value = try parser.parseValue()
        try parser.requireEnd()
        return value
    }

    /// compact single-line serialization.
    public func serialize() -> String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            return Self.numberString(value)
        case .string(let value):
            return "\"\(Self.escapeString(value))\""
        case .array(let elements):
            return "[" + elements.map { $0.serialize() }.joined(separator: ",") + "]"
        case .object(let object):
            return "{" + object.map { "\"\(Self.escapeString($0.key))\":" + $0.value.serialize() }.joined(separator: ",") + "}"
        }
    }

    /// json string escaping: `"`, `\`, and control characters
    /// (`\b \f \n \r \t`, everything else as `\uXXXX`).
    public static func escapeString(_ string: String) -> String {
        var out = ""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5c: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x0c: out += "\\f"
            case 0x0a: out += "\\n"
            case 0x0d: out += "\\r"
            case 0x09: out += "\\t"
            case 0x00...0x1f: out += Self.hex4(scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private static func numberString(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        let rounded = value.rounded()
        if rounded == value, Int64(value) == Int64(rounded), value >= -9_007_199_254_740_992, value <= 9_007_199_254_740_992 {
            return String(Int64(value))
        }
        return String(value)
    }

    private static func hex4(_ value: UInt32) -> String {
        let digits = Array("0123456789abcdef".unicodeScalars)
        func d(_ shift: UInt32) -> Unicode.Scalar { digits[Int((value >> shift) & 0xf)] }
        return "\\u\(String.UnicodeScalarView([d(12), d(8), d(4), d(0)]))"
    }
}

// MARK: - JSONError

/// structural errors from `JSONValue.parse`.
public enum JSONError: Error, Equatable, Sendable {
    case unexpectedEnd
    case invalidToken(Unicode.Scalar)
    case invalidString
    case invalidEscape
    case invalidNumber
    case trailingCharacters
    /// container nesting exceeded `JSONParser.maxNestingDepth`. thrown instead
    /// of overflowing the stack: a wire message of nested brackets/objects is
    /// probe-verified to segfault a 16 kb-bounded frame at depth ~5000.
    case nestingTooDeep
}

// MARK: - Parser

private struct JSONParser {
    /// maximum container nesting accepted by `parse`. bounds the recursion
    /// depth of `parseValue`/`parseObject`/`parseArray` so a pathological wire
    /// message throws `nestingTooDeep` instead of overflowing the stack.
    static let maxNestingDepth = 128

    private let scalars: [Unicode.Scalar]
    private var index = 0
    private var depth = 0

    init(_ text: String) {
        self.scalars = Array(text.unicodeScalars)
    }

    var isAtEnd: Bool { index >= scalars.count }
    private func peek() -> Unicode.Scalar? { index < scalars.count ? scalars[index] : nil }
    private mutating func advance() { index += 1 }

    mutating func requireEnd() throws {
        skipWhitespace()
        guard isAtEnd else { throw JSONError.trailingCharacters }
    }

    mutating func skipWhitespace() {
        while let c = peek(), c.value == 0x20 || c.value == 0x09 || c.value == 0x0A || c.value == 0x0D {
            advance()
        }
    }

    mutating func parseValue() throws -> JSONValue {
        skipWhitespace()
        guard let c = peek() else { throw JSONError.unexpectedEnd }
        switch c.value {
        case 0x7B: return try parseObject()
        case 0x5B: return try parseArray()
        case 0x22: return .string(try parseString())
        case 0x74: try parseLiteral("true"); return .bool(true)
        case 0x66: try parseLiteral("false"); return .bool(false)
        case 0x6E: try parseLiteral("null"); return .null
        case 0x2D, 0x30...0x39: return .number(try parseNumber())
        default: throw JSONError.invalidToken(c)
        }
    }

    mutating func parseLiteral(_ literal: String) throws {
        for expected in literal.unicodeScalars {
            guard peek() == expected else { throw JSONError.invalidToken(expected) }
            advance()
        }
    }

    mutating func parseObject() throws -> JSONValue {
        advance() // '{'
        depth += 1
        defer { depth -= 1 }
        guard depth <= Self.maxNestingDepth else { throw JSONError.nestingTooDeep }
        var object: [String: JSONValue] = [:]
        skipWhitespace()
        if peek()?.value == 0x7D { advance(); return .object(object) }
        while true {
            skipWhitespace()
            guard let quote = peek() else { throw JSONError.unexpectedEnd }
            guard quote.value == 0x22 else { throw JSONError.invalidToken(quote) }
            let key = try parseString()
            skipWhitespace()
            guard let colon = peek() else { throw JSONError.unexpectedEnd }
            guard colon.value == 0x3A else { throw JSONError.invalidToken(colon) }
            advance()
            object[key] = try parseValue()
            skipWhitespace()
            guard let separator = peek() else { throw JSONError.unexpectedEnd }
            advance()
            if separator.value == 0x7D { return .object(object) }
            guard separator.value == 0x2C else { throw JSONError.invalidToken(separator) }
        }
    }

    mutating func parseArray() throws -> JSONValue {
        advance() // '['
        depth += 1
        defer { depth -= 1 }
        guard depth <= Self.maxNestingDepth else { throw JSONError.nestingTooDeep }
        var elements: [JSONValue] = []
        skipWhitespace()
        if peek()?.value == 0x5D { advance(); return .array(elements) }
        while true {
            elements.append(try parseValue())
            skipWhitespace()
            guard let separator = peek() else { throw JSONError.unexpectedEnd }
            advance()
            if separator.value == 0x5D { return .array(elements) }
            guard separator.value == 0x2C else { throw JSONError.invalidToken(separator) }
        }
    }

    mutating func parseString() throws -> String {
        advance() // '"'
        var out = ""
        while true {
            guard let c = peek() else { throw JSONError.unexpectedEnd }
            switch c.value {
            case 0x22:
                advance()
                return out
            case 0x5C:
                advance()
                guard let escaped = peek() else { throw JSONError.unexpectedEnd }
                advance()
                switch escaped.value {
                case 0x22: out.unicodeScalars.append("\"")
                case 0x5C: out.unicodeScalars.append("\\")
                case 0x2F: out.unicodeScalars.append("/")
                case 0x62: out.unicodeScalars.append("\u{08}")
                case 0x66: out.unicodeScalars.append("\u{0C}")
                case 0x6E: out.unicodeScalars.append("\n")
                case 0x72: out.unicodeScalars.append("\r")
                case 0x74: out.unicodeScalars.append("\t")
                case 0x75:
                    let scalar = try parseUnicodeEscape()
                    out.unicodeScalars.append(scalar)
                default: throw JSONError.invalidEscape
                }
            case 0x00...0x1F:
                throw JSONError.invalidString
            default:
                out.unicodeScalars.append(c)
                advance()
            }
        }
    }

    private mutating func parseHex4() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let digit = hexDigitValue(peek()) else { throw JSONError.invalidEscape }
            value = (value << 4) | digit
            advance()
        }
        guard value <= 0x10FFFF else { throw JSONError.invalidEscape }
        return value
    }

    private func hexDigitValue(_ c: Unicode.Scalar?) -> UInt32? {
        guard let c else { return nil }
        let v = c.value
        switch v {
        case 0x30...0x39: return v - 0x30
        case 0x61...0x66: return v - 0x61 + 10
        case 0x41...0x46: return v - 0x41 + 10
        default: return nil
        }
    }

    private mutating func parseUnicodeEscape() throws -> UnicodeScalar {
        let first = try parseHex4()
        // surrogate pair: a high surrogate must be followed by \uXXXX low.
        if first >= 0xD800 && first <= 0xDBFF {
            guard peek()?.value == 0x5C else { throw JSONError.invalidEscape }
            advance()
            guard peek()?.value == 0x75 else { throw JSONError.invalidEscape }
            advance()
            let second = try parseHex4()
            guard second >= 0xDC00 && second <= 0xDFFF else { throw JSONError.invalidEscape }
            let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
            guard let scalar = UnicodeScalar(combined) else { throw JSONError.invalidEscape }
            return scalar
        }
        // a lone low surrogate is invalid.
        if first >= 0xDC00 && first <= 0xDFFF { throw JSONError.invalidEscape }
        guard let scalar = UnicodeScalar(first) else { throw JSONError.invalidEscape }
        return scalar
    }

    mutating func parseNumber() throws -> Double {
        let start = index
        if peek()?.value == 0x2D { advance() }
        while let c = peek(), c.value >= 0x30 && c.value <= 0x39 { advance() }
        if peek()?.value == 0x2E {
            advance()
            guard let c = peek(), c.value >= 0x30 && c.value <= 0x39 else { throw JSONError.invalidNumber }
            while let c = peek(), c.value >= 0x30 && c.value <= 0x39 { advance() }
        }
        if peek()?.value == 0x65 || peek()?.value == 0x45 {
            advance()
            if peek()?.value == 0x2B || peek()?.value == 0x2D { advance() }
            guard let c = peek(), c.value >= 0x30 && c.value <= 0x39 else { throw JSONError.invalidNumber }
            while let c = peek(), c.value >= 0x30 && c.value <= 0x39 { advance() }
        }
        let slice = String(String.UnicodeScalarView(scalars[start..<index]))
        guard let value = Double(slice), value.isFinite else { throw JSONError.invalidNumber }
        return value
    }
}

// MARK: - Codable
//
// `Decoder`/`Encoder` are unavailable in embedded swift; the island path uses
// `parse`/`serialize` only, so the conformance is host/full-stdlib surface.
#if !hasFeature(Embedded)
extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "unrepresentable json value")
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
#endif

// MARK: - Literal conformances

// so write-sites that passed `[String: String]` literals keep compiling as
// `[String: JSONValue]` after the p3 payload widening (`data: ["value": "a"]`).
extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}
