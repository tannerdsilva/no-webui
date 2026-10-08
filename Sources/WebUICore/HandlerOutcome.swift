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
    /// surface a typed failure to the client.
    case fail(code: String, message: String)

    /// a redirect that pushes a history entry.
    public static func redirect(to url: String) -> HandlerOutcome {
        .redirect(to: url, replace: false)
    }

    /// the frame this outcome sends, or `nil` for "send nothing".
    ///
    /// an empty fragment list is deliberately silent: it is how a handler says
    /// "handled, nothing changed" without a round trip's worth of noise. that is
    /// the pre-outcome behaviour, preserved.
    public var wireMessage: WSOutgoing? {
        switch self {
        case .fragments(let updates):
            return updates.isEmpty ? nil : .update(fragments: updates)
        case .redirect(let to, let replace):
            return .redirect(url: to, replace: replace)
        case .state(let path, let value):
            return .state(path: path, value: value)
        case .reload:
            return .reload
        case .fail(let code, let message):
            return .error(code: code, message: message)
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
        case .redirect, .reload: return true
        default: return false
        }
    }
}

/// a handler that can answer with more than fragments.
public typealias OutcomeHandler = @Sendable (EventData) async -> HandlerOutcome