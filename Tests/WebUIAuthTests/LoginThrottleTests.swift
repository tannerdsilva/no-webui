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
}
