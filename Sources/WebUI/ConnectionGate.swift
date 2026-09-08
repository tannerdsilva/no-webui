import Synchronization

// MARK: - ConnectionGate

/// an admission counter for concurrent connections, used by reference servers
/// to bound memory on small hosts. each accepted channel whose negotiation
/// completes `tryAcquire`s one slot; the channel's handler releases it when
/// the connection ends. at capacity new connections are closed immediately —
/// with the reference servers' large embedded pages (a ~300 kb inlined
/// stylesheet per launched page) and the awaited-response write, a slow or
/// non-reading client can hold a page-sized buffer, so the cap is a hard
/// memory ceiling (e.g. 256 connections × ~300 kb ≈ 80 mb worst case).
public final class ConnectionGate: Sendable {
	private struct State {
		var active: Int
	}
	private let state: Mutex<State>

	/// the maximum number of concurrently-held acquisitions.
	public let maximum: Int

	public init(maximum: Int) {
		precondition(maximum > 0, "ConnectionGate requires a positive maximum")
		self.maximum = maximum
		self.state = Mutex(State(active: 0))
	}

	/// take a slot if capacity remains, else return `false` (caller closes the
	/// connection).
	public func tryAcquire() -> Bool {
		state.withLock { s in
			guard s.active < maximum else { return false }
			s.active += 1
			return true
		}
	}

	/// the number of slots currently held (observability + tests).
	public var activeCount: Int {
		state.withLock { $0.active }
	}

	/// release a slot taken by `tryAcquire`.
	public func release() {
		state.withLock { s in
			s.active = max(0, s.active - 1)
		}
	}
}
