import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
import WebUI
import WebUIDesignSystem
@testable import WebUIServer

// MARK: - lane R semantics (DX-13 + DX-16)
//
// the frozen semantics of LIVE_DX appendix A.2, exercised in-process against
// the real registry (injected pushes, no socket) plus the apple-only socket
// legs (frame ordering, wire bytes). the twins — a custom `LiveRegion` struct
// and a custom `LiveState` actor — run the same suite the defaults run.

// MARK: - test doubles

/// records every batch of fragments the registry pushes, thread-safely.
private final class PushRecorder: Sendable {
	private let state = Mutex<[[FragmentUpdate]]>([])

	func record(_ updates: [FragmentUpdate]) { state.withLock { $0.append(updates) } }
	var count: Int { state.withLock { $0.count } }
	var fragments: [FragmentUpdate] { state.withLock { $0.flatMap { $0 } } }
}

/// a thread-safe monotonic counter.
private final class Counter: Sendable {
	private let state = Mutex(0)
	func increment() { state.withLock { $0 += 1 } }
	var value: Int { state.withLock { $0 } }
}

/// a `LiveRegion` STRUCT the framework has never seen — the DX-13 twin. it
/// carries its own state binding (a `LiveBox`) and renders its own markup.
private struct TwinRegion: LiveRegion {
	let id: String
	let cadence: Duration?
	let box: LiveBox<Int>

	var source: (any LiveState)? { box }

	func render() async -> String? {
		let value = box.value           // one locked snapshot, before any await
		return "<span id=\"\(id)\">\(value)</span>"
	}
}

/// a thread-safe cell — a reference type, so a `LiveRegion` struct (or an
/// escaping render closure) can hold it (`Mutex` is noncopyable).
private final class Cell<Value: Sendable>: Sendable {
	private let storage: Mutex<Value>

	init(_ value: Value) { storage = Mutex(value) }

	var value: Value {
		get { storage.withLock { $0 } }
		set { storage.withLock { $0 = newValue } }
	}
}

/// a `LiveRegion` STRUCT over a plain `Cell` — invalidation-driven, with no
/// `source`, so a test can change the render output WITHOUT a state wake.
private struct CellRegion: LiveRegion {
	let id: String
	let cadence: Duration?
	let cell: Cell<Int>

	func render() async -> String? {
		"<span id=\"\(id)\">\(cell.value)</span>"
	}
}

/// a `LiveState` ACTOR the framework has never seen — the DX-16 twin. its
/// `subscribe` witness is `nonisolated` (forwards to its `LiveNotifier`), so the
/// registry's synchronous subscribe never hops onto the actor (d-x7).
private actor TwinState: LiveState {
	private let notifier = LiveNotifier()
	private var value: Int

	init(seed: Int) { self.value = seed }

	nonisolated func subscribe(_ onChange: @escaping @Sendable () -> Void) -> LiveSubscription {
		notifier.add(onChange)
	}

	func snapshot() -> Int { value }

	func bump() {
		value += 1
		notifier.notify()
	}
}

// MARK: - an in-process registry harness

/// starts a registry against an injected push recorder and runs its workers as
/// tasks, so the semantic suite never needs a socket. `stop()` sets the flag and
/// joins every worker — an unbounded wait there would hang this test.
private final class RegistryHarness: Sendable {
	let registry: WebUILiveRegions
	let router: EventRouter
	let recorder: PushRecorder
	private let tasks: [Task<Void, Never>]

	init(_ regions: [any LiveRegion]) async {
		let router = EventRouter()
		let recorder = PushRecorder()
		let registry = WebUILiveRegions(regions)
		let work = await registry.start(router: router, push: { updates in
			recorder.record(updates)
		})
		self.registry = registry
		self.router = router
		self.recorder = recorder
		self.tasks = work.map { closure in Task { await closure() } }
	}

	func stop() async {
		registry.stop()
		for task in tasks { await task.value }
	}
}

