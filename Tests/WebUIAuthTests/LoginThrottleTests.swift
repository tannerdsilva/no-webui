import Testing
import Foundation
import WebUIAuth

// MARK: - LoginThrottle

@Suite("LoginThrottle")
struct LoginThrottleTests {

	@Test("allows up to the window budget then limits")
	func windowBudget() {
		let throttle = LoginThrottle(windowSeconds: 60, maxAttempts: 3)
		let t0 = Date(timeIntervalSince1970: 1_000_000)
		#expect(throttle.record("ip:1.1.1.1", now: t0))
		#expect(throttle.record("ip:1.1.1.1", now: t0.addingTimeInterval(1)))
		#expect(throttle.record("ip:1.1.1.1", now: t0.addingTimeInterval(2)))
		// fourth attempt in the same window is limited.
		#expect(!throttle.record("ip:1.1.1.1", now: t0.addingTimeInterval(3)))
		// different keys are independent.
		#expect(throttle.record("ip:2.2.2.2", now: t0))
	}

	@Test("window rollover reopens the budget")
	func rollover() {
		let throttle = LoginThrottle(windowSeconds: 60, maxAttempts: 2)
		let t0 = Date(timeIntervalSince1970: 1_000_000)
		#expect(throttle.record("user:alice", now: t0))
		#expect(throttle.record("user:alice", now: t0))
		#expect(!throttle.record("user:alice", now: t0.addingTimeInterval(30)))
		// 61s after the window start a fresh window begins.
		#expect(throttle.record("user:alice", now: t0.addingTimeInterval(61)))
	}

	@Test("reset clears a key's history")
	func resetClears() {
		let throttle = LoginThrottle(windowSeconds: 60, maxAttempts: 2)
		let t0 = Date(timeIntervalSince1970: 1_000_000)
		#expect(throttle.record("user:alice", now: t0))
		#expect(throttle.record("user:alice", now: t0))
		#expect(!throttle.record("user:alice", now: t0))
		throttle.reset("user:alice")
		#expect(throttle.record("user:alice", now: t0))
	}

	@Test("prune drops only rolled-over windows and bounds memory")
	func pruneBounds() {
		let throttle = LoginThrottle(windowSeconds: 60, maxAttempts: 1)
		let t0 = Date(timeIntervalSince1970: 1_000_000)
		_ = throttle.record("a", now: t0)                          // window a starts t0, 1/1
		_ = throttle.record("b", now: t0.addingTimeInterval(30))   // window b starts t0+30, 1/1
		_ = throttle.record("c", now: t0.addingTimeInterval(90))   // window c starts t0+90, 1/1
		throttle.prune(before: t0.addingTimeInterval(100))
		// a and b have rolled over by t0+100 -> pruned -> fresh windows budget one attempt.
		#expect(throttle.record("a", now: t0.addingTimeInterval(100)))
		#expect(throttle.record("b", now: t0.addingTimeInterval(100)))
		// c started at t0+90 and is still inside its 60s window at t0+101:
		// the second attempt is limited, proving the window was retained.
		#expect(!throttle.record("c", now: t0.addingTimeInterval(101)))
	}

	@Test("the window cap self-prunes rolled-over entries without a host calling prune")
	func capSelfPrunes() {
		let throttle = LoginThrottle(windowSeconds: 60, maxAttempts: 1, maxWindows: 3)
		let t0 = Date(timeIntervalSince1970: 1_000_000)
		_ = throttle.record("a", now: t0)                          // starts t0
		_ = throttle.record("b", now: t0.addingTimeInterval(1))    // starts t0+1
		_ = throttle.record("c", now: t0.addingTimeInterval(2))    // starts t0+2 — the cap is full
		// at t0+63 every tracked window has rolled over (60s after its start);
		// recording three further keys must self-prune the rolled-over entries —
		// the dictionary stays bounded and the limiter keeps working with no
		// host-side prune call.
		#expect(throttle.record("d", now: t0.addingTimeInterval(63)))
		#expect(throttle.record("e", now: t0.addingTimeInterval(63)))
		#expect(throttle.record("f", now: t0.addingTimeInterval(63)))
		// the cap is full of live windows again: a fourth key fails closed,
		// proving the dictionary stayed bounded (no unbounded growth).
		#expect(!throttle.record("g", now: t0.addingTimeInterval(63.5)))
		// and the tracked keys' attempt caps still govern: f's window is live at
		// 1 of 1 attempts used, so a second attempt is refused by the budget.
		#expect(!throttle.record("f", now: t0.addingTimeInterval(63.5)))
	}

	@Test("a cap full of live windows fails closed for new keys, never for a tracked key")
	func capFailsClosed() {
		let throttle = LoginThrottle(windowSeconds: 60, maxAttempts: 2, maxWindows: 2)
		let t0 = Date(timeIntervalSince1970: 1_000_000)
		_ = throttle.record("a", now: t0)
		_ = throttle.record("b", now: t0.addingTimeInterval(1))
		// both windows are live (their 60s budgets run to t0+60 and t0+61): a new
		// key is refused — fail closed — instead of evicting a live limit under a
		// key-rotation flood.
		#expect(!throttle.record("attacker-1", now: t0.addingTimeInterval(2)))
		#expect(!throttle.record("attacker-2", now: t0.addingTimeInterval(3)))
		// a tracked key keeps its own budget through the flood: b's second attempt
		// lands inside its window and is allowed, the third hits the attempt cap.
		#expect(throttle.record("b", now: t0.addingTimeInterval(3)))
		#expect(!throttle.record("b", now: t0.addingTimeInterval(4)))
	}
}
