import Synchronization
import Testing
import WebUICore
import WebUIState

// design B's gates (plan §6.6), one suite per slice so a failure names the slice.
//
// the suite lives in the `WebUIStateTests` bundle the spine declares (its
// placeholder `StateTests.swift` is replaced by these files), so the state
// target is a declared edge of a test target and nothing is imported across an
// undeclared boundary.

// MARK: - b1: the store

/// what every page in these tests counts. a struct, because the port's
/// atomicity guarantee is a value-semantics one.
private struct Tally: Sendable {
	var count = 0
}

@Suite("design b — state store")
struct DesignBStoreTests {
	/// b1's gate, literally: 10,000 mutations from 8 concurrent tasks, final
	/// count exact, revisions strictly increasing.
	@Test("10,000 mutations from 8 concurrent tasks land exactly once each")
	func concurrentMutationsAreExact() async {
		let store = Store(Tally())
		let workers = 8
		let total = 10_000

		await withTaskGroup(of: Int.self) { group in
			for _ in 0..<workers {
				group.addTask {
					var applied = 0
					for _ in 0..<(total / workers) {
						store.commit { $0.count += 1 }
						applied += 1
					}
					return applied
				}
			}
			var reported = 0
			for await applied in group {
				reported += applied
			}
			#expect(reported == total)
		}

		#expect(store.read().count == total)
		#expect(store.revision == UInt64(total))
	}

	/// the second half of b1's gate: no revision is handed out twice, none is
	/// skipped, and each worker sees its own revisions strictly increasing.
	@Test("revisions are strictly increasing and dense")
	func revisionsAreStrictlyIncreasing() async {
		let store = Store(Tally())
		let workers = 8
		let perWorker = 500

		let perTask = await withTaskGroup(of: [UInt64].self) { group in
			for _ in 0..<workers {
				group.addTask {
					var seen: [UInt64] = []
					seen.reserveCapacity(perWorker)
					for _ in 0..<perWorker {
						seen.append(store.commit { $0.count += 1 })
					}
					return seen
				}
			}
			var all: [[UInt64]] = []
			for await revisions in group {
				all.append(revisions)
			}
			return all
		}

		#expect(perTask.count == workers)
		for revisions in perTask {
			#expect(revisions == revisions.sorted())
			#expect(Set(revisions).count == revisions.count)
		}
		let merged = perTask.flatMap { $0 }.sorted()
		#expect(merged == Array(1...(UInt64(workers * perWorker))))
	}

	/// the port's second promise: a rejected mutation is not a committed one, and
	/// a reader never sees the half-applied write.
	@Test("a throwing mutation commits nothing")
	func rejectedMutationCommitsNothing() {
		struct Rejected: Error {}
		let store = Store(Tally())

		#expect(throws: Rejected.self) {
			try store.mutate { state in
				state.count += 1
				throw Rejected()
			}
		}

		#expect(store.read().count == 0)
		#expect(store.revision == 0)
	}

	/// a mutation's return value survives the commit, which is what lets a
	/// handler decide something from the state it just wrote.
	@Test("mutate returns the body's value and bumps once")
	func mutateReturnsValue() throws {
		let store = Store(Tally())
		let previous = try store.mutate { state -> Int in
			state.count += 7
			return state.count
		}
		#expect(previous == 7)
		#expect(store.revision == 1)
	}

	/// the binding is the door a control gets; it must commit through the store's
	/// own path, so a control's write is indistinguishable from any other.
	@Test("a binding commits through the store and bumps the revision")
	func bindingCommitsThroughStore() {
		let store = Store(Tally())
		let binding = store.binding
		#expect(binding.revision == 0)
		binding.mutate { $0.count = 41 }
		#expect(store.read().count == 41)
		#expect(store.revision == 1)
	}

	/// a described mutation is the value form of the same door.
	@Test("a Mutation value commits through the store")
	func mutationValueCommits() {
		let store = Store(Tally())
		let revision = store.apply(Mutation { $0.count = 9 })
		#expect(revision == 1)
		#expect(store.read().count == 9)
		#expect(store.revision == 1)
	}

	/// the store is usable wherever the *port* is asked for, which is what keeps
	/// the render loop and any future host written against `StateStore` rather
	/// than against `Store`.
	@Test("the store satisfies the StateStore port generically")
	func storeSatisfiesPort() throws {
		func bump<S: StateStore>(_ store: S, _ body: @Sendable (inout S.State) -> Void) throws where S.State == Tally {
			try store.mutate { body(&$0) }
		}

		let store = Store(Tally())
		try bump(store) { $0.count += 2 }
		#expect(store.read().count == 2)
		#expect(store.revision == 1)
	}
}

