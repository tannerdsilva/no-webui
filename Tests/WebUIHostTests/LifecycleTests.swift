import Logging
import Synchronization
import Testing
import WebUICore
import WebUIHost
import WebUIState

// MARK: - C1 gate: the idle-session reaper
//
// the gate, verbatim: "with an injected clock, one idle store is reaped and a
// live one is kept; the service returns cleanly when its task is cancelled. no
// `sleep` in any test."
//
// the clock below is the whole instrument: it parks until the test fires a
// tick, so every wait is an explicit handshake and no test measures wall time
// (N08 — a reaper tested by sleeping is a test of the machine, not the loop).

// MARK: - the clock

/// a clock that only moves when the test says so.
///
/// `sleep` parks on a continuation; `fire()` hands it one tick, and a `fire()`
/// that lands before the reaper asks for a tick is remembered and delivered
/// immediately — which is what keeps the tests raceless in both directions.
private final class ManualClock: LifecycleClock, Sendable {
	private enum Arrival {
		/// a tick was already pending: return without parking.
		case deliverNow
		/// cancellation arrived first: throw instead of parking.
		case cancelNow
		/// park until `fire()` or cancellation.
		case park
	}

	private struct State: Sendable {
		var waiting: CheckedContinuation<Void, any Error>?
		var pending: Int = 0
		/// how many times the reaper asked to sleep — the loop's own heartbeat,
		/// which is what a test waits on to know a tick finished.
		var waits: Int = 0
		var cancelled = false
		var sleepWaiters: [CheckedContinuation<Void, Never>] = []
	}

	private let state = Mutex(State())

	func sleep(for interval: Duration) async throws {
		// already cancelled before the wait began: the loop's next iteration is
		// a shutdown, not a tick.
		if Task.isCancelled { throw CancellationError() }
		try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
				let (arrival, heartbeat) = state.withLock { state -> (Arrival, [CheckedContinuation<Void, Never>]) in
					state.waits += 1
					let heartbeat = state.sleepWaiters
					state.sleepWaiters = []
					if state.cancelled { return (.cancelNow, heartbeat) }
					if state.pending > 0 {
						state.pending -= 1
						return (.deliverNow, heartbeat)
					}
					state.waiting = continuation
					return (.park, heartbeat)
				}
				for waiter in heartbeat { waiter.resume() }
				switch arrival {
				case .deliverNow: continuation.resume()
				case .cancelNow: continuation.resume(throwing: CancellationError())
				case .park: break
				}
			}
		} onCancel: {
			resumeWaiting(throwing: CancellationError())
		}
	}

	/// deliver one tick to the reaper.
	func fire() {
		let continuation = state.withLock { state -> CheckedContinuation<Void, any Error>? in
			guard let waiting = state.waiting else {
				state.pending += 1
				return nil
			}
			state.waiting = nil
			return waiting
		}
		continuation?.resume()
	}

	/// wait until the reaper has parked on the clock `count` times. the first
	/// park is the loop's first wait; the second is the proof that tick one ran
	/// to completion.
	func waitForSleeps(_ count: Int = 1) async {
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			let already = state.withLock { state -> Bool in
				guard state.waits < count else { return true }
				state.sleepWaiters.append(continuation)
				return false
			}
			if already { continuation.resume() }
		}
	}

	private func resumeWaiting(throwing error: any Error) {
		let continuation = state.withLock { state -> CheckedContinuation<Void, any Error>? in
			state.cancelled = true
			let waiting = state.waiting
			state.waiting = nil
			return waiting
		}
		continuation?.resume(throwing: error)
	}
}

// MARK: - the reap log

/// what the service reported reaping, and the door a test awaits it on.
private final class ReapLog: Sendable {
	private struct State: Sendable {
		var keys: [SessionKey] = []
		/// every key ever reported — what a test asserts a tick count on.
		var reported = 0
		var waiting: CheckedContinuation<SessionKey, Never>?
	}

	private let state = Mutex(State())

	func record(_ key: SessionKey) {
		let waiter = state.withLock { state -> CheckedContinuation<SessionKey, Never>? in
			state.reported += 1
			guard let waiting = state.waiting else {
				state.keys.append(key)
				return nil
			}
			state.waiting = nil
			return waiting
		}
		waiter?.resume(returning: key)
	}

	/// the next reaped key, whether it already arrived or is still to come.
	func next() async -> SessionKey {
		await withCheckedContinuation { (continuation: CheckedContinuation<SessionKey, Never>) in
			let ready = state.withLock { state -> SessionKey? in
				guard !state.keys.isEmpty else {
					state.waiting = continuation
					return nil
				}
				return state.keys.removeFirst()
			}
			if let ready { continuation.resume(returning: ready) }
		}
	}

	/// how many keys the service has reported in total, across every tick.
	var reported: Int { state.withLock { $0.reported } }
}

// MARK: - the router-table spy

/// a ``SessionRouterTable`` that only records what it was told to drop — the
/// observation the "and drops what it reaps" half of the gate needs, without a
/// rendered page behind it.
private final class DropSpy: SessionRouterTable, Sendable {
	private let dropped = Mutex<[SessionKey]>([])

