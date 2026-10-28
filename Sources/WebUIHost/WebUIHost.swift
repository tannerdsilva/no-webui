// MARK: - WebUIHost
//
// the multi-tenant host (design A) — the one target that knows `WebUIServer`
// and `WebUIAuth` together. `WebUIServer` has no edge to auth, and that absent
// edge is the compile-time proof that identity is not the transport's job.
//
// what lives here, and why each piece is a separate file:
//
// - `Ports.swift` — the four ports (`PrincipalResolver`, `PageCatalog`,
//   `SessionRouterTable`, `RevocationBus`) plus the two write doors they pair
//   with (`SessionRevocation`, `IdentityDirectory`) and `ConnectionToken`.
//   protocols first, so every one of them has a test double from day one.
// - `CookieSessionResolver.swift` — the cookie → token hash → store → principal
//   join, and the session cookie's safe attribute set.
// - `Catalog.swift` — the declared/resolved split (`Page`, `PageRequest`,
//   `RenderedPage`) and the two catalogs (`AuthenticatedCatalog`,
//   `StaticCatalog`).
// - `SessionRouterTable.swift` — the session → render → router table with its
//   forward chain (`RouterTable`, a lock-guarded final class).
// - `RevocationBus.swift` — the session → live connections registry
//   (`SocketRevocationBus`, an actor).
// - `SessionPages.swift` — the per-session state layer (`SessionStores` +
//   one render loop per session), and `PageActions`, the door a control uses
//   to mutate and ship the patch it caused.
// - `AuthenticatedHost.swift` — the struct façade that composes all four.
// - `AuthenticatedHostService.swift` — the same composition as a `Service`:
//   the server, its authorizer and observer, and the idle-session reaper in
//   one `ServiceGroup`.
//
// the target depends on `WebUIState`, and `SessionPages` is what makes that
// edge real: the manifest declared it from the start, and until the host owned
// a `SessionStores` no file here imported it.
