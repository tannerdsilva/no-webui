import Logging
import ServiceLifecycle
import WebUICore
import WebUIState

// MARK: - the clock
//
// the reaper's interval is a dependency, not a constant, and the thing it
// depends on is *sleeping* — the one operation a test must never really do
// (N08: "inject the clock; no `sleep`, no real time in a test"). so the seam is
// one method wide, and the production conformer is the only place
// `Task.sleep` appears.

/// the clock an ``IdleSessionReaper`` ticks on.
///
/// makes unrepresentable: "the reaper's cadence is hard-wired to wall time" —
/// the loop asks this protocol to wait, so a test drives the same loop the host
/// runs and no test waits for a real minute.
public protocol LifecycleClock: Sendable {
	/// suspend for `interval`, or throw `CancellationError` when the calling
	/// task is cancelled.
	///
	/// a conformer must not swallow cancellation: the reaper treats a throw
	/// from this method as the shutdown door.
	func sleep(for interval: Duration) async throws
}

/// the production clock: `ContinuousClock` through `Task.sleep`, which is
/// already the monotonic sleep a ServiceGroup expects.
public struct ContinuousLifecycleClock: LifecycleClock {
	public init() {}

	public func sleep(for interval: Duration) async throws {
		try await Task.sleep(for: interval)
	}
}

// MARK: - IdleSessionReaper

/// reaps idle session stores on a clock, and drops what it reaps.
///
/// the seam this closes (S5): `SessionStores.reapIdle()` is the policy for
/// "an abandoned session's store is garbage whether or not the table is at its
/// cap", but nothing called it — `resolve` only reaps under capacity pressure,
/// so a long-lived host leaked one store per abandoned session forever. this
/// service is that caller.
///
/// third law: the loop lives inside ``run()``, the cleanup is the last thing
/// ``run()`` does, cancellation is the shutdown door, there is no `shutdown()`,
/// no `atexit`, no `DispatchMain`, and no unstructured `Task {}` that outlives
/// the run. the whole service is a value — it owns no state of its own, only
/// references the host injected.
///
/// what "drops what it reaps" means: ``SessionStores/reapIdle()`` detaches the
/// registry's reference, and that is not enough on its own — a control's
/// handler registered in the router captured the store's binding, so the store
/// lives until its render session ends. the reaper therefore hands every reaped
/// key to the host's ``SessionRouterTable`` (when one is injected), which ends
/// those render sessions. sockets are deliberately not its business: a session
/// is only idle once its last socket has closed (`markClosed`), so there is
/// nothing left to close.
public struct IdleSessionReaper: Service, Sendable {
	/// the registry whose idle stores this service drops.
	public let stores: SessionStores

	/// how long one tick waits. 60 s by default: long enough that the walk is
	/// noise beside a render, short enough that an abandoned session's store is
	/// gone within a minute of its last socket.
	public let interval: Duration

	/// where the handler tables live, or `nil` for a host without one (a static
	/// page host keeps no routers, and then the store is the whole reap).
	private let routers: (any SessionRouterTable)?

	private let clock: any LifecycleClock

	private let logger: Logger

	/// told about each reaped key, after its routers are dropped.
	///
	/// a hook rather than a return value: a tick's result has no caller — the
	/// loop is the caller — and a test that wants to observe a tick
	/// deterministically needs to be told when one finished. `nil` (the
	/// default) logs the count and nothing else.
	private let onReap: (@Sendable (SessionKey) -> Void)?

	public init(
		stores: SessionStores,
		routers: (any SessionRouterTable)? = nil,
		interval: Duration = .seconds(60),
		clock: any LifecycleClock = ContinuousLifecycleClock(),
		logger: Logger = Logger(label: "webui.lifecycle"),
		onReap: (@Sendable (SessionKey) -> Void)? = nil
	) {
		self.stores = stores
		self.routers = routers
		self.interval = interval
		self.clock = clock
		self.logger = logger
		self.onReap = onReap
	}

	// MARK: run

	/// tick until the task is cancelled, then leave nothing idle behind.
	///
	/// cancellation is a clean return, not a throw: the group asked the service
	/// to stop, so `CancellationError` out of the clock means "stop", and a
	/// service that rethrew it would report a shutdown as a failure. any other
	/// error from the clock is logged and also ends the loop — a reaper whose
	/// clock died must not keep a group alive on a cadence nobody can measure.
	public func run() async throws {
		logger.info("webui lifecycle: reaping idle sessions every \(interval)")

		// a loop that only watches cancellation stalls a group's *graceful*
		// shutdown: the group runs every registered handler and then waits for
		// the service task, and this loop registers none — so the group waits
		// out `maximumGracefulShutdownDuration` before escalating to
		// cancellation. measured: five seconds of dead air per shutdown with a
		// five-second bound. the sibling below awaits the group's shutdown and
		// ends the loop, so either door stops it, and the loop's own
		// `CancellationError` stays the expected exit rather than a failure.
		try await withThrowingTaskGroup(of: Void.self) { group in
			group.addTask { await self.loopUntilStopped() }
			group.addTask { try await gracefulShutdown() }
			do {
				try await group.next()
			} catch is CancellationError {
				// the group asked the service to stop: expected, not a failure.
			}
			group.cancelAll()
			// drain the sibling; its CancellationError is the point, not a fault.
			while let _ = try? await group.next() {}
		}

		// the cleanup, at the end of `run()`: one last sweep, so stopping the
		// service does not leave the stores it was watching to a process that
		// is about to exit. live stores are kept — they were never this
		// service's to drop.
		await tick()
		logger.info("webui lifecycle: stopped")
	}

	/// tick until the task is cancelled or the group shuts down.
	///
	/// cancellation is a clean return: the group asked the service to stop, so
	/// `CancellationError` out of the clock means "stop", and a loop that
	/// rethrew it would report a shutdown as a failure. any other error from
	/// the clock is logged and also ends the loop — a reaper whose clock died
	/// must not keep a group alive on a cadence nobody can measure.
	private func loopUntilStopped() async {
		while true {
			do {
				try await clock.sleep(for: interval)
			} catch {
				if !(error is CancellationError) {
					logger.warning("webui lifecycle: clock failed, stopping the reaper: \(error)")
				}
				break
			}
			// `sleep` may return after a cancellation it did not throw on (a
			// clock that resumes early). either signal ends the loop.
			if Task.isCancelled { break }
			await tick()
		}
	}

	// MARK: one tick

	/// one reaping pass: drop every idle store, then the routers that held them.
	///
	/// synchronous work on the store table (one lock), then one `await` per
	/// reaped session for its router table.
	private func tick() async {
		guard stores.count > 0 else { return }
		let reaped = stores.reapIdle()
		guard !reaped.isEmpty else {
			logger.debug("webui lifecycle: every store is live (\(stores.liveCount))")
			return
		}
		for key in reaped {
			await routers?.drop(session: key)
			onReap?(key)
		}
		logger.info(
			"webui lifecycle: reaped \(reaped.count) idle session(s), \(stores.count) store(s) left"
		)
	}
}
