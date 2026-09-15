// MARK: - Base64

/// pure-swift base64 (rfc 4648) and base64url (rfc 4648 §5) over `[UInt8]` —
/// the data-free replacement for Foundation's `Data`-backed base64. encode
/// emits the exact byte patterns `Data.base64EncodedString()` would (standard
/// alphabet + `=` padding); decode tolerates missing padding and validates the
/// alphabet, rejecting stray or non-ascii bytes.
public enum Base64 {
    private static let alphabet: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    private static let urlAlphabet: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)

    /// standard base64 with `=` padding.
    public static func encode(_ bytes: [UInt8]) -> String {
        encode(bytes, using: alphabet, pad: true)
    }

    /// base64url without padding.
    public static func encodeURL(_ bytes: [UInt8]) -> String {
        encode(bytes, using: urlAlphabet, pad: false)
    }

    /// decode standard base64; padding optional.
    public static func decode(_ string: String) -> [UInt8]? {
        decode(string, url: false)
    }

    /// decode base64url (`-`/`_` alphabet); padding optional.
    public static func decodeURL(_ string: String) -> [UInt8]? {
        decode(string, url: true)
    }

    private static func encode(_ bytes: [UInt8], using table: [UInt8], pad: Bool) -> String {
        var out = [UInt8]()
        out.reserveCapacity((bytes.count + 2) / 3 * 4)
        var i = 0
        while i < bytes.count {
            let b0 = bytes[i]
            let b1 = i + 1 < bytes.count ? bytes[i + 1] : 0
            let b2 = i + 2 < bytes.count ? bytes[i + 2] : 0
            let n = (Int(b0) << 16) | (Int(b1) << 8) | Int(b2)
            out.append(table[(n >> 18) & 0x3f])
            out.append(table[(n >> 12) & 0x3f])
            if i + 1 < bytes.count {
                out.append(table[(n >> 6) & 0x3f])
            } else if pad {
                out.append(61) // '='
            }
            if i + 2 < bytes.count {
                out.append(table[n & 0x3f])
            } else if pad {
                out.append(61) // '='
            }
            i += 3
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func decode(_ string: String, url: Bool) -> [UInt8]? {
        var lookup = [Int](repeating: -1, count: 128)
        let table = url ? urlAlphabet : alphabet
        for (index, byte) in table.enumerated() {
            lookup[Int(byte)] = index
        }
        var out = [UInt8]()
        out.reserveCapacity((string.count * 3) / 4)
        var buffer = 0
        var bits = 0
        for scalar in string.unicodeScalars {
            let value = Int(scalar.value)
            guard value < 128 else { return nil }
            if value == 61 { continue } // '=' padding; only legal at the end, but tolerate here
            let index = lookup[value]
            guard index >= 0 else { return nil }
            buffer = (buffer << 6) | index
            bits += 6
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((buffer >> bits) & 0xff))
            }
        }
        return out
    }
}
