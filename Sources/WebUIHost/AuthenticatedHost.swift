import WebUI
import WebUIServer
import WebUIAuth

// MARK: - EventDispatch

/// what routing one websocket event answered.
///
/// `HandlerOutcome` alone cannot carry the in-place token refresh: the wire has
/// a `token` frame, the enum does not have a case for it, and adding one is
/// `WebUICore`'s decision, not the host's. so the host returns the outcome plus
/// the token the page should adopt, and the transport writes both.
public struct EventDispatch: Sendable {
	/// the handler's answer. `.fail(code: "token", …)` is a refusal — the frame
	/// resolved to no live render for this session, and the transport should
	/// close the socket rather than let a page retry forever.
	public let outcome: HandlerOutcome
	/// the token the page must adopt because its own was evicted from the live
	/// window. `nil` on an ordinary frame.
	public let refreshedToken: RenderKey?

	public init(outcome: HandlerOutcome, refreshedToken: RenderKey? = nil) {
		self.outcome = outcome
		self.refreshedToken = refreshedToken
	}

	/// the refusal code, matching the example's wire vocabulary so a client that
	/// already handles `token` errors needs no change.
	public static let tokenRefusalCode = "token"

	/// whether this dispatch was refused for want of a live render.
	public var isRefused: Bool {
		guard case .fail(let code, _, _) = outcome else { return false }
		return code == Self.tokenRefusalCode
	}
}

// MARK: - AuthenticatedHost

/// the composition point: resolver + catalog + router table + revocation.
///
/// it is a `struct` deliberately — **a value façade that owns nothing mutable
/// itself.** every piece of shared state it touches is a reference the caller
/// injected (`RouterTable`, `SocketRevocationBus`, the session store behind the
/// resolver), so copying a host cannot fork a session table, and a host can be
/// stored in a `Route` closure or handed to a `Service` without an identity of
/// its own.
///
/// it is also a `Responder`, so it drops straight into `Router`/`Route` — the
/// host is not a second routing layer, it is one responder that happens to
/// resolve identity first.
public struct AuthenticatedHost: Sendable, Responder {
	public let resolver: any PrincipalResolver
	public let catalog: any PageCatalog
	public let routers: any SessionRouterTable
	public let revocation: any RevocationBus
	/// the store half of revocation. separate from ``revocation`` because the
	/// bus closes sockets and this ends the session record; a logout must do
	/// both and neither can do the other's job.
	public let sessions: any SessionRevocation
	/// where a signed-out or unauthenticated visitor is sent.
	public let loginPath: String
	public let cookieName: String
	/// whether the session cookie carries `Secure`. `true` by default: a host
	/// that terminates tls in front of itself must pass `false` explicitly
	/// rather than get a cookie a browser silently refuses to store.
	public let secureCookies: Bool

	public init(
		resolver: any PrincipalResolver,
		catalog: any PageCatalog,
		routers: any SessionRouterTable,
		revocation: any RevocationBus,
		sessions: any SessionRevocation,
		loginPath: String = "/login",
		cookieName: String = CookieSessionResolver.defaultCookieName,
		secureCookies: Bool = true
	) {
		self.resolver = resolver
		self.catalog = catalog
		self.routers = routers
		self.revocation = revocation
		self.sessions = sessions
		self.loginPath = loginPath
		self.cookieName = cookieName
		self.secureCookies = secureCookies
	}

	// MARK: http

	public func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		if let principal = try await resolver.principal(for: request) {
			guard let responder = try await catalog.responder(
				for: request.path,
				principal: principal
			) else {
				return Self.notFound
			}
			return try await responder.respond(to: request)
		}

		// anonymous: the catalog decides what a request that resolved to nobody
		// gets — a public page, a 303 to `/login`, or nothing (→ 404). the host
		// does not guess, because only the catalog knows which paths exist.
		guard let responder = try await catalog.responder(for: request.path) else {
			return Self.notFound
		}
		return try await responder.respond(to: request)
	}

	/// the 404 an unknown path earns, authenticated or not. the same body the
	/// server's router uses, so a host route and a server route are
	/// indistinguishable to a client.
	public static var notFound: HTTPResponse {
		HTTPResponse(status: .notFound, body: .text("not found"))
	}

	// MARK: events

	/// route one event into the session that minted its token.
	///
	/// refusal is one shape and it names the token: a frame whose token this
	/// session never minted — a forgery, a page from before a restart, or any
	/// frame arriving after logout dropped the session's table entry — resolves
	/// to nothing and answers `.fail(code: "token", …)`. the transport closes
	/// the socket on that, which is why logout does not have to chase sockets
	/// twice.
	public func dispatch(
		_ event: EventData,
		session: SessionKey,
		renderToken: RenderKey
	) async -> EventDispatch {
		guard let resolved = await routers.router(for: session, renderToken: renderToken) else {
			return EventDispatch(
				outcome: .fail(
					code: EventDispatch.tokenRefusalCode,
					message: "no live render for this session"
				)
			)
		}
		let outcome = await resolved.router.dispatch(
			event,
			in: RenderSessionID(resolved.liveToken.value)
		)
		return EventDispatch(
			outcome: outcome,
			refreshedToken: resolved.needsRefresh ? resolved.liveToken : nil
		)
	}

	// MARK: logout

	/// the session cookie that plants `token` — the one thing a login route needs
	/// from the host besides the store.
	public func sessionCookie(token: [UInt8], maxAge: Int? = nil) -> SessionCookie {
		CookieSessionResolver.sessionCookie(
			name: cookieName,
			token: token,
			secure: secureCookies,
			maxAge: maxAge
		)
	}

	/// end `principal`'s session: sockets, handler table, then the store record.
	///
	/// the order is the guarantee. sockets first so nothing can dispatch once
	/// revocation starts; the router table second so the handlers those sockets
	/// would have reached are gone (a frame in flight resolves to nothing);
	/// the store last, because it is the record everyone else reads. reverse any
	/// two and there is a window where a live socket resolves against a session
	/// the store has already forgotten.
	public func signOut(_ principal: AuthContext) async throws -> HTTPResponse {
		let key = SessionKey(hash: principal.session.tokenHash)
		await revocation.revoke(session: key)
		await routers.drop(session: key)
		try await sessions.endSession(tokenHash: key.hash)
		return signedOutResponse()
	}

	/// sign out whatever session `request` presents. idempotent: a request with
	/// no live session still gets the redirect and the cleared cookie, so a
	/// double logout lands on `/login` instead of an error page.
	public func signOut(for request: HTTPRequest) async throws -> HTTPResponse {
		if let principal = try await resolver.principal(for: request) {
			return try await signOut(principal)
		}
		return signedOutResponse()
	}

	private func signedOutResponse() -> HTTPResponse {
		HTTPResponse(
			status: .redirect,
			cookies: [CookieSessionResolver.clearingCookie(name: cookieName, secure: secureCookies)],
			body: .redirect(to: loginPath)
		)
	}
}
