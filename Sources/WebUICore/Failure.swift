// MARK: - Failure vocabulary
//
// one vocabulary for every way a render, a registration or an admission can
// refuse. the point is that a refusal is a *value*, not a silent branch: a
// caller either handles the case or lets it propagate, and the server can turn
// the case into a status code without parsing a string.
//
// the words are the domain's (§4 of the multi-tenant plan): a capacity is
// counted per connections/sessions/handlers, a session is one sign-in, and a
// refusal names the limit it ran into.

/// which table a capacity refusal ran out of.
public enum CapacityKind: String, Sendable {
	/// accepted sockets held at once (`WebUIServerConfig.maxConnections`).
	case connections
	/// render sessions the router holds (`WebUIServerConfig.maxSessions`).
	case sessions
	/// event handlers registered into one session
	/// (`WebUIServerConfig.maxHandlers`, `EventRouter.maxHandlers`).
	case handlers
}

/// a refusal, carrying enough to answer with: which capacity, and the limit it
/// hit.
///
/// every case is `Equatable` so a test can pin the exact refusal a call
/// produced instead of matching a message.
public enum WebUIFailure: Error, Sendable, Equatable {
	/// a table is full: admitting one more would exceed `limit`.
	case atCapacity(kind: CapacityKind, limit: Int)
	/// a session already holds `limit` handlers, so a registration is refused —
	/// the render that tried to register fails rather than shipping a page whose
	/// control answers nothing.
	case handlerCapReached(session: String, limit: Int)
	/// a session was reaped because its last socket closed.
	case sessionEvicted(session: String)
	/// the platform entropy source failed, so no render token could be minted.
	/// a tokenless page is a degraded render, never a guessable token.
	case entropyUnavailable
	/// a component id the page declared does not name a registered component.
	case unknownComponent(String)
	/// a render threw. the payload is the error's description, kept as a string
	/// so the failure stays `Sendable` and `Equatable`.
	case renderThrew(String)
}

/// what the framework does when it cannot honour a request in full.
///
/// the switch exists so an upgrade cannot silently turn every degradation into
/// a warning. `strict` is the loud default for `WebUIHost`; `degrade` is the
/// opt-in 1.x shape that logs and continues.
public enum FailurePolicy: Sendable {
	/// every degrade is loud: a thrown render error, a 503 with a body, an
	/// error log, a counter.
	case strict
	/// legacy: warnings only. opt-in, and logs a startup warning naming each
	/// relaxation.
	case degrade
}
