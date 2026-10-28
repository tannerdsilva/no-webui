import Testing
import WebUICore
import WebUIState

// stage 0's reaper seam: the public `reapIdle()` is the clock's door, so it
// drops idle stores without being over the cap and reports what it dropped.

private struct Tally: Sendable {
	var count = 0
}

@Suite("stage 0 — idle reaping")
struct SpineReapIdleTests {
	private func key(_ byte: UInt8) -> SessionKey { SessionKey(hash: [byte]) }

	@Test("a tick drops the idle store and keeps the live one")
	func tickDropsIdleKeepsLive() throws {
		// the default cap on purpose: nothing here is under pressure, so a drop
		// proves the clock's walk is not cap-gated.
		let stores = SessionStores()
		let live = key(1)
		let idle = key(2)
		let liveStore = try #require(stores.resolve(for: live) { Tally() }.store)
		_ = try #require(stores.resolve(for: idle) { Tally() }.store)
		stores.markLive(live)

		let dropped = stores.reapIdle()

		#expect(dropped == [idle])
		#expect(stores.existing(for: idle, as: Tally.self) == nil)
		#expect(stores.existing(for: live, as: Tally.self) === liveStore)
		#expect(stores.count == 1)
		#expect(stores.liveCount == 1)
	}

	@Test("a tick with every store live drops nothing and answers nothing")
	func tickWithNothingIdle() throws {
		let stores = SessionStores()
		let only = key(3)
		_ = try #require(stores.resolve(for: only) { Tally() }.store)
		stores.markLive(only)

		#expect(stores.reapIdle().isEmpty)
		#expect(stores.count == 1)
		#expect(stores.liveCount == 1)
	}

	@Test("a closed socket makes its store reapable again")
	func closedSocketIsReapable() throws {
		let stores = SessionStores()
		let session = key(4)
		_ = try #require(stores.resolve(for: session) { Tally() }.store)
		stores.markLive(session)
		#expect(stores.reapIdle().isEmpty)

		stores.markClosed(session)
		#expect(stores.reapIdle() == [session])
		#expect(stores.count == 0)
	}
}
