import WebUICore
import Synchronization

// MARK: - Session stores
//
// the per-session registry: one store per `(page, session)`, resolved by
// `SessionKey`, bounded.
//
// reference semantics are the point (§6.4): one registry, many sessions and tabs
// resolving the same store through the same key — a struct registry would copy
// the table per caller and fork the state it exists to share.
//
// eviction obeys §7.2 rule 3 and §14 N14, which is the settled reading of this
// plan's two conflicting sentences: **a live session is never reaped**. "oldest"
// means oldest *idle* — a session whose last socket closed. a live incumbent at
// the cap is refused by policy (design C answers 503); the registry keeps it, so
// the cap bounds *reapable* state rather than pages someone is looking at. when
// every over-cap session is live the table stays above the cap, which is the
// honest outcome and the same one `EventRouter.evict` produces.
//
// makes unrepresentable: "two sessions share a counter" — a store is keyed by
// session, and a store of the wrong state type is refused rather than replaced,
// so a caller can never silently fork or alias another session's state.

/// one store per session, bounded, with idle-only eviction.
public final class SessionStores: Sendable {
	/// one registration: the tick that orders it, and the (type-erased) store.
	private struct Entry: Sendable {
		let tick: UInt64
		let store: any AnyObject & Sendable
	}

	/// one entry in the recency list; a stale tick marks a superseded row.
	private struct Row: Sendable {
		let key: SessionKey
		let tick: UInt64
	}

	private struct Values: Sendable {
		var entries: [SessionKey: Entry] = [:]
		var order: [Row] = []
		var live: Set<SessionKey> = []
		var clock: UInt64 = 0
	}

	/// the cap on **idle** stores. live sessions are never reaped to honour it.
	public let maxSessions: Int

	private let values: Mutex<Values>

	public init(maxSessions: Int = 1_024) {
		self.maxSessions = maxSessions
		self.values = Mutex(Values())
	}

	// MARK: resolving

	/// what one resolve produced: the session's store, and the idle stores the
	/// insert reaped (the caller ends those router sessions too).
	public struct Resolution<State: Sendable>: Sendable {
		/// the session's store, or nil when the session holds a store of a
		/// different state type.
		public let store: Store<State>?
		/// idle sessions this resolve reaped to hold the cap.
		public let evicted: [SessionKey]
	}

	/// the store for `session`, created from `initial` on first use, and the idle
	/// stores the insert reaped.
	///
	/// a nil store means the session already holds a store of a different state
	/// type. that is a caller bug (one session key, one page), and replacing the
	/// store would silently drop a live page's state, so the refusal is visible.
	public func resolve<State: Sendable>(
		for session: SessionKey,
		initial: @Sendable () -> State
	) -> Resolution<State> {
		values.withLock { values -> Resolution<State> in
			values.clock &+= 1
			if let entry = values.entries[session] {
				guard let existing = entry.store as? Store<State> else {
					return Resolution(store: nil, evicted: [])
				}
				values.entries[session] = Entry(tick: values.clock, store: existing)
				values.order.append(Row(key: session, tick: values.clock))
				return Resolution(store: existing, evicted: [])
			}
			let fresh = Store(initial())
			values.entries[session] = Entry(tick: values.clock, store: fresh)
			values.order.append(Row(key: session, tick: values.clock))
			return Resolution(store: fresh, evicted: Self.reapIdle(&values, cap: maxSessions))
		}
	}

	/// the store `session` already holds, or nil.
	///
	/// the state type is an explicit argument rather than inferred: a caller
	/// asking "is there a store for this session" must say which store it means,
	/// so a typo cannot read as "no store".
	public func existing<State: Sendable>(
		for session: SessionKey,
		as _: State.Type
	) -> Store<State>? {
		values.withLock { $0.entries[session]?.store as? Store<State> }
	}

	// MARK: liveness

	/// mark `session`'s socket open: eviction must not reap a page still on
	/// screen.
	public func markLive(_ session: SessionKey) {
		values.withLock { _ = $0.live.insert(session) }
	}

	/// mark `session`'s last socket closed, so it becomes reapable again.
	///
	/// the store is not dropped here — ending a session is a lifecycle decision
	/// (``remove(_:)``), not a liveness one.
	public func markClosed(_ session: SessionKey) {
		values.withLock { _ = $0.live.remove(session) }
	}

	public func isLive(_ session: SessionKey) -> Bool {
		values.withLock { $0.live.contains(session) }
	}

	// MARK: accounting

	/// how many stores the registry holds — live ones included.
	public var count: Int {
		values.withLock { $0.entries.count }
	}

	/// how many of them belong to open sockets.
	public var liveCount: Int {
		values.withLock { $0.live.count }
	}

	/// the keys the registry holds, oldest first.
	public var sessions: [SessionKey] {
		values.withLock { $0.entries.keys.sorted { $0.hash.lexicographicallyPrecedes($1.hash) } }
	}

	/// drop `session`'s store. returns whether one was registered.
	@discardableResult
	public func remove(_ session: SessionKey) -> Bool {
		values.withLock { values in
			values.live.remove(session)
			return values.entries.removeValue(forKey: session) != nil
		}
	}

	/// reap idle stores until the cap holds. returns the evicted keys so the
	/// caller can end those router sessions too.
	///
	/// dropping a store detaches *this* registry's reference only: a control's
	/// handler registered in the router captured the store's binding, so the
	/// store lives until that render session ends. ending the session
	/// (`EventRouter.end`) is the caller's step, and the evicted keys are
	/// returned for exactly that — a reaped store whose session still routes is
	/// a leak the registry cannot see.
	@discardableResult
	public func reapIdle() -> [SessionKey] {
		values.withLock { Self.reapIdle(&$0, cap: maxSessions) }
	}

	// MARK: the reaper

	/// drop least-recently-used **idle** sessions until the cap holds.
	///
	/// the walk is `EventRouter.evict`'s, for the same reasons: a stale row (the
	/// session was used again after this row was appended) is skipped because the
	/// newer row speaks for it, and a live session is kept however old it is.
	private static func reapIdle(_ values: inout Values, cap: Int) -> [SessionKey] {
		guard values.entries.count > cap else { return [] }
		var evicted: [SessionKey] = []
		var kept: [Row] = []
		kept.reserveCapacity(values.order.count)
		for row in values.order {
			guard let entry = values.entries[row.key], entry.tick == row.tick else { continue }
			if values.entries.count <= cap || values.live.contains(row.key) {
				kept.append(row)
				continue
			}
			values.entries.removeValue(forKey: row.key)
			evicted.append(row.key)
		}
		values.order = kept
		return evicted
	}
}
