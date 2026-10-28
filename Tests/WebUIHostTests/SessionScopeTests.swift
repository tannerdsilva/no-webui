import Testing
import WebUI
import WebUIServer
import WebUIAuth
import WebUIHost
import WebUIState

// MARK: - B2 / B3: per-session state, and a logout that leaves nothing
//
// B2's gate: "two authenticated sessions mutate their own state independently
// **through the host**, not through the example." the example owns its
// `SessionStores` itself; before this, no `WebUIHost` file did. every case here
// reaches state through ``AuthenticatedHost`` and renders through it too, so a
// per-session fork in the host would fail them.
//
// B3's gate: "logout closes the live socket, drops the store, and `handlerCount`
// for that session reaches 0 — all within one event-loop turn." the store and
// the handler table are asserted with no polling at all: the values are read
// after `signOut` returned, which is the one-turn claim. the socket's close is
// its own case (`ProductAcceptanceTests`), because it needs a real peer.

@Suite("session scope", .serialized)
struct SessionScopeTests {

	private func markup(in host: AuthenticatedHost, cookie: String) async throws -> String {
		let response = try await host.respond(to: Fixture.request("/", cookie: cookie))
		return bodyText(response)
	}

	@Test("two sessions mutate their own state through the host")
	func sessionsHoldSeparateState() async throws {
		let fixture = try await HostedFixture.make(portBase: 52_200)
		let host = fixture.host
		let alice = fixture.login
		let bob = try await Fixture.logIn(store: fixture.store, identityID: "bob")

		// both pages render, from two stores the host resolved.
		let aliceFirst = try await markup(in: host, cookie: alice.cookie)
		let bobFirst = try await markup(in: host, cookie: bob.cookie)
		#expect(aliceFirst.contains("<span>0</span>"))
		#expect(bobFirst.contains("<span>0</span>"))
		#expect(host.stores.count == 2)

		// the mutation goes through the host's own door, not through a render.
		let aliceStore = try await host.store(for: alice.sessionKey) { MemberDashboard.State() }
		let bobStore = try await host.store(for: bob.sessionKey) { MemberDashboard.State() }
		#expect(aliceStore !== bobStore, "one store per session, never a shared one")
		aliceStore.commit { $0.count = 7 }

		let alicePage = try await markup(in: host, cookie: alice.cookie)
		let bobPage = try await markup(in: host, cookie: bob.cookie)
		#expect(alicePage.contains("<span>7</span>"), "alice's own page renders alice's state")
		#expect(bobPage.contains("<span>0</span>"), "bob's page must not see alice's commit")

		// and the resolution is the same store on the second visit, not a fresh
		// one seeded from `initialState()`.
		let again = try await host.store(for: alice.sessionKey) { MemberDashboard.State() }
		#expect(again === aliceStore)
		#expect(again.read().count == 7)
	}

	@Test("capacity pressure drops the evicted session's store and its handlers")
	func evictionDropsStoreAndHandlers() async throws {
		// one store at the cap: alice renders, bob renders, and alice's idle
		// store is the eviction the insert performs. the render path must end
		// alice's handler table too, or the page keeps dispatching into a store
		// nothing can reach.
		let fixture = try await HostedFixture.make(portBase: 52_250, maxStores: 1)
		let host = fixture.host
		let alice = fixture.login
		let bob = try await Fixture.logIn(store: fixture.store, identityID: "bob")

		_ = try await markup(in: host, cookie: alice.cookie)
		let aliceToken = try #require(await fixture.table.renderTokens(for: alice.sessionKey).last)
		let aliceRouter = try #require(
			await fixture.table.router(for: alice.sessionKey, renderToken: aliceToken)
		).router
		#expect(aliceRouter.handlerCount(in: RenderSessionID(aliceToken.value)) == 1)

		// bob's first render inserts a second store into a one-store registry,
		// so alice's (idle) store is evicted.
		_ = try await markup(in: host, cookie: bob.cookie)

		#expect(host.stores.count == 1)
		#expect(host.stores.existing(for: alice.sessionKey, as: MemberDashboard.State.self) == nil)
		#expect(aliceRouter.handlerCount(in: RenderSessionID(aliceToken.value)) == 0)
	}

	@Test("logout reaps the store and ends the router session in one call")
	func logoutReapsStoreAndHandlers() async throws {
		let fixture = try await HostedFixture.make(portBase: 52_300)
		let host = fixture.host
		let alice = fixture.login

		_ = try await markup(in: host, cookie: alice.cookie)
		let token = try #require(await fixture.table.renderTokens(for: alice.sessionKey).last)
		let resolved = try #require(
			await fixture.table.router(for: alice.sessionKey, renderToken: token)
		)
		#expect(host.stores.count == 1)
		#expect(resolved.router.handlerCount(in: RenderSessionID(token.value)) == 1)

		_ = try await host.signOut(for: Fixture.request("/", cookie: alice.cookie))

		// no polling: these are the values as `signOut` left them, which is what
		// "within one event-loop turn" means. a reaped store whose session still
		// routes is the leak this asserts against — the handler holds the
		// store's binding, so the page would keep dispatching into dead state.
		#expect(host.stores.count == 0)
		#expect(host.stores.existing(for: alice.sessionKey, as: MemberDashboard.State.self) == nil)
		#expect(await fixture.table.renderTokens(for: alice.sessionKey).isEmpty)
		#expect(resolved.router.handlerCount(in: RenderSessionID(token.value)) == 0)
		#expect(!resolved.router.contains(RenderSessionID(token.value)))
		#expect(await fixture.bus.trackedCount == 0)

		// the session record itself is gone too, so the cookie is worth nothing.
		let after = try await host.respond(to: Fixture.request("/", cookie: alice.cookie))
		#expect(after.status.code == 303)
	}

	@Test("a signed-out session's store cannot be resurrected by a stale frame")
	func logoutRefusesStaleFrames() async throws {
		let fixture = try await HostedFixture.make(portBase: 52_350)
		let host = fixture.host
		let alice = fixture.login

		_ = try await markup(in: host, cookie: alice.cookie)
		let token = try #require(await fixture.table.renderTokens(for: alice.sessionKey).last)

		_ = try await host.signOut(for: Fixture.request("/", cookie: alice.cookie))

		let dispatch = await host.dispatch(
			EventData(component: ComponentID("counter-value"), event: .click),
			session: alice.sessionKey,
			renderToken: token
		)
		#expect(dispatch.isRefused, "a frame whose session ended must resolve to nothing")
		#expect(host.stores.count == 0)
	}
}
