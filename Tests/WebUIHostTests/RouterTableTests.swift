import Foundation
import Testing
import WebUI
import WebUIServer
import WebUIAuth
import WebUIHost

// MARK: - C3: the router table's mechanics
//
// the table is promoted from `WebUIAuthExample`'s `RouterRegistry`, so these
// tests pin the four properties that promotion must preserve: a direct hit, the
// cross-session gate, the LRU window, and the forward chain that keeps a page
// alive across eviction. the ten ceremony behaviours are in
// `CeremonyParityTests`; this suite is about the table itself.

@Suite("session router table")
struct RouterTableTests {

	private let sessionA = SessionKey(hash: [1, 1, 1, 1])
	private let sessionB = SessionKey(hash: [2, 2, 2, 2])

	@Test("a bound token resolves to the router that was bound")
	func directHit() async throws {
		let table = RouterTable()
		let router = EventRouter()
		let token = RenderKey(value: "t1")

		await table.bind(router, session: sessionA, renderToken: token)
		let hit = try #require(await table.router(for: sessionA, renderToken: token))

		#expect(hit.router === router)
		#expect(hit.liveToken == token)
		#expect(hit.needsRefresh == false)
	}

	@Test("a token from another session never resolves — cross-session replay")
	func crossSessionGate() async throws {
		let table = RouterTable()
		await table.bind(EventRouter(), session: sessionA, renderToken: RenderKey(value: "t1"))

		#expect(await table.router(for: sessionB, renderToken: RenderKey(value: "t1")) == nil)
		#expect(await table.router(for: sessionA, renderToken: RenderKey(value: "forged")) == nil)
	}

	@Test("the live window is bounded, and evicted tokens forward to their successor")
	func forwardChain() async throws {
		let table = RouterTable(maxRendersPerSession: 2)
		let first = EventRouter()
		let second = EventRouter()
		let third = EventRouter()
		let one = RenderKey(value: "t1")
		let two = RenderKey(value: "t2")
		let three = RenderKey(value: "t3")

		await table.bind(first, session: sessionA, renderToken: one)
		await table.bind(second, session: sessionA, renderToken: two)
		#expect(table.renderTokens(for: sessionA).map(\.value) == ["t1", "t2"])

		// binding a third evicts the oldest from the live window
		await table.bind(third, session: sessionA, renderToken: three)
		#expect(table.renderTokens(for: sessionA).map(\.value) == ["t2", "t3"])

		// ... and the evicted page still resolves, through the chain, told to
		// adopt the token that replaced it
		let forwarded = try #require(await table.router(for: sessionA, renderToken: one))
		#expect(forwarded.router === third)
		#expect(forwarded.liveToken == three)
		#expect(forwarded.needsRefresh)

		// while a token this session never minted still fails
		#expect(await table.router(for: sessionA, renderToken: RenderKey(value: "t0")) == nil)
	}

	@Test("using a token promotes it, so a busy page is not evicted by a quiet one")
	func usePromotes() async throws {
		let table = RouterTable(maxRendersPerSession: 2)
		let one = RenderKey(value: "t1")
		let two = RenderKey(value: "t2")
		await table.bind(EventRouter(), session: sessionA, renderToken: one)
		await table.bind(EventRouter(), session: sessionA, renderToken: two)

		// touch t1, then bind t3: t2 is now the oldest and must be the evicted one
		_ = await table.router(for: sessionA, renderToken: one)
		await table.bind(EventRouter(), session: sessionA, renderToken: RenderKey(value: "t3"))

		#expect(table.renderTokens(for: sessionA).map(\.value) == ["t1", "t3"])
		#expect(await table.router(for: sessionA, renderToken: two) != nil)
	}

	@Test("the forward chain is bounded, and an old token eventually fails cleanly")
	func forwardChainIsBounded() async throws {
		let table = RouterTable(maxRendersPerSession: 2)
		for token in ["t1", "t2", "t3", "t4", "t5"] {
			await table.bind(EventRouter(), session: sessionA, renderToken: RenderKey(value: token))
		}

		// the window holds t4,t5. t2's forward entry still points at t4, so a page
		// two renders behind still migrates in place ...
		let forwarded = try #require(await table.router(for: sessionA, renderToken: RenderKey(value: "t2")))
		#expect(forwarded.liveToken == RenderKey(value: "t4"))
		#expect(forwarded.needsRefresh)

		// ... while t1's forward entry fell off the bounded chain, so it answers
		// `nil` — the clean refusal, never a stale router.
		#expect(await table.router(for: sessionA, renderToken: RenderKey(value: "t1")) == nil)
	}

	@Test("drop ends every bound render session and forgets the session")
	func dropEndsSessions() async throws {
		let table = RouterTable()
		let router = EventRouter()
		let token = RenderKey(value: "t1")
		await table.bind(router, session: sessionA, renderToken: token)

		// a handler registered by a render pass, in the session the token names
		router.register({ _ in [] }, for: ComponentID("c0"), in: RenderSessionID(token.value))
		#expect(router.handlerCount(in: RenderSessionID(token.value)) == 1)

		await table.drop(session: sessionA)

		#expect(router.handlerCount(in: RenderSessionID(token.value)) == 0)
		#expect(table.sessionCount == 0)
		#expect(await table.router(for: sessionA, renderToken: token) == nil)
	}

	@Test("dropping one session leaves another's routing intact")
	func dropIsScoped() async throws {
		let table = RouterTable()
		let a = EventRouter()
		let b = EventRouter()
		await table.bind(a, session: sessionA, renderToken: RenderKey(value: "ta"))
		await table.bind(b, session: sessionB, renderToken: RenderKey(value: "tb"))

		await table.drop(session: sessionA)

		#expect(await table.router(for: sessionA, renderToken: RenderKey(value: "ta")) == nil)
		#expect(await table.router(for: sessionB, renderToken: RenderKey(value: "tb"))?.router === b)
		#expect(table.liveSessions().map(\.hash) == [sessionB.hash])
	}

	@Test("binding the same token twice replaces the router rather than growing the window")
	func rebindReplaces() async throws {
		let table = RouterTable(maxRendersPerSession: 2)
		let token = RenderKey(value: "t1")
		let first = EventRouter()
		let second = EventRouter()

		await table.bind(first, session: sessionA, renderToken: token)
		await table.bind(second, session: sessionA, renderToken: token)

		#expect(table.renderTokens(for: sessionA).map(\.value) == ["t1"])
		#expect(await table.router(for: sessionA, renderToken: token)?.router === second)
	}
}
