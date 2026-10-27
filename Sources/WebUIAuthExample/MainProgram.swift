import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import WebUI
import WebUIDesignSystem
import WebUIAuth
import WebUIHost
import WebUIServer
import WebUIState

// MARK: - the authenticated page

/// the demo's only authenticated screen, as a pure function of its state. every
/// control is a mutation and nothing else: the body never authors a fragment,
/// never escapes a string, and never sees a request.
struct Dashboard: StatefulPage {
	struct State: Sendable {
		var identity = ""
		var roles = ""
		/// the session's csrf token for the logout form. a session-lifetime
		/// token, not a per-render one: validation is stateless hmac, so it
		/// survives every re-render of the page it was minted for.
		var logoutToken = ""
		var count = 0
		var progress = 0.25
	}

	func initialState() -> State { State() }

	func body(_ state: State) -> some View {
		let binding = self.binding
		return Div(id: "app", class: "app") {
			Header(class: "app__header") {
				Heading("Member Dashboard", level: .h1)
				Div(class: "app__session") {
					Text("signed in as \(state.identity) · roles: \(state.roles)")
					// a native post form: no event handler, so the runtime does
					// not hijack the submit; the token is the session's.
					Form(action: "/logout", method: "post", class: "app__logout", csrfToken: state.logoutToken) {
						Button("sign out", class: "button button--ghost button--sm", type: .submit)
					}
				}
			}
			Main(class: "app__content") {
				WebUICard(elevation: .elevated) {
					Heading("Counter", level: .h3)
					Div(id: "counter-value", class: "counter-value") {
						Span { Text("\(state.count)") }
					}
					Div(class: "app__actions") {
						WebUIButton("−", appearance: .secondary, size: .md, id: "btn-dec")
							.onClick(binding) { $0.mutate { state in state.count -= 1 } }
						WebUIButton("+", appearance: .primary, size: .md, id: "btn-inc")
							.onClick(binding) { $0.mutate { state in state.count += 1 } }
						WebUIButton("Reset", appearance: .ghost, size: .sm, id: "btn-reset")
							.onClick(binding) { $0.mutate { state in state.count = 0 } }
					}
				}
				WebUICard(elevation: .outlined) {
					Heading("Progress", level: .h3)
					Div(id: "progress-value") {
						WebUIProgress(value: state.progress, tone: .primary, showLabel: true, size: .md)
					}
					Div(class: "app__actions") {
						WebUIButton("−10%", appearance: .secondary, size: .sm, id: "btn-pdec")
							.onClick(binding) { $0.mutate { state in state.progress = max(0, state.progress - 0.1) } }
						WebUIButton("+10%", appearance: .primary, size: .sm, id: "btn-pinc")
							.onClick(binding) { $0.mutate { state in state.progress = min(1, state.progress + 0.1) } }
					}
				}
			}
		}
	}
}

// MARK: - the login page (public, static, no runtime)

// the page's own layout vocabulary. the design sheet ships in every page and
// deliberately has no rule for `.login*`, so it is scoped here. comment-free on
// purpose — these bytes ship verbatim.
let loginLayoutStyles = """
.login { display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: var(--space-4); }
.login__card { width: 100%; max-width: 24rem; background: var(--color-bg-raised); border: var(--border-width) solid var(--color-border); border-radius: var(--radius-card); box-shadow: var(--shadow-lg); padding: var(--space-8); }
.login__card h1 { margin-bottom: var(--space-6); }
.login__form { display: flex; flex-direction: column; gap: var(--space-4); }
.login__error { background: var(--color-danger-soft); border: var(--border-width) solid var(--color-danger); border-radius: var(--radius-md); padding: var(--space-3) var(--space-4); margin-bottom: var(--space-5); font-size: var(--font-size-sm); color: var(--color-danger); }
"""

