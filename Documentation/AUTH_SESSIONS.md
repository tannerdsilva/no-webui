# Authentication & Sessions

_Status: design decision record, augmented against an adversarial software-skeptic
review (2026-08-26) and verified against the current source tree. Decisions in
this document override the earlier exploratory analysis wherever they conflict._

_Implementation status (current tree):_ AD-1 (native form-POST login) and the
M0 foundation (identity, sessions, cookies, stores, Argon2id, `AuthContext`)
are delivered and exerciseable via `WebUIAuthExample` on :9091. hardening
deltas now implemented in the example: accept-time session validation on the
WebSocket upgrade (refused upgrades answer 403), per-session connection
registry with logout teardown, ping-path liveness checks, an idle read
timeout, a global Argon2 concurrency cap, per-IP + per-account login
throttles, single-use login CSRF tokens (with a per-token nonce in the token
format), `Cache-Control: no-store` + `X-Content-Type-Options: nosniff` on
every response, and a client `sanitizeFragmentHTML` scheme check that strips
ASCII whitespace/C0 controls (whitespace-obfuscated `javascript:` schemes are
neutralized on the client side exactly as the server-side sanitizer does).
still designed but **not yet implemented**: AD-2 (the `hello` render-token
handshake), session-bound CSRF (`AuthenticatedSession.csrfSeed` is stored but
unused), per-session state containers, AD-4 (secret persistence + rotation),
a framework-level teardown fan-out `SessionManager`, the sweep `Service`, and
the audit trail (milestones M1–M2 of `Documentation/IMPLEMENTATION_PLAN.md`).
line numbers cited below reflect the tree at the time of the last adversarial
pass and may drift.

## Purpose

Give WebUI backends a first-class way to issue login pages and authenticated
sessions for real users in browsers. This replaces a prior deployment model
where identity was guaranteed by the network layer (a private tunnel, one
cryptographic key per device → source IP → user). That guarantee held no
credential database, no public login surface, and no session state — and it
required distributing a key per user, which is unacceptable for consumer apps
such as a country-club reservation system.

The core question this document answers is not "can sessions be added" but
"what changes about the guarantee, and what therefore must the framework own."
Each fork in the design is resolved here with a decision and a rationale.

## Trust model: what changes and what does not

| Property | Tunnel guarantee (prior) | Session design (this document) |
|---|---|---|
| Identity established before app logic | kernel authenticates every packet | session cookie validated at HTTP request and at WS accept-time, before render and before event dispatch |
| Publicly reachable auth surface | none | login page + POST endpoint — new abuse surface, explicitly mitigated (§hardening) |
| Revocation latency | kernel-instant (peer dropped) | next-interaction, bounded by active teardown fan-out — not kernel-instant, enforced at every interaction and by connection close on invalidate |
| Secrets at rest | none (private keys in config) | tokens hashed at rest in LMDB; HMAC secret persisted + rotatable |
| Password database | none | appears — Argon2id via rawdog, no password stored in plaintext |
| Phishing-resistant device binding | by construction | only via WebAuthn (roadmap); passwords are v1 |
| Multi-identity per network endpoint | one device → one user per IP | per-browser identity — a strict improvement for "whose reservation is this" |

**What does not change:** the rendering core. `View.render() -> String` stays
pure, views stay `Sendable` value types, one router per render pass stays the
house rule, CSP nonces, the sanitizer stack, `CSRFProtection`'s mechanism, and
the absence of a `script` WS message all survive verbatim. Auth is a new layer,
not a restructuring of the render model.

## Design constraints (invariants this design must honor)

- protocols first; structs around protocols; macros deferred
- value types by default; `actor` only for shared mutable state
- no ad-hoc cleanup — cleanup lives at the end of `Service.run()`; long-lived
  processes launch only through `ServiceGroup` (swift-service-lifecycle)
- `View` purity — authorization is server-side by construction, never client-side
- one `EventRouter` per render pass; positional component IDs
- comment-free shipped web assets (html/css/js); comments welcome in Swift
- Swift Testing; Swift Regex (macOS 13+); `Int` over `size_t`
- LMDB over SQLite; zero external JS/CSS frameworks; cross-platform macOS + Linux

