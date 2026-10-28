import Logging
import Synchronization
import WebUI
import WebUIServer
import WebUIAuth
import WebUIState

// MARK: - per-session pages
//
// the join `Package.swift` declared and no file used: `WebUIHost -> WebUIState`.
// the host owns one `SessionStores`, and every render pass is handed the store
// of the session that asked for it — so two signed-in people render the same
// page value against two stores, and one's mutation cannot move the other's.
//
// what the host adds above the registry is the *diff*: a `StatefulPageSession`
// per session, kept across passes, because the loop's `RenderBaseline` is the
// only thing that knows what the previous render looked like. the example
// rebuilt the loop on every pass, which is why every one of its patches was a
// full page: a fresh loop has no baseline, so `patch(in:)` answered
// `isFullPage` every time.
//
// makes unrepresentable: "a page ships the whole document for a one-control
// change" — a control's mutation runs through ``PageActions``, which commits
// and then renders the *same* loop in one call, so the bytes a socket receives
// are the ones the differ produced and not a second render's opinion.

// MARK: - what a render pass hands its controls

/// the type-erased shape of ``PageActions``: enough for a task-local to carry
/// one without naming the state it is bound to.
public protocol AnyPageActions: Sendable {
	/// the store's revision when these actions were made.
	var revision: UInt64 { get }
}

/// the door a control uses to mutate the page *and* ship what moved.
///
/// `StateBinding` commits and returns nothing, which is the right shape for a
/// page whose host re-renders it whole. a hosted page over a socket needs the
/// answer to be the patch itself — the server writes the fragments a handler
/// returns to the connection that sent the event, and nothing else — so this
/// value carries both halves: the commit and the render that follows it.
///
/// makes unrepresentable: "a control mutates state and the page never hears
/// about it" — there is no `mutate` without a patch on this door, and no patch
/// without the commit that caused it.
public struct PageActions<State: Sendable>: AnyPageActions, Sendable {
	/// the store's revision when this pass handed the actions out.
	public let revision: UInt64

	private let commit: @Sendable (@Sendable (inout State) -> Void) -> Void
	private let patch: @Sendable () -> [FragmentUpdate]

	public init(
		revision: UInt64,
		commit: @escaping @Sendable (@Sendable (inout State) -> Void) -> Void,
		patch: @escaping @Sendable () -> [FragmentUpdate]
	) {
		self.revision = revision
		self.commit = commit
		self.patch = patch
	}

	/// an event handler that mutates `State` and answers with the bytes the
	/// mutation moved.
	///
	/// the handler is synchronous work on the dispatching task — a store commit
	/// is an `inout` write and a render is a pure function — so it cannot be
	/// cancelled halfway and cannot leave the page half-updated.
	public func handler(_ mutation: @escaping @Sendable (inout State) -> Void) -> EventHandler {
		{ _ in
			commit(mutation)
			return patch()
		}
	}

	/// the same door for a handler that needs the event it answers.
	public func handler(
		_ mutation: @escaping @Sendable (EventData, inout State) -> Void
	) -> EventHandler {
		{ event in
			commit { state in mutation(event, &state) }
			return patch()
		}
	}
}

/// the actions the current render pass is bound to.
public enum PageScope {
	/// the host's door for the pass in flight, or nil outside a hosted render.
	///
	/// a task-local for the same reason ``StateRenderScope`` is one: the page
	/// body receives its state by value and cannot be handed anything else, so
	/// the pass installs what the body may reach.
	@TaskLocal public static var current: (any AnyPageActions)?

	/// the ambient actions as their concrete state type, or nil when this
	/// render is not bound to a store of that type.
	public static func actions<State: Sendable>(of _: State.Type) -> PageActions<State>? {
		current as? PageActions<State>
	}
}

extension StatefulPage {
	/// the hosted door for this pass's controls — mutate and ship in one call.
	///
	/// nil outside a render the host drove (a bare `.markup`, a test's own
	/// loop), which is what lets a page that also renders standalone degrade
	/// visibly instead of shipping dead controls.
	public var actions: PageActions<State>? {
		PageScope.actions(of: State.self)
	}
}

// MARK: - errors

