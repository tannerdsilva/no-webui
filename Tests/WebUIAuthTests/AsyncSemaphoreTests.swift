import Testing
import Foundation
import WebUIAuth

// MARK: - AsyncSemaphore

@Suite("AsyncSemaphore")
struct AsyncSemaphoreTests {

	@Test("concurrent holders never exceed the permit count")
	func capsConcurrency() async {
		let semaphore = AsyncSemaphore(permits: 2)
		let counter = ConcurrencyCounter()
		await withTaskGroup(of: Void.self) { group in
			for _ in 0..<10 {
				group.addTask {
					await semaphore.wait()
					let observed = await counter.enter()
					#expect(observed <= 2)
					try? await Task.sleep(for: .milliseconds(20))
					await counter.exit()
					semaphore.signal()
				}
			}
		}
		let ran = await counter.total
		#expect(ran == 10)
	}

	@Test("signal without waiters releases a permit for a later wait")
	func signalLeavesPermit() async {
		let semaphore = AsyncSemaphore(permits: 1)
		await semaphore.wait()
		semaphore.signal()
		// a second acquire succeeds immediately because the permit was returned.
		await semaphore.wait()
		semaphore.signal()
	}

	@Test("waiters are resumed in order")
	func resumesWaiters() async {
		let semaphore = AsyncSemaphore(permits: 1)
		let first = await semaphore.waitThenHold() // hold the single permit
		_ = first
		let order = OrderRecorder()
		async let a: Void = {
			await semaphore.wait()
			await order.record("a")
			semaphore.signal()
		}()
		async let b: Void = {
			await semaphore.wait()
			await order.record("b")
			semaphore.signal()
		}()
		semaphore.signal() // release the held permit; wakes a (FIFO)
		_ = await (a, b)
		let recorded = await order.sequence
		#expect(recorded == ["a", "b"])
	}
}

private actor ConcurrencyCounter {
	private var _active = 0
	private var _total = 0
	func enter() -> Int {
		_active += 1
		_total += 1
		return _active
	}
	func exit() {
		_active -= 1
	}
	var total: Int { _total }
}

private actor OrderRecorder {
	private var _sequence: [String] = []
	func record(_ name: String) { _sequence.append(name) }
	var sequence: [String] { _sequence }
}

private extension AsyncSemaphore {
	func waitThenHold() async -> Bool {
		await wait()
		return true
	}
}