private func settle(_ milliseconds: Int = 70) async {
	try? await Task.sleep(for: .milliseconds(milliseconds))
}

// MARK: - DX-16 — live state

@Suite("live state (DX-16)")
struct LiveStateTests {

	@Test("LiveBox notifies on write; cancel is idempotent and suppresses delivery")
	func boxNotifiesAndCancelSuppresses() {
		let box = LiveBox(0)
		let counter = Counter()
		let subscription = box.subscribe { counter.increment() }

		box.value = 1
		#expect(counter.value == 1, "a write notifies")

		subscription.cancel()
		subscription.cancel()          // idempotent — a second cancel is a no-op
		box.value = 2
		#expect(counter.value == 1, "no delivery after cancel")
		#expect(box.value == 2, "the value still changes")
	}

	@Test("LiveBox.mutate writes under the lock, then notifies once")
	func boxMutate() {
		let box = LiveBox([Int]())
		let counter = Counter()
		let subscription = box.subscribe { counter.increment() }
		defer { subscription.cancel() }

		box.mutate { $0.append(7) }
		#expect(box.value == [7])
		#expect(counter.value == 1)
	}

	@Test("LiveNotifier add/notify/cancel and its live-bit suppression")
	func notifierLifecycle() {
		let notifier = LiveNotifier()
		let first = Counter()
		let second = Counter()
		let a = notifier.add { first.increment() }
		_ = notifier.add { second.increment() }

		notifier.notify()
		#expect(first.value == 1)
		#expect(second.value == 1)

		a.cancel()
		notifier.notify()
		#expect(first.value == 1, "the cancelled callback is suppressed")
		#expect(second.value == 2)
		#expect(notifier.subscriberCount == 1)
	}

	@Test("the defaulted source is nil; a closure region carries no cadence by default")
	func defaults() {
		let region = ClosureLiveRegion(id: "plain") { () async -> String? in nil }
		#expect(region.source == nil, "ClosureLiveRegion defaults its source to nil")
		#expect(region.cadence == nil)
		#expect(region.id == "plain")
	}
}

// MARK: - DX-13 / DX-16 — registry semantics (in-process)

@Suite("live regions — registry semantics (DX-13)", .serialized)
struct LiveRegionRegistryTests {

	@Test("start renders baselines eagerly and pushes NOTHING; an invalidate pushes exactly one frame")
	func baselineSilenceThenOnePush() async {
		let cell = Cell(1)
		let harness = await RegistryHarness([CellRegion(id: "a", cadence: nil, cell: cell)])

		#expect(harness.recorder.count == 0, "nothing is pushed at start")
		#expect(harness.registry.currentHTML("a") == "<span id=\"a\">1</span>", "the baseline is the committed render")

		cell.value = 2
		harness.registry.invalidate("a")
		await settle()
		#expect(harness.recorder.count == 1)
		#expect(harness.recorder.fragments.first == FragmentUpdate(id: "a", html: "<span id=\"a\">2</span>"))

		await harness.stop()
	}

	@Test("an unchanged render pushes ZERO frames — byte-compare dedupe (I7)")
	func unchangedIsSilent() async {
		let cell = Cell(0)
		let harness = await RegistryHarness([CellRegion(id: "u", cadence: nil, cell: cell)])

		cell.value = 1
		harness.registry.invalidate("u")
		await settle()
		#expect(harness.recorder.count == 1)

		harness.registry.invalidate("u")            // same state → same render
		harness.registry.invalidate("u")
		await settle()
		#expect(harness.recorder.count == 1, "no frame for an unchanged region")

		await harness.stop()
	}

	@Test("a render returning nil pushes nothing")
	func nilRenderPushesNothing() async {
		let harness = await RegistryHarness([
			ClosureLiveRegion(id: "nil") { () async -> String? in nil }
		])
		harness.registry.invalidate("nil")
		await settle()
		#expect(harness.recorder.count == 0)
		await harness.stop()
	}