/// why a hosted render refused to produce a page.
public enum SessionPageError: Error, Sendable {
	/// the session already holds a store of another state type. one session
	/// key, one page: replacing the store would drop a live page's state.
	case stateTypeConflict

	/// another pass was still rendering this page's loop, so this one
	/// coalesced into it and has no bytes of its own.
	case renderBusy
}

// MARK: - one session's loop

/// one session's render loop for one page value: the store the host resolved
/// and the loop that remembers what the last render looked like.
///
/// reference semantics are the requirement — the handler a control registers in
/// pass N must find pass N's baseline in pass N+1 — so this is a final class
/// over the loop's own lock, not a value the caller copies.
final class HostedPage<P: StatefulPage>: Sendable {
	let store: Store<P.State>
	private let loop: StatefulPageSession<P>

	init(page: P, store: Store<P.State>) {
		self.store = store
		self.loop = StatefulPageSession(page, store: store)
	}

	/// render this pass and describe what moved since the previous one.
	///
	/// the actions are installed *inside* the pass, not around it: every render
	/// re-wires the body, so a pass that rendered without them would re-register
	/// every control against the inert fallback — the page would look right and
	/// stop mutating on the next click. that is exactly the bug a
	/// once-installed-on-the-first-render door ships.
	func render(in context: RenderContext) -> PagePatch? {
		PageScope.$current.withValue(actions(in: context), operation: { loop.patch(in: context) })
	}

	/// the fragments a mutation produced, rendered in `context`.
	///
	/// empty when the loop coalesced into a pass already in flight (nil), and
	/// empty when nothing moved at all — a handler that answered without
	/// changing state ships nothing, which is the pre-patch behaviour kept.
	///
	/// the one case worth a warning is a change the *wire* cannot express: the
	/// body's bytes moved but no control did, so the differ answered a full
	/// page. that is a page authoring error — a heading bound to state looks
	/// fine and never updates — and it is logged rather than silently dropped.
	func patchFragments(in context: RenderContext) -> [FragmentUpdate] {
		PageScope.$current.withValue(actions(in: context), operation: {
			guard let patch = loop.patch(in: context) else { return [] }
			if patch.fragments.isEmpty, !patch.changedRegions.isEmpty {
				hostLog.warning(
					"""
					webui host: a mutation moved bytes outside every control, so the page \
					cannot be patched (session \(context.session.rawValue), revision \
					\(patch.revision)). give the state-bearing element an id and register \
					its handler with that same id, so the differ has a control to ship.
					"""
				)
			}
			return patch.fragments
		})
	}

	/// the door this pass hands its controls: the store's commit, and the patch
	/// rendered in this pass's own context.
	///
	/// `revision` is the pass's baseline: a handler whose mutation left the
	/// store where it found it has nothing to ship, so the render is skipped
	/// rather than run to discover the same bytes.
	private func actions(in context: RenderContext) -> PageActions<P.State> {
		let baseline = store.revision
		return PageActions(
			revision: baseline,
			commit: { [store] mutation in _ = store.commit(mutation) },
			patch: { [self] in
				guard store.revision != baseline else { return [] }
				return patchFragments(in: context)
			}
		)
	}
}

/// the host's log line. one label for the target: a socket's patch and a
/// session's reap read as the same component.
private let hostLog = Logger(label: "webui.host")

// MARK: - the session page table

/// the per-session render table: one store per session, one loop per session
/// and page, and the router every pass registers into.
///
/// ``events`` is the router the *server* dispatches through. it is handed to
/// the server at construction (`WebUIServer.init(router:eventRouter:…)`), so a
/// control registered in a render pass is reachable by the socket that page
/// opened — the composition the two halves were missing.
///
/// makes unrepresentable: "two sessions render the same store" — the store is
/// resolved by `SessionKey`, and the loop is keyed by it too, so a session's
/// baseline never mixes with another's.
public final class SessionPages: Sendable {
	/// the registry every session's store lives in.
	public let stores: SessionStores

	/// the router every render pass registers into, and the one the server
	/// dispatches events through.
	public let events: EventRouter

	private let routers: any SessionRouterTable

	/// the loop per session. one entry per session: a session renders one page
	/// (the registry's own rule), so a second page type is a caller error that
	/// the store's type check already refuses.
	private let live = Mutex<[SessionKey: any AnyHostedPage]>([:])

