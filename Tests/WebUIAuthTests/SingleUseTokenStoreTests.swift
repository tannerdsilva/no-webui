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
}
