// MARK: - State ports
//
// the seam between a page and the state it renders — shapes only. stage 0
// declares it so later stages can conform it without editing the render core
// again; nothing here stores, locks, or schedules anything.
//
// the shape says three things:
// 1. a store owns exactly one `State` value that it can hand out;
// 2. a mutation runs with exclusive access to that state and may throw, so a
//    rejected write is a value the caller sees rather than a silent no-op;
// 3. every accepted mutation moves `revision` forward, which is what lets a
//    render decide whether its output is still current.
//
// `State` is `Sendable` because a read crosses tasks; the mutating closure is
// `@Sendable` for the same reason.

/// the owned state one page instance renders from.
///
/// a conformer is the store, not a cache: `read()` returns the committed value,
/// `mutate` is the only way it changes, and `revision` is the monotonic counter
/// that names which value a render saw.
public protocol StateStore<State> {
	/// the value a page renders from.
	associatedtype State: Sendable

	/// the committed state, without mutating it.
	func read() -> State

	/// run `body` with exclusive access to the state. a throw propagates to the
	/// caller and must not bump `revision` — a rejected mutation is not a
	/// committed one.
	func mutate<R>(_ body: @Sendable (inout State) throws -> R) throws -> R

	/// monotonic counter, bumped once per accepted mutation.
	var revision: UInt64 { get }
}
