import Foundation
import WebUICore

// MARK: - CSRF Protection
public enum CSRFError: Error, Equatable, Sendable {
    /// the os entropy source failed — no fallback was attempted. the signing
    /// key must fail loudly rather than degrade to a prng (mirrors
    /// `SessionToken.generate`).
    case entropyUnavailable
    /// hmac failure while signing a token.
    case signingFailed
}

public enum CSRFProtection {
    public static let defaultMaxAge: TimeInterval = 1800
    public static func generateSecret() throws -> String {
        guard let bytes = SecureRandom.bytes(32) else {
            throw CSRFError.entropyUnavailable
        }
        return Base64.encode(bytes)
    }
    public static func token(for formID: String, secret: String, maxAge: TimeInterval = defaultMaxAge) throws -> String {
        let expires = Date().timeIntervalSince1970 + maxAge
        // a per-token random nonce is required: the embedded expiry is
        // second-quantized (`Int` truncation), so without a nonce two tokens
        // minted in the same wall-clock second would be byte-identical —
        // harmless for stateless validation, but fatal for the single-use
        // login-token store, which would reject the second one as consumed.
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let payload = "\(formID):\(Int(expires)):\(nonce)"
        let signature = try hmacSHA256(key: secret, message: payload)
        return Base64.encode([UInt8]("\(payload):\(signature)".utf8))
    }
    public static func validate(_ token: String, for formID: String, secret: String) -> Bool {
        guard let tokenBytes = Base64.decode(token) else {
            return false
        }
        let tokenStr = String(decoding: tokenBytes, as: UTF8.self)
        let parts = tokenStr.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let payloadFormID = String(parts[0])
        let expiresStr = String(parts[1])
        let nonce = String(parts[2])
        let signature = String(parts[3])

        guard payloadFormID == formID,
              let expires = TimeInterval(expiresStr),
              Date().timeIntervalSince1970 < expires else {
            return false
        }

        let expectedSignature: String
        do {
            expectedSignature = try hmacSHA256(key: secret, message: "\(formID):\(expiresStr):\(nonce)")
        } catch {
            // an hmac failure must reject, never accept. the old `try?` + ""
            // fallback compared attacker-supplied "" against expected "" when
            // the hmac threw — an empty-signature token would validate.
            return false
        }
        // constant-time compare — the caller's signature is attacker-controlled,
        // and a short-circuiting == would leak prefix bytes of the MAC.
        return constantTimeEquals(Array(signature.utf8), Array(expectedSignature.utf8))
    }
    /// the embedded expiry (seconds since 1970) of a well-formed token, or
    /// `nil` when the token does not decode to `formID:expiry:nonce:signature`.
    /// callers should only pass tokens that have already passed `validate`.
    public static func expiry(of token: String) -> TimeInterval? {
        guard let tokenBytes = Base64.decode(token) else {
            return nil
        }
        let tokenStr = String(decoding: tokenBytes, as: UTF8.self)
        let parts = tokenStr.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return TimeInterval(parts[1])
    }
    private static func hmacSHA256(key: String, message: String) throws -> String {
        try HMACSHA256.hex(message: [UInt8](message.utf8), key: [UInt8](key.utf8))
    }
}
