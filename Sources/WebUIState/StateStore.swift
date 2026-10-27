import WebUICore
import Synchronization

// MARK: - Store
//
// one page instance's committed state, synchronously readable.
//
// `Store` is a final class over a `Mutex`, not an actor, for the reason the port
// states: render is synchronous (`func render(into buffer: inout HTMLBuffer)`,
// and `View` is not async), so a store an actor held could not be read from a
// render body without `await`. the lock is the serialization mechanism, and the
// type system sees it — the payload is `Sendable`, so the class declares plain
// `Sendable` with no `@unchecked` anywhere.
//
// reference semantics are the point (and the heap justification §6.4 gives): the
// router handler, the render body and a background task must all observe the
// same mutations through aliases, and a struct copy would silently fork state.
//
// makes unrepresentable: "two writers race" (mutation is the only write door and
// it is serialized), "a page renders a half-applied mutation" (a mutation is
// atomic against readers), "a mutation that awaits" (the body is `@Sendable` and
// synchronous — there is no `await` in a lock), and "state changed and no
// observer heard about it" (the one write door notifies after the commit).

/// one page instance's state, mutated only through ``commit(_:)``/``mutate(_:)``.
public final class Store<State: Sendable>: StateStore, Sendable {
	/// one observer registration: the session it speaks for, and the sink.
	private struct Registration: Sendable {
		let session: SessionKey
		let observer: any StateObserver
	}

	private struct Values: Sendable {
		var state: State
		var revision: UInt64 = 0
		var observers: [Registration] = []
	}

	private let values: Mutex<Values>

	/// how many observers one store carries. a page has one (its loop), so the
	/// default is small on purpose: the cap makes a leak a rejected registration
	/// (`observe` returns false) rather than an unbounded fan-out.
	public let maxObservers: Int

	public init(_ initial: State, maxObservers: Int = 8) {
		self.values = Mutex(Values(state: initial))
		self.maxObservers = maxObservers
	}

	// MARK: reading

	/// the committed state, without mutating it. synchronous by contract — a
	/// render body cannot await, which is why this type is not an actor.
	public func read() -> State {
		values.withLock { $0.state }
	}

	/// monotonic; bumped once per accepted mutation.
	public var revision: UInt64 {
		values.withLock { $0.revision }
	}

	// MARK: writing

	/// run `body` with exclusive access, commit the result and bump the revision.
	///
	/// a throw propagates and commits nothing: a rejected mutation is not a
	/// committed one, so neither the revision nor any observer sees it.
	public func mutate<R>(_ body: @Sendable (inout State) throws -> R) throws -> R {
		let outcome = try commitThrough(body)
		return outcome.value
	}

	/// commit a mutation that cannot fail — the door a control handler uses.
	///
	/// this is not a swallowing variant of ``mutate(_:)``: the body is
	/// non-throwing by signature, so there is no error to drop. the two share one
	/// commit path, so a store cannot grow a second way to write.
	@discardableResult
	public func commit(_ body: @Sendable (inout State) -> Void) -> UInt64 {
		let outcome = commitThrough(body)
		return outcome.revision
	}

	/// apply a described mutation — the value form of ``commit(_:)``.
	@discardableResult
	public func apply(_ mutation: Mutation<State>) -> UInt64 {
		commit(mutation.apply)
	}

	// MARK: binding

	/// the typed door a render pass hands its controls.
	///
	/// it commits through this store's own door, so a control's mutation bumps
	/// the revision and notifies exactly like any other write.
	public var binding: StateBinding<State> {
		StateBinding(revision: revision) { body in
			_ = self.commit(body)
		}
	}

	// MARK: observation

	/// register `observer` for `session`, replacing any observer already bound to
	/// that session (one page instance, one loop).
	///
	/// returns false when the store is at its observer cap: the caller decides
	/// what that means — nothing is dropped without the caller seeing it.
	@discardableResult
	public func observe(_ observer: any StateObserver, session: SessionKey) -> Bool {
		values.withLock { values in
			if let index = values.observers.firstIndex(where: { $0.session == session }) {
				values.observers[index] = Registration(session: session, observer: observer)
				return true
			}
			guard values.observers.count < maxObservers else { return false }
			values.observers.append(Registration(session: session, observer: observer))
			return true
		}
	}

	/// drop `session`'s observer. returns whether one was registered.
	@discardableResult
	public func removeObserver(session: SessionKey) -> Bool {
		values.withLock { values in
			let before = values.observers.count
			values.observers.removeAll { $0.session == session }
			return values.observers.count != before
		}
	}

	/// the sessions currently observing this store.
	public var observedSessions: [SessionKey] {
		values.withLock { $0.observers.map(\.session) }
	}

	// MARK: commit path

	/// the one write path: mutate a draft, bump, snapshot the observers, then
	/// notify *after* the lock is released.
	///
	/// the body writes into a copy of the state and the copy is swapped in only
	/// on success, so a throwing mutation commits nothing and no reader ever sees
	/// a half-applied write (a `State` that is a reference type would share the
	/// reference; the port asks for value semantics, and every consumer page's
	/// state is a struct).
	///
	/// notifying outside the lock is not an optimization: an observer renders,
	/// and a render reads the store, so notifying inside would deadlock on a
	/// non-recursive lock. the cost is that two racing commits may notify out of
	/// order — revisions are monotonic, so a subscriber compares revisions rather
	/// than trusting arrival order (``PageSubscription`` does exactly that).
	private func commitThrough<R>(
		_ body: @Sendable (inout State) throws -> R
	) rethrows -> (value: R, revision: UInt64) {
		let outcome = try values.withLock { values -> (R, UInt64, [Registration]) in
			var draft = values.state
			let value = try body(&draft)
			values.state = draft
			values.revision &+= 1
			return (value, values.revision, values.observers)
		}
		for registration in outcome.2 {
			registration.observer.stateDidChange(revision: outcome.1, session: registration.session)
		}
		return (outcome.0, outcome.1)
	}
}
