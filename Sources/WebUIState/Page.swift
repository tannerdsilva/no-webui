import WebUICore
import Synchronization

// MARK: - Stateful page
//
// a page as a pure function of state. the body receives the only state it may
// see, so "a page body reads a mutable global" is unrepresentable: the type
// system carries the state, and the render loop hands it over by value.
//
// the loop itself (``StatefulPageSession``) is the render → revision-check →
// re-render shape: render once, compare the store's revision to the one the pass
// started from, and render again only when a commit raced the pass. that keeps
// the bytes a client receives consistent with a committed revision without
// storing any previous html.

/// a page as a pure function of state.
public protocol StatefulPage: Sendable {
	associatedtype State: Sendable
	associatedtype Body: View

	/// the state a fresh page instance starts from — the host seeds its store
	/// with this, once.
	func initialState() -> State

	/// the page, rendered from `state`.
	func body(_ state: State) -> Body
}

extension StatefulPage {
	/// the store this render is bound to, as a typed door.
	///
	/// nil outside a state-bound render (a fragment re-render, a bare
	/// `.markup`), which is what lets a control's handler degrade loudly instead
	/// of mutating a store nobody observes.
	public var binding: StateBinding<State>? {
		StateRenderScope.binding(of: State.self)
	}
}

/// a mutation a control may perform. the handler names intent, not markup.
public struct Mutation<State: Sendable>: Sendable {
	public let apply: @Sendable (inout State) -> Void

	public init(_ apply: @escaping @Sendable (inout State) -> Void) {
		self.apply = apply
	}
}

// MARK: - Renders and patches

/// one render of a page: the bytes, the revision they were rendered from, and
/// whether a commit raced the pass.
///
/// `package`, not `public`: nothing outside this module reads it. the wire door
/// a host drives is ``PagePatch`` — the loop's whole-page render is the settling
/// step that produces it, and the package door keeps a type with no consumer off
/// the frozen surface.
package struct PageRender: Sendable {
	/// the page's html for this revision.
	package let html: String
	/// the revision the bytes were rendered from.
	package let revision: UInt64
	/// how many passes the loop spent settling; 1 when nothing raced.
	package let passes: Int
	/// false when `maxRenderPasses` ran out with the store still moving — the
	/// bytes are honest about a revision, but a newer one already exists.
	package let settled: Bool
	/// per-region hashes of this render, for the next patch's comparison.
	package let digest: RenderDigest
}

/// the bytes that moved since a page's previous render: at most one per call.
public struct PagePatch: Sendable {
	/// the page's html at ``revision``.
	///
	/// always the whole page, so a caller whose change ``fragments`` cannot
	/// express (a first render, a value outside every control) has the bytes it
	/// needs without a second render.
	public let html: String
	public let revision: UInt64
	/// region ids whose bytes moved, sorted by id.
	///
	/// the loop's own mark, not the scan: this is the digest the render buffer
	/// recorded, which is one region for the whole body. it stays because a
	/// caller that predates ``fragments`` reads it; the per-control ids that can
	/// actually be patched are ``fragments``'.
	public let changedRegions: [RegionID]
	/// the per-control bytes that moved, in byte order.
	///
	/// one entry per element carrying `data-component-id` whose bytes moved, and
	/// nothing for a change the wire cannot express: a first render, a value
	/// outside every control (the differ's `residue`), or a control that
	/// appeared or vanished. ``html`` is the answer in every one of those cases,
	/// which is why it is never absent.
	public let fragments: [FragmentUpdate]
	/// true for a page's first render: there is no previous render to compare.
	///
	/// it is not the fragment verdict. ``fragments`` is empty whenever the whole
	/// page must be sent, and ``html`` always is that page — a caller that only
	/// needs to know whether it can patch reads `fragments.isEmpty`.
	public let isFullPage: Bool
	/// the passes the loop spent settling this patch.
	public let passes: Int
}

// MARK: - The render loop

/// one page instance bound to one store: the loop a host drives.
///
/// `patch(in:)` is what a host calls after an interaction or a background
/// mutation. it renders, diffs the region digest against the previous render,
/// and describes what moved — one patch for one committed revision, no handler
/// authoring a fragment.
///
/// the loop begins the router session itself (restarting its mint counters) on
/// every pass, so a caller must not wrap the call in `EventRouter.begin` and
/// registrations made *outside* a render pass are not preserved — the page body
/// is the only thing that registers, and a re-render re-registers it under the
/// same ids.
public final class StatefulPageSession<Page: StatefulPage>: Sendable {
	public let page: Page
	public let store: Store<Page.State>
	/// how many render passes the loop may spend settling one render. a mutation
	/// that keeps racing the render (a hot background writer) is bounded here
	/// rather than looping forever; `PageRender.settled` says which happened.
	public let maxRenderPasses: Int

	private struct Loop: Sendable {
		var previous: PageRender?
		/// what the next patch's fragment diff compares against: one hash per
		/// region plus the residue hash. never the page's bytes — a session's
		/// diff state is 8 bytes per region, which is the whole reason a patch
		/// can be built without keeping the previous page.
		var baseline: RenderBaseline?
		/// true while a pass is settling on some thread. a second caller
		/// coalesces into that pass instead of interlacing with it: two passes
		/// over one session would mint the same component ids twice and register
		/// the second pass's handlers over the first's.
		var rendering = false
	}

