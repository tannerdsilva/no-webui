import Logging
import ServiceLifecycle
import WebUI
import WebUIServer
import WebUIAuth
import WebUIState
import Synchronization

// MARK: - the hosting service
//
// the composition point, as a `Service`. before this file, `WebUIHost` could
// answer http as a `Responder` and nothing could host it: the websocket
// upgrade, the accept loop and the process lifecycle belonged to `WebUIServer`,
// and the example carried 309 lines of transport to bridge the two. this is
// that bridge, and it owns nothing the server already owns — the server keeps
// its accept loop, the reaper keeps its clock, and this type says which of them
// runs and in what order.
//
// third law: the loop lives inside `run()`, cleanup is the last thing `run()`
// does, cancellation is the shutdown door, and there is no `shutdown()`, no
// `atexit`, no `DispatchMain`, and no unstructured task that outlives the run.
// the two children are ordinary `Service`s in one `ServiceGroup`; the group's
// own shutdown cascade is what stops them, and the final sweep is the three
// lines after it returns.
//
// what makes it a *product* rather than a pair of loops: the authorizer hands
// the server the session the cookie resolves to (so a page's socket and its
// page agree by construction), the observer keeps the store registry's
// liveness table honest, and the reaper drops an idle session's store once its
// last socket is gone.

// MARK: - the two server seams, answered by the host

/// answers the server's ``RequestAuthorizer`` from the host's resolver.
///
/// the server asks this about two requests: the page route (stamped onto
/// `HTTPRequest.principal`) and the websocket upgrade. both are bare requests
/// whose identity is in the headers — `routePage` never parses a cookie map —
/// so the answer comes from the resolver, which reads the `cookie` header. a
/// resolver that throws answers "no session" here: the server's seam is
/// non-throwing by design, and a store failure must not become a socket the
/// page cannot open.
public struct HostAuthorizer: RequestAuthorizer {
	private let resolver: any PrincipalResolver

	public init(resolver: any PrincipalResolver) {
		self.resolver = resolver
	}

	public func authorize(_ request: HTTPRequest) async -> SessionKey? {
		guard let principal = try? await resolver.principal(for: request) else { return nil }
		return SessionKey(hash: principal.session.tokenHash)
	}
}

/// keeps the store registry's liveness table in step with the sockets the
/// server opened and closed.
///
/// the registry's eviction rule is "a live session is never reaped", and only
/// the transport knows when a page is on screen. this is the one writer of that
/// fact: `markLive` before a frame is read, `markClosed` after the last one.
/// a reference type on purpose: the connection map must be one map, and a
/// struct copy would fork it — the copy would hold no tokens and a revocation
/// could never close a socket the original tracked.
public final class SessionLivenessObserver: SocketLifecycleObserver, Sendable {
	private let stores: SessionStores
	/// when present, every open socket is registered under its session so a
	/// revocation can close it now instead of waiting for its next frame.
	private let revocation: (any RevocationBus)?
	/// connection id → the token the bus owns, so close untracks exactly one.
	private let connections = Mutex<[UInt64: ConnectionToken]>([:])

	public init(stores: SessionStores, revocation: (any RevocationBus)? = nil) {
		self.stores = stores
		self.revocation = revocation
	}

	public func socketOpened(
		session: SessionKey,
		connection: UInt64,
		close: @escaping @Sendable () -> Void
	) async {
		stores.markLive(session)
		guard let revocation else { return }
		let token = ConnectionToken(id: connection, close: close)
		connections.withLock { $0[connection] = token }
		await revocation.track(token, session: session)
	}

	public func socketClosed(session: SessionKey, connection: UInt64) async {
		let token = connections.withLock { $0.removeValue(forKey: connection) }
		if let token { await revocation?.untrack(token) }
		stores.markClosed(session)
	}
}

// MARK: - AuthenticatedHostService

/// a hosted authenticated app: the server, the host's four ports and the
/// per-session state layer, started and stopped as one `Service`.
///
/// ```swift
/// let service = AuthenticatedHostService(
///     resolver: CookieSessionResolver(store: sessions),
///     routers: RouterTable(),
///     revocation: SocketRevocationBus(),
///     sessions: resolver,
///     config: WebUIServerConfig(port: 9091)
/// ) { pages in
///     [pages.page(Dashboard(), at: "/", title: "Member Dashboard")]
/// }
/// try await ServiceGroup(
///     services: [service],
///     gracefulShutdownSignals: [.sigterm, .sigint]
/// ).run()
/// ```
///
/// the page declarations are a closure over the session layer rather than a
/// list, because a page that renders a session's own store has to be built
/// *from* that layer — passing `[Page]` in would mean the caller had already
/// resolved the store it cannot yet see.
public struct AuthenticatedHostService: Service, Sendable {
	/// the composition the service runs: resolver, catalog, router table,
	/// revocation and the state layer.
	public let host: AuthenticatedHost

	/// the server. exposed so a host can read `connectedPages`, stop it
	/// directly, or hand it a route of its own — the service does not hide the
	/// transport it owns.
	public let server: WebUIServer

	/// the config the server was built with, authorizer and observer included.
	public let config: WebUIServerConfig

