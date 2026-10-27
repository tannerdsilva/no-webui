import Testing
import WebUI

// MARK: - 0.10 session liveness
//
// `evict` walks the LRU by tick, which on its own makes "evict the oldest" and
// "never evict a page that is still open" contradict each other. the seam adds
// the missing bit: a session marked live is never reaped, however old it is; a
// session whose socket closed is reaped in LRU order exactly as before.

@Suite("EventRouter liveness")
struct EventRouterLivenessTests {

	private func session(_ name: String) -> RenderSessionID { RenderSessionID(name) }

	@Test("a live session survives eviction pressure and a closed one is reaped")
	func liveSessionSurvivesPressure() {
		let router = EventRouter(maxSessions: 2)
		let incumbent = session("incumbent")
		let closed = session("closed")
		let newcomer = session("newcomer")

		router.begin(incumbent)
		router.markLive(incumbent)
		router.begin(closed)
		// `closed` is the default (not live) — its socket is gone
		router.begin(newcomer)

		#expect(router.contains(incumbent), "a live session must never be evicted")
		#expect(router.isLive(incumbent))
		#expect(!router.contains(closed), "the closed session is the LRU victim")
		#expect(router.contains(newcomer))
		#expect(router.sessionCount == 2)
	}

	@Test("markClosed makes a live session reapable again")
	func markClosedRestoresReapability() {
		let router = EventRouter(maxSessions: 1)
		let first = session("first")
		let second = session("second")

		router.begin(first)
		router.markLive(first)
		// the newcomer is the only reapable session, so it is the one reaped
		router.begin(second)
		#expect(router.contains(first))
		#expect(!router.contains(second))
		#expect(router.sessionCount == 1)

		router.markClosed(first)
		#expect(!router.isLive(first))
		router.begin(session("third"))
		#expect(!router.contains(first), "once closed, the oldest is reaped again")
	}

	@Test("when every over-cap session is live the table stays above the cap")
	func allLiveStaysAboveCap() {
		let router = EventRouter(maxSessions: 1)
		let first = session("first")
		let second = session("second")

		// a socket can open before its page renders, so liveness may be marked
		// before the session exists — and no live session is ever reaped
		router.markLive(first)
		router.begin(first)
		router.markLive(second)
		router.begin(second)

		#expect(router.contains(first))
		#expect(router.contains(second))
		#expect(router.sessionCount == 2, "the cap bounds reapable state, not live pages")
	}

	@Test("all sessions are reapable by default, exactly as before")
	func defaultSessionsBehaveLikeBefore() {
		let router = EventRouter(maxSessions: 2)
		router.begin(session("a"))
		router.begin(session("b"))
		router.begin(session("c"))
		#expect(!router.contains(session("a")))
		#expect(router.contains(session("b")))
		#expect(router.contains(session("c")))
		#expect(router.sessionCount == 2)
	}

	@Test("a re-render does not close a socket, so it does not clear liveness")
	func beginKeepsLiveness() {
		let router = EventRouter(maxSessions: 1)
		let page = session("page")
		router.begin(page)
		router.markLive(page)
		// a re-render resets handlers and mint counters — not the open socket
		router.begin(page, preservingRegistrations: true)
		#expect(router.isLive(page))
		#expect(router.contains(page))
	}

	@Test("ending a session drops it and its liveness in one step")
	func endClearsLiveness() {
		let router = EventRouter(maxSessions: 4)
		let page = session("page")
		router.begin(page)
		router.markLive(page)
		#expect(router.isLive(page))
		router.end(page)
		#expect(!router.contains(page))
		#expect(!router.isLive(page))
	}

	@Test("liveness is per session, not per router")
	func livenessIsPerSession() {
		let router = EventRouter(maxSessions: 8)
		let live = session("live")
		let idle = session("idle")
		router.begin(live)
		router.begin(idle)
		router.markLive(live)
		#expect(router.isLive(live))
		#expect(!router.isLive(idle))
		// marking an unknown session is a no-op rather than a crash
		router.markLive(session("unknown"))
		router.markClosed(session("unknown"))
		#expect(!router.isLive(session("unknown")))
	}
}
