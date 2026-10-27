import Synchronization
import WebUI
import WebUIServer
import WebUIAuth

// MARK: - RouterTable

/// the session → render → router table, promoted from `WebUIAuthExample`'s
/// `RouterRegistry`.
///
/// it is a `final class` + `Mutex`, not a struct and not an actor: **reference
/// semantics are the requirement** — one table is consulted by every render
/// pass, every socket and every reaper, and each of them must see the same
/// entries. a struct copy would give two callers two tables and silently lose
/// the cross-session gate; an actor would make each lookup an async hop for a
/// dictionary read that the render path performs on every frame.
///
/// the shape, in one paragraph: a session's token hash owns N recent render
/// tokens (LRU, `maxRendersPerSession`), each bound to the `EventRouter` that
/// render pass registered into. a token evicted from that window is not
/// forgotten — it *forwards* to the token that replaced it, and the LRU of
/// forward entries is bounded by the same capacity. so an open page whose token
/// falls off the window resolves through the chain and is handed the live token
/// (`needsRefresh`), which is an in-place migration: never a reload, never a
/// login kick. only tokens this session actually minted ever enter the chain, so
/// a forged or foreign token still fails resolution.
///
/// the binding contract: a router bound under `renderToken` registered its
/// handlers into `RenderSessionID(renderToken.value)` — ``PageRequest/render(on:_:)``
/// is what guarantees that, because it derives the session from the token rather
/// than accepting a second spelling. ``drop(session:)`` relies on it to end
/// exactly the handlers a logout must not leave behind.
public final class RouterTable: SessionRouterTable, Sendable {

	/// one session's live window plus its forward chain.
	private struct Entry {
		var routers: [String: EventRouter] = [:]
		/// the live window, least-recently-used first.
		var order: [String] = []
		/// evicted token → the token that replaced it.
		var forward: [String: String] = [:]
		/// the forward chain's own LRU bound, so it cannot grow without limit
		/// under a client that re-renders forever.
		var forwardOrder: [String] = []
	}

	private struct Values {
		var sessions: [[UInt8]: Entry] = [:]
	}

	private let values = Mutex(Values())

	/// how many of a session's recent render tokens stay directly addressable.
	/// the example's default, kept: it is one entry per open tab plus headroom,
	/// and the forward chain is what makes a bigger number unnecessary.
	public let maxRendersPerSession: Int

	public init(maxRendersPerSession: Int = 8) {
		self.maxRendersPerSession = maxRendersPerSession
	}

	// MARK: resolve

	public func router(
		for session: SessionKey,
		renderToken: RenderKey
	) async -> (router: EventRouter, liveToken: RenderKey, needsRefresh: Bool)? {
		values.withLock { values in
			guard var entry = values.sessions[session.hash] else { return nil }
			var current = renderToken.value
			var hops = 0
			// one hop per forward entry, and the chain is capped at the window
			// size, so this bound is unreachable except through a cycle — which
			// is why it exists: a corrupt chain terminates, it does not spin.
			let bound = maxRendersPerSession + 1
			while hops <= bound {
				if let router = entry.routers[current] {
					// touch: an actively-used token is re-promoted, so frequent
					// renderers do not evict a live page out from under itself.
					if let index = entry.order.firstIndex(of: current) {
						entry.order.remove(at: index)
						entry.order.append(current)
						values.sessions[session.hash] = entry
					}
					return (router, RenderKey(value: current), current != renderToken.value)
				}
				guard let next = entry.forward[current] else { return nil }
				current = next
				hops += 1
			}
			return nil
		}
	}

	// MARK: bind

	public func bind(_ router: EventRouter, session: SessionKey, renderToken: RenderKey) async {
		values.withLock { values in
			let token = renderToken.value
			var entry = values.sessions[session.hash] ?? Entry()
			if let seen = entry.order.firstIndex(of: token) {
				entry.order.remove(at: seen)
			}
			entry.routers[token] = router
			entry.order.append(token)
			while entry.order.count > maxRendersPerSession {
				let evicted = entry.order.removeFirst()
				entry.routers.removeValue(forKey: evicted)
				// record the forward *before* the entry is gone: that write is
				// what keeps the page alive.
				entry.forward[evicted] = token
				entry.forwardOrder.append(evicted)
				while entry.forwardOrder.count > maxRendersPerSession {
					let old = entry.forwardOrder.removeFirst()
					entry.forward.removeValue(forKey: old)
				}
			}
			values.sessions[session.hash] = entry
		}
	}

	// MARK: drop

	public func drop(session: SessionKey) async {
		let entry = values.withLock { values in
			values.sessions.removeValue(forKey: session.hash)
		}
		guard let entry else { return }
		// end every render session this table bound. after this the routers hold
		// no handlers for the session, which is the C4 gate's `handlerCount == 0`
		// and the reason a frame arriving after logout finds nothing to dispatch.
		for token in entry.routers.keys {
			_ = entry.routers[token]?.end(RenderSessionID(token))
		}
	}

	// MARK: inspection

	/// how many sessions hold at least one bound render.
	public var sessionCount: Int {
		values.withLock { $0.sessions.count }
	}

	/// the tokens currently bound for `session`, least-recently-used first. the
	/// forward chain is not included: these are the ones that resolve directly.
	public func renderTokens(for session: SessionKey) -> [RenderKey] {
		values.withLock { values in
			(values.sessions[session.hash]?.order ?? []).map(RenderKey.init(value:))
		}
	}

	/// every session holding at least one bound render — the walk a maintenance
	/// sweep uses to drop entries whose session has expired or been purged.
	public func liveSessions() -> [SessionKey] {
		values.withLock { values in
			values.sessions.keys.map(SessionKey.init(hash:))
		}
	}
}