	/// how long one graceful shutdown may take before the group escalates to
	/// cancellation. a bound is a safety net, not a shutdown strategy: the
	/// server closes its listener and the reaper returns on its own.
	public let shutdownGrace: Duration

	private let logger: Logger

	/// build the whole product from its ports.
	///
	/// `routes` declares the pages: it receives the session layer and returns
	/// the catalog's declarations, so a page value never has to be built before
	/// the store it renders is reachable.
	///
	/// pass `requireRenderToken: true` in `config` for a multi-tenant
	/// deployment: a frame carrying a token this session never minted is then
	/// refused and its socket closed, instead of falling back to the shared
	/// default render session.
	public init(
		resolver: any PrincipalResolver,
		routers: any SessionRouterTable,
		revocation: any RevocationBus,
		sessions: any SessionRevocation,
		stores: SessionStores = SessionStores(),
		loginPath: String = "/login",
		cookieName: String = CookieSessionResolver.defaultCookieName,
		secureCookies: Bool = true,
		config: WebUIServerConfig = WebUIServerConfig(),
		shutdownGrace: Duration = .seconds(5),
		logger: Logger = Logger(label: "webui.host"),
		routes: @Sendable (SessionPages) -> [Page]
	) {
		let pages = SessionPages(
			stores: stores,
			// the caps the config names are the numbers the table enforces, so
			// the router the server dispatches through is built from them.
			events: EventRouter(maxHandlers: config.maxHandlers, maxSessions: config.maxSessions),
			routers: routers
		)
		let declarations = routes(pages)
		let catalog = AuthenticatedCatalog(pages: declarations, loginPath: loginPath, table: routers)
		let host = AuthenticatedHost(
			resolver: resolver,
			catalog: catalog,
			routers: routers,
			revocation: revocation,
			sessions: sessions,
			loginPath: loginPath,
			cookieName: cookieName,
			secureCookies: secureCookies,
			pages: pages
		)
		var serverConfig = config
		serverConfig.authorizer = HostAuthorizer(resolver: resolver)
		serverConfig.socketObserver = SessionLivenessObserver(stores: stores, revocation: revocation)
		self.init(
			host: host,
			server: WebUIServer(
				router: Self.routeTable(declarations, host: host),
				eventRouter: pages.events,
				config: serverConfig,
				logger: logger
			),
			config: serverConfig,
			shutdownGrace: shutdownGrace,
			logger: logger
		)
	}

	/// host a composition that was assembled elsewhere — the seam a test uses
	/// to inspect the ports the service runs, and a deployment uses when its
	/// catalog is not `AuthenticatedCatalog`.
	public init(
		host: AuthenticatedHost,
		server: WebUIServer,
		config: WebUIServerConfig = WebUIServerConfig(),
		shutdownGrace: Duration = .seconds(5),
		logger: Logger = Logger(label: "webui.host")
	) {
		self.host = host
		self.server = server
		self.config = config
		self.shutdownGrace = shutdownGrace
		self.logger = logger
	}

	// MARK: the route table

	/// one route per declared page, all of them answered by the host.
	///
	/// the table exists so the server's own router knows which paths are its
	/// business; the host re-decides, against the *same* path, who may see them.
	/// a path the table does not carry is the server's 404 before a principal is
	/// ever resolved — the cheapest refusal there is.
	private static func routeTable(_ declarations: [Page], host: AuthenticatedHost) -> Router {
		Router {
			for declaration in declarations {
				Route(method: .get, pattern: declaration.pattern, responder: host)
			}
		}
	}

	// MARK: run

	/// run the server and the reaper until the enclosing group shuts down.
	///
	/// the group handles both doors: the enclosing group's graceful shutdown
	/// cascades into this one (a nested `ServiceGroup` sees the parent's
	/// manager), and a cancelled run cancels the children. either way `run()`
	/// returns, and the sweep below is the cleanup the third law asks for.
	public func run() async throws {
		logger.info("webui host: starting")

		var configuration = ServiceGroupConfiguration(
			services: [
				WebUIServerService(server: server, logger: logger),
				IdleSessionReaper(stores: host.stores, routers: host.routers, logger: logger),
			],
			logger: logger
		)
		configuration.maximumGracefulShutdownDuration = shutdownGrace
		let group = ServiceGroup(configuration: configuration)

		var failure: (any Error)?
		do {
			try await group.run()
		} catch is CancellationError {
			// the enclosing group asked for exactly this: the listener is down
			// and the reaper has swept.
		} catch {
			failure = error
		}

		await endEverySession()
		if let failure { throw failure }
		logger.info("webui host: stopped")
	}

	/// the cleanup at the end of `run()`.
	///
	/// a stopped server leaves no socket, but the handler tables and the store
	/// registry outlive it as ordinary values: a control's closure holds its
	/// store's binding, and a process that keeps running would keep every
	/// session's state alive for nobody. one sweep ends both.
	private func endEverySession() async {
		for key in host.stores.sessions {
			await host.routers.drop(session: key)
			host.pages.forget(key)
			host.stores.remove(key)
		}
	}
}