## Resolved decisions (the forks)

### Decision 1 — Login transport: native HTTP form POST

The framework hijacks any `submit` event originating from a
`[data-component-id]` element into a WebSocket event
(`webui-runtime.js:261–263`). Verified: the event delegator early-returns for
events with no component element (`handleEvent`, `webui-runtime.js:233–237`),
so a login form rendered **without** an event-handler modifier submits natively.

**Decision:** the login page is a static document built with
`includeRuntime: false` — no WebSocket, no delegation. `LoginView` renders
username/password + a pre-auth CSRF token (formID-scoped, the existing
mechanism). The server owns a single-purpose `application/x-www-form-urlencoded`
body reader for `/login` only. Success responds `303 See Other` + `Set-Cookie`
to the post-login URL; failure re-renders the static login page with an error
and a fresh CSRF token.

**Rationale:** this is the smallest possible server surface (one parser, one
route) and eliminates any need for guest sessions, post-auth ticket relay, and
the reload/rotation race that a WebSocket-ride login would force. It also means
the WebSocket upgrade can require a real user session unconditionally — the
login page never connects, so "upgrades are rejected without a session" can
never strand the login form. Alternative (WS-ride login with a guest session)
rejected: it drags in session rotation across a live connection, cookie issuance
on a 101 handshake (unreliable across browsers), and a reload race.

### Decision 2 — Per-render identity: one `hello` handshake message

Two tabs in one browser share one session cookie but render two independent
pages with independent `c0, c1, …` component ID sets. A reconnecting socket is
indistinguishable from a second tab. The server therefore cannot map a
connection to the correct router without per-render identity on the wire.

**Decision:** the WS protocol gains exactly one new client→server message —
`hello` carrying a per-render token embedded in the page on the `body`
element (`data-webui-render="<uuid>"`). On connect the runtime sends it once;
the server maintains `connection → (session, render) → router`. A reconnect
carrying the same render token rebinds the existing page's router; a new render
token (fresh page load or new tab) creates a new router. All other messages
stay anonymous.

**Rationale:** alternative (re-render on every reconnect) causes visible
full-page reloads on flaky networks and a full render per reconnect — rejected.
The `hello` message is a structural WireGuard-adjacent property: identity is
established *before* application messages flow. The "anonymous message set"
claim is revised to "anonymous except for one-time connection establishment."

### Decision 3 — Session write policy: absolute expiry, throttled touch, read cache

**Decision:** sessions carry `createdAt` + `expiresAt` under an absolute max-age
policy (default 8h) with an optional sliding window (inactivity timeout, default
8h) implemented as a throttled `touch` (at most once per 60s per session). One
persistent LMDB environment for the lifetime of the process (never the
transient open/close-per-call pattern). LMDB reads and writes run on a dedicated
`DBSessionStore` actor, off the NIO event loop. Per-event liveness checks read an
in-memory validation cache (session ID → validated-until, 60s window), not LMDB.

**Rationale:** per-event LMDB reads on the event loop stall every connection on
that loop on a dirty-page fault (verified: `router.handle` is awaited directly
in the inbound frame loop in the reference servers). Per-event writes serialize
on LMDB's single writer. Primary revocation enforcement is **teardown** —
`SessionManager.invalidate()` closes all of the session's connections — and the
per-event check is a backstop with bounded staleness, not the primary mechanism.
A 60s validation window is the honest bound on "revocation immediacy": an
attacker holding a live socket cannot prevent close, and the next read of the
cache cell forces a fresh DB check within one window tick of `invalidate()` if
teardown were ever missed.

### Decision 4 — Secret persistence: LMDB metadata env + env-var override

**Decision:** the auth HMAC secret (CSRF + login-ticket signing) is generated on
first boot and persisted in a `webui_auth_meta` LMDB env; an environment variable
`WEBUI_AUTH_SECRET` overrides it (for proxy-fronted or ephemeral deployments).
Explicit rotation command regenerates; all outstanding signed tokens (CSRF
max-age 1800s) are invalidated on rotation — documented, accepted behavior.