	@Test("an unknown id is a debug no-op — never a crash, never a frame")
	func unknownIDIsNoop() async {
		let cell = Cell(0)
		let harness = await RegistryHarness([CellRegion(id: "known", cadence: nil, cell: cell)])
		harness.registry.invalidate("ghost")
		harness.registry.markDirty(["ghost"])
		harness.registry.wakePending()
		harness.registry.invalidateAll()            // wakes "known", but its render is unchanged
		await settle()
		#expect(harness.recorder.count == 0)
		await harness.stop()
	}

	@Test("a state source drives dirty → wake → push with no wiring; stop cancels the subscription")
	func sourceDrivesAndStopCancels() async {
		let box = LiveBox(0)
		let harness = await RegistryHarness([TwinRegion(id: "s", cadence: nil, box: box)])

		box.value = 5
		await settle()
		#expect(harness.recorder.count == 1)
		#expect(harness.recorder.fragments.first?.html == "<span id=\"s\">5</span>")

		await harness.stop()
		box.value = 9
		await settle()
		#expect(harness.recorder.count == 1, "the subscription is cancelled at stop")

		harness.registry.invalidate("s")
		await settle()
		#expect(harness.recorder.count == 1, "zero frames after stop")
	}

	@Test("markDirty defers the wake; wakePending is what pushes (the two-push substrate)")
	func markDirtyDefersWake() async {
		let cell = Cell(0)
		let harness = await RegistryHarness([CellRegion(id: "d", cadence: nil, cell: cell)])

		cell.value = 4
		harness.registry.markDirty(["d"])
		await settle(90)
		#expect(harness.recorder.count == 0, "marked dirty but not woken — no push")

		harness.registry.wakePending()
		await settle()
		#expect(harness.recorder.count == 1, "the deferred wake renders and pushes")

		await harness.stop()
	}

	@Test("racing invalidates converge: an older snapshot never pushes (d-k)")
	func racingInvalidatesNeverPushStale() async {
		let cell = Cell(0)
		// a slow render: it snapshots once, then suspends, so a later invalidate
		// lands DURING the render — the dirty-since-snapshot case.
		let region = ClosureLiveRegion(id: "race") { () async -> String? in
			let value = cell.value
			try? await Task.sleep(for: .milliseconds(120))
			return "<span id=\"race\">\(value)</span>"
		}
		let harness = await RegistryHarness([region])

		cell.value = 1
		harness.registry.invalidate("race")          // pass 1: reads 1, then suspends
		await settle(40)                              // pass 1 is mid-render now
		cell.value = 2
		harness.registry.invalidate("race")          // newer state lands during the render

		await settle(500)
		let htmls = harness.recorder.fragments.map(\.html)
		#expect(htmls.last == "<span id=\"race\">2</span>", "the last frame is the newest state")
		#expect(!htmls.contains("<span id=\"race\">1</span>"), "the stale snapshot (1) never pushes")

		await harness.stop()
	}

	@Test("a cadence re-renders on the cadence; late ticks coalesce, never stack")
	func cadencePushesButNeverStacks() async {
		let counter = Counter()
		let region = ClosureLiveRegion(id: "tick", cadence: .milliseconds(25)) { () async -> String? in
			counter.increment()
			let n = counter.value
			return "<span id=\"tick\">\(n)</span>"
		}
		let harness = await RegistryHarness([region])

		await settle(240)
		let frames = harness.recorder.count
		#expect(frames >= 2, "the cadence re-renders and pushes changes")
		#expect(frames <= 9, "late ticks are skipped, not stacked (bounded a-priori)")

		await harness.stop()
		await settle(180)
		#expect(harness.recorder.count == frames, "zero frames after stop")
	}

