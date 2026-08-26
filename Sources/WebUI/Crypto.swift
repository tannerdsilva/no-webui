import Foundation

#if os(Linux)
import Glibc
#else
import Security
#endif

// MARK: - SHA-256 (FIPS 180-4)

// pure-swift sha-256 so the framework compiles and behaves byte-identically on
// linux and apple platforms without pulling in a crypto dependency. verified
// against the rfc 4231 hmac test vectors in Tests/WebUITests/CryptoTests.swift.
private enum SHA256 {
    static let blockSize = 64

    static let roundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var state: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]

        var msg = message
        let bitLength = UInt64(msg.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            msg.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        for chunkStart in stride(from: 0, to: msg.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let base = chunkStart + i * 4
                w[i] = (UInt32(msg[base]) << 24) | (UInt32(msg[base + 1]) << 16)
                    | (UInt32(msg[base + 2]) << 8) | UInt32(msg[base + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = state[0], b = state[1], c = state[2], d = state[3]
            var e = state[4], f = state[5], g = state[6], h = state[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = h &+ s1 &+ ch &+ Self.roundConstants[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                h = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            state[0] &+= a; state[1] &+= b; state[2] &+= c; state[3] &+= d
            state[4] &+= e; state[5] &+= f; state[6] &+= g; state[7] &+= h
        }

        var out = [UInt8]()
        out.reserveCapacity(32)
        for word in state {
            out.append(UInt8((word >> 24) & 0xff))
            out.append(UInt8((word >> 16) & 0xff))
            out.append(UInt8((word >> 8) & 0xff))
            out.append(UInt8(word & 0xff))
        }
        return out
    }

    private static func rotr(_ value: UInt32, _ n: UInt32) -> UInt32 {
        (value >> n) | (value << (32 - n))
    }
}

// MARK: - HMAC-SHA256 (RFC 2104 / RFC 4231)

// public cross-platform hmac-sha256. identical bytes on every platform — no
// CommonCrypto, no OpenSSL, no swift-crypto dependency.
public enum HMACSHA256 {
    public static let blockSize = 64
    public static let digestSize = 32

    public static func authenticate(message: [UInt8], with key: [UInt8]) -> [UInt8] {
        var key = key
        if key.count > blockSize {
            key = SHA256.hash(key)
        }
        if key.count < blockSize {
            key.append(contentsOf: [UInt8](repeating: 0, count: blockSize - key.count))
        }

        var ipad = [UInt8](repeating: 0x36, count: blockSize)
        var opad = [UInt8](repeating: 0x5c, count: blockSize)
        for i in 0..<blockSize {
            ipad[i] ^= key[i]
            opad[i] ^= key[i]
        }
        return SHA256.hash(opad + SHA256.hash(ipad + message))
    }

    public static func hex(message: [UInt8], key: [UInt8]) -> String {
        bytesToHex(authenticate(message: message, with: key))
    }

    public static func hex(message: String, key: String) -> String? {
        guard let keyData = key.data(using: .utf8),
              let messageData = message.data(using: .utf8) else {
            return nil
        }
        return hex(message: [UInt8](messageData), key: [UInt8](keyData))
    }
}

// MARK: - Byte helpers

public func bytesToHex(_ bytes: [UInt8]) -> String {
    let table = Array("0123456789abcdef".utf8)
    var out = [UInt8]()
    out.reserveCapacity(bytes.count * 2)
    for byte in bytes {
        out.append(table[Int(byte >> 4)])
        out.append(table[Int(byte & 0x0f)])
    }
    return String(decoding: out, as: UTF8.self)
}

// MARK: - Secure Random

// cryptographically secure random bytes: /dev/urandom on linux (getrandom is
// not exposed by every swift linux sdk's glibc module map),
// SecRandomCopyBytes on apple platforms.
public enum SecureRandom {
    public static func bytes(_ count: Int) -> [UInt8]? {
        guard count > 0 else { return count == 0 ? [] : nil }
        var out = [UInt8](repeating: 0, count: count)
        #if os(Linux)
        let fd = open("/dev/urandom", O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var offset = 0
        while offset < count {
            let n = read(fd, &out[offset], count - offset)
            if n < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if n == 0 { return nil }
            offset += n
        }
        return out
        #else
        let status = out.withUnsafeMutableBytes { (ptr) -> Int32 in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        guard status == errSecSuccess else { return nil }
        return out
        #endif
    }
}
