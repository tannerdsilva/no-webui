import Foundation
import Logging
import NIOPosix
import ServiceLifecycle
import WebUI
import WebUIDesignSystem
import WebUIAuth
import WebUIHost
import WebUIServer
import WebUIState

// MARK: - the login screen's layout
//
// the design sheet ships in every page and has no rule for `.login*`, so this
// screen scopes its own vocabulary. comment-free on purpose — these bytes ship.
let loginLayoutStyles = """
.login { display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: var(--space-4); }
.login__card { width: 100%; max-width: 24rem; background: var(--color-bg-raised); border: var(--border-width) solid var(--color-border); border-radius: var(--radius-card); box-shadow: var(--shadow-lg); padding: var(--space-8); }
.login__card h1 { margin-bottom: var(--space-6); }
.login__form { display: flex; flex-direction: column; gap: var(--space-4); }
.login__error { background: var(--color-danger-soft); border: var(--border-width) solid var(--color-danger); border-radius: var(--radius-md); padding: var(--space-3) var(--space-4); margin-bottom: var(--space-5); font-size: var(--font-size-sm); color: var(--color-danger); }
"""

/// the sign-in screen: public, anonymous, no runtime and no session — so it is a
/// pure function, not a `StatefulPage`. `SessionPages` has no door for a page no
/// principal reaches, which is the one screen an authenticated app always has.
func loginScreen(error: String?, csrfToken: String) -> String {
	let body = Div(class: "login") {
		Div(class: "login__card") {
			Heading("Sign in", level: .h1)
			if let error { Div(class: "login__error") { Text(error) } }
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
		// header-only and the server sends it.
		contentSecurityPolicy: "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; form-action 'self'; base-uri 'self'",
		rawStyles: [loginLayoutStyles]
	).markup.html
}

// MARK: - the dashboard

/// the demo's one authenticated screen: a pure function of the session's state.
/// a control mutates through `PageActions`, so a click ships the bytes the differ
/// produced and nothing an author wrote by hand.
struct Dashboard: StatefulPage {
	struct State: Sendable {
		var identity = ""
		var roles = ""
		/// the session's logout form token, minted once with the store, so a tab
		/// left open keeps a working sign-out button.
		var logoutToken = ""
		var count = 0
	}

	/// the handler a render outside a hosted pass gets: the same bytes, and
	/// nothing to route to.
	static let inert: EventHandler = { _ in [] }

	func initialState() -> State { State() }

	func body(_ state: State) -> some View {
		let actions = self.actions
		let bump = actions?.handler { $0.count += 1 } ?? Self.inert
		return Div(id: "app", class: "app") {
			Header(class: "app__header") {
				Heading("Member Dashboard", level: .h1)
				Div(class: "app__session") {
					Text("signed in as \(state.identity) · roles: \(state.roles)")
					// a native post form: no event handler, so the runtime does not
					// hijack the submit. the token is the session's.
					Form(action: "/logout", method: "post", class: "app__logout", csrfToken: state.logoutToken) {
						Button("sign out", class: "button button--ghost button--sm", type: .submit)
					}
				}
			}
			Main(class: "app__content") {
				WebUICard(elevation: .elevated) {
					Heading("Counter", level: .h3)
					// the value is the control, not beside it: a bound value outside
					// every `data-component-id` is residue, and the differ answers
					// that honestly with the whole page.
					Div(id: "counter-value", class: "counter-value") {
						Span { Text("\(state.count)") }
					}
					.onClick(id: "counter-value", perform: bump)
					Div(class: "app__actions") {
						WebUIButton("−1", appearance: .secondary, size: .sm, id: "btn-dec",
							onTap: actions?.handler { $0.count -= 1 } ?? Self.inert)
						WebUIButton("+1", appearance: .primary, size: .sm, id: "btn-inc",
							onTap: actions?.handler { $0.count += 1 } ?? Self.inert)
						WebUIButton("reset", appearance: .ghost, size: .sm, id: "btn-reset",
							onTap: actions?.handler { $0.count = 0 } ?? Self.inert)
					}
				}
			}
		}
	}
}

// MARK: - the app

/// the ceremony: a login form, a throttle and one argon2 verify. everything below
/// it — the accept loop, the websocket, the cookie, the router table, the
/// per-session stores, the idle reaper — is the framework's.
struct AuthDemo: Sendable {
	static let username = "admin"
	static let password = "password"
	/// the mint's throttle bucket. `HTTPRequest` carries no transport peer, so this
	/// app cannot key on the caller's address.
	static let bucket = "anonymous"

	let store: InMemoryAuthSessionStore
	let resolver: CookieSessionResolver
	let pages: SessionPages
	let host: AuthenticatedHost
	let secret: String
	let passwordRecord: PasswordRecord
	let pool: NIOThreadPool
	let limiter = AsyncSemaphore(permits: 4)
	/// a page's mint refreshes must not burn submit attempts, so the page and the
	/// submit keep separate budgets.
	let pageThrottle = LoginThrottle(windowSeconds: 60, maxAttempts: 60)
	let throttle = LoginThrottle(windowSeconds: 60, maxAttempts: 20)
	let tokens = SingleUseTokenStore()

	init(pool: NIOThreadPool) throws {
		let salt = try PasswordVerifier.makeSalt()
		let store = InMemoryAuthSessionStore()
		let resolver = CookieSessionResolver(store: store, identities: DictionaryIdentityDirectory([
			Identity(id: Self.username, roles: [Role.member, Role.admin])
		]))
		let table = RouterTable()
		// one router for the demo: the pages render into it and the server
		// dispatches through it, both taken from `pages.events`.
		let events = EventRouter()
		let pages = SessionPages(events: events, routers: table)
		// one bus for the demo: the host revokes with it and the observer
		// registers each socket with it, so a logout closes the live socket.
		let bus = SocketRevocationBus()
		let secret = try CSRFProtection.generateSecret()
		let hash = try PasswordVerifier.hash(
			password: [UInt8](Self.password.utf8), salt: salt, parameters: .interactive
		)
		self.store = store
		self.resolver = resolver
		self.pages = pages
		self.secret = secret
		self.pool = pool
		self.passwordRecord = PasswordRecord(salt: salt, hash: hash, parameters: .interactive)
		self.host = AuthenticatedHost(
			resolver: resolver,
			catalog: AuthenticatedCatalog(pages: [Self.dashboard(pages, secret: secret)], loginPath: "/login", table: table),
			routers: table,
			revocation: bus,
			sessions: resolver,
			secureCookies: false,
			pages: pages
		)
	}

	/// the dashboard's declaration. the framework seeds a session's store from
	/// `initialState()`, which cannot see the principal — so this seeds it from the
	/// request first, then lets the framework's own loop render it.
	static func dashboard(_ pages: SessionPages, secret: String) -> Page {
		Page(pattern: "/") { request in
			let principal = request.principal
			_ = try await pages.store(for: SessionKey(hash: principal.session.tokenHash)) {
				Dashboard.State(
					identity: principal.identity?.id ?? principal.session.identityID,
					roles: principal.identity?.roles.sorted().joined(separator: ", ") ?? "none",
					logoutToken: (try? CSRFProtection.token(for: "logout", secret: secret, maxAge: 8 * 3600)) ?? ""
				)
			}
			return try await pages.render(Dashboard(), for: request, document: document)
		}
	}

	/// the dashboard's document: the design sheet, and this pass's render token.
	static func document(_ body: String, _ token: RenderToken) -> String {
		WebUIDocument(title: "Member Dashboard", body: .trusted(body),
			runtimeConfig: RuntimeConfig(renderToken: token.value)).markup.html
	}

	/// this app's ceremony in front of the host's page.
	var routes: Router {
		Router {
			Route.get("/login") { request in await loginPage(request) }
			Route.post("/login") { request in await login(request) }
			Route.post("/logout") { request in await logout(request) }
			Route(method: .get, pattern: "/", responder: host)
		}
	}

	/// the composition, as one `Service`: the server, the host's four ports, the
	/// per-session state layer and the reaper.
	func run(port: Int, maxConnections: Int) async throws {
		var config = WebUIServerConfig(port: port, maxConnections: maxConnections, requireRenderToken: true)
		config.authorizer = HostAuthorizer(resolver: resolver)
		config.socketObserver = SessionLivenessObserver(stores: pages.stores, revocation: host.revocation)
		let service = AuthenticatedHostService(
			host: host,
			// the host's own event router: a page rendered into a fresh one ships
			// controls the server can never dispatch.
			server: WebUIServer(router: routes, eventRouter: pages.events, config: config),
			config: config
		)
		try await ServiceGroup(services: [service], gracefulShutdownSignals: [.sigterm, .sigint]).run()
	}
}

// MARK: - ceremony

extension AuthDemo {
	static var tooMany: HTTPResponse {
		HTTPResponse(status: 429, headers: ["Retry-After": "60"], body: .text("too many requests — try again later"))
	}

	/// a token's embedded expiry on the store's clock.
	static func expiry(_ token: String) -> TimeInterval {
		CSRFProtection.expiry(of: token).map { TimeInterval($0) } ?? 0
	}

	/// a fresh login-form token, or nil when os entropy fails.
	func mint() -> String? { try? CSRFProtection.token(for: "login", secret: secret) }

	/// GET /login: throttle the mint, reserve the single-use token under the
	/// caller's outstanding budget, then render the static page.
	func loginPage(_ request: HTTPRequest) async -> HTTPResponse {
		guard pageThrottle.record(Self.bucket), let token = mint() else { return Self.tooMany }
		guard await tokens.reserve(token, expiresAt: Self.expiry(token), key: Self.bucket) else { return Self.tooMany }
		return HTTPResponse(.trusted(loginScreen(error: nil, csrfToken: token)))
	}

	func login(_ request: HTTPRequest) async -> HTTPResponse {
		guard case .form(let fields) = request.body,
		      let csrf = fields["_csrf"],
		      CSRFProtection.validate(csrf, for: "login", secret: secret)
		else { return failure("invalid or expired form token — try again") }
		guard await tokens.consume(csrf, expiresAt: Self.expiry(csrf), key: Self.bucket) else {
			return failure("invalid or expired form token — try again")
		}
		let username = fields["username"] ?? ""
		let userKey = "user:\(username.lowercased())"
		guard throttle.record(userKey) else { return Self.tooMany }

		// constant-time username compare, then argon2 on the pool behind a global
		// permit cap: an unknown user burns the same verify, so "no such user"
		// costs what "wrong password" costs.
		let matches = constantTimeEquals([UInt8](username.utf8), [UInt8](Self.username.utf8))
		await limiter.wait()
		let valid = (try? await pool.runIfActive {
			try PasswordVerifier.verify(password: [UInt8](fields["password"]?.utf8 ?? "".utf8), record: passwordRecord)
		}) ?? false
		limiter.signal()
		guard matches, valid else { return failure("invalid credentials") }
		throttle.reset(userKey)

		guard let token = try? SessionToken.generate(),
		      let id = SecureRandom.bytes(16),
		      let seed = SecureRandom.bytes(16),
		      let hash = try? SessionToken.hash(token)
		else { return HTTPResponse(status: 500, body: .text("500 — entropy unavailable")) }
		try? await store.create(AuthenticatedSession(
			id: id, tokenHash: hash, identityID: Self.username, csrfSeed: seed,
			createdAt: Date(), expiresAt: Date().addingTimeInterval(8 * 3600), lastSeenAt: Date()
		))
		let cookie = CookieSessionResolver.sessionCookie(token: token, secure: false, maxAge: 8 * 3600)
		return HTTPResponse(status: .redirect, cookies: [cookie], body: .redirect(to: "/"))
	}

	/// the failure page's token is minted but not reserved: reserving it would spend
	/// the caller's outstanding budget on every wrong guess.
	func failure(_ message: String) -> HTTPResponse {
		guard let token = mint() else { return Self.tooMany }
		return HTTPResponse(.trusted(loginScreen(error: message, csrfToken: token)))
	}

	/// POST /logout: the form token, then the host's one-call teardown.
	func logout(_ request: HTTPRequest) async -> HTTPResponse {
		guard case .form(let fields) = request.body,
		      let csrf = fields["_csrf"],
		      CSRFProtection.validate(csrf, for: "logout", secret: secret)
		else { return HTTPResponse(status: 403, body: .text("invalid or expired form token")) }
		return (try? await host.signOut(for: request)) ?? Self.tooMany
	}
}

// MARK: - entry point

@main
struct WebUIAuthExample {
	static func main() async throws {
		let pool = NIOThreadPool(numberOfThreads: intFlag("--argon2-workers", fallback: 2))
		pool.start()
		let demo = try AuthDemo(pool: pool)
		try await demo.run(
			port: intFlag("--port", fallback: 9091),
			maxConnections: intFlag("--max-connections", fallback: 256)
		)
		pool.shutdownGracefully { _ in }
	}
}

func intFlag(_ name: String, fallback: Int) -> Int {
	guard let index = CommandLine.arguments.firstIndex(of: name),
	      index + 1 < CommandLine.arguments.count,
	      let value = Int(CommandLine.arguments[index + 1]), value > 0 else { return fallback }
	return value
}
