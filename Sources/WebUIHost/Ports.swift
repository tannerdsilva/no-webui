import Synchronization
import WebUI
import WebUIServer
import WebUIAuth

// MARK: - PrincipalResolver

/// resolves the principal of a request. one job, one method.
///
/// makes unrepresentable: "a page renders without anyone having decided who
/// asked". the host reaches a page table only through the value this protocol
/// returns, so "who is asking" is settled before any page is chosen, and there
/// is no second door that skips it.
public protocol PrincipalResolver: Sendable {
	/// the principal this request authenticates as, or `nil` when it
	/// authenticates as nobody.
	///
	/// a resolver throws only when the answer cannot be *determined* — a store
	/// that failed. an absent, malformed, expired or revoked credential is
	/// `nil`, never an error: "not signed in" is an ordinary answer, and the
	/// difference between it and "the store is down" is the difference between
	/// a redirect and a 500.
	func principal(for request: HTTPRequest) async throws -> AuthContext?
}

// MARK: - PageCatalog

/// the page a principal is allowed to see at this path.
///
/// makes unrepresentable: "one global page table serves every identity" — the
/// table cannot be consulted without a principal and a path together, so there
/// is no call that answers "what is at `/dashboard`" without also answering
/// "for whom".
public protocol PageCatalog: Sendable {
	/// the responder for `path` as seen by `principal`, or `nil` when this
	/// catalog has no page there *or* the principal is not admitted to it.
	///
	/// the two `nil`s are deliberately not distinguished: a catalog must not
	/// tell an unauthorised principal that a page exists.
	func responder(for path: String, principal: AuthContext) async throws -> Responder?

	/// the anonymous door — what a request that resolved to nobody gets at
	/// `path`.
	///
	/// the default answers `nil`, which is the honest answer for a catalog
	/// whose every page requires a principal. a conformer that wants to send an
	/// anonymous visitor to a login page (rather than 404) overrides it, and a
	/// public-page catalog serves those pages here. the host distinguishes
	/// nothing itself: "anonymous + known guarded path → 303" lives in the
	/// catalog that owns the knowledge.
	func responder(for path: String) async throws -> Responder?
}

extension PageCatalog {
	public func responder(for path: String) async throws -> Responder? { nil }
}

// MARK: - SessionRouterTable

/// the routers a session's live pages are bound to.
///
/// makes unrepresentable: "a frame minted by session A dispatches into session
/// B's handlers" — resolution requires both the session key and a render token
/// that session actually minted, and the forward chain preserves that property
/// across LRU eviction instead of breaking it (a page evicted from the live
/// table forwards to the token that replaced it, so an open page migrates in
/// place rather than losing its handlers).
///
/// the binding contract, which ``RouterTable`` documents and enforces at
/// `drop(session:)` time: a router bound under `renderToken` registers its
/// handlers in `RenderSessionID(renderToken.value)`. that is what lets a
/// logout end exactly the handlers a session's pages registered.
public protocol SessionRouterTable: Sendable {
	/// the router serving `renderToken` for `session`.
	///
	/// `nil` for a token this session never minted — forged, foreign, or from
	/// a page whose session has ended. `needsRefresh` is true when the token
	/// was found through the forward chain rather than directly: the page is
	/// live but its own token was evicted, so the caller hands it `liveToken`
	/// to adopt. never a reload, never a logout.
	func router(
		for session: SessionKey,
		renderToken: RenderKey
	) async -> (router: EventRouter, liveToken: RenderKey, needsRefresh: Bool)?

	/// bind one render pass's router to the session that minted it.
	func bind(_ router: EventRouter, session: SessionKey, renderToken: RenderKey) async

	/// drop every router bound to `session` and end their render sessions.
	/// called by revocation, never by a page.
	func drop(session: SessionKey) async
}

// MARK: - RevocationBus

/// the live connection a ``RevocationBus`` can tear down.
///
/// the token carries the close action rather than naming a transport type, so
/// the bus never learns what a socket is: a NIO channel, a test double and a
/// future transport all arrive as "something that can be closed". `id` is what
/// `untrack` matches on, and it must be unique per live connection — use
/// ``next(close:)``, which draws from a process-wide counter.
public struct ConnectionToken: Sendable, Hashable {
	/// unique per live connection, for `untrack`.
	public let id: UInt64
	/// closes the connection this token names. must be safe to call twice and
	/// must not block: the bus calls it while holding nothing.
	public let close: @Sendable () -> Void

	private static let counter = Mutex(UInt64(0))

	public init(id: UInt64, close: @escaping @Sendable () -> Void) {
		self.id = id
		self.close = close
	}

	/// a token with a process-unique id.
	public static func next(close: @escaping @Sendable () -> Void) -> ConnectionToken {
		let id = counter.withLock { value in
			value += 1
			return value
		}
		return ConnectionToken(id: id, close: close)
	}

	/// identity is the id alone: two tokens for one live connection are the
	/// same connection, whatever closure each happens to carry.
	public static func == (lhs: ConnectionToken, rhs: ConnectionToken) -> Bool {
		lhs.id == rhs.id
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}

/// tears down what a revoked session still holds.
///
/// makes unrepresentable: "a logged-out session keeps a live socket" —
/// revocation is one call, and every socket tracked under the session is
/// closed by it. the bus is the *transport* half of revocation; the store half
/// is ``SessionRevocation``, and ``AuthenticatedHost`` calls both.
public protocol RevocationBus: Sendable {
	/// register a live connection under the session it authenticated as.
	func track(_ connection: ConnectionToken, session: SessionKey) async
	/// forget a connection that ended on its own (idle reap, client close).
	/// revocation must not close a descriptor the kernel already reclaimed.
	func untrack(_ connection: ConnectionToken) async
	/// close every connection tracked under `session`, and forget them.
	func revoke(session: SessionKey) async
}

// MARK: - SessionRevocation

/// ends a session at the store a ``PrincipalResolver`` reads.
///
/// the write door that pairs with the resolver's read door, kept separate so a
/// resolver stays "one job, one method" and a host composes the two halves of
/// revocation explicitly: the store entry here, the sockets and handlers through
/// ``RevocationBus`` and ``SessionRouterTable``.
public protocol SessionRevocation: Sendable {
	/// remove the session `tokenHash` names. idempotent: a hash the store no
	/// longer knows is not an error, because logging out twice is ordinary.
	func endSession(tokenHash: [UInt8]) async throws
}

// MARK: - IdentityDirectory

/// the roles a session's identity carries.
///
/// a session stores an `identityID`, not an `Identity`: the role set belongs to
/// the backend's directory and can change while a session lives. without this
/// lookup `AuthContext.identity` could never carry a role, and a catalog could
/// never guard one.
public protocol IdentityDirectory: Sendable {
	/// the identity `id` names, or `nil` when the directory has no such
	/// identity (deleted account, revoked membership).
	func identity(for id: String) async throws -> Identity?
}

/// a fixed directory — the shape a test and a small deployment use.
public struct DictionaryIdentityDirectory: IdentityDirectory {
	private let identities: [String: Identity]

	public init(_ identities: [Identity] = []) {
		var table: [String: Identity] = [:]
		for identity in identities {
			table[identity.id] = identity
		}
		self.identities = table
	}

	public func identity(for id: String) async throws -> Identity? {
		identities[id]
	}
}