// MARK: - b2 helper: a page that renders through its own loop mid-pass

/// a slot the page uses to reach the loop that is rendering it, which is how the
/// coalescing test makes a *nested* render attempt.
private final class CoalesceSlot: Sendable {
	let loop = Mutex<StatefulPageSession<ReentrantPage>?>(nil)
	/// true when the nested call coalesced.
	let inner = Mutex(false)
	/// guards against recursing forever if the claim ever fails to hold.
	let attempted = Mutex(false)
}

private struct ReentrantPage: StatefulPage {
	let slot: CoalesceSlot

	func initialState() -> Int { 0 }

	func body(_ state: Int) -> some View {
		// try to render the same loop from inside its own pass: the claim is held,
		// so the inner call must coalesce and report nil.
		let first = slot.attempted.withLock { attempted -> Bool in
			guard !attempted else { return false }
			attempted = true
			return true
		}
		if first, let loop = slot.loop.withLock({ $0 }) {
			let context = RenderContext(router: EventRouter(), session: RenderSessionID("b2-coalesce-inner"))
			slot.inner.withLock { $0 = loop.patch(in: context) == nil }
		}
		return Text("state \(state)")
	}
}

// MARK: - b2: stateful page + render loop

private struct CounterPage: StatefulPage {
	struct State: Sendable, Equatable {
		var count = 0
	}

	func initialState() -> State { State() }

	func body(_ state: State) -> some View {
		VStack {
			Text("count \(state.count)")
			Button("+1").onClick(binding) { store in
				store.mutate { $0.count += 1 }
			}
		}
	}
}

@Suite("design b — stateful page")
struct DesignBPageTests {
	/// b2's gate: a click that only mutates produces exactly one patch, and the
	/// handler returns no fragment — it cannot, the closure returns Void.
	@Test("a click that only mutates produces exactly one patch")
	func clickProducesOnePatch() async throws {
		let router = EventRouter()
		let session = RenderSessionID("b2-one-patch")
		let context = RenderContext(router: router, session: session)
		let loop = StatefulPageSession(CounterPage())

		let first = try #require(loop.patch(in: context))
		#expect(first.isFullPage)
		#expect(first.revision == 0)
		#expect(first.passes == 1)
		#expect(first.html.contains("count 0"))
		#expect(router.handlerCount(in: session) == 1)

		// the page built one control; its id is the session's first minted id.
		let fragments = await router.handle(
			EventData(component: "c0", event: .click),
			in: session
		)
		#expect(fragments.isEmpty, "a mutation-only handler must not author a fragment")
		#expect(loop.store.revision == 1)
		#expect(loop.store.read().count == 1)

		let patch = try #require(loop.patch(in: context))
		#expect(patch.isFullPage == false)
		#expect(patch.revision == 1)
		#expect(patch.passes == 1)
		#expect(patch.changedRegions == [RegionID(rawValue: "body")])
		#expect(patch.html.contains("count 1"))
		#expect(router.handlerCount(in: session) == 1, "a re-render reuses the page's ids")
	}

