import WebUICore
import Synchronization

// MARK: - Observation
//
// what a committed mutation tells the host. the store is the one writer, and
// this is the only notification door, so "state changed and no page heard about
// it" cannot happen through a store: `commit` notifies on the same call path,
// after the lock is released.
//
// `StateObservation` is the value an observer records rather than two loose
// arguments — a revision and the session it belongs to are one fact, and a
// subscription that keeps it can drop a stale delivery (a racing commit may
// notify out of order; revisions are monotonic, so the comparison is exact).

/// one committed change, as a value.
public struct StateObservation: Sendable, Equatable {
	/// the revision the store reached.
	public let revision: UInt64
	/// the session the observing page belongs to.
	public let session: SessionKey

	public init(revision: UInt64, session: SessionKey) {
		self.revision = revision
		self.session = session
	}
}

/// notifies after a mutation commits. the host uses it to re-render and patch.
///
/// makes unrepresentable: "state changed and no page heard about it" — the only
/// mutation door emits on the same call path.
public protocol StateObserver: Sendable {
	func stateDidChange(revision: UInt64, session: SessionKey)
}

// MARK: - Page subscription
//
// the observer a page's render loop registers: one committed mutation becomes at
// most one patch. this is B4's shape — a mutation from a detached task reaches a
// connected page without the mutator knowing a page exists.
//
// a store may be notified from any task, so `stateDidChange` renders on the
// mutating thread. that is safe by construction: `Store` notifies after
// releasing its lock, and the render reads the store through `read()` (a fresh
// lock acquisition). the cost is that a slow page render delays the mutator —
// the coarse-invalidation tradeoff §6.7 chose.

/// a page's connection to its store: a commit becomes one patch, in order.
public final class PageSubscription<Page: StatefulPage>: StateObserver, Sendable {
	/// the page loop this subscription patches.
	private let loop: StatefulPageSession<Page>
	/// the render context (router + session) the patches are rendered under.
	private let context: RenderContext
	/// where a patch goes: a websocket write, a test sink, a log.
	private let push: @Sendable (PagePatch) -> Void
	/// the last observation delivered, so an out-of-order notification is dropped
	/// instead of re-rendering bytes a client already has.
	private let lastPushed = Mutex<StateObservation?>(nil)

	public init(
		to loop: StatefulPageSession<Page>,
		in context: RenderContext,
		push: @escaping @Sendable (PagePatch) -> Void
	) {
		self.loop = loop
		self.context = context
		self.push = push
	}

	/// register with the loop's store for `session`.
	///
	/// returns false when the store is at its observer cap — the caller decides
	/// what to do (the host answers with a failure page); nothing is dropped
	/// silently.
	@discardableResult
	public func connect(for session: SessionKey) -> Bool {
		loop.store.observe(self, session: session)
	}

	/// stop delivering to this subscription.
	@discardableResult
	public func disconnect(from session: SessionKey) -> Bool {
		loop.store.removeObserver(session: session)
	}

	public func stateDidChange(revision: UInt64, session: SessionKey) {
		let observation = StateObservation(revision: revision, session: session)
		let fresh = lastPushed.withLock { last -> Bool in
			guard revision > (last?.revision ?? 0) else { return false }
			last = observation
			return true
		}
		guard fresh else { return }
		// a pass already in flight on this loop re-reads the revision before it
		// commits its bytes, so a coalesced notification needs no patch of its
		// own: the in-flight pass ships the newer state.
		guard let patch = loop.patch(in: context) else { return }
		push(patch)
	}
}
