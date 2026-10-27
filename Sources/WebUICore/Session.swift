// MARK: - Session value types
//
// the two keys that name *who* a render belongs to, as values and nothing
// else. no store, no lookup, no policy — the types exist so a later stage can
// key a session table on a hash and a render table on a string without
// inventing a second spelling for either.
//
// both are `Hashable` because they are dictionary keys, and `Sendable` because
// a key crosses from the accept loop to the render and back.

/// the hash a resolved session is keyed by.
///
/// opaque bytes on purpose: how a cookie becomes a hash is the resolver's
/// business (`WebUIHost`), and the render path only ever compares it.
public struct SessionKey: Hashable, Sendable {
	/// the session's hash, exactly as the resolver produced it.
	public let hash: [UInt8]

	public init(hash: [UInt8]) {
		self.hash = hash
	}
}

/// the key of one page render — the value the client echoes back so a frame
/// can be bound to the render that minted it.
public struct RenderKey: Hashable, Sendable {
	/// the wire form of the key.
	public let value: String

	public init(value: String) {
		self.value = value
	}
}