	/// a second click, dispatched against the re-rendered page, still routes: the
	/// loop restarts the mint counters, so the ids a patch ships are the ids the
	/// handlers are registered under.
	@Test("a re-rendered page keeps its controls routable")
	func rerenderKeepsControlsRoutable() async {
		let router = EventRouter()
		let session = RenderSessionID("b2-rerender")
		let context = RenderContext(router: router, session: session)
		let loop = StatefulPageSession(CounterPage())

		_ = loop.patch(in: context)
		_ = await router.handle(EventData(component: "c0", event: .click), in: session)
		_ = loop.patch(in: context)
		_ = await router.handle(EventData(component: "c0", event: .click), in: session)

		#expect(loop.store.read().count == 2)
		#expect(loop.store.revision == 2)
	}

	/// the store can move while a render is in flight; the loop re-renders so the
	/// bytes match a committed revision, and says so in `passes`.
	@Test("a commit that races a render is settled by a second pass")
	func racingCommitIsSettled() throws {
		final class Racer: Sendable {
			let store: Store<CounterPage.State>
			let lock = Mutex(false)
			init(store: Store<CounterPage.State>) { self.store = store }
			func bumpOnce() {
				let first = lock.withLock { done -> Bool in
					guard !done else { return false }
					done = true
					return true
				}
				if first { store.commit { $0.count += 100 } }
			}
		}

		// a page whose body commits once, mid-render: the loop must notice the
		// revision moved and render again.
		struct RacingPage: StatefulPage {
			let racer: Racer
			typealias State = CounterPage.State
			func initialState() -> State { State() }
			func body(_ state: State) -> some View {
				racer.bumpOnce()
				return Text("count \(state.count)")
			}
		}

		let store = Store(CounterPage.State())
		let racer = Racer(store: store)
		let loop = StatefulPageSession(RacingPage(racer: racer), store: store, maxRenderPasses: 3)
		let rendered = try #require(
			loop.render(in: RenderContext(router: EventRouter(), session: RenderSessionID("b2-race")))
		)

		#expect(rendered.passes == 2)
		#expect(rendered.settled)
		#expect(rendered.revision == 1)
		#expect(rendered.html.contains("count 100"))
	}

	/// the region mark follows the *bytes*, in both directions: a mutation the
	/// body renders moves the region hash, and a mutation the body does not
	/// render leaves it alone. without the second half a patch could claim
	/// "changed" for every commit and the first half would prove nothing.
	@Test("the region mark follows the bytes, not the revision")
	func regionMarkFollowsBytes() throws {
		struct TwoFieldPage: StatefulPage {
			struct State: Sendable {
				var shown = 0
				var hidden = 0
			}

			func initialState() -> State { State() }

			func body(_ state: State) -> some View {
				Text("shown \(state.shown)")
			}
		}

		let context = RenderContext(router: EventRouter(), session: RenderSessionID("b2-region"))
		let loop = StatefulPageSession(TwoFieldPage())
		_ = loop.patch(in: context)

		// a commit the body does not render: bytes identical, nothing to patch.
		loop.store.commit { $0.hidden += 1 }
		let invisible = try #require(loop.patch(in: context))
		#expect(invisible.revision == 1)
		#expect(invisible.changedRegions.isEmpty)

		// a commit the body renders: exactly the one region moved.
		loop.store.commit { $0.shown += 1 }
		let visible = try #require(loop.patch(in: context))
		#expect(visible.revision == 2)
		#expect(visible.changedRegions == [RegionID(rawValue: "body")])
		#expect(visible.html.contains("shown 1"))
	}

	/// two callers must never interlace passes over one session — the second
	/// coalesces into the pass in flight instead of minting the same ids again.
	@Test("a second renderer coalesces into the pass in flight")
	func concurrentRenderCoalesces() throws {
		let slot = CoalesceSlot()
		let loop = StatefulPageSession(ReentrantPage(slot: slot))
		slot.loop.withLock { $0 = loop }

		_ = try #require(
			loop.patch(in: RenderContext(router: EventRouter(), session: RenderSessionID("b2-coalesce")))
		)
		#expect(slot.inner.withLock { $0 } == true, "the nested call must coalesce, not render")
		#expect(loop.lastRender != nil)
	}

	/// outside a state-bound render a control still renders identical bytes and
	/// still registers; firing it is loud and harmless rather than a crash.
	@Test("a control rendered outside a state loop degrades loudly")
	func unboundControlDegrades() async {
		let router = EventRouter()
		let session = RenderSessionID("b2-unbound")
		let html = RenderContext.$current.withValue(RenderContext(router: router, session: session)) {
			CounterPage().body(CounterPage.State()).markup.html
		}
		#expect(html.contains("data-component-id=\"c0\""))

		let fragments = await router.handle(EventData(component: "c0", event: .click), in: session)
		#expect(fragments.isEmpty)
	}
}

