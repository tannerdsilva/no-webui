// MARK: - State render scope
//
// the seam between a render and the state it renders for. `WebUIState` owns the
// store and depends on this target, so the door a control's modifier calls has
// to be declared here, without naming the store: a `StateBinding<State>` carries
// the one operation a handler is allowed — `mutate` — and nothing else.
//
// the binding is typed, not erased. `State` is the page's own state type, so a
// handler closure's parameter is that type and the compiler checks the write.
// the ambient value is a task-local rather than a `RenderContext` field because
// `StatefulPage.body(_:)` receives its state *by value*: a control inside the
// body can only reach the store through the environment the render pass
// installed, and a task-local nests correctly with fragment renders and needs no
// change to `RenderContext`'s stored shape.
//
// makes unrepresentable: "the handler writes markup" — a binding has no html
// door at all; and "the handler awaits" — `mutate` is synchronous by signature,
// which is the same constraint `StateStore` states (a render body cannot await).

/// the type-erased shape of a binding: enough for a task-local to carry one
/// without naming the state it is bound to.
public protocol AnyStateBinding: Sendable {
	/// the store's revision when this binding was made.
	var revision: UInt64 { get }
}

/// a typed door to the store one render is bound to.
///
/// `commit` runs the mutation through the store's own door, so the revision bump
/// and the observer notification happen exactly where every other write happens:
/// a binding cannot produce a change no observer hears about.
public struct StateBinding<State: Sendable>: AnyStateBinding {
	/// the store's revision when this binding was handed out — what a render
	/// that used it was looking at.
	public let revision: UInt64

	private let commit: @Sendable (@Sendable (inout State) -> Void) -> Void

	public init(
		revision: UInt64,
		commit: @escaping @Sendable (@Sendable (inout State) -> Void) -> Void
	) {
		self.revision = revision
		self.commit = commit
	}

	/// apply `body` to the live state and commit the result.
	///
	/// synchronous and non-throwing on purpose: a control's mutation is a short
	/// `inout` write, and a handler that could throw would need an error page the
	/// modifier has no way to render. use `Store.mutate` when the write must be
	/// rejectable.
	public func mutate(_ body: @Sendable (inout State) -> Void) {
		commit(body)
	}
}

/// the state binding the current render pass is bound to.
public enum StateRenderScope {
	/// the binding installed by a host's render loop, or nil outside a
	/// state-bound render.
	@TaskLocal public static var current: (any AnyStateBinding)?

	/// the ambient binding as its concrete state type, or nil when this render
	/// is not bound to a store of that state type.
	public static func binding<State: Sendable>(of _: State.Type) -> StateBinding<State>? {
		current as? StateBinding<State>
	}
}
