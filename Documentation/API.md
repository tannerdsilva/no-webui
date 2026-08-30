# API Reference

## WebUI

### View Protocol

| Protocol | Requirement | Notes |
|---|---|---|
| `View` | `func render() -> String` | pure function, no side effects, `Sendable` |
| `ViewModifier` | `func apply(to html: String) -> String` | wraps rendered html with attributes or styles |
| `ModifiedView<Content: View, M: ViewModifier>` | `View` | type-preserving wrapper returned by every modifier |
| `AnyView` | `View` | type-erased wrapper; erases the concrete view type |
| `EmptyView` | `View` | renders nothing |

### ViewBuilder

`@resultBuilder` used by every container closure. single-expression blocks preserve
the concrete view type; multi-view blocks produce `[any View]`.

### Primitives

| Type | Initializer | Notes |
|---|---|---|
| `Text(_ content: String)` | escaped | plain text, html-escaped |
| `Raw(_ content: String)` | unescaped | escape hatch — content goes through verbatim |
| `Div` / `Span` | `id:class:content:` | generic containers |
| `Button(_ label:, id:class:type:disabled:name:)` | escaped label | `ButtonType` = `.submit/.button/.reset` |
| `Input(id:name:placeholder:type:value:disabled:required:attributes:)` | escaped | `InputType` — 22 html input types |
| `Image(src:alt:class:loading:decoding:)` | sanitized src | `ImageLoading`/`ImageDecoding` enums |
| `Link(_ text:, href:class:target:rel:)` | sanitized href | `LinkTarget` enum, `LinkRel` option set |
| `Heading(_ text:, level:class:)` | escaped | `HeadingLevel` = `.h1`…`.h6` |
| `Paragraph`, `Label`, `TextArea`, `Select`, `Table`, `Form` | escaped | `SelectOption.value/label` |
| `ForEach<Data: RandomAccessCollection>` | — | renders each element; no wrapper |
| `Group` | — | renders children without a wrapper |

every attribute parameter (`id`, `class`, `name`, `for`, `data-status`,
`Form.method`, …) is html-escaped before emission. url-valued parameters
(`Link.href`, `Image.src`, `Form.action`) pass through `sanitizeURL` first.

### Layouts

| Type | Initializer | Output |
|---|---|---|
| `VStack` / `HStack` | `alignment:spacing:content:` | `.vstack/.hstack spacing-N align-X` divs |
| `ZStack` | `alignment:verticalAlignment:content:` | `.zstack` grid overlay — children overlap via `.zstack > *` (shipped in `LayoutStyles.complete`) |
| `Spacer(minSize:)` | — | `flex:1` div |
| `ScrollView` | — | `.scrollview` div |
| `Grid(columns:spacing:content:)` | `GridColumns` | inline `display:grid` |

`GridColumns` cases:

| Case | Emits |
|---|---|
| `.fixed(n)` | `repeat(n, minmax(0, 1fr))` — grid-safe equal tracks |
| `.fraction(n)` | `repeat(n, 1fr)` |
| `.minmax(a, b)` | `repeat(auto-fill, minmax(a, b))` |
| `.autoFill(n)` / `.autoFit(n)` | `repeat(auto-fill, minmax(npx, 1fr))` — n is the minimum track size in px |
| `.custom(String)` | passthrough |

### Modifiers