func renderLoginPage(error: String?, csrfToken: String) -> String {
	let body = Div(class: "login") {
		Div(class: "login__card") {
			Heading("Sign in", level: .h1)
			if let error {
				Div(class: "login__error") { Text(error) }
			}
			Form(action: "/login", method: "post", class: "login__form", csrfToken: csrfToken) {
				Label("Username", for: "username")
				Input(id: "username", name: "username", placeholder: "admin", type: .text, required: true)
				Label("Password", for: "password")
				Input(id: "password", name: "password", placeholder: "password", type: .password, required: true)
				Button("Sign in", class: "button button--primary button--md", type: .submit)
			}
		}
	}
	return WebUIDocument(
		title: "Sign in",
		body: body.markup,
		includeRuntime: false,
		// form-action + base-uri are meta-valid; clickjacking control is
		// header-only and the transport sends it.
		contentSecurityPolicy: "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; form-action 'self'; base-uri 'self'",
		rawStyles: [loginLayoutStyles]
	).markup.html
}

// MARK: - per-session scope

enum DemoError: Error {
	case stateTypeConflict
	case renderBusy
	case refused
}

/// the per-session half of the app: one store per session, the table its
/// renders route through, and the secret a logout token is minted with. a
/// reference type because the registry and the table are shared state that
/// every render and every socket must see through the same identity.
final class SessionScope: Sendable {
	let stores = SessionStores()
	let table = RouterTable()
	let secret: String

	init(secret: String) {
		self.secret = secret
	}

	/// render the dashboard for `request`, binding this pass's router to the
	/// render token the catalog minted.
	func dashboard(_ request: PageRequest) async throws -> RenderedPage {
		let key = SessionKey(hash: request.principal.session.tokenHash)
		let resolution = stores.resolve(for: key) {
			Dashboard.State(
				identity: request.principal.identity?.id ?? request.principal.session.identityID,
				roles: request.principal.identity?.roles.sorted().joined(separator: ", ") ?? "none",
				logoutToken: (try? CSRFProtection.token(for: "logout", secret: secret)) ?? ""
			)
		}
		// a reaped store whose session still routes is a leak the registry
		// cannot see, so the caller ends each reaped session's handlers.
		for evicted in resolution.evicted {
			await table.drop(session: evicted)
		}
		guard let store = resolution.store else { throw DemoError.stateTypeConflict }
		// the logout token is minted with the store and lives 30 minutes
		// (CSRFProtection.defaultMaxAge), while a session lives eight hours.
		// refresh it on the first render that finds it stale, or the demo's
		// sign-out button dies an hour into a long tab.
		if let expires = CSRFProtection.expiry(of: store.read().logoutToken),
		   Date(timeIntervalSince1970: TimeInterval(expires)) < Date() {
			store.commit { state in
				state.logoutToken = (try? CSRFProtection.token(for: "logout", secret: secret)) ?? state.logoutToken
			}
		}
		let router = EventRouter()
		let loop = StatefulPageSession(Dashboard(), store: store)
		guard let patch = loop.patch(in: RenderContext(router: router, session: request.renderSession)) else {
			throw DemoError.renderBusy
		}
		let document = WebUIDocument(
			title: "Member Dashboard",
			body: .trusted(patch.html),
			runtimeConfig: RuntimeConfig(renderToken: request.renderToken.value)
		)
		return RenderedPage(html: document.markup, router: router, renderToken: request.renderToken)
	}

	/// re-render `key`'s page after a mutation, or nil when the store's revision
	/// did not move — a handler that changed nothing produces no patch.
	func patch(after before: UInt64, for key: SessionKey, renderToken: RenderKey) async -> String? {
		guard let store = stores.existing(for: key, as: Dashboard.State.self),
		      store.revision != before,
		      let resolved = await table.router(for: key, renderToken: renderToken) else {
			return nil
		}
		let loop = StatefulPageSession(Dashboard(), store: store)
		let context = RenderContext(router: resolved.router, session: RenderSessionID(resolved.liveToken.value))
		return loop.patch(in: context)?.html
	}
}

// MARK: - the app

/// the whole composition: the framework's resolver, catalogs, router table,
/// revocation bus and state stores, plus the routes this demo serves.
struct AuthDemo: Sendable {
	static let demoUsername = "admin"
	static let demoPassword = "password"
	static let maxBodyBytes = 16 * 1024

	let store: InMemoryAuthSessionStore
	let resolver: CookieSessionResolver
	let sessions: SessionScope
	let bus: SocketRevocationBus
	let host: AuthenticatedHost
	let passwordRecord: PasswordRecord
	let argonPool: NIOThreadPool
	let limiter = AsyncSemaphore(permits: 4)
	let throttle = LoginThrottle(windowSeconds: 60, maxAttempts: 20)
	/// the mint page has its own, more generous budget: refreshing the login
	/// page must not burn a submit attempt.
	let pageThrottle = LoginThrottle(windowSeconds: 60, maxAttempts: 60)
	let tokens = SingleUseTokenStore()
	let gate: ConnectionGate

