import Testing
import Foundation
import WebUIAuth

// MARK: - SingleUseTokenStore

@Suite("SingleUseTokenStore")
struct SingleUseTokenStoreTests {

	@Test("a token can be consumed exactly once")
	func singleUse() async {
		let store = SingleUseTokenStore(maxEntries: 100)
		let now = Date().timeIntervalSince1970
		#expect(await store.consume("token-a", expiresAt: now + 60))
		#expect(!(await store.consume("token-a", expiresAt: now + 60)))
		#expect(await store.consume("token-b", expiresAt: now + 60))
	}

	@Test("expired tokens are pruned and can be re-consumed")
	func expiryPrunes() async {
		let store = SingleUseTokenStore(maxEntries: 100)
		// real wall-clock base: the store's prune compares against the current
		// time, so synthetic epochs in the past expire immediately.
		let now = Date().timeIntervalSince1970
		#expect(await store.consume("old", expiresAt: now - 10))
		#expect(await store.consume("live", expiresAt: now + 60))
		// force the prune path by consuming into the prune threshold.
		for i in 0..<70 {
			_ = await store.consume("filler-\(i)", expiresAt: now + 60)
		}
		// the expired entry is gone; the live one is retained.
		#expect(await store.consume("old", expiresAt: now + 60))
		#expect(!(await store.consume("live", expiresAt: now + 60)))
	}

	@Test("fails closed at capacity")
	func failClosedAtCapacity() async {
		let store = SingleUseTokenStore(maxEntries: 3)
		let now = Date().timeIntervalSince1970
		#expect(await store.consume("a", expiresAt: now + 60))
		#expect(await store.consume("b", expiresAt: now + 60))
		#expect(await store.consume("c", expiresAt: now + 60))
		#expect(!(await store.consume("d", expiresAt: now + 60)))
	}

	@Test("reserve enforces the per-key outstanding budget")
	func reserveBudget() async {
		let store = SingleUseTokenStore(maxEntries: 100, maxOutstandingPerKey: 3)
		let now = Date().timeIntervalSince1970
		#expect(await store.reserve("t1", expiresAt: now + 60, key: "ip:a"))
		#expect(await store.reserve("t2", expiresAt: now + 60, key: "ip:a"))
		#expect(await store.reserve("t3", expiresAt: now + 60, key: "ip:a"))
		// budget exhausted for this key...
		#expect(!(await store.reserve("t4", expiresAt: now + 60, key: "ip:a")))
		// ...but a different key still has room.
		#expect(await store.reserve("t5", expiresAt: now + 60, key: "ip:b"))
	}

	@Test("consuming a reserved token releases its key's budget")
	func reserveReleasedByConsume() async {
		let store = SingleUseTokenStore(maxEntries: 100, maxOutstandingPerKey: 2)
		let now = Date().timeIntervalSince1970
		#expect(await store.reserve("t1", expiresAt: now + 60, key: "ip:a"))
		#expect(await store.reserve("t2", expiresAt: now + 60, key: "ip:a"))
		#expect(!(await store.reserve("t3", expiresAt: now + 60, key: "ip:a")))
		// submit one: the key's outstanding drops, freeing a slot.
		#expect(await store.consume("t1", expiresAt: now + 60, key: "ip:a"))
		#expect(await store.reserve("t3", expiresAt: now + 60, key: "ip:a"))
		// the consumed token cannot be replayed or re-reserved.
		#expect(!(await store.consume("t1", expiresAt: now + 60)))
		#expect(!(await store.reserve("t1", expiresAt: now + 60, key: "ip:a")))
	}

	@Test("expired reserved tokens release their key's budget")
	func reserveExpiryReleases() async {
		let store = SingleUseTokenStore(maxEntries: 100, maxOutstandingPerKey: 1)
		let now = Date().timeIntervalSince1970
		#expect(await store.reserve("t1", expiresAt: now - 10, key: "ip:a"))
		#expect(!(await store.reserve("t2", expiresAt: now + 60, key: "ip:a")))
		// drive the prune path (>= 64 entries) so the expired pending entry drops.
		for i in 0..<70 {
			_ = await store.consume("filler-\(i)", expiresAt: now + 60)
		}
		#expect(await store.reserve("t2", expiresAt: now + 60, key: "ip:a"))
	}

	@Test("pending reservations occupy capacity")
	func reserveCountsTowardCapacity() async {
		let store = SingleUseTokenStore(maxEntries: 2, maxOutstandingPerKey: 10)
		let now = Date().timeIntervalSince1970
		#expect(await store.reserve("t1", expiresAt: now + 60, key: "ip:a"))
		#expect(await store.reserve("t2", expiresAt: now + 60, key: "ip:a"))
		#expect(!(await store.consume("t3", expiresAt: now + 60)))
		#expect(!(await store.reserve("t4", expiresAt: now + 60, key: "ip:a")))
	}
}