	@Test("bounded coalescing: M=200 mutations → last frame == render(final); 1 ≤ R ≤ N, silence after")
	func boundedCoalescing() async {
		let box = LiveBox(0)
		// a deliberately slow render, so a burst coalesces (the honest stress form).
		let region = StateLiveRegion(id: "coalesce", state: box) { box in
			let value = box.value
			try? await Task.sleep(for: .milliseconds(5))
			return "<span id=\"coalesce\">\(value)</span>"
		}
		let harness = await RegistryHarness([region])

		for i in 1...200 { box.value = i }
		await settle(400)

		let R = harness.recorder.count
		let N = 8                                     // fixed a-priori
		#expect(R >= 1)
		#expect(R <= N, "the burst coalesced into ≤ N pushes (R = \(R))")
		#expect(harness.recorder.fragments.last?.html == "<span id=\"coalesce\">200</span>",
		        "the last frame is the final state")

		let settled = harness.recorder.count
		await settle(180)
		#expect(harness.recorder.count == settled, "silence in the final settle window")

		await harness.stop()
	}

	@Test("renders run inside the render context; a stable id does not grow the handler map")
	func renderInContextStableIDs() async {
		let region = ClosureLiveRegion(id: "rc") { () async -> String? in
			// the control self-registers under a STABLE id, inside the region's render
			let attributes = control("rc-btn", event: .click) { (_: EventData) async -> NoOutcome in
				NoOutcome()
			}
			return "<div id=\"rc\"><button\(attributes)>go</button></div>"
		}
		let harness = await RegistryHarness([region])

		let baseline = harness.router.handlerCount
		#expect(baseline == 1, "the region's control registered at baseline")

		harness.registry.invalidate("rc")
		await settle()
		#expect(harness.router.handlerCount == baseline, "a stable id never grows the map (overwrite-wins)")
		#expect(harness.recorder.count == 0, "the same html → no push")

		await harness.stop()
	}

	@Test("invalidateAll wakes every region")
	func invalidateAllWakesAll() async {
		let cellA = Cell(0)
		let cellB = Cell(0)
		let harness = await RegistryHarness([
			CellRegion(id: "a", cadence: nil, cell: cellA),
			CellRegion(id: "b", cadence: nil, cell: cellB),
		])
		cellA.value = 1
		cellB.value = 2
		harness.registry.invalidateAll()
		await settle()
		let ids = Set(harness.recorder.fragments.map(\.id))
		#expect(ids == ["a", "b"])
		await harness.stop()
	}

	@Test("twins: a custom LiveRegion struct and a custom LiveState actor pass the same suite")
	func twins() async {
		let box = LiveBox(0)
		let structRegion = TwinRegion(id: "struct", cadence: nil, box: box)
		let actorState = TwinState(seed: 7)
		let actorRegion = StateLiveRegion(id: "actor", state: actorState) { state in
			let value = await state.snapshot()
			return "<span id=\"actor\">\(value)</span>"
		}
		let harness = await RegistryHarness([structRegion, actorRegion])

		#expect(harness.registry.currentHTML("actor") == "<span id=\"actor\">7</span>",
		        "the actor twin's baseline reflects its seed")

		box.value = 3
		await actorState.bump()
		await settle()

		let pushed = harness.recorder.fragments
		#expect(pushed.contains(FragmentUpdate(id: "struct", html: "<span id=\"struct\">3</span>")))
		#expect(pushed.contains(FragmentUpdate(id: "actor", html: "<span id=\"actor\">8</span>")))

		await harness.stop()
	}
}

// MARK: - DX-13 — the socket legs

#if !os(Linux)
@Suite("live regions — socket legs (DX-13)", .serialized)
struct LiveRegionSocketTests {