// MARK: - b3: session stores

@Suite("design b — session stores")
struct DesignBSessionStoresTests {
	private func key(_ byte: UInt8) -> SessionKey { SessionKey(hash: [byte]) }

	/// b3's first gate: two sessions' counters never cross.
	@Test("two sessions' counters never cross")
	func sessionsDoNotCross() throws {
		let registry = SessionStores(maxSessions: 8)
		let first = key(1)
		let second = key(2)

		let firstStore = try #require(registry.resolve(for: first) { Tally() }.store)
		let secondStore = try #require(registry.resolve(for: second) { Tally() }.store)

		firstStore.commit { $0.count += 3 }
		secondStore.commit { $0.count += 1 }

		#expect(firstStore.read().count == 3)
		#expect(secondStore.read().count == 1)
		#expect(firstStore !== secondStore)

		// resolving again hands back the same instance, not a fresh copy.
		let again = try #require(registry.resolve(for: first) { Tally() }.store)
		#expect(again === firstStore)
		#expect(again.read().count == 3)
	}

	/// b3's second gate: 300 sessions stay bounded, and it is the oldest *idle*
	/// ones that go.
	@Test("300 idle sessions stay bounded at the cap")
	func threeHundredSessionsStayBounded() {
		let registry = SessionStores(maxSessions: 256)
		var evicted: [SessionKey] = []

		for index in 0..<300 {
			let session = SessionKey(hash: [UInt8(index % 256), UInt8(index / 256)])
			evicted.append(contentsOf: registry.resolve(for: session) { Tally() }.evicted)
		}

		#expect(registry.count == 256)
		#expect(evicted.count == 44)
		// the survivors are the newest 256: the first 44 inserted were reaped.
		for index in 0..<44 {
			let gone = SessionKey(hash: [UInt8(index % 256), UInt8(index / 256)])
			#expect(registry.existing(for: gone, as: Tally.self) == nil)
		}
		for index in 44..<300 {
			let kept = SessionKey(hash: [UInt8(index % 256), UInt8(index / 256)])
			#expect(registry.existing(for: kept, as: Tally.self) != nil)
		}
	}

	/// §14 n14, binding: pressure never reaps a live incumbent. "oldest" means
	/// oldest idle, and a live session at the cap keeps its store while the cap
	/// is exceeded — the honest bound is on *reapable* state.
	@Test("a live session is never reaped, however old")
	func liveSessionSurvivesPressure() throws {
		let registry = SessionStores(maxSessions: 2)
		let live = key(99)
		let liveStore = try #require(registry.resolve(for: live) { Tally() }.store)
		registry.markLive(live)

		for index in 0..<10 {
			_ = registry.resolve(for: key(UInt8(index))) { Tally() }
		}

		#expect(registry.isLive(live))
		#expect(
			registry.existing(for: live, as: Tally.self) === liveStore,
			"the oldest session survives because its socket is open"
		)
		#expect(registry.count <= registry.maxSessions)