| Method | Effect |
|---|---|
| `.font(size:weight:)` | `style="font-size:Npx;font-weight:W"` — `weight` accepts `FontWeight` or `String` |
| `.textAlign(_ alignment:)` | `style="text-align:..."` — accepts `TextAlignment` or `String` |
| `.foregroundColor(_ color: String)` | `style="color:..."` |
| `.foregroundColor(_ token: ColorToken)` | `style="color:var(--color-...)"` |
| `.backgroundColor(_ color: String)` | `style="background-color:..."` |
| `.padding(_ value: Int)` | `style="padding:Npx"` |
| `.padding(_ token: SpaceToken)` | `style="padding:var(--space-N)"` |
| `.cornerRadius(_ value: Int)` | `style="border-radius:Npx"` |
| `.width(_ value: String)` | `style="width:..."` |
| `.height(_ value: String)` | `style="height:..."` |
| `.class(_ name: String)` | `class="..."` |
| `.id(_ id: String)` | `id="..."` |
| `.attribute(_ key: String, _ value: String)` | emits `key="value"` on the root element (e.g. `data-prevent-enter="false"`) |
| `.showIf(_ condition: Bool)` | `display:none` when false |
| `.onClick(_ handler:)` | `data-component-id="cN" data-event="click"` (auto-allocated id) |
| `.onClick(id: String, perform: handler)` | `data-component-id="<id>" data-event="click"` — **stable** id you choose; registers under that id so re-rendered fragments keep routing (use for interactive regions like tables) |
| `.onSubmit(_ handler:)` | `data-component-id="cN" data-event="submit"` |
| `.onInput(_ handler:)` | `data-component-id="cN" data-event="input"` |
| `.onChange(_ handler:)` | `data-component-id="cN" data-event="change"` |
| `.onFocus(_ handler:)` | `data-component-id="cN" data-event="focus"` |
| `.onBlur(_ handler:)` | `data-component-id="cN" data-event="blur"` |
| `.onFocusIn(_ handler:)` | `data-component-id="cN" data-event="focusin"` |
| `.onFocusOut(_ handler:)` | `data-component-id="cN" data-event="focusout"` |
| `.onKeyDown(_ handler:)` | `data-component-id="cN" data-event="keydown"` |
| `.onKeyUp(_ handler:)` | `data-component-id="cN" data-event="keyup"` |
| `.onKeyPress(_ handler:)` | `data-component-id="cN" data-event="keypress"` |
| `.onMouseDown(_ handler:)` | `data-component-id="cN" data-event="mousedown"` |
| `.onMouseUp(_ handler:)` | `data-component-id="cN" data-event="mouseup"` |
| `.onMouseOver(_ handler:)` | `data-component-id="cN" data-event="mouseover"` |
| `.onMouseOut(_ handler:)` | `data-component-id="cN" data-event="mouseout"` |
| `.onOptimisticClick(predict:perform:)` | click + `data-optimistic="{json prediction}"` — client patches before the round-trip, confirms on update, rolls back on timeout |

### Event Handling

| Type | Description |
|---|---|
| `EventData` | `{ component: String, event: String, data: [String: String] }` — `click` data carries `targetId` and `targetClass` of the clicked element |
| `EventHandler` | `@Sendable (EventData) async -> [FragmentUpdate]` |
| `EventRouter` | routes events to registered handlers. `maxHandlers: Int` (default 10,000), `handlerCount: Int`. one router per render pass — call `reset()` before rendering a fresh page |
| `RenderContext` | `@TaskLocal` context providing component ID generation and handler registration |
| `ComponentID` | hashable/codable string wrapper for component ids |
| `FragmentUpdate` | `{ id: String, html: String }` — DOM patch instruction |
| `SpaceToken` | spacing-scale tokens (`.one`…`.twentyFour`) → `var(--space-N)` |
| `ColorToken` | nexus color tokens (`.primary`, `.text`, `.danger`, …) → `var(--color-...)` |
| `FontWeight` | `.thin` … `.black`, `.custom(_:)` → numeric `font-weight` |
| `TextAlignment` | `.left`, `.center`, `.right`, `.justify` → `text-align` |
| `RuntimeConfig` | typing knobs for the js runtime — `wsUrl`, `wsReconnect`, reconnect/ping/pong/debounce/optimistic timings, `logLevel` |

### Observability

| Type | Description |
|---|---|
| `ObservableEvent` | enum with 10 cases: viewRendered, eventReceived, eventHandled, fragmentSent, websocketConnected/Disconnected/Error, error, debug |
| `ObserverList` | thread-safe collection of `Observable` conformers. `maxObservers: Int` (default 100) |
| `Logger.emit(_:observers:)` | logs an event and notifies observers |

### HTML Document

| Type | Parameters | Description |
|---|---|---|
| `HTMLDocument` | title, body, styles, rawStyles, scripts, contentSecurityPolicy, includeRuntime, runtimeConfig, devMode, head, bodyAttributes, lang | complete HTML document with auto-generated CSP and nonce. shipped css is minified (comments + blank lines stripped) at render time |
| `WebUIDocument` | same as HTMLDocument | HTML document with the full design system css (`LayoutStyles.complete` + `WebUIAssets.css`) |

`runtimeConfig` (a `RuntimeConfig?`) changes only the runtime bootstrap: with a
non-empty config the page emits `WebUIRuntime.init({...})`; with no config the
default `WebUIRuntime.init();` is emitted byte-for-byte.

### CSS

| Type | Description |
|---|---|
| `CSSRule(_ selector: String, _ declarations: [CSSDeclaration])` | a single CSS rule |
| `CSSStylesheet(_ rules: [CSSRule])` | a collection of rules, renders to a `<style>` block |
| `CSSMediaQuery`, `CSSKeyframes`, `CSSFontFace` | at-rule renderers |
| `LayoutStyles` | layout sheet: `.vstack/.hstack/.zstack/.zstack > */.spacer/.scrollview/.grid` + spacing/alignment classes via `.complete` |
| `minifyCSS(_ css: String) -> String` | strips `/* */` comments, trims lines, drops blank lines — applied to shipped page css |

