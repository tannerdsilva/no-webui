import Testing
import WebUI

// MARK: - ConnectionGate

@Suite("ConnectionGate")
struct ConnectionGateTests {

	@Test("admits up to the maximum and rejects beyond it")
	func admitsUpToMax() {
		let gate = ConnectionGate(maximum: 3)
		#expect(gate.tryAcquire())
		#expect(gate.tryAcquire())
		#expect(gate.tryAcquire())
		#expect(!gate.tryAcquire())
	}

	@Test("release returns capacity")
	func releaseReturnsCapacity() {
		let gate = ConnectionGate(maximum: 2)
		#expect(gate.tryAcquire())
		#expect(gate.tryAcquire())
		#expect(!gate.tryAcquire())
		gate.release()
		#expect(gate.tryAcquire())
	}

	@Test("release beyond acquired never collapses the bookkeeping")
	func releaseIsClamped() {
		let gate = ConnectionGate(maximum: 1)
		gate.release()
		gate.release()
		#expect(gate.tryAcquire())
		#expect(!gate.tryAcquire())
		#expect(gate.activeCount == 1)
	}

	@Test("concurrent acquire/release churn stays consistent")
	func concurrentChurn() async {
		let gate = ConnectionGate(maximum: 4)
		let total = 300
		await withTaskGroup(of: Int.self) { group in
			for _ in 0..<total {
				group.addTask {
					var spins = 0
					while !gate.tryAcquire() {
						await Task.yield()
						spins += 1
						if spins > 100_000 { return -1 }
					}
					gate.release()
					return 0
				}
			}
			var failed = 0
			for await result in group {
				if result != 0 { failed += 1 }
			}
			#expect(failed == 0)
			#expect(gate.activeCount == 0)
		}
	}
}