**Rationale:** an in-memory-only secret silently invalidates every outstanding
token on process restart; a persisted secret needs a storage location anyway and
LMDB is the house choice. Session tokens never use the `SystemRandomNumberGenerator`
fallback path in `CSRFProtection.generateSecret` (`Utilities.swift:280–283`);
token material comes from `SecureRandom.bytes` exclusively.

## Core protocols

```swift
public protocol UserStore: Sendable {              // backend supplies
    func identity(forUsername: String) async throws -> Identity?
}
public struct Credential: Sendable {               // opaque to the framework
    public let username: String
    public let secret: Data                        // raw password bytes, single use
}
public protocol Authenticator: Sendable {          // verify credentials
    func authenticate(_ credential: Credential) async throws -> Identity?
}
public protocol AuthSessionStore: Sendable {
    func create(_ session: AuthenticatedSession) async throws
    func find(tokenHash: Data) async throws -> AuthenticatedSession?
    func touch(_ session: AuthenticatedSession) async throws
    func invalidate(id: Data) async throws
    func invalidateAll(for identityID: String) async throws   // logout-everywhere
    func listSessions(for identityID: String) async throws -> [AuthenticatedSession]
    func purgeExpired(before: Date) async throws
}
public struct Identity: Sendable, Codable, Hashable {
    public let id: String
    public let roles: Set<String>                  // "member", "admin", ...
}
public struct AuthenticatedSession: Sendable, Codable {
    public let id: Data                            // 16 random bytes
    public let tokenHash: Data                     // SHA-256 of the 32-byte token
    public let identityID: String
    public let csrfSeed: Data                      // per-session CSRF keying
    public let createdAt: Date
    public let expiresAt: Date
    public let lastSeenAt: Date
}
```

- `AuthenticatedSession` stores the **hash** of the token, never the token. A
  database dump is not a session-theft kit.
- `AuthContext` mirrors `RenderContext`: a `@TaskLocal` carrying
  `(session, identity)` set by the server around `router.handle` and around
  authenticated re-renders. Views branch on `identity.roles`; handlers receive
  identity without a signature change to `EventHandler`.
- `constantTimeEquals(_:_:)` — new tiny pure-Swift utility. All token and MAC
  comparisons use it, including the existing `CSRFProtection.validate` which
  currently uses `String ==` (`Utilities.swift:309`).

## Session store & LMDB layout

Single `webui_sessions` env, one persistent environment, one writer:

| Key | Value | Purpose |
|---|---|---|
| `tok:<sha256(token)>` | `AuthenticatedSession` JSON | primary lookup by presented token |
| `user:<identityID>` | DupSort of `<sessionID>` | logout-everywhere + per-user session caps (default max 10; oldest evicted on create) |
| `audit:<seq>` | auth event record | optional audit trail (append-only) |

- expiry is computed from `createdAt`/`expiresAt`; a sweep `Service` in the
  `ServiceGroup` purges expired rows on a 5-minute cadence and evicts stale
  validation-cache cells.
- QuickLMDB is a **new dependency** for this package (today only swift-log,
  swift-nio, rawdog are present). Accepted and recorded; the store protocol
  keeps it swappable for tests (`InMemoryAuthSessionStore`).

## Cookie layer

- session cookie: `__Host-auth` with `HttpOnly; Secure; SameSite=Lax; Path=/;`
  plus `Max-Age` matched to session expiry. `__Host-` requires `Secure` + no
  `Domain` + `Path=/`.
- a small pure-Swift `HTTPCookie` parse/build pair (manual parsing over the raw
  `Cookie` header; no new server framework dependency) with full flag surface
  and unit tests for every escaping rule.
- development exception: on plain-HTTP non-localhost deployments (LAN demo),
  `Secure` silently prevents cookie storage — the builder logs a warning when
  emitting a `Secure` cookie over plain HTTP, and dev configs override `Secure`
  for localhost only. Documented; production requires TLS (§operational surface).

## Login ceremony (normative sequence)

1. `GET /login` → `200` static page (`includeRuntime: false`). `LoginView`
   renders the username/password form and a pre-auth CSRF token (single-use —
   see step 4); a `next` allowlist (open-redirect defense) is still future work.
