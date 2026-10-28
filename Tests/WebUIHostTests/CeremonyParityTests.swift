import Foundation
import Synchronization
import Testing
import WebUI
import WebUIServer
import WebUIAuth
import WebUIHost
import WebUIState

// MARK: - C3 parity: the ten ceremony behaviours
//
// `Tests/WebUIAuthTests/AuthServerCeremonyTests.swift` has ten `@Test` cases
// that drive the *example's* hand-rolled server over a real socket. four of them
// are behaviours of the example's own ceremony (a login page's headers, csrf
// single-use, the wrong-password throttle, the login-token stockpile cap); four
// are behaviours of the router table and the host; two belong to the transport.
//
// the parity obligation for this stage is that each of the ten has a test here,
// against the framework types, and that the example's suite is untouched and
// still green (`git diff --stat` empty for it). the doc comment on each test
// names the case it mirrors and says plainly when the assertion is a
// framework-path *equivalent* rather than the same mechanic — a proxy named as a
// proxy, never a claim of literal parity.

@Suite("ceremony parity")
struct CeremonyParityTests {

	// 1 — mirrors "login page carries the hardening headers and a csrf token".
	// the host does not serve a login page (that is the app's, and stage 2's F1
	// rewrites it), so the framework-side property is the one the host owns: the
	// anonymous answer must not hand out a session, an identity, or a page.
	@Test("the anonymous answer for a guarded path leaks no session cookie")
	func anonymousRedirectLeaksNoCookie() async throws {
		let fixture = TestHost(pages: [Fixture.page("/dashboard")])

		let response = try await fixture.host.respond(to: Fixture.request("/dashboard"))

		#expect(response.status.code == 303)
		#expect(location(of: response) == "/login")
		#expect(response.cookies.isEmpty)
		#expect(response.headers["Set-Cookie"] == nil)
		#expect(bodyText(response).isEmpty)
	}

	// 2 — mirrors "a login csrf token is consumed on the first submit". the csrf
	// store is `WebUIAuth`'s and untouched; what the host contributes is that a
	// render token is minted per render and names exactly one render, so a token
	// from one pass can never authorise a second.
	@Test("each render mints its own token, and a token names one render")
	func eachRenderMintsItsOwnToken() async throws {
		let fixture = TestHost(pages: [Fixture.page("/")])
		let login = try await fixture.logIn()

		let first = bodyText(try await fixture.host.respond(to: Fixture.request("/", cookie: login.cookie)))
		let second = bodyText(try await fixture.host.respond(to: Fixture.request("/", cookie: login.cookie)))

		let firstToken = try #require(renderToken(in: first))
		let secondToken = try #require(renderToken(in: second))
		#expect(firstToken != secondToken)

		// both are live (two tabs), and each resolves to the router its own pass
		// registered — never to the other's.
		let a = try #require(await fixture.table.router(for: login.sessionKey, renderToken: RenderKey(value: firstToken)))
		let b = try #require(await fixture.table.router(for: login.sessionKey, renderToken: RenderKey(value: secondToken)))
		#expect(a.router !== b.router)
	}

	// 3 — mirrors "wrong-password floods are throttled to 429". `LoginThrottle`
	// is `WebUIAuth`'s and untouched. the framework-side property a resolver must
	// hold: a *failed* resolution creates nothing — it cannot be used as a token
	// factory, so a flood of bad cookies leaves no state to throttle.
	@Test("a failed resolution creates no session, no render and no router")
	func failedResolutionCreatesNothing() async throws {
		let fixture = TestHost(pages: [Fixture.page("/")])

		for index in 0..<50 {
			let response = try await fixture.host.respond(
				to: Fixture.request("/", cookie: Base64.encodeURL([UInt8](repeating: UInt8(index), count: 32)))
			)
			#expect(response.status.code == 303)
		}

		#expect(fixture.table.sessionCount == 0)
		#expect(await fixture.bus.trackedCount == 0)
	}

	// 4 — mirrors "a single ip cannot stockpile login tokens". `SingleUseTokenStore`
	// is `WebUIAuth`'s and untouched. the framework-side bound is the render
	// window: however many tokens a session presents, the table keeps exactly
	// `maxRendersPerSession` of them live.
	@Test("a session's live render window stays bounded")
	func renderWindowStaysBounded() async throws {
		let fixture = TestHost(pages: [Fixture.page("/")], table: RouterTable(maxRendersPerSession: 4))
		let login = try await fixture.logIn()

		for _ in 0..<20 {
			_ = try await fixture.host.respond(to: Fixture.request("/", cookie: login.cookie))
		}

		#expect(fixture.table.renderTokens(for: login.sessionKey).count == 4)
	}