		// once the socket closes it is reapable again: the next insert reaps it.
		registry.markClosed(live)
		_ = registry.resolve(for: key(50)) { Tally() }
		#expect(registry.existing(for: live, as: Tally.self) == nil)
	}

	/// one session key, one state type: a different type is refused rather than
	/// silently replacing a live page's store.
	@Test("a store of the wrong state type is refused, not replaced")
	func wrongStateTypeIsRefused() throws {
		let registry = SessionStores(maxSessions: 4)
		let session = key(7)
		let original = try #require(registry.resolve(for: session) { Tally() }.store)

		let other = registry.resolve(for: session) { 0 }
		#expect(other.store == nil)
		#expect(registry.existing(for: session, as: Tally.self) === original)
	}
}

// MARK: - b4: observation

@Suite("design b — observation")
struct DesignBObservationTests {
	/// b4's gate: a mutation from a detached task reaches a connected page within
	/// one patch.
	@Test("a detached mutation reaches a connected page in one patch")
	func detachedMutationPatchesOnce() async throws {
		let router = EventRouter()
		let session = RenderSessionID("b4-detached")
		let context = RenderContext(router: router, session: session)
		let loop = StatefulPageSession(CounterPage())
		let sink = Mutex<[PagePatch]>([])

		let subscription = PageSubscription(to: loop, in: context) { patch in
			sink.withLock { $0.append(patch) }
		}
		let sessionKey = SessionKey(hash: [42])
		#expect(subscription.connect(for: sessionKey))

		// a first render, so the page has bytes to diff against.
		_ = loop.patch(in: context)

		let store = loop.store
		await Task.detached {
			store.commit { $0.count += 1 }
		}.value

		let patches = sink.withLock { $0 }
		#expect(patches.count == 1)
		let patch = try #require(patches.first)
		#expect(patch.revision == 1)
		#expect(patch.changedRegions == [RegionID(rawValue: "body")])
		#expect(patch.html.contains("count 1"))
	}

	/// an out-of-order delivery is dropped: a client that already has revision 2
	/// must not be re-sent revision 1's bytes.
	@Test("a stale observation is dropped")
	func staleObservationIsDropped() {
		let loop = StatefulPageSession(CounterPage())
		let context = RenderContext(router: EventRouter(), session: RenderSessionID("b4-stale"))
		let sink = Mutex<[PagePatch]>([])
		let subscription = PageSubscription(to: loop, in: context) { patch in
			sink.withLock { $0.append(patch) }
		}

		subscription.stateDidChange(revision: 2, session: SessionKey(hash: [1]))
		subscription.stateDidChange(revision: 1, session: SessionKey(hash: [1]))

		#expect(sink.withLock { $0 }.count == 1)
	}

	/// the observer cap is a refusal the caller sees, never a silent drop.
	@Test("the observer cap refuses rather than dropping silently")
	func observerCapRefuses() {
		let store = Store(Tally(), maxObservers: 1)
		let first = RecordingObserver()
		let second = RecordingObserver()

		#expect(store.observe(first, session: SessionKey(hash: [1])))
		#expect(store.observe(second, session: SessionKey(hash: [2])) == false)
		#expect(store.observedSessions == [SessionKey(hash: [1])])
	}

	/// one observer per session: re-registering replaces, so a reconnect does not
	/// accumulate sinks for one page.
	@Test("re-registering a session replaces its observer")
	func reregisterReplaces() {
		let store = Store(Tally(), maxObservers: 4)
		let first = RecordingObserver()
		let second = RecordingObserver()
		let session = SessionKey(hash: [3])

		#expect(store.observe(first, session: session))
		#expect(store.observe(second, session: session))

		store.commit { $0.count += 1 }
		#expect(first.observations.withLock { $0 }.isEmpty)
		#expect(second.observations.withLock { $0 }.count == 1)
	}
}

/// a sink that records the observations it is handed.
private final class RecordingObserver: StateObserver, Sendable {
	let observations = Mutex<[StateObservation]>([])

	func stateDidChange(revision: UInt64, session: SessionKey) {
		observations.withLock { $0.append(StateObservation(revision: revision, session: session)) }
	}
}