### Utilities

| Function | Description |
|---|---|
| `htmlEscape(_ string: String) -> String` | escape HTML special characters (&, <, >, ", ') |
| `constantTimeEquals(_ lhs:, _ rhs:)` | constant-time equality over byte sequences (`[UInt8]`, `Data`) — no early exit on an equal-length input; used for MAC and token compares |
| `injectAttributes(into html: String, _ attributes: String) -> String` | inject attributes into the first HTML tag |
| `sanitizeURL(_ url: String) -> String?` | nil for `javascript:`, `data:`, `vbscript:` — strips c0 controls and ascii whitespace first, matching the browser's URL parser, so padded/obfuscated schemes are caught too |
| `markdownToHTML(_ markdown: String) -> String` | minimal safe markdown subset: atx headings, bullet/numbered lists, `**bold**`, `*emphasis*`, `` `code` ``, `[label](url)` (url-sanitized). input is escaped before tokenizing; unpaired delimiters render literally |
| `highlightCode(_ code: String, language: String) -> String` | safe escape-only output — an honest stub until a real lexer lands; never emits raw code |
| `inlineSVG(viewBox:width:height:_ content: String) -> String` | create inline svg element |
| `attrIf(_ name: String, _ value: String, _ condition: Bool) -> String` | conditional HTML attribute |
| `classIf(_ className: String, _ condition: Bool) -> String` | conditional CSS class |

### CSRF Protection

| Method | Description |
|---|---|
| `CSRFProtection.generateSecret() -> String` | 32-byte random server secret |
| `CSRFProtection.token(for:secret:maxAge:) -> String` | HMAC-SHA256 stateless token |
| `CSRFProtection.validate(_:for:secret:) -> Bool` | validate token (signature + expiration) |

## WebUIDesignSystem

### WebUIDocument

`HTMLDocument` variant that ships `LayoutStyles.complete` plus the full
`WebUIAssets.css` (the nexus design system, ~110 CSS custom properties). the
css is minified at render time, so served pages carry no comments and no blank
lines. see `Documentation/DESIGN_SYSTEM.md` for the complete token and
component catalog.

### Components

| Component | Key Parameters |
|---|---|
| `WebUIButton` | label, variant (.primary/.secondary/.outline/.ghost/.danger/.success/.warning), size (.sm/.md/.lg), disabled, loading, fullWidth |
| `WebUIInput` | placeholder, state (.normal/.error/.success/.warning), disabled, id, type, label, helpText |
| `WebUICard` | variant (.elevated/.outlined/.flat/.interactive), id, content |
| `WebUIBadge` | text, variant, size, dot |
| `WebUIAlert` | variant (.info/.success/.warning/.danger), title, message, dismissible, icon — close button carries `data-dismiss` |
| `WebUITabs` | tabs: [TabItem(id,label)], activeTab, id |
| `WebUIAvatar` | initials, size, src, status |
| `WebUIProgress` | value (0.0–1.0), variant, showLabel, size |
| `WebUISkeleton` | variant, width, height, count |
| `WebUIToast` | variant, message, id, dismissible — close button carries `data-dismiss` |
| `WebUIModal` | title, id, content, footer — close button carries `data-dismiss` |
| `WebUITable` | headers, rows ([[any View]]), striped, hoverable, compact |
| `WebUIChip` | text, variant, removable, id — remove button carries `data-remove` |
| `WebUIEmptyState` | icon, title, message, action (label, id) |
| `WebUISpinner` | size, label |
| `WebUITooltip` | text, position, content |

dismiss/remove/close buttons render with `data-dismiss` / `data-remove`
markers and no auto-wiring — attach `.onClick` to the container and read
`event.data["targetId"]`/`event.data["targetClass"]` to disambiguate (the
runtime sends both for every click).

## WebUIExample

A SwiftNIO-based HTTP/WebSocket server that serves a live counter + echo page.

**Endpoints:**
- `GET /` — the page HTML
- `GET /__assets/css` — design system css (source bytes)
- `GET /__assets/js` — js runtime (source bytes)
- `WebSocket /ws` — event handling endpoint

**Port:** 9090 (configurable in source)

## WebUIAuth

authentication + sessions foundation for WebUI backends. design rationale and
threat model live in `Documentation/AUTH_SESSIONS.md`; the execution breakdown
in `Documentation/IMPLEMENTATION_PLAN.md`.

### Identity model

| Type | Description |
|---|---|
| `Identity` | `{ id: String, roles: Set<String> }` — `Codable`, `Hashable`, `Sendable`. `id` is the backend's stable identifier; `roles` is the role set guards branch on |
| `Role` | well-known role strings: `Role.member` (`"member"`), `Role.admin` (`"admin"`) |
| `Credential` | `{ username: String, secret: Data }` — raw password bytes, single-use |

### Sessions

| Type | Description |
|---|---|
| `AuthenticatedSession` | `{ id: Data, tokenHash: Data, identityID: String, csrfSeed: Data, createdAt, expiresAt, lastSeenAt }` — the raw token never reaches storage, only its SHA-256 `tokenHash`. `id` is 16 random bytes (the LMDB store enforces this size) |
| `SessionToken.generate()` | 32 bytes from `SecureRandom` **only** — fails loudly on entropy failure, no PRNG fallback |
| `SessionToken.hash(_:)` | SHA-256 of a token — the only form a store may persist |

### Protocols

| Protocol | Job |
|---|---|
| `UserStore.identity(forUsername:) async throws -> Identity?` | backend resolves a username to an identity |
| `Authenticator.authenticate(_ credential:) async throws -> Identity?` | verifies credentials; `nil` for invalid OR unknown (never leaks existence) |
| `AuthSessionStore` | `create` / `find(tokenHash:)` / `touch` / `invalidate(id:)` / `invalidateAll(for:)` / `listSessions(for:)` / `purgeExpired(before:)` — `AuthStoreError` = `.duplicateSession`, `.notFound`, `.malformedRecord` |

### Stores

| Store | Notes |
|---|---|
| `InMemoryAuthSessionStore` | actor-backed test double + reference semantics: primary id map, tokenHash index, per-identity reverse index |
| `LMDBAuthSessionStore` | one persistent LMDB environment (`tok`, `tk`, `user`, `audit` databases), one transaction per actor call on the actor's thread. quicklmdb discipline: every `loadEntry` must be guarded by a `containsEntry` in the same transaction (the get path **throws** `.notFound` on a missing key); the `user` index is a denormalized raw array of fixed 16-byte id records (not LMDB dupsort — that requires consumer-declared `MDB_comparable` types) |

### Cookies

| Type | Description |
|---|---|
| `HTTPCookie` | `name`/`value`/`Attributes` (`expires`, `maxAge`, `domain`, `path`, `secure`, `httpOnly`, `sameSite`). `setCookieHeaderValue()` throws on violation of the `__Host-` rules (Secure required, no Domain, `Path=/`) |
| `HTTPCookie.SameSite` | `.lax` / `.strict` / `.none` |
| `CookieParser.requestCookies(_:)` | quote-aware request-cookie parse: `$`-attributes ignored, values trimmed and unquoted |

### Password verification

| Type | Description |
|---|---|
| `Argon2Parameters` | `timeCost` / `memoryCostKiB` / `parallelism`; `Argon2Parameters.interactive` (19 MiB, t=2, p=1 — OWASP interactive) and `Argon2Parameters.recommended` (64 MiB, t=3, p=4) |
| `PasswordRecord` | `{ salt, hash, parameters }` with PHC-shaped `encodedString()` / `init(encoded:)` round-trip |
| `PasswordVerifier.hash()` / `.verify()` / `.makeSalt()` | Argon2id built on rawdog `RAW_argon2`; verify = re-hash + `constantTimeEquals` |
| `PasswordVerifier.dummyRecord()` | same-cost hash for unknown users — equalizes "user exists" vs "unknown" timing |

### Context

| Type | Description |
|---|---|
| `AuthContext` | `@TaskLocal` carrying `(session, identity?)` — set around authenticated renders and around event dispatch; `hasRole(_:)` helper. mirrors `RenderContext` mechanics |

## WebUIAuthExample

A SwiftNIO-based login-gated interactive demo on :9091 (sign in with `admin` /
`password`). demonstrates the auth stack end to end: runtime-free login page
(native POST, synchronizer CSRF, hardened CSP, `X-Frame-Options`), Argon2id
credential verification with dummy-hash equalization, `SessionToken` +
in-memory session store + cookie issuance, the interactive dashboard
(counter / progress / echo / optimistic reset) under `AuthContext`, a
per-session interactive router, Origin-checked WebSocket upgrade, per-event
session-liveness enforcement (post-logout sockets are redirected and closed),
and CSRF-protected POST logout.

**Endpoints:**
- `GET /login` — static login page (no JS runtime)
- `POST /login` — urlencoded credentials + CSRF → `303` + `Set-Cookie`
- `GET /` — authenticated dashboard, else `303` to `/login`
- `POST /logout` — CSRF-protected logout → `303` + cookie clear (`GET` → 405)
- `GET /__assets/css` / `GET /__assets/js` — design system + runtime
- `WebSocket /ws` — same-origin interactive events (foreign/no-origin refused)

**Port:** 9091

not a deployment template: the Argon2 concurrency cap, session caps/sweep, and
per-session state containers are deferred to M2 (see the plan).
