import Foundation
import WebUICore

// MARK: - CSRF Protection
public enum CSRFError: Error, Equatable, Sendable {
    /// the os entropy source failed — no fallback was attempted. every minting
    /// door in this layer fails loudly rather than degrade to a prng (mirrors
    /// `SessionToken.generate`), and this one case is that failure for both
    /// `CSRFProtection` and the document's render nonce.
    case entropyUnavailable
    /// hmac failure while signing a token.
    case signingFailed
}

public enum CSRFProtection {
    /// 30 minutes, in `Epoch` seconds — the framework's one time
    /// representation (`Epoch` is unix seconds, defined in `WebUISharedCore`).
    public static let defaultMaxAge: Epoch = 1800
    public static func generateSecret() throws -> String {
        guard let bytes = SecureRandom.bytes(32) else {
            throw CSRFError.entropyUnavailable
        }
        return Base64.encode(bytes)
    }
    /// the one bridge from wall time to the framework's clock: `Date` speaks
    /// double seconds, everything else in this file speaks `Epoch`. computed and
    /// private — it is only the default the injectable `now` parameter falls back
    /// to, never a settable seam, so nothing can pin or skew time behind a
    /// caller's back.
    private static var currentEpoch: Epoch { Epoch(Date().timeIntervalSince1970) }
    /// `now` is the clock this token is minted against — the injectable seam, not
    /// a stored one: production callers take the default, tests pass a pinned
    /// `Epoch` and never sleep.
    public static func token(
        for formID: String,
        secret: String,
        maxAge: Epoch = defaultMaxAge,
        now instant: Epoch? = nil
    ) throws -> String {
        let now = instant ?? currentEpoch
        let expires = now + maxAge
        // a per-token random nonce is required: the embedded expiry has
        // one-second resolution, so without a nonce two tokens minted at the
        // same `now` would be byte-identical — harmless for stateless
        // validation, but fatal for the single-use login-token store, which
        // would reject the second one as consumed. the bytes come from
        // `SecureRandom` — the same os-entropy door `generateSecret()` uses —
        // hex-encoded to the 32-character shape this payload always carried.
        // (a Foundation uuid string used to sit here: a second entropy source
        // with its own failure semantics, in a layer that otherwise refuses
        // anything but `SecureRandom`.)
        guard let nonceBytes = SecureRandom.bytes(16) else {
            throw CSRFError.entropyUnavailable
        }
        let nonce = bytesToHex(nonceBytes)
        // `expires` is an `Epoch` and interpolates as whole seconds — the same
        // digits the old `Int(expires)` truncation produced, so the wire format
        // (`base64(formID:expiry:nonce:signature)`) did not move.
        let payload = "\(formID):\(expires):\(nonce)"
        let signature: String
        do {
            signature = try hmacSHA256(key: secret, message: payload)
        } catch {
            // a signing failure must surface as this module's own error. letting
            // the hmac layer's error escape a public `throws` would force every
            // caller to import the crypto dependency just to catch it, and no
            // caller can act differently on which internal step failed — so the
            // cause is collapsed on purpose rather than leaked.
            throw CSRFError.signingFailed
        }
        return Base64.encode([UInt8]("\(payload):\(signature)".utf8))
    }
    public static func validate(
        _ token: String,
        for formID: String,
        secret: String,
        now instant: Epoch? = nil
    ) -> Bool {
        let now = instant ?? currentEpoch
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
              let expires = Epoch(expiresStr),
              now < expires else {
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
    /// the embedded expiry (unix seconds, `Epoch`) of a well-formed token, or
    /// `nil` when the token does not decode to `formID:expiry:nonce:signature`.
    /// callers should only pass tokens that have already passed `validate`.
    public static func expiry(of token: String) -> Epoch? {
        guard let tokenBytes = Base64.decode(token) else {
            return nil
        }
        let tokenStr = String(decoding: tokenBytes, as: UTF8.self)
        let parts = tokenStr.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return Epoch(parts[1])
    }
    private static func hmacSHA256(key: String, message: String) throws -> String {
        try HMACSHA256.hex(message: [UInt8](message.utf8), key: [UInt8](key.utf8))
    }
}
