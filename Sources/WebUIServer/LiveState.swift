import Logging
import Synchronization

// MARK: - DX-16 — the live-state binding
//
// a `LiveState` is anything that can tell a subscriber "the value changed".
// the framework ships `LiveBox` (a Mutex-backed value, the ergonomic default)
// and `LiveNotifier` (an embeddable mixin for a custom type or an actor that
// already owns its state). a region whose `source` is non-nil is subscribed by
// the registry at `start()`, so a state change reaches dirty → wake → render →
// push with no consumer wiring (LIVE_DX appendix A.2).

/// a change-notification source. the registry subscribes every region's
/// non-nil ``LiveRegion/source`` at start.
///
/// the method is synchronous by contract: a custom actor's witness **must be
/// `nonisolated`** (forwarding to its `LiveNotifier`) — a synchronous hop onto
/// a busy actor can block `start()` (d-x7).
public protocol LiveState: Sendable {
	func subscribe(_ onChange: @escaping @Sendable () -> Void) -> LiveSubscription
}

/// a cancellation handle returned by `subscribe`. `cancel()` is idempotent and
/// suppresses every future delivery.
public struct LiveSubscription: Sendable {
	private let onCancel: @Sendable () -> Void

	public init(_ onCancel: @escaping @Sendable () -> Void) {
		self.onCancel = onCancel
	}

	/// stop receiving changes. idempotent: a second call is a no-op, and no
	/// delivery that would have been made after the first call is ever made.
	public func cancel() {
		onCancel()
	}
}

// MARK: - LiveNotifier

/// an embeddable notification mixin for custom / actor state.
///
/// a hand-written `LiveState` embeds one and forwards its `subscribe` witness
/// to ``add(_:)``; an actor conforms with a `nonisolated` witness so the
/// registry's synchronous subscribe never hops onto the actor (d-x7).
///
/// delivery is **strictly after unlock**: `notify()` snapshots the live
/// callbacks under the lock, releases it, and only then invokes them — so a
/// callback that re-enters `add`/`cancel`/`notify` cannot deadlock (the
/// `ObserverList` precedent, LIVE_DX appendix A.2 semantic 9).
public final class LiveNotifier: Sendable {
	/// one registered callback plus its live bit. the bit is what makes
	/// `cancel()` suppress a delivery that was already snapshotted.
	private final class Callback: Sendable {
		let body: @Sendable () -> Void
		private let live = Mutex(true)

		init(_ body: @escaping @Sendable () -> Void) {
			self.body = body
		}

		var isLive: Bool { live.withLock { $0 } }
		func deactivate() { live.withLock { $0 = false } }
	}

	private struct State {
		var next: Int = 0
		var callbacks: [Int: Callback] = [:]
	}

	private let state = Mutex(State())

	public init() {}

	/// register a callback and return its cancellation handle.
	@discardableResult
	public func add(_ onChange: @escaping @Sendable () -> Void) -> LiveSubscription {
		let callback = Callback(onChange)
		let token = state.withLock { state -> Int in
			let token = state.next
			state.next += 1
			state.callbacks[token] = callback
			return token
		}
		return LiveSubscription { [weak self] in
			guard let self else { return }
			self.state.withLock { state in
				state.callbacks.removeValue(forKey: token)?.deactivate()
			}
		}
	}

	/// deliver to every live callback. the snapshot is taken under the lock and
	/// delivered outside it.
	public func notify() {
		let snapshot = state.withLock { Array($0.callbacks.values) }
		for callback in snapshot where callback.isLive {
			callback.body()
		}
	}

	/// how many callbacks are currently registered (diagnostics and tests).
	public var subscriberCount: Int {
		state.withLock { $0.callbacks.count }
	}
}

// MARK: - LiveBox

/// the framework's default ``LiveState``: a `Mutex`-backed value.
///
/// reading is a single locked snapshot; writing swaps the value **then**
/// notifies, strictly after the lock is released (d-x4). a region whose render
/// reads `.value` gets the value at the instant of the read — the render
/// closure is responsible for taking that snapshot once, before any `await`.
///
/// ```swift
/// let count = LiveBox(0)
/// let region = StateLiveRegion(id: "count", state: count) { box in
///     let value = box.value          // one locked snapshot
///     return "<span id=\"count\">\(value)</span>"
/// }
/// count.value = 1                    // → dirty → wake → render → push
/// ```
public final class LiveBox<Value: Sendable>: LiveState {
	private let storage: Mutex<Value>
	private let notifier = LiveNotifier()

	public init(_ value: Value) {
		self.storage = Mutex(value)
	}

	/// the current value, read under the lock.
	public var value: Value {
		get { storage.withLock { $0 } }
		set {
			storage.withLock { $0 = newValue }
			// strictly after unlock: the callbacks may read `.value` again.
			notifier.notify()
		}
	}

	/// mutate under the lock, then notify once, strictly after unlock.
	@discardableResult
	public func mutate<T>(_ body: (inout Value) -> T) -> T {
		let result = storage.withLock { value in body(&value) }
		notifier.notify()
		return result
	}

	public func subscribe(_ onChange: @escaping @Sendable () -> Void) -> LiveSubscription {
		notifier.add(onChange)
	}
}