	private let loop = Mutex(Loop())

	/// the coarse mark the render buffer records around the whole body.
	///
	/// it is not the wire's region set: ``patch(in:)`` derives one region per
	/// `data-component-id` element from the finished bytes. this mark is what
	/// ``PagePatch/changedRegions`` reports, kept for a caller written against
	/// the digest the buffer records.
	private static var bodyRegion: RegionID { RegionID(rawValue: "body") }

	public init(
		_ page: Page,
		store: Store<Page.State>,
		maxRenderPasses: Int = 3
	) {
		self.page = page
		self.store = store
		self.maxRenderPasses = maxRenderPasses
	}

	/// a session whose store is seeded from ``StatefulPage/initialState()``.
	public convenience init(_ page: Page, maxRenderPasses: Int = 3) {
		self.init(page, store: Store(page.initialState()), maxRenderPasses: maxRenderPasses)
	}

	/// the most recent render this loop produced.
	package var lastRender: PageRender? {
		loop.withLock { $0.previous }
	}

	/// render the page, settling against the store's revision.
	///
	/// returns nil when another thread is already rendering this page. that is
	/// coalescing, not a failure: the pass in flight re-reads the revision after
	/// rendering (the settle loop), so the bytes it produces already include this
	/// caller's commit and there is nothing for a second pass to add.
	///
	/// `package`: the consumer-facing door is ``patch(in:)``, which carries the
	/// same bytes plus the fragments. this one exists for the settling step and
	/// for a caller inside the package that only wants the render.
	@discardableResult
	package func render(in context: RenderContext) -> PageRender? {
		guard claimRender() else { return nil }
		let rendered = renderSettled(in: context)
		// the same scan a patch takes, so "the last render" means one thing
		// whichever door produced it: a render followed by a patch diffs against
		// this render, not against nothing.
		let baseline = RenderSnapshot.derived(fromMarkup: rendered.html).baseline
		loop.withLock { state in
			state.previous = rendered
			state.baseline = baseline
			state.rendering = false
		}
		return rendered
	}

	/// render the page and describe what moved since the previous render.
	///
	/// one call, one patch: the loop renders at most `maxRenderPasses` times to
	/// settle, then derives the page's regions from the finished bytes and diffs
	/// them against the baseline this session keeps. the regions are the elements
	/// carrying `data-component-id` — the same scan the server runs — so a
	/// control's change ships as that control's bytes and nothing else. nil when
	/// another pass is already in flight — see ``render(in:)``.
	@discardableResult
	public func patch(in context: RenderContext) -> PagePatch? {
		guard claimRender() else { return nil }
		let (before, prior) = loop.withLock { ($0.previous, $0.baseline) }
		let rendered = renderSettled(in: context)
		let snapshot = RenderSnapshot.derived(fromMarkup: rendered.html)
		let moved = RenderDiffer(previous: prior).patch(snapshot)
		loop.withLock { state in
			state.previous = rendered
			state.baseline = snapshot.baseline
			state.rendering = false
		}
		return PagePatch(
			html: rendered.html,
			revision: rendered.revision,
			changedRegions: Self.changed(from: before?.digest, to: rendered.digest),
			fragments: moved.changed,
			isFullPage: before == nil,
			passes: rendered.passes
		)
	}

	/// take the loop's render claim, or false when one is already in flight.
	///
	/// the claim is taken *before* the render and released *after* the pass is
	/// stored, so a mutation that arrives mid-render either coalesces here or is
	/// caught by the settle loop's revision check — never interlaced.
	private func claimRender() -> Bool {
		loop.withLock { state in
			guard !state.rendering else { return false }
			state.rendering = true
			return true
		}
	}

	// MARK: the loop

	/// render → revision check → re-render, bounded by `maxRenderPasses`.
	private func renderSettled(in context: RenderContext) -> PageRender {
		var passes = 0
		while true {
			passes += 1
			// restart the session's mint counters so a re-render of the same page
			// reuses the ids the first pass registered. that is what keeps a
			// patch's controls routing to the handlers the page built, and it is
			// why one click is one patch rather than a re-registration storm.
			context.router.begin(context.session)
			let state = store.read()
			let revision = store.revision
			let binding = store.binding
			var buffer = HTMLBuffer()
			let mark = buffer.beginRegion(Self.bodyRegion)
			StateRenderScope.$current.withValue(binding) {
				RenderContext.$current.withValue(context) {
					page.body(state).render(into: &buffer)
				}
			}
			buffer.endRegion(Self.bodyRegion, from: mark)
			let rendered = PageRender(
				html: buffer.finish(),
				revision: revision,
				passes: passes,
				settled: store.revision == revision,
				digest: buffer.renderDigest
			)
			if rendered.settled || passes >= maxRenderPasses {
				return rendered
			}
		}
	}

	/// region ids whose hash moved between two renders, sorted for determinism.
	private static func changed(from before: RenderDigest?, to after: RenderDigest) -> [RegionID] {
		guard let before else { return [] }
		var moved: [RegionID] = []
		for (id, hash) in after.regions where before.regions[id] != hash {
			moved.append(id)
		}
		for id in before.regions.keys where after.regions[id] == nil {
			moved.append(id)
		}
		return moved.sorted { $0.rawValue < $1.rawValue }
	}
}
