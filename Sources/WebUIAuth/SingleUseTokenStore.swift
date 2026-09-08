import Foundation

// MARK: - SingleUseTokenStore

/// a bounded, expiring set of consumed stateless tokens. used to make
/// pre-auth login CSRF tokens single-use: the stateless HMAC token is
/// validated cryptographically first, and its string is additionally recorded
/// here so a replayed token — double submit, a captured form, a token scraped
/// by a bot before the victim submits — is rejected once. entries expire with
/// the token's embedded expiry; the store is memory-bounded and fails closed
/// (refuses new tokens) at capacity.
///
/// issuance is budgeted per key via `reserve`: an issuer (keyed by client ip
/// in the auth demo) may hold at most `maxOutstandingPerKey` *unsubmitted*
/// tokens at once. without the budget, an unthrottled token-minting endpoint
/// lets one ip stockpile and then flood the store past capacity, locking out
/// legitimate logins (availability DoS).
public actor SingleUseTokenStore {
	private enum Entry: Sendable {
		/// issued via `reserve` but not yet submitted — counts toward the
		/// issuer's `outstanding` budget.
		case pending(expiresAt: TimeInterval, key: String)
		/// submitted once and recorded for replay rejection.
		case consumed(expiresAt: TimeInterval, key: String?)
	}

	private var entries: [String: Entry] = [:]
	private var outstanding: [String: Int] = [:]

	public let maxEntries: Int
	public let maxOutstandingPerKey: Int

	public init(maxEntries: Int = 10_000, maxOutstandingPerKey: Int = 5) {
		precondition(maxEntries > 0 && maxOutstandingPerKey > 0)
		self.maxEntries = maxEntries
		self.maxOutstandingPerKey = maxOutstandingPerKey
	}

	/// record a token issuance under `key` so one issuer cannot stockpile more
	/// than `maxOutstandingPerKey` unsubmitted tokens. returns `false` when the
	/// key already holds its budget, the token string is already in the store,
	/// or the store is at capacity.
	@discardableResult
	public func reserve(_ token: String, expiresAt: TimeInterval, key: String) -> Bool {
		prune()
		guard entries[token] == nil else { return false }
		guard entries.count < maxEntries else { return false }
		guard (outstanding[key] ?? 0) < maxOutstandingPerKey else { return false }
		entries[token] = .pending(expiresAt: expiresAt, key: key)
		outstanding[key, default: 0] += 1
		return true
	}

	/// mark `token` consumed. returns `false` when the token was already
	/// consumed or the store is at capacity. when the token was previously
	/// reserved under a key, that key's outstanding budget is released (the
	/// submitter may present from a different ip than the issuer; the budget is
	/// keyed by the issuer recorded at `reserve`).
	public func consume(_ token: String, expiresAt: TimeInterval, key: String? = nil) -> Bool {
		prune()
		if case .consumed? = entries[token] { return false }
		guard entries.count < maxEntries else { return false }
		if case .pending(_, let reservedKey)? = entries[token] {
			outstanding[reservedKey] = max((outstanding[reservedKey] ?? 1) - 1, 0)
		}
		entries[token] = .consumed(expiresAt: expiresAt, key: key)
		return true
	}

	/// remove entries whose embedded expiry has passed; pending (issued but
	/// unsubmitted) entries release their issuer's budget.
	public func prune(now: TimeInterval = Date().timeIntervalSince1970) {
		guard entries.count >= 64 else { return }
		for (token, entry) in entries {
			switch entry {
			case .pending(let expiresAt, let key):
				if expiresAt <= now {
					entries[token] = nil
					outstanding[key] = max((outstanding[key] ?? 1) - 1, 0)
				}
			case .consumed(let expiresAt, _):
				if expiresAt <= now {
					entries[token] = nil
				}
			}
		}
	}
}
