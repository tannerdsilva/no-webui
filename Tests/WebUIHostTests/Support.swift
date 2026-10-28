import Foundation
import Synchronization
import Testing
import NIOHTTP1
import WebUI
import WebUIServer
import WebUIAuth
import WebUIHost
import WebUIState

// MARK: - fixtures
//
// shared by every suite in this target. the shape that matters: a *real*
// `InMemoryAuthSessionStore`, a *real* `SessionToken`, and a *real* cookie value
// — nothing here fakes the hash → store path, because a fixture that fakes it
// would let the resolver pass against a store that does not behave like one.

enum Fixture {
	static let cookieName = CookieSessionResolver.defaultCookieName

	/// one signed-in principal: the raw token, its stored session, and the
	/// cookie value a browser would carry.
	struct Login: Sendable {
		let token: [UInt8]
		let session: AuthenticatedSession
		/// the base64url form the cookie holds.
		let cookie: String

		var sessionKey: SessionKey { SessionKey(hash: session.tokenHash) }
	}

	/// create a live session in `store` and return everything a client would
	/// hold afterwards. `expiresAt` is injectable so the expiry path needs no
	/// sleep.
	static func logIn(
		store: InMemoryAuthSessionStore,
		identityID: String = "alice",
		expiresAt: Date = Date().addingTimeInterval(3600)
	) async throws -> Login {
		let token = try SessionToken.generate()
		let hash = try SessionToken.hash(token)
		let session = AuthenticatedSession(
			// unique per token: the first 16 bytes of a 32-byte digest.
			id: Array(hash.prefix(16)),
			tokenHash: hash,
			identityID: identityID,
			csrfSeed: Array(hash.suffix(16)),
			createdAt: Date(),
			expiresAt: expiresAt,
			lastSeenAt: Date()
		)
		try await store.create(session)
		return Login(token: token, session: session, cookie: Base64.encodeURL(token))
	}

	/// a request as a browser sends it: the parsed cookie map, or the raw header
	/// when `asHeader` is set (which is how the resolver's header fallback is
	/// exercised).
	static func request(
		_ path: String,
		cookie: String? = nil,
		asHeader: Bool = false,
		query: [String: String] = [:]
	) -> HTTPRequest {
		guard let cookie else {
			return HTTPRequest(method: .get, path: path, query: query)
		}
		if asHeader {
			var headers = HTTPHeaders()
			headers.add(name: "cookie", value: "\(cookieName)=\(cookie)")
			return HTTPRequest(method: .get, path: path, query: query, headers: headers)
		}
		return HTTPRequest(method: .get, path: path, query: query, cookies: [cookieName: cookie])
	}

	/// the identity directory a resolver reads roles out of.
	static func directory(_ identities: [(String, Set<String>)]) -> DictionaryIdentityDirectory {
		DictionaryIdentityDirectory(identities.map { Identity(id: $0.0, roles: $0.1) })
	}

	/// a page that renders one line of text and one clickable control, so a
	/// render has a handler to bind and a dispatch has something to reach.
	static func page(
		_ pattern: PathPattern,
		requiresRole: String? = nil,
		heading: @escaping @Sendable (AuthContext) -> String = { "page for \($0.session.identityID)" },
		handler: @escaping EventHandler = { _ in [] }
	) -> Page {
		Page(pattern: pattern, requiresRole: requiresRole) { request in
			// the router is named, never invented: a fresh one per render is
			// fine for a one-shot page (the catalog binds it under the render
			// token) and wrong for a stateful one, so the API no longer hides it.
			request.render(on: EventRouter()) {
				PageBody(
					heading: heading(request.principal),
					renderToken: request.renderToken.value,
					handler: handler
				)
			}
		}
	}
}

// MARK: - PageBody

/// one text node, one token echo, and one button. small on purpose: a page body
/// in these tests exists to prove the render → router → bind path, not to look
/// like an app. the token echo is what a client holds, so a test reads the token
/// off the html exactly as a browser would.
struct PageBody: View, Sendable {
	let heading: String
	let renderToken: String
	let handler: EventHandler

