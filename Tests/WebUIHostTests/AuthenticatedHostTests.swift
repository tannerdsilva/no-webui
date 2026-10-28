import Foundation
import Testing
import NIOCore
import NIOEmbedded
import WebUI
import WebUIServer
import WebUIAuth
import WebUIHost
import WebUIState

// MARK: - C5 gate: the facade, end to end
//
// the gate, verbatim: "the full flow end to end over a real embedded channel".
// the channel here is a real `EmbeddedChannel` carrying nio's real http codecs,
// so a request enters as wire bytes and a response leaves as wire bytes — status
// line, headers and body. the flow driven over it is the whole ceremony: an
// anonymous visitor is redirected, a signed-in one gets their own page, the
// page's control is dispatched into the session that minted it, logout ends the
// session on every side, and the old cookie is worth nothing afterwards.

@Suite("authenticated host")
struct AuthenticatedHostTests {

	@Test("the full flow runs over one embedded channel")
	func fullFlowOverEmbeddedChannel() async throws {
		let fixture = TestHost(pages: [Fixture.page("/dashboard")])
		let login = try await fixture.logIn(identityID: "alice")
		let lab = HTTPLab()
		defer { lab.finish() }

		// 1. anonymous: a 303 on the wire, `Location: /login`
		let anonymous = try await lab.exchange("/dashboard", through: fixture.host)
		#expect(anonymous.status == 303)
		#expect(anonymous.header("Location") == "/login")

		// 2. signed in: the page, with the token its render minted
		let page = try await lab.exchange("/dashboard", cookie: login.cookie, through: fixture.host)
		#expect(page.status == 200)
		#expect(page.body.contains("page for alice"))
		let token = try #require(renderToken(in: page.body))

		// ... and that token routes a frame into this session's handlers
		let dispatch = await fixture.host.dispatch(
			click(),
			session: login.sessionKey,
			renderToken: RenderKey(value: token)
		)
		#expect(!dispatch.isRefused)

		// 3. logout: 303, and the cookie is cleared on the wire
		let out = try await lab.exchange("/logout", cookie: login.cookie, through: SignOutRoute(host: fixture.host))
		#expect(out.status == 303)
		#expect(out.header("Location") == "/login")
		let cleared = try #require(out.header("Set-Cookie"))
		#expect(cleared.hasPrefix("auth="))
		#expect(cleared.contains("Max-Age=0"))

		// 4. the old cookie is worth nothing now
		let after = try await lab.exchange("/dashboard", cookie: login.cookie, through: fixture.host)
		#expect(after.status == 303)
		#expect(after.header("Location") == "/login")
		// and the render that the page held is gone with the session
		#expect(await fixture.table.router(for: login.sessionKey, renderToken: RenderKey(value: token)) == nil)
	}

	@Test("logout runs the tracked connection's close action")
	func logoutClosesTrackedChannel() async throws {
		let fixture = TestHost(pages: [Fixture.page("/")])
		let login = try await fixture.logIn()
		let closes = CountingCloses()
		let socket = EmbeddedChannel()
		await fixture.bus.track(
			ConnectionToken.next {
				closes.record("closed")
				socket.close(promise: nil)
			},
			session: login.sessionKey
		)

		_ = try await fixture.host.signOut(for: Fixture.request("/", cookie: login.cookie))

		// the action ran, and the bus kept nothing afterwards. that a real peer
		// observes the close is C4's socket test; this is the composition.
		#expect(closes.values == ["closed"])
		#expect(await fixture.bus.trackedCount == 0)
		_ = try? socket.finish()
	}

	@Test("an event routes to the handler the page registered")
	func eventReachesHandler() async throws {
		let hit = MutexList()
		let page = Fixture.page("/", handler: { _ in
			hit.append("clicked")
			return [FragmentUpdate(id: "out", html: "clicked")]
		})
		let fixture = TestHost(pages: [page])
		let login = try await fixture.logIn()
		let html = bodyText(try await fixture.host.respond(to: Fixture.request("/", cookie: login.cookie)))
		let token = RenderKey(value: try #require(renderToken(in: html)))

		let dispatch = await fixture.host.dispatch(click(), session: login.sessionKey, renderToken: token)

		#expect(hit.values == ["clicked"])
		if case .fragments(let updates) = dispatch.outcome {
			#expect(updates.map(\.id) == ["out"])
			#expect(updates.first?.html == "clicked")
		} else {
			Issue.record("expected fragments, got \(dispatch.outcome)")
		}
	}

	@Test("the host is a responder, so it drops into a Router")
	func hostDropsIntoRouter() async throws {
		let fixture = TestHost(pages: [Fixture.page("/")])
		let login = try await fixture.logIn()
		let router = Router {
			Route(method: .get, pattern: "/", responder: fixture.host)
		}

		let anonymous = try await router.respond(to: Fixture.request("/"))
		let authenticated = try await router.respond(to: Fixture.request("/", cookie: login.cookie))

		#expect(anonymous.status.code == 303)
		#expect(authenticated.status.code == 200)
	}

	@Test("signing out twice is not an error")
	func signOutIsIdempotent() async throws {
		let fixture = TestHost(pages: [Fixture.page("/")])
		let login = try await fixture.logIn()
		let request = Fixture.request("/", cookie: login.cookie)

		let first = try await fixture.host.signOut(for: request)
		let second = try await fixture.host.signOut(for: request)

		#expect(first.status.code == 303)
		#expect(second.status.code == 303)
		#expect(location(of: second) == "/login")
		#expect(second.cookies.count == 1)
	}

	@Test("a resolver that cannot answer throws instead of redirecting")
	func brokenResolverThrows() async throws {
		// the page layer is required, so a host cannot stand on a router
		// the server never dispatches through: name it here too.
		let table = RouterTable()
		let host = AuthenticatedHost(
			resolver: BrokenResolver(),
			catalog: StaticCatalog(pages: [:]),
			routers: table,
			revocation: SocketRevocationBus(),
			sessions: NoopRevocation(),
			pages: SessionPages(
				stores: SessionStores(),
				events: EventRouter(),
				routers: table
			)
		)

		await #expect(throws: BrokenResolver.Failure.self) {
			_ = try await host.respond(to: Fixture.request("/"))
		}
	}

	@Test("a role-guarded page is a 404 for a principal without the role")
	func roleGuardHidesThePage() async throws {
		let fixture = TestHost(
			pages: [Fixture.page("/admin", requiresRole: Role.admin)],
			identities: Fixture.directory([("alice", [Role.member]), ("root", [Role.admin])])
		)
		let alice = try await fixture.logIn(identityID: "alice")
		let root = try await fixture.logIn(identityID: "root")

		let refused = try await fixture.host.respond(to: Fixture.request("/admin", cookie: alice.cookie))
		let allowed = try await fixture.host.respond(to: Fixture.request("/admin", cookie: root.cookie))

		// 404, not 403: a catalog must not tell an unauthorised principal that
		// the page exists.
		#expect(refused.status.code == 404)
		#expect(allowed.status.code == 200)
	}
}

// MARK: - SignOutRoute

/// the app-side logout route: one line, which is the point of the facade.
struct SignOutRoute: Responder {
	let host: AuthenticatedHost

	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		try await host.signOut(for: request)
	}
}
