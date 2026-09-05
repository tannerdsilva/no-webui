import Foundation

// MARK: - SingleUseTokenStore

/// a bounded, expiring set of consumed stateless tokens. used to make
/// pre-auth login CSRF tokens single-use: the stateless HMAC token is
/// validated cryptographically first, and its string is additionally recorded
/// here so a replayed token — double submit, a captured form, a token scraped
/// by a bot before the victim submits — is rejected once. entries expire with
/// the token's embedded expiry; the store is memory-bounded and fails closed
/// (refuses new tokens) at capacity.
public actor SingleUseTokenStore {
	private var consumed: [String: TimeInterval] = [:]

	public let maxEntries: Int

	public init(maxEntries: Int = 10_000) {
		self.maxEntries = maxEntries
	}

	/// mark `token` consumed. returns `false` when the token was already
	/// consumed or the store is at capacity.
	public func consume(_ token: String, expiresAt: TimeInterval) -> Bool {
		prune()
		guard consumed[token] == nil else { return false }
		guard consumed.count < maxEntries else { return false }
		consumed[token] = expiresAt
		return true
	}

	/// remove entries whose embedded expiry has passed.
	public func prune(now: TimeInterval = Date().timeIntervalSince1970) {
		guard consumed.count >= 64 else { return }
		consumed = consumed.filter { $0.value > now }
	}
}
