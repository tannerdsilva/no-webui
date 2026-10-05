import Logging
import Synchronization
import WebUI

// MARK: - DX-13 — the live-region protocol
//
// a live region is a protocol value: a server-owned piece of the page that
// re-renders and pushes only when it changed. the framework ships the registry
// (`WebUILiveRegions`) that owns rendering, change detection, cadence,
// serialization and pump lifetime; a consumer customizes by conforming a type
// (or using `ClosureLiveRegion` / `StateLiveRegion`) and passing it in.

/// one server-rendered region of the document.
///
/// `render()` runs inside the render context (so a control it emits
/// self-registers) and returns the region's markup, or `nil` for "nothing to
/// push". the registry is responsible for the push: it byte-compares the render
/// against the last committed one and stays silent when they are equal (I7).
public protocol LiveRegion: Sendable {
	/// the DOM id AND the pushed fragment id.
	var id: String { get }
	/// `nil` = invalidation/state-driven only; otherwise re-render on the cadence.
	var cadence: Duration? { get }
	/// the region's state source, when it has one — the registry subscribes
	/// every non-nil source at start, before baselines (rev4/b1).
	var source: (any LiveState)? { get }
	/// the region's markup, or `nil` for nothing to push.
	func render() async -> String?
}

extension LiveRegion {
	/// the default: a region with no state binding is driven by `invalidate(_:)`.
	public var source: (any LiveState)? { nil }
}

// MARK: - the ergonomic default

/// a live region whose markup comes from a closure — the default conformance.
public struct ClosureLiveRegion: LiveRegion {
	public let id: String
	public let cadence: Duration?
	public let source: (any LiveState)?
	private let body: @Sendable () async -> String?

	public init(
		id: String,
		cadence: Duration? = nil,
		source: (any LiveState)? = nil,
		render: @escaping @Sendable () async -> String?
	) {
		self.id = id
		self.cadence = cadence
		self.source = source
		self.body = render
	}

	public func render() async -> String? { await body() }
}

// MARK: - the state-bound form

/// a live region bound to a ``LiveState``: the registry subscribes `state` at
/// start, and `render` receives it. the closure is responsible for snapshotting
/// the value once, before any `await` (LIVE_DX appendix A.2 semantic 9).
public struct StateLiveRegion<State: LiveState>: LiveRegion {
	public let id: String
	public let cadence: Duration?
	public let state: State
	private let body: @Sendable (State) async -> String?

	public var source: (any LiveState)? { state }

	public init(
		id: String,
		cadence: Duration? = nil,
		state: State,
		render: @escaping @Sendable (State) async -> String?
	) {
		self.id = id
		self.cadence = cadence
		self.state = state
		self.body = render
	}

	public func render() async -> String? { await body(state) }
}

// MARK: - the registry handle

/// the live-region registry: the `EventRouter`-shaped handle a host creates
/// before the server and passes as `regions:`.
///
/// it owns every region's worker, its per-start subscriptions, the change
/// detection and the pump lifetime. `nil` at the server means none of this
/// exists (d-b). the public surface is the invalidation vocabulary; the
/// server drives `start`/`stop` through internal methods.
public final class WebUILiveRegions: Sendable {
	/// declaration order (first-seen), so pushes are deterministic.
	private let order: [String]
	/// id → region definition. a duplicate id keeps the last definition.
	private let definitions: [String: any LiveRegion]
	/// the per-start runtime; `nil` before `start()` and after a fresh instance.
	private let runtime = Mutex<Runtime?>(nil)
	private let logger: Logger

	public init(_ regions: [any LiveRegion] = [], logger: Logger = Logger(label: "webui.regions")) {
		var order: [String] = []
		var definitions: [String: any LiveRegion] = [:]
		for region in regions {
			if definitions[region.id] == nil { order.append(region.id) }
			definitions[region.id] = region
		}
		self.order = order
		self.definitions = definitions
		self.logger = logger
	}

	// MARK: public invalidation vocabulary

	/// mark the region dirty and wake its worker. unknown ids and a not-yet-started
	/// registry are a debug-logged no-op — never a crash.
	public func invalidate(_ id: String) {
		guard let runtime = runtime.withLock({ $0 }) else {
			logger.debug("live region '\(id)' invalidated before start — no-op")
			return
		}
		guard let run = runtime.runs[id] else {
			logger.debug("unknown live region '\(id)' — no-op")
			return
		}
		guard !runtime.token.isStopped else { return }
		run.markDirty()
		run.pump.signal()
	}