2. `POST /login` (urlencoded, server-owned single-route parser) → CSRF
   validation → **single-use check** (the stateless token is recorded as
   consumed before any KDF work) → per-IP + per-account throttle
   (§hardening; `429` + `Retry-After` when exceeded) → `PasswordAuthenticator`
   with Argon2id under a **global concurrency cap** (default 4); **dummy-hash
   discipline**: unknown usernames hash a fixed dummy so timing does not
   reveal existence.
3. success → create session row, `303 See Other` + `Set-Cookie: …` → `/`.
   Fresh session token + id on every login (session-fixation defense).
4. failure → `200` re-render of the static login page with a generic error and
   a fresh CSRF token. pre-auth tokens are formID-scoped and **single-use**:
   the login page mints a new token every GET, and each token may be submitted
   exactly once (a replayed or scraped token is rejected before the KDF).
5. `POST /logout` → CSRF validation → invalidate session row → remove the
   per-session router → **close every live socket for that session** (the demo
   connection registry is the teardown fan-out; per-event liveness checks
   remain the backstop) → `303` to `/login`.

## WebSocket integration

- **accept-time:** `shouldUpgrade` requires a valid session cookie (resolved
  against the store) **and** `Origin == Host`. Anything else is refused; the
  rejection is written directly by `shouldUpgrade` (a `403` + close) because
  the typed upgrader's fallback replay re-delivers only `.end` — routing can
  never see a refused upgrade's request head. The login page never upgrades,
  so a strict policy is safe. confirmed live: no-cookie, wrong-method, and
  wrong-origin upgrades all receive `403`, while a valid session upgrades `101`.
  per-session sockets are registered in an in-memory connection registry so
  `invalidate()` (logout) closes them immediately; each socket also carries an
  `IdleStateHandler` read timeout (120s) so a silent authenticated socket is
  reaped, and the ping path runs the same per-event liveness check as events
  (a revoked session's socket cannot ping forever).
- **hello handshake:** first message carries the render token; the server binds
  `connection → (session, render) → router` (Decision 2).
- **per-event:** `AuthenticatedRouter` wraps dispatch: liveness backstop via the
  validation cache, `AuthContext` set via `@TaskLocal` around `handle()`.
  Constraints for handler authors: no `Task.detached` inside handlers; audit
  and logging read the bound session, not the TaskLocal.
- **server-initiated invalidation:** `invalidate()` closes all of the session's
  connections — server sends `{type:"redirect", url:"/login"}` then closes, and
  the runtime follows the redirect. This is the primary enforcement path; the
  runtime does **not** need to interpret close codes (the browser reports 1006
  and cannot distinguish a 403 handshake).
- **server pushes:** any future server-initiated push (broadcast, admin->member)
  must check session liveness and happen strictly **after** teardown ordering —
  never push to a socket whose session was invalidated in the same logical step.
- **terminal failure path (runtime):** for the residual case where the upgrade
  fails without a server message (proxy, expired cookie mid-session), the
  runtime caps reconnect attempts (default 5) and then `location.replace('/login')`.
  On `redirect`, the runtime clears the offline message queue (up to 1000
  queued events must never replay across a session boundary — verified
  queue-flush behavior in `webui-runtime.js:54–62,129–139`).

## CSRF

- token format: base64(`formID:expiration:nonce:signature`) — HMAC over
  `formID:expiration:nonce` with the shared server secret. the **per-token
  random nonce** makes every freshly-minted token unique even within the same
  wall-clock second (the embedded expiry is second-truncated, so without it a
  single-use store would reject the second of two same-second tokens as
  already consumed). validated with `constantTimeEquals`.
- pre-auth login form: formID-scoped stateless tokens (correct — no session
  exists yet, and `SameSite=Lax` is the second layer). in the example these
  are additionally **single-use** via the `SingleUseTokenStore`: recorded as
  consumed before any KDF work, so a replayed or scraped token is rejected
  once.
- authenticated forms: session-bound tokens — HMAC payload becomes
  `sessionID:formID:expiration` so a token minted for one session cannot be
  replayed against another. `Form(csrfToken:)` renders them unchanged.
  **not yet implemented** — `AuthenticatedSession.csrfSeed` is stored but
  unused; the example's logout token is still the global stateless formID
  token.
- logout is CSRF-protected (POST only; `GET` → 405).

## Hardening deltas (extends the ARCHITECTURE.md security table)

| Threat | Mitigation |
|---|---|
| Clickjacking | `X-Frame-Options: SAMEORIGIN` on every response (the `frame-ancestors` CSP directive is inert in a `<meta>` element). implemented. `form-action 'self'` + `base-uri 'self'` on the login page CSP |
| Timing side channels | `constantTimeEquals` on all MAC/token compares |
| Token theft at rest | tokens hashed in LMDB; raw token never logged |
| Entropy weakness | `SecureRandom.bytes` only — the `SystemRandomNumberGenerator` fallback (`Utilities.swift`) is unreachable for session/token material (it remains the CSRF-secret fallback; noted as a future fail-loud change) |
| Open redirect | server-fixed redirect targets in the example (login → `/`, logout → `/login`); runtime redirect already blocks `javascript:`/`data:` |
| Brute force / stuffing | per-account + per-IP **fixed-window throttle** (`LoginThrottle`, `429` + `Retry-After`) + **global Argon2 concurrency cap** (`AsyncSemaphore`, default 4) + **single-use login CSRF** (`SingleUseTokenStore`) — all implemented in the example. LMDB-backed attempt log still future |
| Account enumeration | dummy-hash discipline equalizes timing |
| Proxy spoofing | trusted-proxy configuration for `X-Forwarded-For`; unconfigured ⇒ per-IP throttles key on the socket peer (the example keys on the NIO peer address) |
| Session fixation | fresh session token + id on every login; logout-everywhere |
| Cross-site WS hijacking | `Origin == Host` **and** a valid session cookie at accept-time; refused upgrades answer `403` and close |
| Revoked-session push | **implemented in the example**: per-session connection registry — logout closes every live socket immediately; per-event + ping liveness checks remain the backstop |
| Cache / bfcache leak | `Cache-Control: no-store` + `X-Content-Type-Options: nosniff` on every response (keeps the authenticated dashboard out of the http cache and out of the back-forward cache after logout) |
| Client fragment XSS | `sanitizeFragmentHTML` strips ASCII whitespace/C0 controls from URL values before the scheme check — whitespace-obfuscated `javascript:` schemes (`java&#x09;script:`, `java\t script:`) are neutralized client-side, mirroring the server sanitizer |
| Stale client replay | queue scrub on redirect/terminal failure (above) |
| Secret loss on restart | persisted HMAC secret + documented rotation (Decision 4) — **not yet implemented** |
| Credential database loss | LMDB backup/restore runbook (§operational surface) |

## JS runtime changes (comment-free, string-pinned)

- `hello` message with the render token (one-time, on connect).
- queue scrub on `redirect` (server-initiated) and on terminal failure.
- capped reconnect attempts with `location.replace('/login')` terminal path.
- nothing else. No new server→client messages; `redirect`/`reload`/`error`
  already cover the session lifecycle. All changes pin-tested via the existing
  substring-probe tests, which stay byte-exact for the untouched runtime.

## Authorization

- `RequiresLogin` / `RequiresRole` are render-time guards: they render either
  the protected subtree or the login redirect. Because every render happens
  server-side after session validation, there is no client-side authorization
  path to bypass.
- per-user state is app-owned (the backend's member/reservation state), scoped
  by `identityID`. The framework supplies per-session routers and the
  connection registry; it does not store domain state.

## Operational surface (recorded, not deferred)

- TLS + HSTS in front of cookie issuance (no HSTS header exists anywhere in the
  stack today).
- password reset/recovery is a required P2 subsystem: single-use HMAC reset
  ticket (like CSRF), short expiry, consumed on use, `Mailer` protocol for the
  out-of-band channel — SMTP implementation is a named, isolated dependency
  decision (no SMTP code in the framework core).
- audit: `AuthEventAudit` logs login success/failure, logout, revocation,
  reset issuance/consumption via swift-log; optional LMDB `audit:` table for
  durable trails.
- backups: member hashes and session state are catastrophic-loss data — the
  LMDB env is a documented backup/restore artifact.
- concurrent-session cap (default 10/user, oldest evicted) and per-user
  logout-everywhere via the `user:` secondary index.

## WebAuthn roadmap (v2, framed honestly)

- passkeys replace the **password**, never the session — revocation semantics
  stay identical, riding the LMDB session row. The "heir" claim is scoped to
  authentication with no shared secret (no password DB, phishing-resistant
  device binding).
- real constraints recorded: RP ID is the hostname (proxy host changes and LAN
  IPs silently invalidate credentials), secure context required (HTTPS or
  localhost only), and the ceremony is a subsystem — `navigator.credentials`
  calls, CBOR/COSE key parsing, `clientDataHash`/`authData` verification, origin
  checks, counter checks — in a comment-free embedded runtime with no CBOR
  dependency today.
- `WebAuthnAuthenticator` conforms to the same `Authenticator` protocol. The
  login UX forks (password form vs. passkey button/conditional mediation) — an
  accepted fork, not an extension of `LoginView`.

## Phases

### Phase 0 — Foundation (pure, no server changes)
- `Identity`, `Credential`, `AuthenticatedSession`, protocol set
- `constantTimeEquals` + `CSRFProtection.validate` switch
- `HTTPCookie` parse/build with full flag surface
- `InMemoryAuthSessionStore` + `LMDBAuthSessionStore` (new dependency: QuickLMDB)
- rawdog Argon2id wrapper: hash + verify + parameter serialization + dummy-hash
- Swift Testing: cookie round-trips, session lifecycle, constant-time compare,
  Argon2 verify vectors

### Phase 1 — Server + wire
- `WebUIAuthServer` `Service` (ServiceGroup): single-route urlencoded parser,
  `Set-Cookie` emission, `303` flow, upgrade auth + `Origin` check
- `hello`/render-token handshake in protocol + runtime; string pins updated
- `SessionManager` actor: `session → [connections]`, `connection → (render) → router`
- `AuthenticatedRouter` (liveness backstop + `AuthContext` TaskLocal)
- CSP delta: `form-action`, `base-uri`, `frame-ancestors`
- runtime: queue scrub, capped reconnect → `/login`
- `WebUIAuthExample` executable demonstrating login → dashboard → logout

### Phase 2 — UX + hardening
- `LoginView`/`RequiresLogin`/`RequiresRole`, `next` allowlist
- session-bound CSRF (+ single-use pre-auth login CSRF)
- throttle (per-account, per-IP, trusted-proxy config) + global Argon2 cap
- reset/recovery (`Mailer` protocol + ticket lifecycle)
- audit trail, secret persistence + rotation (Decision 4), sweep service
- session cap + logout-everywhere

### Phase 3 — Gates + operations
- new `auth-smoke` gate (separate from the untouched existing gates): seeded
  test user, login POST, authenticated WS round-trip, logout teardown, expiry
  redirect; fullstack + browser drivers gain a login step
- TLS/HSTS runbook, backup/restore, rotation runbook
- load test: Argon2 cap behavior under flooding; validation-cache hit rate

## Gate strategy (iterate, not extend)

The existing `smoke` gate pins **exactly 7** `data-component-id` attributes on
its page (`WebUISmokePlugin.swift:113–118`) and the `fullstack-smoke`/`browser-smoke`
drivers assert its document structure and selectors. Those gates stay untouched
— they are the framework gate. Auth gets **its own** server and gate
(`WebUIAuthExample` + `auth-smoke`) with a seeded credential, so the pinned
count and content signatures of the framework gate never move. The only shared
assets the auth gate reuses are the design system and the runtime pins.

## Risk register / explicitly open

- SMTP provider for reset email: named decision, isolated behind `Mailer`
  (v1 may ship a no-op/test double).
- self-service registration: explicitly out of scope; members provisioned
  by staff in v1 (matches "issuing" framing).
- horizontal scale: LMDB is single-node; a multi-replica deployment requires
  sticky sessions or a shared session backend — out of scope, recorded.
- rate-limit tuning: defaults chosen conservatively; observable via audit.
- passkey enrollment UX: v2, after the protocol surface proves out.