	init(gate: ConnectionGate, argonPool: NIOThreadPool) throws {
		let store = InMemoryAuthSessionStore()
		let sessions = SessionScope(secret: try CSRFProtection.generateSecret())
		let resolver = CookieSessionResolver(
			store: store,
			identities: DictionaryIdentityDirectory([
				Identity(id: Self.demoUsername, roles: [Role.member, Role.admin])
			])
		)
		let bus = SocketRevocationBus()
		let catalog = AuthenticatedCatalog(
			pages: [Page(pattern: "/", render: sessions.dashboard)],
			loginPath: "/login",
			table: sessions.table
		)
		let salt = try PasswordVerifier.makeSalt()
		self.store = store
		self.resolver = resolver
		self.sessions = sessions
		self.bus = bus
		self.passwordRecord = PasswordRecord(
			salt: salt,
			hash: try PasswordVerifier.hash(password: [UInt8](Self.demoPassword.utf8), salt: salt, parameters: .interactive),
			parameters: .interactive
		)
		self.argonPool = argonPool
		self.gate = gate
		self.host = AuthenticatedHost(
			resolver: resolver,
			catalog: catalog,
			routers: sessions.table,
			revocation: bus,
			sessions: resolver,
			loginPath: "/login",
			secureCookies: false
		)
	}

	/// the route table. a computed value because every closure names `self`, and
	/// a stored one could not be built before the rest of the demo exists.
	var router: Router {
		Router {
			Route.get("/login") { request in await self.loginPage(request) }
			Route.post("/login") { request in await self.login(request) }
			Route.post("/logout") { request in await self.logout(request) }
			Route.get("/") { request in await self.page(request) }
		}
	}

	/// the framework's own assets. a host that owns its listener serves these
	/// itself; `WebUIServer` serves them for a host that does not.
	static func asset(_ path: String) -> HTTPResponse? {
		guard path.hasPrefix("/__assets/css") || path.hasPrefix("/ui/webui-") else { return nil }
		let (body, type): (String, String) = path.contains("engine")
			? (WebUIAssets.engine, "text/javascript; charset=utf-8")
			: path.contains("shell")
				? (WebUIAssets.shell, "text/javascript; charset=utf-8")
				: (DesignSystemAssets.minifiedCss, "text/css; charset=utf-8")
		return HTTPResponse(
			status: .ok,
			headers: ["Content-Type": type, "Cache-Control": "public, max-age=3600"],
			body: .bytes(Array(body.utf8), contentType: type)
		)
	}

	func page(_ request: HTTPRequest) async -> HTTPResponse {
		do {
			return try await host.respond(to: request)
		} catch {
			return HTTPResponse(status: 500, body: .text("500 — the page failed to render: \(error)"))
		}
	}
}

// MARK: - ceremony

extension AuthDemo {
	static var tooMany: HTTPResponse {
		HTTPResponse(
			status: 429,
			headers: ["Retry-After": "60"],
			body: .text("too many requests — try again later")
		)
	}

	/// the caller's throttle key. the transport overwrites `X-WebUI-Peer` from
	/// the socket's remote address, so a client cannot choose its own bucket.
	static func peer(_ request: HTTPRequest) -> String {
		"ip:\(request.headers.first(name: "X-WebUI-Peer") ?? "unknown")"
	}

	func mint() -> (token: String, expiresAt: TimeInterval)? {
		guard let token = try? CSRFProtection.token(for: "login", secret: sessions.secret) else { return nil }
		return (token, CSRFProtection.expiry(of: token).map { TimeInterval($0) } ?? Date().timeIntervalSince1970)
	}

	/// the failure page's token is minted but not reserved: reserving it would
	/// spend the caller's outstanding budget on every wrong guess, and a
	/// submitter may legitimately carry it straight back.
	func failure(_ message: String) -> HTTPResponse {
		guard let minted = mint() else { return Self.tooMany }
		return HTTPResponse(.trusted(renderLoginPage(error: message, csrfToken: minted.token)))
	}