	/// mark every region dirty and wake every worker.
	public func invalidateAll() {
		guard let runtime = runtime.withLock({ $0 }), !runtime.token.isStopped else { return }
		for id in order {
			guard let run = runtime.runs[id] else { continue }
			run.markDirty()
			run.pump.signal()
		}
	}

	/// the last committed render at the instant of the call — best-effort
	/// baseline, not a per-client snapshot.
	public func currentHTML(_ id: String) -> String? {
		guard let runtime = runtime.withLock({ $0 }), let run = runtime.runs[id] else { return nil }
		return run.committed
	}

	// MARK: start / stop (driven by the server)

	/// subscribe every non-nil source → render all baselines eagerly → hand back
	/// the worker/ticker closures for the caller's task group. the server calls
	/// this after `prewarm()` and before the accept loop; tests call it directly.
	///
	/// nothing is pushed at start: baselines seed `currentHTML` and the dedupe
	/// target only.
	func start(
		router: EventRouter,
		push: @escaping @Sendable ([FragmentUpdate]) async -> Void
	) async -> [@Sendable () async -> Void] {
		let runtime = Runtime(router: router, push: push, ids: order)
		self.runtime.withLock { $0 = runtime }

		// 1. subscribe every non-nil source (before baselines).
		for id in order {
			guard let region = definitions[id], let source = region.source else { continue }
			// a weak capture: the registry holds the region (and the box holds
			// this closure) — a strong capture would be a cycle.
			let subscription = source.subscribe { [weak self] in
				self?.sourceDidChange(id)
			}
			runtime.subscriptions.withLock { $0.append(subscription) }
		}

		// 2. render all baselines eagerly-synchronously (no push).
		for id in order {
			guard let region = definitions[id], let run = runtime.runs[id] else { continue }
			let html = await renderInContext(region, router: router)
			run.commitBaseline(html)
		}

		// 3. the worker (and a cadence ticker when the region asks for one).
		var work: [@Sendable () async -> Void] = []
		for id in order {
			guard let region = definitions[id], let run = runtime.runs[id] else { continue }
			work.append { [weak self] in
				await self?.worker(region: region, run: run, runtime: runtime)
			}
			if let cadence = region.cadence {
				work.append { [weak self] in
					await self?.ticker(run: run, cadence: cadence, runtime: runtime)
				}
			}
		}
		return work
	}

	/// the per-start stop flag is set FIRST, then subscriptions are cancelled and
	/// the pumps are woken and finished, so the server's discarding task group
	/// can join the workers before it shuts the event loop group down.
	func stop() {
		guard let runtime = runtime.withLock({ $0 }) else { return }
		runtime.token.stop()
		let subscriptions = runtime.subscriptions.withLock { current -> [LiveSubscription] in
			let snapshot = current
			current.removeAll()
			return snapshot
		}
		for subscription in subscriptions { subscription.cancel() }
		for id in order {
			runtime.runs[id]?.pump.signal()
			runtime.runs[id]?.pump.finish()
		}
	}

	// MARK: the dispatch seam's invalidate provider (two-push ordering, A.5/d-k)

	/// mark the given regions dirty WITHOUT waking their workers. the dispatch
	/// path calls this from inside `EventOutcome.resolve`, then writes the
	/// handler's own frame, then calls ``wakePending()`` — so a region worker
	/// woken by this dispatch can never push before the dispatch frame is on the
	/// wire.
	func markDirty(_ ids: [String]) {
		guard let runtime = runtime.withLock({ $0 }), !runtime.token.isStopped else { return }
		for id in ids {
			guard let run = runtime.runs[id] else {
				logger.debug("unknown live region '\(id)' invalidated by a dispatch — no-op")
				continue
			}
			run.markDirty()
			_ = runtime.pending.withLock { $0.insert(id) }
		}
	}

	/// wake every region marked since the last drain. called by the dispatch path
	/// after the handler frame has been written.
	func wakePending() {
		guard let runtime = runtime.withLock({ $0 }), !runtime.token.isStopped else { return }
		let ids = runtime.pending.withLock { pending -> Set<String> in
			let snapshot = pending
			pending.removeAll()
			return snapshot
		}
		for id in ids { runtime.runs[id]?.pump.signal() }
	}

	// MARK: internals

	private func sourceDidChange(_ id: String) {
		guard let runtime = runtime.withLock({ $0 }), !runtime.token.isStopped else { return }
		guard let run = runtime.runs[id] else { return }
		run.markDirty()
		run.pump.signal()
	}