	/// connect and prove the sink is registered: a ping answered by a pong means
	/// the upgrade completed and the connection joined the push targets. retries,
	/// because a fully-loaded test run can delay the handshake; the buffer is
	/// drained afterward so a retry never leaves a stale pong in front of a
	/// region frame.
	private func readySocket(port: Int) async -> HarnessSocket {
		let socket = HarnessSocket(url: URL(string: "ws://127.0.0.1:\(port)/ws")!)
		for _ in 0..<8 {
			try? await socket.send("{\"type\":\"ping\"}")
			if let pong = await socket.nextFrame(timeout: .seconds(2)), pong.contains("pong") {
				_ = await socket.framesWithin(.milliseconds(100))
				return socket
			}
		}
		Issue.record("the socket handshake never completed")
		return socket
	}

	@Test("a region pushes a frame over the wire on change (≤ html + 512 B) and is silent when unchanged")
	func regionPushOverTheWire() async throws {
		let box = LiveBox(0)
		let region = StateLiveRegion(id: "panel", state: box) { box in
			let value = box.value
			return "<span id=\"panel\">\(value)</span>"
		}
		let regions = WebUILiveRegions([region])
		let expected = "<span id=\"panel\">1</span>"

		try await withServer(
			requestRender: { _ in "<span id=\"panel\">0</span>" },
			router: EventRouter(),
			assets: [],
			regions: regions,
			portBase: 26000
		) { port in
			let socket = await readySocket(port: port)
			defer { socket.close() }

			// a real change each attempt; a loaded run can delay the frame, so poll.
			var frame: String? = nil
			for value in 1...30 {
				box.value = value
				if let received = await socket.nextFrame(timeout: .milliseconds(400)) {
					frame = received
					break
				}
			}
			#expect(frame != nil, "a change pushed a frame")
			#expect(frame?.contains("\"panel\"") == true)

			let bytes = ByteCounter()
			bytes.add(frame ?? "")
			#expect(bytes.total <= expected.utf8.count + 512, "a region push is ≤ html + 512 B (I8)")

			// drain any coalesced frames, then an unchanged state must be silent (I7).
			_ = await socket.framesWithin(.milliseconds(300))
			box.value = box.value                 // same value → same render → no push
			let silent = await socket.framesWithin(.milliseconds(600))
			#expect(silent.isEmpty, "an unchanged region pushes zero frames")
		}
	}

	@Test("two-push ordering: the dispatch frame precedes the region push it wakes (A.5/d-k)")
	func twoPushOrdering() async throws {
		// the region's markup is driven by a plain (non-source) cell, so the ONLY
		// trigger is the dispatch's RegionInvalidations — the deferred wake.
		let cell = Cell<String>("before")
		let region = ClosureLiveRegion(id: "live") { () async -> String? in
			let value = cell.value
			return "<span id=\"live\">\(value)</span>"
		}
		let regions = WebUILiveRegions([region])

		let router = EventRouter()
		// register the control through the erased adapter so its CombinedOutcome
		// calls context.invalidate at dispatch time.
		_ = RenderContext.withCurrent(router: router) {
			control("ctl", event: .click) { (_: EventData) async -> CombinedOutcome<FragmentUpdate, RegionInvalidations> in
				cell.value = "after"                  // change the region's state…
				return CombinedOutcome(
					FragmentUpdate(id: "ctl", html: "<button id=\"ctl\">hit</button>"),
					RegionInvalidations(["live"])      // …and ask the registry to re-render it
				)
			}
		}

		try await withServer(
			requestRender: { _ in "<button id=\"ctl\">go</button><span id=\"live\">before</span>" },
			router: router,
			assets: [],
			regions: regions,
			portBase: 27000
		) { port in
			let socket = await readySocket(port: port)
			defer { socket.close() }

			try await socket.send("{\"type\":\"event\",\"component\":\"ctl\",\"event\":\"click\",\"data\":{}}")

			let first = await socket.nextFrame(timeout: .seconds(8))
			let second = await socket.nextFrame(timeout: .seconds(8))
			#expect(first?.contains("\"ctl\"") == true, "the dispatch frame arrives first")
			#expect(second?.contains("\"live\"") == true, "the region push arrives second")
			#expect(second?.contains("after") == true)
		}
	}
}
#endif