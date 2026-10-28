import WebUICore
import Synchronization

// MARK: - the consumer-facing differ
//
// a page's whole diff tail in one value: the baseline it compares against, the
// exclusions it honours, the transition flag it stamps, and the root replace it
// falls back to. a consumer holds one of these per page instance and calls
// `messages(forMarkup:root:)` after every render — it never builds a
// `RenderSnapshot`, never keeps a `RenderBaseline` and never decides when a
// patch is impossible.
//
// the policy is stated once, at construction, and travels into every snapshot
// this type derives: exclusion is a property of the *render* (it changes which
// hashes exist), so a differ that dropped it would silently re-ship every
// token-owned subtree. `PageDiffer` carries it; `RenderSnapshot` applies it.

/// the diff a page instance is served from: one baseline, one policy, one
/// answer per render.
///
/// `messages(forMarkup:root:)` returns `[FragmentUpdate]` — the frames to put
/// on the wire — and an empty array means "nothing moved". the baseline is
/// advanced by *every* call, so a caller can render as often as it likes and
/// the diff always describes the last render it was shown.
///
/// a differ is safe to call from any thread: the baseline is guarded, and one
/// call's read-diff-write is atomic with respect to another's, so two renders
/// can never be diffed against the same baseline.
public final class PageDiffer: Sendable {
	/// what survives between two renders: hashes only, never the html.
	private struct State: Sendable {
		var baseline: RenderBaseline?
	}

	/// how every render is scanned and diffed, and what the transition flag on
	/// each frame carries. fixed at construction: a policy that moved between
	/// renders would compare hashes derived under two different rules.
	private let policy: RegionPolicy
	/// the baseline, guarded. `Mutex` rather than an `actor` because the calls
	/// are synchronous: a render is a pure function of state and must answer
	/// its frames without suspending, so a consumer's send path never becomes
	/// async just to ask what changed.
	private let loop = Mutex(State())

	/// a differ for one page instance.
	///
	/// `.default` is the coarse contract — `data-component-id` regions, a
	/// changed parent carrying its children, an insertion a full page. a
	/// streaming page states `.finest` with its token-owned spans excluded.
	public init(policy: RegionPolicy = .default) {
		self.policy = policy
	}

	/// declare what the client already holds — the page just served — so the
	/// first patch is minimal instead of a whole-root replace.
	///
	/// call this after a full page has been delivered by some other path (the
	/// initial HTTP response, a reload, a reconnect). without it the first
	/// `messages(forMarkup:root:)` answers a full page, because a differ that
	/// has never seen a render has nothing to compare against.
	public func seed(withMarkup markup: String) {
		let snapshot = RenderSnapshot.derived(fromMarkup: markup, policy: policy)
		loop.withLock { state in
			state.baseline = snapshot.baseline
		}
	}

	/// the frames to send for this render; empty means "nothing moved".
	///
	/// `markup` is the **root element's own markup**, not a document: the
	/// returned frame replaces element `root` with exactly these bytes. a
	/// caller holding a full document must pass the root element's markup (the
	/// `<body>`'s contents, an `#app` subtree) — passing the document would
	/// replace `#app` with a whole `<html>…</html>` and nest a page inside a
	/// page.
	///
	/// `root` is the id the client resolves with `getElementById`; it is used
	/// only when the answer is a whole-root replace, because that is the one
	/// frame the differ has to name itself.
	///
	/// the baseline advances on every call, including the one that returns
	/// `[]`: a baseline left at the previous render would re-ship this render's
	/// bytes as a change next time, so a page whose renders alternate between
	/// two steady states would ship twice as much as it needs to.
	public func messages(forMarkup markup: String, root: String) -> [FragmentUpdate] {
		// the scan is the expensive half and needs no state, so it runs outside
		// the lock; only the read-diff-write pair has to be atomic.
		let snapshot = RenderSnapshot.derived(fromMarkup: markup, policy: policy)
		return loop.withLock { state -> [FragmentUpdate] in
			let patch = RenderDiffer(previous: state.baseline, policy: policy).patch(snapshot)
			state.baseline = snapshot.baseline
			guard patch.isFullPage else { return patch.changed }
			// a first render, a change outside every region, or a region that
			// vanished: only the whole root can put those bytes on screen. the
			// transition flag is stated explicitly here — `nil` would leave the
			// client's policy in charge, which is what `.default` asks for.
			return [FragmentUpdate(id: root, html: markup, transition: policy.transition)]
		}
	}

	/// forget the baseline, so the next render is a whole-root replace.
	///
	/// for a client that may have lost frames (a reconnect, a navigated-away
	/// tab): the server can no longer assume what the client holds, and
	/// resending a page is always safe where guessing is not.
	public func reset() {
		loop.withLock { state in
			state.baseline = nil
		}
	}
}