	func render(into buffer: inout HTMLBuffer) {
		buffer.beginElement("span")
		buffer.addAttributeValue("data-render-token", renderToken)
		buffer.endOpenTag()
		buffer.endElement()
		Text(heading).render(into: &buffer)
		Button("press", type: .button).onClick(perform: handler).render(into: &buffer)
	}
}

// MARK: - FixedResolver

/// a resolver that answers the same principal for every request — for suites
/// that are about what happens *after* identity is known.
struct FixedResolver: PrincipalResolver {
	let fixed: AuthContext?

	func principal(for request: HTTPRequest) async throws -> AuthContext? { fixed }
}

/// a resolver that always fails — the 500 path, not the anonymous one.
struct BrokenResolver: PrincipalResolver {
	struct Failure: Error {}

	func principal(for request: HTTPRequest) async throws -> AuthContext? {
		throw Failure()
	}
}

// MARK: - TestHost

/// the whole composition, wired the way an app wires it: a real store, a real
/// resolver, one router table, one revocation bus. suites that are about the
/// host take this and nothing else.
struct TestHost: Sendable {
	let store: InMemoryAuthSessionStore
	let resolver: CookieSessionResolver
	let table: RouterTable
	let bus: SocketRevocationBus
	let host: AuthenticatedHost

	init(
		pages: [Page],
		identities: DictionaryIdentityDirectory? = nil,
		loginPath: String = "/login",
		store: InMemoryAuthSessionStore = InMemoryAuthSessionStore(),
		table: RouterTable = RouterTable(),
		bus: SocketRevocationBus = SocketRevocationBus()
	) {
		let resolver = CookieSessionResolver(store: store, identities: identities)
		let catalog = AuthenticatedCatalog(pages: pages, loginPath: loginPath, table: table)
		self.store = store
		self.resolver = resolver
		self.table = table
		self.bus = bus
		self.host = AuthenticatedHost(
			resolver: resolver,
			catalog: catalog,
			routers: table,
			revocation: bus,
			sessions: resolver,
			loginPath: loginPath,
			secureCookies: false,
			// these fixtures render one-shot pages, so the page layer is a
			// plain one; a stateful app hands its own, built on the router the
			// server dispatches through.
			pages: SessionPages(stores: SessionStores(), events: EventRouter(), routers: table)
		)
	}

	func logIn(identityID: String = "alice", expiresAt: Date = Date().addingTimeInterval(3600)) async throws -> Fixture.Login {
		try await Fixture.logIn(store: store, identityID: identityID, expiresAt: expiresAt)
	}
}

// MARK: - response helpers

/// the body as text, whatever shape it holds. a redirect answers "" and its
/// target is read by `location(of:)`.
func bodyText(_ response: HTTPResponse) -> String {
	switch response.body {
	case .html(let markup): return markup.html
	case .text(let text): return text
	case .bytes(let bytes, _): return String(decoding: bytes, as: UTF8.self)
	case .empty: return ""
	case .redirect: return ""
	case .stream: return "<stream>"
	}
}

/// where a response sends the client: the explicit header if a caller set one,
/// otherwise the redirect body case (which the server turns into `Location`).
func location(of response: HTTPResponse) -> String? {
	if let header = response.headers["Location"] { return header }
	if case .redirect(let to, _) = response.body { return to }
	return nil
}

/// the render token a rendered page embedded, read the way a browser would.
func renderToken(in html: String) -> String? {
	let marker = "data-render-token=\""
	guard let start = html.range(of: marker) else { return nil }
	let rest = html[start.upperBound...]
	guard let end = rest.firstIndex(of: "\"") else { return nil }
	return String(rest[..<end])
}

// MARK: - RecordingResponder

/// a responder that records that it was reached and answers a fixed body. what
/// "the catalog chose this page" is asserted on.
final class RecordingResponder: Responder, Sendable {
	private let body: String
	private let counter = Mutex(0)

	init(_ body: String) { self.body = body }

	var calls: Int { counter.withLock { $0 } }

	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		counter.withLock { $0 += 1 }
		return HTTPResponse(.trusted(body))
	}
}