	// 5 — mirrors "a stale or foreign render token cannot drive a session's socket".
	@Test("a stale or foreign render token cannot drive a session's socket")
	func staleAndForeignTokensRefused() async throws {
		let fixture = TestHost(pages: [Fixture.page("/")])
		let alice = try await fixture.logIn(identityID: "alice")
		let bob = try await fixture.logIn(identityID: "bob")

		let aliceHTML = bodyText(try await fixture.host.respond(to: Fixture.request("/", cookie: alice.cookie)))
		let bobHTML = bodyText(try await fixture.host.respond(to: Fixture.request("/", cookie: bob.cookie)))
		let aliceToken = try #require(renderToken(in: aliceHTML))
		// bob's own render is bound, and stays his
		#expect(await fixture.table.router(for: bob.sessionKey, renderToken: RenderKey(value: try #require(renderToken(in: bobHTML)))) != nil)

		// bob presents alice's token
		let stolen = await fixture.host.dispatch(
			click(),
			session: bob.sessionKey,
			renderToken: RenderKey(value: aliceToken)
		)
		#expect(stolen.isRefused)

		// a token nobody minted
		let forged = await fixture.host.dispatch(
			click(),
			session: alice.sessionKey,
			renderToken: RenderKey(value: "forged-token")
		)
		#expect(forged.isRefused)

		// and alice's own token still works — the gate refuses strangers, not her
		let own = await fixture.host.dispatch(
			click(),
			session: alice.sessionKey,
			renderToken: RenderKey(value: aliceToken)
		)
		#expect(!own.isRefused)
	}

