// the typed response model (`HTTPResponse`, `HTTPStatus`, `HTTPCookie`)
// lives on the shared leaf so the event layer can carry a response too
// (`HandlerOutcome.response`), and this makes that split invisible to a host
// that imports only WebUIServer — the same pattern WebUICore uses for its
// consumers.
@_exported import WebUISharedCore