	/// GET /login: throttle the mint, reserve the single-use token under the
	/// caller's outstanding budget, then render the static page.
	func loginPage(_ request: HTTPRequest) async -> HTTPResponse {
		let peer = Self.peer(request)
		guard pageThrottle.record(peer) else { return Self.tooMany }
		guard let minted = mint() else { return HTTPResponse(status: 500, body: .text("500 — entropy unavailable")) }
		guard await tokens.reserve(minted.token, expiresAt: minted.expiresAt, key: peer) else { return Self.tooMany }
		return HTTPResponse(.trusted(renderLoginPage(error: nil, csrfToken: minted.token)))
	}

	func login(_ request: HTTPRequest) async -> HTTPResponse {
		guard case .form(let fields) = request.body,
		      let csrf = fields["_csrf"],
		      CSRFProtection.validate(csrf, for: "login", secret: sessions.secret) else {
			return failure("invalid or expired form token — try again")
		}
		let peer = Self.peer(request)
		let expiresAt = CSRFProtection.expiry(of: csrf).map { TimeInterval($0) } ?? Date().timeIntervalSince1970
		guard await tokens.consume(csrf, expiresAt: expiresAt, key: peer) else {
			return failure("invalid or expired form token — try again")
		}
		let username = fields["username"] ?? ""
		let userKey = "user:\(username.lowercased())"
		guard throttle.record(peer), throttle.record(userKey) else { return Self.tooMany }

		// constant-time username compare, then argon2 on the pool behind a
		// global permit cap. an unknown user burns the same verify so the
		// timing of "no such user" equals "wrong password".
		let matches = constantTimeEquals([UInt8](username.utf8), [UInt8](Self.demoUsername.utf8))
		await limiter.wait()
		let valid = (try? await argonPool.runIfActive {
			try PasswordVerifier.verify(password: [UInt8](fields["password"]?.utf8 ?? "".utf8), record: passwordRecord)
		}) ?? false
		limiter.signal()
		guard matches, valid else { return failure("invalid credentials") }
		throttle.reset(userKey)

		guard let token = try? SessionToken.generate(),
		      let sessionID = SecureRandom.bytes(16),
		      let seed = SecureRandom.bytes(16),
		      let hash = try? SessionToken.hash(token) else {
			return HTTPResponse(status: 500, body: .text("500 — entropy unavailable"))
		}
		try? await store.create(AuthenticatedSession(
			id: sessionID,
			tokenHash: hash,
			identityID: Self.demoUsername,
			csrfSeed: seed,
			createdAt: Date(),
			expiresAt: Date().addingTimeInterval(8 * 60 * 60),
			lastSeenAt: Date()
		))
		return HTTPResponse(
			status: .redirect,
			cookies: [host.sessionCookie(token: token, maxAge: 8 * 60 * 60)],
			body: .redirect(to: "/")
		)
	}

	/// POST /logout: the form token, then the host's one-call teardown
	/// (sockets, handler table, store record) and a cleared cookie.
	func logout(_ request: HTTPRequest) async -> HTTPResponse {
		guard case .form(let fields) = request.body,
		      let csrf = fields["_csrf"],
		      CSRFProtection.validate(csrf, for: "logout", secret: sessions.secret) else {
			return HTTPResponse(status: 403, body: .text("invalid or expired form token"))
		}
		return (try? await host.signOut(for: request)) ?? Self.tooMany
	}

	/// bounded housekeeping: expired sessions lose their store, their router
	/// entries, and their throttle bookkeeping.
	func sweep() async {
		let now = Date()
		_ = (try? await store.purgeExpired(before: now)) ?? 0
		throttle.prune(before: now)
		pageThrottle.prune(before: now)
		await tokens.prune(now: now.timeIntervalSince1970)
		for key in sessions.table.liveSessions() {
			if (try? await store.find(tokenHash: key.hash)) == nil {
				await sessions.table.drop(session: key)
				sessions.stores.remove(key)
			}
		}
	}
}

// MARK: - transport