	// 6 — mirrors "an evicted render token refreshes in place over the live
	// socket — no reload, no logout".
	@Test("an evicted render token refreshes in place rather than reloading")
	func evictedTokenRefreshesInPlace() async throws {
		let fixture = TestHost(pages: [Fixture.page("/")], table: RouterTable(maxRendersPerSession: 2))
		let login = try await fixture.logIn()

		var tokens: [String] = []
		for _ in 0..<4 {
			let html = bodyText(try await fixture.host.respond(to: Fixture.request("/", cookie: login.cookie)))
			tokens.append(try #require(renderToken(in: html)))
		}
		let oldest = tokens[0]
		// with a window of two and four renders, the live window is the last
		// two tokens; the oldest resolves forward to the *third*, which is the
		// token that replaced it.
		let successor = tokens[2]

		let dispatch = await fixture.host.dispatch(
			click(),
			session: login.sessionKey,
			renderToken: RenderKey(value: oldest)
		)

		// the page is served, not refused: an evicted token is migrated, never
		// treated as a forgery.
		#expect(!dispatch.isRefused)
		// and the transport is told which token to hand the page.
		#expect(dispatch.refreshedToken == RenderKey(value: successor))
	}

	// 7 — mirrors "login issues a session cookie and logout closes the live socket".
	// the wire-level socket assertion is C4's (a real tcp peer observes the
	// close); this is the composition: the cookie resolves, logout ends the
	// session everywhere at once.
	@Test("the session cookie resolves, and logout ends the session everywhere")
	func cookieAndLogout() async throws {
		let fixture = TestHost(pages: [Fixture.page("/")])
		let login = try await fixture.logIn()

		let html = bodyText(try await fixture.host.respond(to: Fixture.request("/", cookie: login.cookie)))
		let token = try #require(renderToken(in: html))
		let socket = ConnectionToken.next {}
		await fixture.bus.track(socket, session: login.sessionKey)
		#expect(await fixture.bus.connectionCount(for: login.sessionKey) == 1)

		let response = try await fixture.host.signOut(for: Fixture.request("/", cookie: login.cookie))

		#expect(response.status.code == 303)
		#expect(response.cookies.count == 1)
		#expect(await fixture.bus.connectionCount(for: login.sessionKey) == 0)
		#expect(await fixture.table.router(for: login.sessionKey, renderToken: RenderKey(value: token)) == nil)
		// the cookie no longer resolves: the store half ran too
		#expect(try await fixture.resolver.principal(for: Fixture.request("/", cookie: login.cookie)) == nil)
	}

	// 8 — mirrors "the connection cap covers bare connects (accept-time admission)".
	// admission is the transport's, owned by `WebUIServer`'s seam. the host-side
	// property: a request that is refused or redirected never reaches a page
	// render, so it costs no render and registers no handler.
	@Test("a refused or redirected request never reaches a page render")
	func refusedRequestNeverRenders() async throws {
		let page = RecordingResponder("never")
		let catalog = StaticCatalog(pages: ["/dashboard": page])
		let table = RouterTable()
		let host = AuthenticatedHost(
			resolver: FixedResolver(fixed: nil),
			catalog: catalog,
			routers: table,
			revocation: SocketRevocationBus(),
			sessions: NoopRevocation(),
			pages: SessionPages(stores: SessionStores(), events: EventRouter(), routers: table)
		)

		// anonymous, static catalog: the page is public, so it IS served — the
		// point of this test is the *host's* 404, which reaches nothing.
		_ = try await host.respond(to: Fixture.request("/dashboard"))
		#expect(page.calls == 1)
		_ = try await host.respond(to: Fixture.request("/missing"))
		#expect(page.calls == 1)
	}

	// 9 — mirrors "dashboard page is delivered byte-complete with the default
	// send buffer". the send buffer is the transport's; what the host owes is that
	// the markup it answers with is exactly the markup the render produced.
	@Test("the host answers with the whole rendered page, byte for byte")
	func renderedPageIsDeliveredWhole() async throws {
		let marker = String(repeating: "x", count: 4096)
		let fixture = TestHost(pages: [
			Page(pattern: "/big") { request in
				request.render(on: EventRouter()) { Text(marker) }
			}
		])
		let login = try await fixture.logIn()

		let response = try await fixture.host.respond(to: Fixture.request("/big", cookie: login.cookie))
		let html = bodyText(response)

		// the page body is a bare text node, so the render and the answer must be
		// byte-identical: nothing added, nothing truncated on the way out.
		#expect(html == marker)
	}

	// 10 — mirrors "two authenticated sessions get independent state containers".
	// per-session *state* is design B's (A6); per-session *routing* is this
	// target's, and that is what is asserted: the same page for two sessions is
	// two handler namespaces, and a frame crosses neither.
	@Test("two authenticated sessions route independently")
	func twoSessionsRouteIndependently() async throws {
		let log = MutexList()
		// the label is explicit: `page` takes two closures (`heading` and
		// `handler`) and a bare trailing closure is ambiguous between them.
		let page = Fixture.page("/", handler: { event in
			log.append("\(event.component.value)")
			return [FragmentUpdate(id: event.component.value, html: "hit")]
		})
		let fixture = TestHost(pages: [page])
		let alice = try await fixture.logIn(identityID: "alice")
		let bob = try await fixture.logIn(identityID: "bob")

		let aliceHTML = bodyText(try await fixture.host.respond(to: Fixture.request("/", cookie: alice.cookie)))
		let bobHTML = bodyText(try await fixture.host.respond(to: Fixture.request("/", cookie: bob.cookie)))
		let aliceToken = try #require(renderToken(in: aliceHTML))
		let bobToken = try #require(renderToken(in: bobHTML))

		let first = await fixture.host.dispatch(click(), session: alice.sessionKey, renderToken: RenderKey(value: aliceToken))
		#expect(!first.isRefused)
		// bob's namespace never saw alice's click
		let crossing = await fixture.host.dispatch(click(), session: bob.sessionKey, renderToken: RenderKey(value: aliceToken))
		#expect(crossing.isRefused)
		let second = await fixture.host.dispatch(click(), session: bob.sessionKey, renderToken: RenderKey(value: bobToken))
		#expect(!second.isRefused)

		#expect(log.values == ["c0", "c0"])
	}
}

// MARK: - helpers

/// a click on the first control a rendered page mints.
func click() -> EventData {
	EventData(component: ComponentID("c0"), event: .click)
}

/// a thread-safe append log — the handler runs on whatever executor dispatches
/// it, so the test cannot use a plain array.
final class MutexList: Sendable {
	private let storage = Mutex<[String]>([])

	func append(_ value: String) {
		storage.withLock { $0.append(value) }
	}

	var values: [String] {
		storage.withLock { $0 }
	}
}

/// the store write door, for a host whose sessions never end. nothing in the
/// suites that use it logs out.
struct NoopRevocation: SessionRevocation {
	func endSession(tokenHash: [UInt8]) async throws {}
}