	func router(
		for session: SessionKey,
		renderToken: RenderKey
	) async -> (router: EventRouter, liveToken: RenderKey, needsRefresh: Bool)? {
		nil
	}

	func bind(_ router: EventRouter, session: SessionKey, renderToken: RenderKey) async {}

	func drop(session: SessionKey) async {
		dropped.withLock { $0.append(session) }
	}

	var keys: [SessionKey] { dropped.withLock { $0 } }
}

// MARK: - tests

@Suite("lifecycle")
struct LifecycleTests {

	private let idleKey = SessionKey(hash: [1, 1, 1, 1])
	private let liveKey = SessionKey(hash: [2, 2, 2, 2])

	/// the service logs every tick at `info`; a suite that fired four ticks
	/// should not print four lines into the gate's output.
	private let quiet = Logger(label: "test.lifecycle") { _ in SwiftLogNoOpLogHandler() }

	@Test("a tick reaps the idle store and keeps the live one")
	func tickReapsIdleKeepsLive() async throws {
		let stores = SessionStores()
		// an idle store: resolved, never marked live (the shape of a session
		// whose last socket closed).
		_ = stores.resolve(for: idleKey, initial: { 0 })
		let live = stores.resolve(for: liveKey, initial: { 0 })
		stores.markLive(liveKey)
		#expect(stores.count == 2)

		let clock = ManualClock()
		let reaped = ReapLog()
		let service = IdleSessionReaper(
			stores: stores,
			interval: .seconds(60),
			clock: clock,
			logger: quiet,
			onReap: { key in reaped.record(key) }
		)
		let task = Task { try await service.run() }
		await clock.waitForSleeps()
		clock.fire()

		// the handshake: the observer runs after the store was dropped, so an
		// answer here means the tick's work is done.
		let key = await reaped.next()
		#expect(key == idleKey)
		#expect(reaped.reported == 1)
		#expect(stores.count == 1)
		#expect(stores.isLive(liveKey))
		let survivor = try #require(stores.existing(for: liveKey, as: Int.self))
		#expect(survivor === live.store)

		task.cancel()
		try await task.value
		// the shutdown sweep must not touch the live store either.
		#expect(stores.count == 1)
	}

	@Test("a live store survives a tick untouched")
	func liveStoreSurvivesTick() async throws {
		let stores = SessionStores()
		let live = try #require(stores.resolve(for: liveKey, initial: { 0 }).store)
		stores.markLive(liveKey)

		let clock = ManualClock()
		let reaped = ReapLog()
		let service = IdleSessionReaper(
			stores: stores,
			interval: .seconds(60),
			clock: clock,
			logger: quiet,
			onReap: { key in reaped.record(key) }
		)
		let task = Task { try await service.run() }
		await clock.waitForSleeps()
		clock.fire()
		// the loop parks again only after the tick finished.
		await clock.waitForSleeps(2)

		#expect(reaped.reported == 0)
		#expect(stores.count == 1)
		#expect(stores.existing(for: liveKey, as: Int.self) === live)

		task.cancel()
		try await task.value
		#expect(stores.count == 1)
	}

	@Test("cancelling the task ends the loop cleanly and sweeps what is idle")
	func cancellationReturnsCleanly() async throws {
		let stores = SessionStores()
		_ = stores.resolve(for: idleKey, initial: { 0 })

		let clock = ManualClock()
		let service = IdleSessionReaper(stores: stores, interval: .seconds(60), clock: clock, logger: quiet)
		let task = Task { try await service.run() }
		// parked on the clock: the cancel below is a cancel of a *waiting*
		// service, which is the real shutdown shape.
		await clock.waitForSleeps()
		#expect(stores.count == 1)

		task.cancel()
		// no throw: cancellation is the shutdown door, not a failure.
		try await task.value
		#expect(stores.count == 0)
	}

	@Test("a cancelled-before-start service still returns and sweeps")
	func cancellationBeforeFirstWait() async throws {
		let stores = SessionStores()
		_ = stores.resolve(for: idleKey, initial: { 0 })

		let service = IdleSessionReaper(stores: stores, clock: ManualClock(), logger: quiet)
		let task = Task { try await service.run() }
		task.cancel()
		try await task.value
		#expect(stores.count == 0)
	}

	@Test("a reaped session's routers are dropped, not just its store")
	func reapDropsTheRouterSessions() async throws {
		let stores = SessionStores()
		_ = stores.resolve(for: idleKey, initial: { 0 })
		stores.markLive(liveKey)
		_ = stores.resolve(for: liveKey, initial: { 0 })

		let spy = DropSpy()
		let clock = ManualClock()
		let reaped = ReapLog()
		let service = IdleSessionReaper(
			stores: stores,
			routers: spy,
			interval: .seconds(60),
			clock: clock,
			logger: quiet,
			onReap: { key in reaped.record(key) }
		)
		let task = Task { try await service.run() }
		await clock.waitForSleeps()
		clock.fire()

		// the observer runs after the drop, so an answer here is the proof that
		// the session's handler table ended with its store.
		let key = await reaped.next()
		#expect(key == idleKey)
		#expect(spy.keys == [idleKey])

		task.cancel()
		try await task.value
		// the shutdown sweep has nothing left to drop on the live session.
		#expect(spy.keys == [idleKey])
	}
}
