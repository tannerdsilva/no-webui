import Foundation
import Logging
import Testing
import WebUI
import WebUIState
import WebUIServer
import WebUIAuth
import WebUIHost

// MARK: - the acceptance app
//
// one authenticated, stateful page: a counter whose value lives *inside* the
// element that carries the routing attributes, and a long static listing beside
// it. that shape is the point (N05/N06): the differ patches elements carrying
// `data-component-id`, and a bound value outside one moves `residue` and
// correctly forces a full page. a heading showing `state.count` would make the
// byte gate fail for an honest reason — so the state lives in a control.
//
// the listing is not decoration: a real page carries content, and a ratio
// measured against three hundred bytes proves nothing about a page a person
// would load.

struct MemberDashboard: StatefulPage {
	struct State: Sendable {
		var count = 0
	}

	/// how many static rows the page carries. enough that the document is a
	/// page rather than a stub, so "less than 2 % of the page's bytes" is a
	/// claim about a page.
	static let rowCount = 220

	/// the handler a render outside a hosted pass gets: the control still
	/// mints the same bytes (so a standalone render is identical), it just has
	/// nothing to route to.
	static let inert: EventHandler = { _ in [] }

	func initialState() -> State { State() }

	func body(_ state: State) -> some View {
		let actions = self.actions
		return Div(class: "app") {
			Heading("Member Dashboard", level: .h1)
			Div(id: "counter-value", class: "counter") {
				Span { Text("\(state.count)") }
			}
			.onClick(id: "counter-value", perform: actions?.handler { $0.count += 1 } ?? Self.inert)
			Div(class: "records") {
				for index in 0 ..< Self.rowCount {
					Div(class: "record") {
						Span { Text("record \(index)") }
						Span(class: "record__note") { Text("unchanged between renders") }
					}
				}
			}
		}
	}
}

// MARK: - the fixture
//
// the whole product, wired the way a deployment wires it: a real session store,
// the framework's resolver, one router table, one revocation bus, and the
// service that hosts all of them. a suite that asserts on a hosted page takes
// this and nothing else.

struct HostedFixture: Sendable {
	let service: AuthenticatedHostService
	let store: InMemoryAuthSessionStore
	let table: RouterTable
	let bus: SocketRevocationBus
	let login: Fixture.Login
	let port: Int

	var host: AuthenticatedHost { service.host }

	var cookie: String { login.cookie }

	/// build the product on a free port, with one signed-in session already in
	/// the store.
	///
	/// `requireRenderToken` is on by default: a frame must carry a token this
	/// session minted, which is what makes a post-logout frame a refusal rather
	/// than a silently unhandled event.
	static func make(
		portBase: Int = 52_000,
		requireRenderToken: Bool = true,
		maxStores: Int = 1_024,
		identities: DictionaryIdentityDirectory? = nil
	) async throws -> HostedFixture {
		let port = try await hostFreePort(base: portBase)
		let store = InMemoryAuthSessionStore()
		let table = RouterTable()
		let bus = SocketRevocationBus()
		let resolver = CookieSessionResolver(store: store, identities: identities)
		let login = try await Fixture.logIn(store: store, identityID: "alice")

		let service = AuthenticatedHostService(
			resolver: resolver,
			routers: table,
			revocation: bus,
			sessions: resolver,
			stores: SessionStores(maxSessions: maxStores),
			loginPath: "/login",
			secureCookies: false,
			config: WebUIServerConfig(
				host: "127.0.0.1",
				port: port,
				requireRenderToken: requireRenderToken
			),
			logger: hostedTestLogger
		) { pages in
			[pages.page(MemberDashboard(), at: "/", title: "Member Dashboard")]
		}

		return HostedFixture(
			service: service,
			store: store,
			table: table,
			bus: bus,
			login: login,
			port: port
		)
	}

	/// start the service on a task and wait until the listener answers.
	func start() async throws -> Task<Void, any Error> {
		let service = self.service
		let port = self.port
		let task = Task { try await service.run() }
		try await hostWaitForListening(port: port, cookie: cookie)
		return task
	}

	/// stop it and prove the listener is gone.
	func stop(_ task: Task<Void, any Error>) async throws {
		task.cancel()
		try await hostRun(bounded: .seconds(10), "the hosting service to stop") {
			try await task.value
		}
		try await hostAssertClosed(port: port)
	}

	/// one authenticated GET of the page.
	func page() async throws -> (body: String, status: Int, location: String?) {
		try await hostGet("/", port: port, cookie: cookie)
	}

	/// the render token this session's live window holds — what a client reads
	/// off the page it was served.
	func renderToken() async throws -> String {
		guard let token = table.renderTokens(for: login.sessionKey).last else {
			throw HostLabError.wire("the session holds no bound render")
		}
		return token.value
	}
}

/// the suite's logger: a service that logs every start and stop into the gate's
/// output is noise, and a gate nobody reads is a gate nobody trusts.
let hostedTestLogger = Logger(label: "test.host") { _ in SwiftLogNoOpLogHandler() }
