import Foundation

/// a server-side authentication session.
///
/// the raw token is never stored — `tokenHash` is the SHA-256 of the token the
/// client holds, so a database dump is not a session-theft kit. `id` is a
/// separate random identifier used for invalidation and index bookkeeping.
public struct AuthenticatedSession: Sendable, Codable, Equatable, Hashable {
	/// session identifier, 16 random bytes. indexing key and invalidation target.
	public let id: [UInt8]
	/// SHA-256 of the client-held 32-byte token.
	public let tokenHash: [UInt8]
	/// the identity this session authenticates.
	public let identityID: String
	/// per-session seed for session-bound CSRF tokens.
	public let csrfSeed: [UInt8]
	public let createdAt: Date
	public let expiresAt: Date
	public var lastSeenAt: Date

	public init(
		id: [UInt8],
		tokenHash: [UInt8],
		identityID: String,
		csrfSeed: [UInt8],
		createdAt: Date,
		expiresAt: Date,
		lastSeenAt: Date
	) {
		self.id = id
		self.tokenHash = tokenHash
		self.identityID = identityID
		self.csrfSeed = csrfSeed
		self.createdAt = createdAt
		self.expiresAt = expiresAt
		self.lastSeenAt = lastSeenAt
	}

	/// absolute-expiry check — sessions expire by wall-clock, independent of
	/// any sliding-window touch.
	public func isExpired(at date: Date = Date()) -> Bool {
		date >= expiresAt
	}
}