/// the listener. it exists because `WebUIHost` has no server binding: the host
/// answers http as a `Responder`, but the websocket upgrade and the loop that
/// calls `dispatch` belong to `WebUIServer`, with no seam to hand either to a
/// host. everything below is that missing seam and nothing else.
struct Transport: Sendable {
	enum Negotiation: Sendable {
		case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>, key: SessionKey?)
		case http(NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>)
	}

	let demo: AuthDemo
	let log = Logger(label: "webui.auth.example")

	func run(port: Int) async throws {
		let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
		do {
			let channel = try await bind(group: group, port: port)
			log.info("auth demo on http://localhost:\(port) (ws://localhost:\(port)/ws)")
			try await withThrowingDiscardingTaskGroup { tasks in
				tasks.addTask {
					while !Task.isCancelled {
						try? await Task.sleep(for: .seconds(60))
						await demo.sweep()
					}
				}
				try await channel.executeThenClose { inbound in
					for try await negotiation in inbound {
						tasks.addTask { await self.handle(negotiation) }
					}
				}
			}
			try await group.shutdownGracefully()
		} catch {
			try? await group.shutdownGracefully()
			throw error
		}
	}

	private func bind(group: EventLoopGroup, port: Int) async throws -> NIOAsyncChannel<EventLoopFuture<Negotiation>, Never> {
		let bootstrap = ServerBootstrap(group: group)
			.serverChannelOption(ChannelOptions.backlog, value: 128)
			.serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
			.childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
		return try await bootstrap.bind(host: "0.0.0.0", port: port) { channel in
			channel.eventLoop.makeCompletedFuture {
				guard demo.gate.tryAcquire() else {
					channel.close(promise: nil)
					return channel.eventLoop.makeFailedFuture(DemoError.refused)
				}
				try channel.pipeline.syncOperations.addHandler(GateRelease(gate: demo.gate))
				let upgrader = NIOTypedWebSocketServerUpgrader<Negotiation>(
					shouldUpgrade: { channel, head in authorize(channel, head) },
					upgradePipelineHandler: { channel, head in
						channel.eventLoop.makeCompletedFuture {
							.websocket(try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(wrappingChannelSynchronously: channel), key: sessionKey(head))
						}
					}
				)
				let configuration = NIOTypedHTTPServerUpgradeConfiguration(
					upgraders: [upgrader],
					notUpgradingCompletionHandler: { channel in
						channel.eventLoop.makeCompletedFuture {
							.http(try NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>(wrappingChannelSynchronously: channel))
						}
					}
				)
				return try channel.pipeline.syncOperations.configureUpgradableHTTPServerPipeline(
					configuration: NIOUpgradableHTTPServerPipelineConfiguration(upgradeConfiguration: configuration)
				)
			}
		}
	}

	private func handle(_ negotiation: EventLoopFuture<Negotiation>) async {
		do {
			switch try await negotiation.get() {
			case .websocket(let channel, let key): try await webSocket(channel, key: key)
			case .http(let channel): try await http(channel)
			}
		} catch {}
	}

	// MARK: http

	private func http(_ channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>) async throws {
		let peer = channel.channel.remoteAddress?.ipAddress ?? "unknown"
		try await channel.executeThenClose { inbound, outbound in
			var head: HTTPRequestHead?
			var body: [UInt8] = []
			for try await part in inbound {
				switch part {
				case .head(let value): head = value
				case .body(let buffer):
					body.append(contentsOf: buffer.readableBytesView)
					// the cap is enforced while reading, not after: a client
					// that streams gigabytes is cut off at the limit.
					if body.count > AuthDemo.maxBodyBytes {
						try await write(
							HTTPResponse(status: 413, body: .text("413 — request body too large")),
							to: outbound
						)
						return
					}
				case .end:
					guard let head else { return }
					try await write(await answer(head, body: body, peer: peer), to: outbound)
					return
				}
			}
		}
	}

	private func answer(_ head: HTTPRequestHead, body: [UInt8], peer: String) async -> HTTPResponse {
		guard body.count <= AuthDemo.maxBodyBytes else {
			return HTTPResponse(status: 413, body: .text("413 — request body too large"))
		}
		guard let method = HTTPMethod(rawValue: head.method.rawValue.lowercased()) else {
			return HTTPResponse(status: 405, body: .text("405 — unsupported method"))
		}
		let path = String(head.uri.prefix(while: { $0 != "?" }))
		if let asset = AuthDemo.asset(path) { return asset }
		var headers = head.headers
		// the transport owns the peer key: a client-supplied value is replaced.
		headers.replaceOrAdd(name: "X-WebUI-Peer", value: peer)
		var request = HTTPRequest(
			method: method,
			path: path,
			headers: headers
		)
		if !body.isEmpty {
			let type = head.headers.first(name: "Content-Type") ?? ""
			request.body = type.hasPrefix("application/x-www-form-urlencoded")
				? .form(BodyReader(maxBodyBytes: AuthDemo.maxBodyBytes, maxMultipartParts: 8).urlencoded(body))
				: .bytes(body)
		}
		do {
			return try await demo.router.respond(to: request)
		} catch {
			return HTTPResponse(status: 500, body: .text("500 — the page failed to render: \(error)"))
		}
	}

	private func write(_ response: HTTPResponse, to outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>) async throws {
		var head = HTTPResponseHead(version: .http1_1, status: HTTPResponseStatus(statusCode: response.status.code))
		var body = ByteBuffer()
		switch response.body {
		case .html(let markup):
			head.headers.replaceOrAdd(name: "Content-Type", value: "text/html; charset=utf-8")
			body.writeString(markup.html)
		case .text(let text):
			head.headers.replaceOrAdd(name: "Content-Type", value: "text/plain; charset=utf-8")
			body.writeString(text)
		case .bytes(let bytes, let contentType):
			head.headers.replaceOrAdd(name: "Content-Type", value: contentType)
			body.writeBytes(bytes)
		case .redirect(let target, let status):
			head = HTTPResponseHead(version: .http1_1, status: HTTPResponseStatus(statusCode: status.code))
			head.headers.replaceOrAdd(name: "Location", value: target)
		case .empty, .stream:
			break
		}
		// the security block every response carries: no-store keeps an
		// authenticated page out of any cache, the rest are the auth-page
		// headers a browser is entitled to.
		head.headers.replaceOrAdd(name: "Content-Length", value: "\(body.readableBytes)")
		head.headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
		head.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
		head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
		for (name, value) in response.headers {
			head.headers.replaceOrAdd(name: name, value: value)
		}
		for cookie in response.cookies {
			if let header = try? cookie.setCookieHeaderValue() {
				head.headers.add(name: "Set-Cookie", value: header)
			}
		}
		try await outbound.write(.head(head))
		try await outbound.write(.body(.byteBuffer(body)))
		try await outbound.write(.end(nil))
	}

	// MARK: websocket

	/// a session cookie must resolve before the 101 is sent, and the origin
	/// must be the host's own: a same-site sibling could otherwise drive this
	/// session's socket.
	private func authorize(_ channel: Channel, _ head: HTTPRequestHead) -> EventLoopFuture<HTTPHeaders?> {
		guard head.method == .GET, head.uri == "/ws", originMatches(head) else {
			return refuse(channel)
		}
		return channel.eventLoop.makeFutureWithTask {
			let request = HTTPRequest(method: .get, path: "/ws", headers: head.headers)
			return (try? await demo.resolver.principal(for: request)) != nil
		}.flatMap { valid in
			valid ? channel.eventLoop.makeSucceededFuture(HTTPHeaders()) : refuse(channel)
		}
	}

	private func refuse(_ channel: Channel) -> EventLoopFuture<HTTPHeaders?> {
		var head = HTTPResponseHead(version: .http1_1, status: .forbidden)
		head.headers.replaceOrAdd(name: "Content-Length", value: "0")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		_ = channel.write(HTTPServerResponsePart.head(head))
		_ = channel.write(HTTPServerResponsePart.body(.byteBuffer(ByteBuffer())))
		return channel.writeAndFlush(HTTPServerResponsePart.end(nil)).map { nil }
	}

	private func originMatches(_ head: HTTPRequestHead) -> Bool {
		guard let origin = head.headers.first(name: "origin"),
		      let host = head.headers.first(name: "host")?.lowercased(),
		      let url = URL(string: origin) else { return false }
		var authority = (url.host ?? "").lowercased()
		if let port = url.port { authority += ":\(port)" }
		return authority == host
	}

	private func sessionKey(_ head: HTTPRequestHead) -> SessionKey? {
		guard let cookie = head.headers.first(name: "cookie"),
		      let value = WebUISharedCore.CookieParser.requestCookies(cookie)[demo.resolver.cookieName],
		      let token = Base64.decodeURL(value),
		      let hash = try? SessionToken.hash(token) else { return nil }
		return SessionKey(hash: hash)
	}

	private func webSocket(_ channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>, key: SessionKey?) async throws {
		guard let key else { return }
		let connection = ConnectionToken.next { _ = channel.channel.close(promise: nil) }
		await demo.bus.track(connection, session: key)
		demo.sessions.stores.markLive(key)
		do {
			try await channel.executeThenClose { inbound, outbound in
				for try await frame in inbound {
					switch frame.opcode {
					case .text: await event(String(buffer: frame.unmaskedData), key: key, outbound: outbound)
					case .ping: try await send(.pong, outbound)
					case .connectionClose: try await sendClose(outbound); return
					default: break
					}
				}
			}
		} catch {}
		await demo.bus.untrack(connection)
		demo.sessions.stores.markClosed(key)
	}

	private func event(_ text: String, key: SessionKey, outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async {
		do {
			switch try WSIncoming(jsonText: text) {
			case .event(let component, let name, let data, let token):
				guard let token, !token.isEmpty else { return try await reject(outbound) }
				let renderKey = RenderKey(value: token)
				let before = demo.sessions.stores.existing(for: key, as: Dashboard.State.self)?.revision ?? 0
				let dispatched = await demo.host.dispatch(
					EventData(component: ComponentID(component), event: name, data: data),
					session: key,
					renderToken: renderKey
				)
				if let refreshed = dispatched.refreshedToken {
					try await send(.token(refreshed.value), outbound)
				}
				if dispatched.isRefused { return try await reject(outbound) }
				if case .redirect(let url, let replace) = dispatched.outcome {
					try await send(.redirect(url: url, replace: replace), outbound)
					return try await sendClose(outbound)
				}
				// the dispatch committed a mutation: re-render the page it now
				// describes and ship the bytes. one commit, one patch.
				if let html = await demo.sessions.patch(after: before, for: key, renderToken: renderKey) {
					try await send(.update(fragments: [FragmentUpdate(id: "app", html: html)]), outbound)
				}
			case .ping:
				try await send(.pong, outbound)
			case .navigate:
				break
			}
		} catch {
			try? await send(.error(code: "decode", message: "bad event: \(error)"), outbound)
		}
	}

	private func reject(_ outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async throws {
		try await send(.redirect(url: "/login", replace: true), outbound)
		try await sendClose(outbound)
	}

	private func send(_ message: WSOutgoing, _ outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async throws {
		try await outbound.write(WebSocketFrame(fin: true, opcode: .text, data: ByteBuffer(bytes: message.jsonBytes)))
	}

	private func sendClose(_ outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async throws {
		var buffer = ByteBuffer()
		buffer.writeInteger(UInt16(1000))
		try await outbound.write(WebSocketFrame(fin: true, opcode: .connectionClose, data: buffer))
	}
}

/// release an admitted connection's slot when it closes.
final class GateRelease: ChannelInboundHandler {
	typealias InboundIn = IOData
	let gate: ConnectionGate
	init(gate: ConnectionGate) { self.gate = gate }
	func channelInactive(context: ChannelHandlerContext) {
		gate.release()
		context.fireChannelInactive()
	}
}

// MARK: - entry point

@main
struct WebUIAuthExample {
	static func main() async throws {
		let port = intFlag("--port", fallback: 9091)
		let pool = NIOThreadPool(numberOfThreads: intFlag("--argon2-workers", fallback: 2))
		pool.start()
		let demo = try AuthDemo(
			gate: ConnectionGate(maximum: intFlag("--max-connections", fallback: 256)),
			argonPool: pool
		)
		DesignSystemAssets.prewarm()
		try await Transport(demo: demo).run(port: port)
		pool.shutdownGracefully { _ in }
	}
}

func intFlag(_ name: String, fallback: Int) -> Int {
	guard let index = CommandLine.arguments.firstIndex(of: name),
	      index + 1 < CommandLine.arguments.count,
	      let value = Int(CommandLine.arguments[index + 1]), value > 0 else { return fallback }
	return value
}