	private func worker(region: any LiveRegion, run: RegionRun, runtime: Runtime) async {
		for await _ in run.pump.stream {
			if runtime.token.isStopped { return }
			await pass(region: region, run: run, runtime: runtime)
			if runtime.token.isStopped { return }
		}
	}

	private func pass(region: any LiveRegion, run: RegionRun, runtime: Runtime) async {
		// the snapshot marker: we are about to render the CURRENT state, so the
		// dirty bit is cleared. if a mutation lands during the render it sets the
		// bit again — that is the "dirty-since-snapshot" signal below.
		run.clearDirty()
		guard !runtime.token.isStopped else { return }
		let html = await renderInContext(region, router: runtime.router)
		guard !runtime.token.isStopped else { return }
		// never push while dirty-since-snapshot: a mutation during the render made
		// this html potentially stale. re-render instead (no version counter) — the
		// mutation also signalled the pump, so the worker runs again.
		if run.isDirty { return }
		guard let html else { return }               // nil → nothing to push
		if run.committed == html { return }          // byte-compare dedupe (I7)
		run.commit(html)
		await runtime.push([FragmentUpdate(id: region.id, html: html)])
	}

	/// render inside the render context so a control the region emits
	/// self-registers; a region that grows the handler map across a render is
	/// warned (minted ids are out of contract — stable ids only).
	private func renderInContext(_ region: any LiveRegion, router: EventRouter) async -> String? {
		let before = router.handlerCount
		let html = await RenderContext.withCurrent(router: router) {
			await region.render()
		}
		let after = router.handlerCount
		if after > before {
			logger.warning(
				"live region '\(region.id)' grew the handler map across a render (\(before) → \(after)); stable ids only"
			)
		}
		return html
	}

	private func ticker(run: RegionRun, cadence: Duration, runtime: Runtime) async {
		while !runtime.token.isStopped {
			do {
				try await Task.sleep(for: cadence)
			} catch {
				return
			}
			if runtime.token.isStopped { return }
			run.pump.signal()
		}
	}
}

// MARK: - per-start runtime

/// the state a single `start()` owns. recreated on each start, so subscriptions
/// and committed baselines never leak across a stop/start pair.
private final class Runtime: Sendable {
	let token = StopToken()
	let router: EventRouter
	let push: @Sendable ([FragmentUpdate]) async -> Void
	let runs: [String: RegionRun]
	let subscriptions = Mutex<[LiveSubscription]>([])
	let pending = Mutex<Set<String>>([])

	init(router: EventRouter, push: @escaping @Sendable ([FragmentUpdate]) async -> Void, ids: [String]) {
		self.router = router
		self.push = push
		var runs: [String: RegionRun] = [:]
		for id in ids { runs[id] = RegionRun() }
		self.runs = runs
	}
}

/// the per-start stop flag: set by `stop()` before the channel closes; checked
/// by every worker after each wake and before each render and push.
private final class StopToken: Sendable {
	private let stopped = Mutex(false)
	func stop() { stopped.withLock { $0 = true } }
	var isStopped: Bool { stopped.withLock { $0 } }
}

/// one region's worker-visible state: the wake pump, the dirty bit and the last
/// committed render. mutation is through the locked helpers — the lock is never
/// held across an `await`.
private final class RegionRun: Sendable {
	let pump = RegionPump()

	private struct State {
		var dirty = false
		var committed: String? = nil
	}

	private let state = Mutex(State())

	func markDirty() { state.withLock { $0.dirty = true } }
	func clearDirty() { state.withLock { $0.dirty = false } }
	var isDirty: Bool { state.withLock { $0.dirty } }
	var committed: String? { state.withLock { $0.committed } }
	func commit(_ html: String) { state.withLock { $0.committed = html } }
	func commitBaseline(_ html: String?) { state.withLock { $0.committed = html } }
}

/// a coalescing wake signal: many `signal()` calls buffer as at most one wake,
/// so a late cadence tick is skipped, never stacked (LIVE_DX appendix A.2
/// semantic 3).
private final class RegionPump: Sendable {
	let stream: AsyncStream<Void>
	private let continuation: AsyncStream<Void>.Continuation

	init() {
		var captured: AsyncStream<Void>.Continuation!
		let stream = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { captured = $0 }
		self.stream = stream
		self.continuation = captured
	}

	func signal() { continuation.yield() }
	func finish() { continuation.finish() }
}