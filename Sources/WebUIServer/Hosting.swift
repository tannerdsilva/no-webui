import WebUI

// MARK: - Hosting seams
//
// the two things a host needs from the server that the server cannot decide for
// itself: which session a request belongs to, and when a page's socket opens or
// closes. both are protocols so the host is written against a contract rather
// than a concrete resolver, and so this target never learns what a session is
// made of — `SessionKey` is opaque bytes it only compares.
//
// they live in this target, not `WebUICore`, because `HTTPRequest` is declared
// here (`HTTP.swift`): the authorizer's whole vocabulary is a request and a
// session key, and `WebUICore` sits below this module — naming a request there
// would mean moving the request (and nio's head type) down into the core the
// client build also compiles. `SessionKey` is `WebUICore`'s (`Session.swift`)
// and reaches this file through `WebUI`'s re-export, which is the direction the
// dependency already points.
//
// neither protocol may mention `WebUIAuth`: this module cannot depend on it,
// and an authorizer that answered an `AuthContext` would drag the auth model
// into every host that only wants routing.

/// decides which session a request belongs to.
///
/// `nil` is "no session presented": the same answer an anonymous request gets.
/// the server accepts one through ``WebUIServerConfig/authorizer``; `nil` there
/// — the default — means no authorizer at all, and the server behaves exactly
/// as it did before this seam existed.
public protocol RequestAuthorizer: Sendable {
	/// the session `request` presents, or nil when it presents none.
	func authorize(_ request: HTTPRequest) async -> SessionKey?
}

/// told when a page's socket opens and closes.
///
/// the server owns the socket; the host owns liveness policy. this is the one
/// notification that lets a host keep its own liveness table honest without
/// this target importing a store layer it has no business knowing about.
///
/// the contract the server keeps: a socket that upgrades announces once on
/// open and once on close, in that order, on every exit path — and a connection
/// that fails before upgrading announces nothing at all. the session named is
/// the ``RequestAuthorizer``'s answer for the upgrade request, which is the
/// only identity a socket presents before its first frame.
public protocol SocketLifecycleObserver: Sendable {
	/// a socket for `session` is open.
	///
	/// `connection` is the server's own id for this socket, and `close` ends it
	/// from any task: it is idempotent, never blocks, and is the only handle a
	/// host gets on a transport it does not own. a host that revokes a session
	/// (logout, an expired token) closes this handle; without it, revocation can
	/// only refuse the socket's *next* frame, which leaves a logged-out browser
	/// holding a live connection until it happens to speak.
	func socketOpened(session: SessionKey, connection: UInt64, close: @escaping @Sendable () -> Void) async
	/// the socket the server named `connection` closed, on every exit path.
	func socketClosed(session: SessionKey, connection: UInt64) async
}