	public init(
		stores: SessionStores = SessionStores(),
		events: EventRouter,
		routers: any SessionRouterTable
	) {
		self.stores = stores
		self.events = events
		self.routers = routers
	}

	// MARK: declaring

	/// the route declaration for `page`: a `Page` that renders the session's
	/// own store, wrapped in a document carrying this pass's render token.
	///
	/// `document` wraps the rendered body in the page a client receives. the
	/// host's default is a plain `HTMLDocument` — this target owns no design
	/// sheet, so a deployment that ships one passes `WebUIDocument`'s builder
	/// here and the host never learns about it.
	public func page<P: StatefulPage>(
		_ page: P,
		at pattern: PathPattern,
		title: String,
		requiresRole: String? = nil,
		document: (@Sendable (String, RenderToken) -> String)? = nil
	) -> Page {
		let build = document ?? Self.plainDocument(title: title)
		return Page(pattern: pattern, requiresRole: requiresRole) { request in
			try await self.render(page, for: request, document: build)
		}
	}

	/// the default document: a body, a title, and the render token the client
	/// echoes back on its socket.
	public static func plainDocument(title: String) -> @Sendable (String, RenderToken) -> String {
		{ body, token in
			HTMLDocument(
				title: title,
				body: .trusted(body),
				runtimeConfig: RuntimeConfig(renderToken: token.value)
			).markup.html
		}
	}

	// MARK: rendering

	/// render `page` for the session that asked, from that session's store.
	///
	/// the pass: resolve the store (creating it from the page's initial state
	/// on first use), take the session's loop, install the actions a control
	/// uses, and let the loop diff. a first render is a full page by
	/// definition; every later pass ships only what moved.
	public func render<P: StatefulPage>(
		_ page: P,
		for request: PageRequest,
		document: @Sendable (String, RenderToken) -> String = SessionPages.plainDocument(title: "WebUI")
	) async throws -> RenderedPage {
		let key = SessionKey(hash: request.principal.session.tokenHash)
		let resolution = stores.resolve(for: key) { page.initialState() }
		// a reaped store whose session still routes is a leak: the handlers
		// that pass registered hold the store's binding. drop both.
		for evicted in resolution.evicted {
			live.withLock { $0.removeValue(forKey: evicted) }
			await routers.drop(session: evicted)
		}
		guard let store = resolution.store else { throw SessionPageError.stateTypeConflict }

		let loop = hostedPage(for: key, page: page, store: store)
		let context = RenderContext(router: events, session: request.renderSession)
		guard let patch = loop.render(in: context) else { throw SessionPageError.renderBusy }

		let markup = document(patch.html, request.renderToken)
		return RenderedPage(html: .trusted(markup), router: events, renderToken: request.renderToken)
	}

	/// the store `session` holds, created from `initial` when it holds none.
	///
	/// the door a test or a background job uses to reach a session's state
	/// through the host — the same registry the render path reads, so a
	/// mutation here is what the next pass renders.
	public func store<State: Sendable>(
		for session: SessionKey,
		initial: @Sendable () -> State
	) async throws -> Store<State> {
		let resolution = stores.resolve(for: session, initial: initial)
		for evicted in resolution.evicted {
			live.withLock { $0.removeValue(forKey: evicted) }
			await routers.drop(session: evicted)
		}
		guard let store = resolution.store else { throw SessionPageError.stateTypeConflict }
		return store
	}

	/// forget a session's loop. called by the host when it ends a session: a
	/// store is dropped by the registry, and the baseline that outlived it must
	/// go with it.
	func forget(_ session: SessionKey) {
		live.withLock { $0.removeValue(forKey: session) }
	}

	// MARK: the loop registry

	private func hostedPage<P: StatefulPage>(
		for key: SessionKey,
		page: P,
		store: Store<P.State>
	) -> HostedPage<P> {
		live.withLock { table in
			if let existing = table[key] as? HostedPage<P>, existing.store === store {
				return existing
			}
			let fresh = HostedPage(page: page, store: store)
			table[key] = fresh
			return fresh
		}
	}
}

/// the type-erased loop a session holds, so one table can carry every page
/// type a host serves.
private protocol AnyHostedPage: Sendable {}
extension HostedPage: AnyHostedPage {}
