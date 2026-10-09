import WebUISharedCore

// MARK: - HandlerOutcome

/// what a handler answers with.
///
/// `[FragmentUpdate]` is the common case and keeps its own spelling; the other
/// cases map onto wire messages the client engine has always understood
/// (`WSOutgoing.redirect`/`.state`/`.reload`/`.error`) but that no shipped server
/// could ever emit, because a handler could only return fragments. those three
/// frames were dead protocol: parsed by the engine, unreachable from Swift.
public enum HandlerOutcome: Sendable {
	/// replace the named fragments in the live page.
	case fragments([FragmentUpdate])
	/// navigate the page. `replace` picks `history.replaceState` over `pushState`.
	case redirect(to: String, replace: Bool)
	/// write one client-state entry (the engine's `State.set(path, value)`).
	case state(path: String, value: String)
	/// reload the page.
	case reload
	/// the answer is a full typed http response.
	///
	/// on a websocket only navigation is expressible — the socket's frames
	/// carry no response head, so headers and cookies cannot leave through one;
	/// those travel on the http request/response pair a page render answers.
	case response(HTTPResponse)
	/// the handler failed.
	///
	/// `fallback` carries fragments that keep the page usable — the router fills
	/// it from the component's registered fallback, when the host supplied one.
	case fail(code: String, message: String, fallback: [FragmentUpdate])

	/// a redirect that pushes a history entry.
	public static func redirect(to url: String) -> HandlerOutcome {
		.redirect(to: url, replace: false)
	}

	/// a failure with nothing to fall back to.
	public static func fail(code: String, message: String) -> HandlerOutcome {
		.fail(code: code, message: message, fallback: [])
	}

	/// the frames this outcome sends, in order.
	///
	/// a list rather than one frame because a failure carries two: the error the
	/// page must be told about, and the fallback that keeps it usable. an empty
	/// fragment list is deliberately silent — it is how a handler says "handled,
	/// nothing changed" without a round trip's worth of noise, which is the
	/// pre-outcome behaviour preserved.
	public var wireMessages: [WSOutgoing] {
		switch self {
		case .fragments(let updates):
			return updates.isEmpty ? [] : [.update(fragments: updates)]
		case .redirect(let to, let replace):
			return [.redirect(url: to, replace: replace)]
		case .state(let path, let value):
			return [.state(path: path, value: value)]
		case .reload:
			return [.reload]
		case .response(let response):
			switch response.body {
			case .redirect(let to, _):
				return [.redirect(url: to, replace: false)]
			default:
				// a body-carrying response has nowhere to go on a websocket.
				return []
			}
		case .fail(let code, let message, let fallback):
			var frames: [WSOutgoing] = [.error(code: code, message: message)]
			if !fallback.isEmpty { frames.append(.update(fragments: fallback)) }
			return frames
		}
	}

	/// the fragments this outcome carries; empty for every other case.
	public var fragments: [FragmentUpdate] {
		if case .fragments(let updates) = self { return updates }
		return []
	}

	/// whether this outcome asks the client to do something other than patch.
	public var navigates: Bool {
		switch self {
		case .redirect, .reload:
			return true
		case .response(let response):
			if case .redirect = response.body { return true }
			return false
		default:
			return false
		}
	}

	/// whether this outcome reports a handler failure.
	public var isFailure: Bool {
		if case .fail = self { return true }
		return false
	}
}

/// a handler that can answer with more than fragments, and may fail.
///
/// the throw is caught by the router and becomes ``HandlerOutcome/fail(code:message:fallback:)``,
/// so a failing handler can no longer die silently. a closure that never throws
/// satisfies this type unchanged — `{ _ in .redirect(to: "/x") }` needs no `try`.
public typealias OutcomeHandler = @Sendable (EventData) async throws -> HandlerOutcome

/// what a server does with a handler that failed.
///
/// the router always reports a failure through the observer funnel
/// (``ObservableEvent/error(message:)``); this decides what the *client* is told.
public enum HandlerFailurePolicy: Sendable, Equatable {
	/// no client frame, no server log — a host that observes programmatically
	/// sees the failure and nothing else does.
	case silent
	/// no client frame; the server logs a warning naming the component and the
	/// thrown error.
	case log
	/// the page is told: an error frame, plus the component's fallback fragment
	/// when the host registered one, so the interaction stays usable.
	case notifyClient
}
