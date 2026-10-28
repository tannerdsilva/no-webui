# Architecture

## Overview

The framework has five layers that connect to form a complete server-rendered
web UI with live DOM updates:

```
┌──────────────────────────── HTTP Server (your app) ────────────────────────────┐
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐                       │
│  │ View Tree   │→ │ HTMLDocument │→ │ HTTP Response  │                       │
│  │ (structs)   │  │ (assembly)   │  │ (HTML string)  │                       │
│  └─────────────┘  └──────────────┘  └────────────────┘                       │
│                        │                                                     │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐                       │
│  │ EventRouter │← │ WebSocket    │← │ Client Event   │                       │
│  │ (dispatch)  │  │ (upgrade)    │  │ (JSON message) │                       │
│  └──────┬──────┘  └──────────────┘  └────────────────┘                       │
│         │                                                                     │
│  ┌──────▼──────┐  ── WS send → engine: optimistic + patch + scroll/focus      │
│  │ Fragment    │  capability islands (wasm) compose regions locally           │
│  │ Updates     │  service worker caches the shell (offline capability)        │
│  └─────────────┘                                                              │
└────────────────────────────────────────────────────────────────────────────────┘
```

the **client runtimes** (next architecture, `NEXT_ARCHITECTURE.md`): the
default is the framework-owned **engine** (`webui-engine.js`, ~58 kb — the
measured size of the committed working file, which is comment-free and ships
as-is) —
event capture on the `data-component-id` contract, `/ws` transport with
reconnect + optimistic prediction, sanitized fragment patching with
scroll/focus survival, keyboard/focus parity (incl. modal trap + return),
view transitions, and capability-island mounting. **wasm islands**
(pure-Swift logic compiled with the embedded sdk, ~kb-scale, e.g.
`WebUIValidateIsland`) are fetched lazily per declared capability and
compose regions with zero round trips. the **wasm monolith client**
(`WebUIClient` — a chamber-hosted boot plus a content-addressed ~55 mb module)
was deleted: it fetched and instantiated that module on every app-mode page for
work the ~58 kb engine does, and it could not render server views. there is no
`ClientBoot(flavor:)`; the engine is the client runtime, and wasm survives only
as capability islands (Layer 5). the server stays authority for persistence,
auth, and render correctness (`FragmentUpdate` is the universal patch
envelope in both directions).

## what this framework is — and is not

the honest boundary, in one place (the README restates it for newcomers):

**is:** a server-authoritative swift web framework. the page is a swift
`View` tree rendered on the server; the shipped client is one engine module
(`webui-engine.js`) that delegates DOM events back over `/ws` and patches the
fragments the server sends; real http on the wire (methods, a typed `Router`,
forms, uploads, streaming, status/headers/cookies); a typed design system
shipped as compiled-in css; and wasm capability islands for pure-swift
client-side logic.

**is not:** a client-side SPA framework. there is no browser `fetch()` api by
design — the only `fetch(` in the engine is the lazy capability-island loader
(`designer/assets/webui-engine.js`) — client state is server-owned (the
client's store is a small optimistic mirror the authoritative `update`
replaces, and it rolls back on timeout), and process isolation for a trapping
handler is not offered: `ErrorBoundary` catches *failures*, never swift traps
(`STABILITY.md`, "what is not stable" item 8).

## Layer 1: View Tree

**Files:** `View.swift`, `ViewBuilder.swift`, `Primitives.swift`, `Layouts.swift`,
`ModifiedView.swift`, `Modifiers.swift`

Every UI is a tree of `View` conformers. Each view implements the one
requirement, `render(into:)`, writing its bytes into a shared `HTMLBuffer`
(`WebUISharedCore/HTMLBuffer.swift`). Views are value types — constructed,
rendered, and discarded within a single request.

### View Protocol

```swift
public protocol View: BufferRendering, Sendable {
    // the sole render requirement, inherited from `BufferRendering`: write this
    // view's bytes into the shared render buffer.
    func render(into buffer: inout HTMLBuffer)
}
```

a view render is pure: same inputs always produce the same HTML, no side
effects, no mutable state passed through the tree. the deprecated
`render() -> String` is an extension *default* that renders through the buffer
and materializes the string — it is not a conformance path, so a 1.x view that
implemented only `render()` does **not** compile against the 2.0 requirement (a
kept `render()` would be silently bypassed through `any View`). see
`Documentation/MIGRATION_2_0.md` (wave 2) for the flip and the shim.

### ViewModifier Protocol

```swift
public protocol ViewModifier: Sendable {
    /// the only requirement: write into the buffer the content renders through.
    func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer)
}
```

`apply(to html: String)` still exists as a **derived** extension, not a
requirement: it wraps finished html in `Raw` and decorates it, which settles the
attribute at the first element exactly as the old splice did. So a modifier has
one implementation and both doors are that behaviour — the property
`ModifierDecorateTests` asserts for every modifier, and `ModifierContractPinTests`
pins structurally. The inversion removed the old default `decorate`, which had
rendered every unmigrated modifier to a `String` and parsed it back.

Modifiers wrap rendered HTML with additional attributes or styles. They compose
via `ModifiedView<Content>` which preserves the concrete type through the chain.

### ViewBuilder

`@ViewBuilder` is a Swift result builder that lets you compose views declaratively:

```swift
VStack {
    Text("Hello")
    Button("Click")
}
```

a single-expression block preserves the concrete view
type (`buildBlock<V: View>(_ view: V) -> V`); a multi-view block produces a tuple
of concrete views (`TupleView`) when the parameter takes `@ElementBuilder`, and
`[any View]` when it takes `@ViewBuilder`.

the split is not taste, it is the array's one capability: `[any View]` can answer
`count`, `isEmpty` and `enumerated`, and the design-system components use exactly
that to decide markup. the primitives only forward their children, so they take
the typed builder — no array, no per-child box. measured on a 2000-row render,
the typed path costs 165 ns/row against the erased 366 ns/row; on the showcase
page the two are within noise. see `Documentation/DESIGN_NOTES.md` for both
measurements and the reason the earlier arc stalled.

### Primitives

| View | HTML Output | Key Properties |
|---|---|---|
| `Text` | `<span>text</span>` | Escapes HTML entities |
| `Heading` | `<h1>…<h6>` | `HeadingLevel` = `.h1`…`.h6`, escaped |
| `Paragraph` | `<p>text</p>` | escaped |
| `Button` | `<button>label</button>` | `ButtonType` (`.submit`/`.button`/`.reset`), `disabled`, `name` |
| `Input` | `<input type="...">` | 22 html input types, `value`, `placeholder`, `required` |
| `TextArea` | `<textarea>value</textarea>` | `rows`, `placeholder` |
| `Select` | `<select><option>...</select>` | `SelectOption.value/label` |
| `Link` | `<a href="...">text</a>` | URL sanitization blocks javascript: |
| `Image` | `<img src="..." alt="...">` | URL sanitization, `loading` attribute |
| `Form` | `<form action="...">...</form>` | Optional CSRF token hidden field |
| `Raw` | raw HTML passthrough | No escaping — use with care |
| `Spacer` | `<div class="spacer">` | Flexible space in layouts |

### Layouts

| Layout | CSS Display | Behavior |
|---|---|---|
| `VStack` | `flex-direction: column` | Children stacked vertically |
| `HStack` | `flex-direction: row` | Children arranged horizontally |
| `ZStack` | `display: grid` + `place-items` | Children painted in order in one grid cell (`.zstack > *` overlap rule) |
| `Grid` | `display: grid` | CSS Grid with a `GridColumns` track template (`GridColumns.cssValue` inline) |
| `ScrollView` | `overflow: auto` | Scrollable container |

`VStack`/`HStack`/`Grid`/`ZStack` take `spacing` (and, where noted, alignment)
in their initializers; `padding`/`width`/`height` arrive as modifiers.
See `Documentation/LAYOUTS.md` for signatures and output.

### Modifiers

Modifiers are applied via extension methods on `View`:

| Method | Effect | HTML Output |
|---|---|---|
| `.font(size:weight:)` | Sets font size and weight | `style="font-size:16px;font-weight:600"` |
| `.foregroundColor(_:)` | Sets text color | `style="color:#e0e0e0"` |
| `.backgroundColor(_:)` | Sets background color | `style="background-color:#1a1a2e"` |
| `.padding(_:)` | Adds padding | `style="padding:16px"` |
| `.cornerRadius(_:)` | Rounds corners | `style="border-radius:8px"` |
| `.width(_:)` / `.height(_:)` | Sets dimensions | `style="width:100%;height:auto"` |
| `.class(_:)` | Adds CSS class | `class="my-class"` |
| `.id(_:)` | Sets HTML id | `id="my-id"` |
| `.onClick(_:)` | Registers click handler | `data-component-id="c0" data-event="click"` |
| `.onInput(_:)` | Registers input handler | `data-component-id="c1" data-event="input"` |
| `.onSubmit(_:)` | Registers submit handler | `data-component-id="c2" data-event="submit"` |

Event handler modifiers require a `RenderContext` (see Layer 2).

## Layer 2: Event Handling

**Files:** `EventHandling.swift`, `Observable.swift`

### EventRouter

The `EventRouter` connects server-side event handlers to client-side DOM events.

**Flow:**

1. During rendering, `EventHandlerModifier.apply()` reads the `RenderContext`
   from the task-local, generates a unique component ID (`c0`, `c1`, ...), and
   registers the handler closure with the router.

2. The modifier injects `data-component-id="c0" data-event="click"` attributes
   into the HTML element.

3. The JS runtime's event delegation captures DOM events on elements with
   `data-component-id` and sends them as JSON over WebSocket.

4. The server receives the event, calls `EventRouter.handle(EventData)`, which
   looks up the registered handler by component ID and executes it.

5. The handler returns `[FragmentUpdate]` — instructions to patch the DOM.

**Lifecycle:** component ids are positional (`c0`, `c1`, ...) — assigned in
render order. the router therefore maps handler ids one-to-one to a rendered
page. render each page once with a dedicated router, or call `reset()` before
rendering a fresh page (see the "one router per render pass" rule in
`GETTING_STARTED.md`).

**in-place re-render preserves registrations.** `EventRouter.begin(_:preservingRegistrations:)`
resets a session's *mint counters* but keeps its *handler and fallback tables*.
the server uses that shape for the `navigate` answer
(`WebUIServer.answerNavigate`), which re-renders a live page's own region rather
than a fresh page. it has to: the `navigate` frame carries no render token, so it
routes to the shared default session — the session a host that wired its handlers
by hand with `register(_:for:)` registered into — and a full reset there would
drop every control in that session, server-wide, with nothing on the wire to say
so (`dispatch` answers a missing handler with an empty fragment list). the default
(`false`) is the original full reset, which is what makes a re-render idempotent
for render-time registrations. a fresh page instance (`WebUIServer.routePage`,
a token-derived session) still takes the full reset.

the honest cost: after a `navigate` to a *different* route, the previous route's
handlers are no longer dropped. because the mint counters restart, the new render
mints `c0…cn` and overwrites those keys; any leftover keys above `n` name
components that are not in the DOM and can never be triggered, bounded by the
previous render's control count. a host that truly leaves a page can still call
`end(_:)`.

### RenderContext

`RenderContext` is a `@TaskLocal` value that flows through the view tree during
rendering. It provides component ID generation and handler registration.

```swift
var context = RenderContext(router: router)
let html = RenderContext.$current.withValue(context) {
    myView.markup.html
}
```

### ObserverList

`ObserverList` is a thread-safe collection of `Observable` protocol conformers,
synchronized with the Swift `Synchronization` framework's `Mutex` (no
`NSLock`/Foundation in the lock layer). registration is identity-deduped;
rejections at the `maxObservers` cap log a warning instead of failing silently.
observers are retained strongly until removed. delivers to a snapshot taken
under the lock, so mutations from inside an `observe(_:)` callback take effect
on the next `emit`.

**what fires today.** the framework itself emits exactly three event kinds, all
from `EventRouter.handle`: `eventReceived`, `eventHandled`, and `debug`
(missing handler). the remaining cases — `viewRendered`, `fragmentSent`, the
`websocket*` triad, and `error` — are extension points: the framework owns no
transport (the WebSocket servers in the example targets drive NIO directly),
and a view render is a pure function by contract, so a render-timing emission
cannot live inside `render(into:)` without violating that invariant. adopters whose
transport/render layer emits these should route them through
`logger.emit(event, observers:)` so logging and notification stay on the single
funnel. use the stack for logging, metrics, or debugging.

## Layer 3: HTML Document Assembly

**Files:** `HTMLDocument.swift`, `WebUIDocument.swift`, `ClientBoot.swift`

### HTMLDocument

Assembles a complete HTML document from four parts:

| Part | Source | Description |
|---|---|---|
| `body` | Rendered view tree | The page content |
| `styles` | `CSSStylesheet` | Static CSS rules |
| `rawStyles` | `[String]` | Raw CSS strings (e.g., design system) |
| `scripts` | JS source | Inline JavaScript |

The document auto-generates:
- A **CSP** (Content-Security-Policy) with a unique nonce per document
- A **nonce** attribute on all inline `<script>` tags
- Default meta tags (charset, viewport)

At render time the combined css (`styles` + `rawStyles`) is passed through
`minifyCSS()` — `/* */` comments, blank lines, and line padding are stripped
before the `<style>` tag is emitted, so shipped pages carry no css comments.

the design sheet is **layered**: `@layer webui, webui.utilities;` wraps the
framework's rules — components in `webui`, the layout primitives in
`webui.utilities` — so *unlayered* css (an app's own sheet, `rawStyles`, the theme
sheet) outranks the framework by cascade origin rather than by selector weight.
`CascadeLayerTests` scans the served bytes and fails if any rule escapes the
layers; the browser gate proves the consequence (a single-class consumer rule
beats a two-class framework rule).

A `RuntimeConfig?` parameter changes the boot config: when non-empty the page
emits a `<meta name="webui-config" content="{...}">` carrying only the set keys;
otherwise the meta carries `{}` and the engine auto-boots with its defaults.
the legacy inline `WebUIRuntime.init(...)` bootstrap was deleted with the
runtime it belonged to.

### WebUIDocument

Extends `HTMLDocument` with the design system: the layered sheet
(`@layer webui, webui.utilities`, 174 `:root` tokens) plus the layout rules,
hoisted to `DesignSystemAssets.minifiedCss` and served content-addressed
(`/__assets/css.<sha256>`, linked by default). Use this for apps that want the
complete design system.

### ClientBoot

`ClientBoot` is the emitted client boot: it renders the `webui-config` meta and
the `<script src="/ui/webui-engine.js">` tag, and supplies the nonce-aware
default CSP (`csp(nonce:)`). `includeRuntime: false` suppresses both.

## Layer 4: WebSocket Protocol

**Files:** `WebSocketProtocol.swift`, `Assets/webui-engine.js`

### Message Types (Server → Client)

| Type | Payload | Effect |
|---|---|---|
| `update` | `{ fragments: [{id, html}], seq }` | Patch DOM elements |
| `redirect` | `{ url, replace }` | Navigate via `location.href` (or `location.replace` when `replace` is true) — blocks `javascript:`/`data:`/`vbscript:` |
| `state` | `{ path, value }` | Write the client state store at a dot path |
| `reload` | — | Full page reload |
| `error` | `{ code, message }` | Log a server error |
| `pong` | — | Keepalive acknowledgement (clears the pending reconnect timer) |

### Message Types (Client → Server)

| Type | Payload | Effect |
|---|---|---|
| `event` | `{ component, event, data }` | DOM event forwarded to handler |
| `ping` | — | Keepalive heartbeat |
| `navigate` | `{ url }` | Client-side navigation (popstate). answered by re-rendering the matched route into the socket's session as an in-place `update` patch of the page region; a path the router cannot answer is answered with a full-page `redirect`. the re-render PRESERVES registrations made outside a render pass — see "in-place re-render preserves registrations" in Layer 2 |

### JS Runtime Modules

The engine (`webui-engine.js`) is organized around a set of factory functions
plus a `Router` helper and a `createMessageDispatcher` that routes incoming
WebSocket messages to the patcher, state store, and router. the core factories:

| Module | Lines | Responsibility |
|---|---|---|
| `createLogger` | ~15 | Configurable log levels (debug, info, warn, error, silent) |
| `createEventDelegator` | ~190 | Captures DOM events on `[data-component-id]` elements, coalesces input into a single trailing send (trailing + max-wait debounce), and forwards to the WebSocket |
| `createFragmentPatcher` | ~120 | Receives fragment updates and patches the DOM via `createContextualFragment()` + `replaceChild()`. Sanitizes HTML before insertion (strips `<script>`, event handlers, javascript: URLs). Preserves input value, checked state, selection, and keyboard focus across a patch. |
| `createStateStore` | ~75 | Key-value store with dot-path access, change subscriptions, and prototype-pollution protection |
| `createWSClient` | ~140 | WebSocket connection with exponential backoff + jitter reconnect, ping/pong keepalive (a pong clears the pending reconnect timer), message queue, and disconnect handling |

See `Documentation/ARCHITECTURE.md` Layer 5 and `NEXT_ARCHITECTURE.md` layer b for
the engine's delivery contract; the engine's own source is `designer/assets/webui-engine.js`.

## Layer 5: Capability Islands (wasm)

there is no wasm client mode.

the monolith client — `WebUIClient`, a chamber-hosted `designer/assets/webui-client.js`
booting a content-addressed ~55 mb module — was deleted. it fetched and
instantiated that module on every app-mode page for work a ~58 kb runtime does,
and it could not render server views at all. the `webui-wasm` meta contract, the
`ClientBoot(flavor: .wasm, …)` spelling and the `clientMode: ClientBoot(wasmURL: …)`
argument went with it. `designer/assets/` ships four files today: the sheet, the
engine, the legacy runtime and the shell.

what remains is **islands**: a page declares a capability, and that island's
compiled artifact is fetched lazily when the capability first needs it. pure-Swift
logic (a capability target on `WebUIIslandWire`, e.g. `WebUIValidateIsland`)
cross-compiles with the officially hosted swift 6.4 wasm sdk and is served as a
`.wasm` the engine mounts into a declared region. `plugin wasm-island` refuses to
ship an artifact whose graph, symbols, or exports leave that capability's shape.

| mode | rendering brain | event routing | ws |
|---|---|---|---|
| server (default) | NIO + `WebUI` | server `EventRouter` over ws | round trip per event |
| island | server renders; wasm owns one region | page's `EventRouter` for dom events; the island computes locally | only when the island asks |
| static | `includeRuntime: false` | none (warn-and-drop) | none |

building one is the `wasm-island` plugin verb:

```bash
swift package --disable-sandbox plugin wasm-island [--product TheirIsland] [--no-strip]
```

it cross-builds into `.build/wasm-island-scratch` — an isolated root, because the
plugin invocation already holds the package `.build` lock and building into it
would deadlock — strips custom sections (name table + DWARF) unless `--no-strip`
keeps devtools stack traces, and copies the artifact to
`.build/out/Products/Release-webassembly-wasm32/<product>.wasm`. `WebUIWasmTool`
is the strip step's tool (invoked through the plugin's own path, not a build
plugin — there is no `WebUIWasmPlugin`), and it emits a `WebUIWasmInfo` enum from
an artifact. `node designer/browser-smoke.mjs` is what verifies an island is
genuinely browser-hosted once its env imports are linked.

**the typed surface (w3.6):** a page declares an island with the `Island`
protocol and the `IslandRegion<I>` view, and declaring it is the whole wiring:

```swift
public protocol Island: Sendable {
    static var name: String { get }                 // wires to the capability grant
    static func render(_ input: String) -> String
}
public struct IslandRegion<I: Island>: View {       // declares the capability + mounts the region
    public init(_ input: @autoclosure () -> String)
}
```

`Island.name` is the capability grant — the engine fetches
`/__assets/webui-<name>.wasm` only for a name in the emitted `capabilities`
list. `render(_:)` is the same swift on both sides: it compiles (via the
`wasm-island` verb) into the island's `webui_render_region` export, and the
server calls it too for the region's first-render fallback, so an absent
artifact degrades to server-rendered markup (`data-webui-island-state=
"unmapped"`) and the page stays fully static. `IslandRegion` renders the engine's
mount point — `data-webui-island="<name>"` plus a JSON `data-webui-args`
envelope carrying the input as its `input` key, both escaped — and
`WebUIDocument` collects every `data-webui-island` name out of the rendered
body (typed or hand-rolled) and folds it into the emitted `RuntimeConfig`
capabilities, merging with any explicit `runtimeConfig:`/`clientMode:` list
(deduplicated, caller order preserved). a body with no islands leaves the
emitted config byte-identical.

the import-surface pin (a fixed `wasi_snapshot_preview1` + `env` function count,
once asserted by a `WasmIntegrityTests` suite) went with the chamber: it described
that module, not the islands. nothing in-tree asserts an island's import list today.

historical detail — `Documentation/WASM_BOOTSTRAP.md` and
`Documentation/WASM_IMPLEMENTATION_PLAN.md` — was deleted with the chamber; the
island machinery that remains is described in `NEXT_ARCHITECTURE.md` §2c–§2d.

## Layer 6: application state and the multi-tenant host

two products sit above the layers above, and both exist because an app was
hand-rolling them:

```
WebUIHost ──▶ WebUIServer ──▶ WebUICore ──▶ WebUISharedCore
    │
    ├────────▶ WebUIAuth ────▶ WebUI ──▶ WebUICore
    │
    └────────▶ WebUIState
```

`WebUIServer` still has **no edge to `WebUIAuth`** — the absent arrow is the
compile-time proof that identity is not the transport's job. `WebUIHost` is the
only target that knows both, so it is the composition point, not a second server.

### WebUIState — a page as a pure function of state

`Store<State>` is a `final class` over a `Mutex`, not an actor: render is
synchronous (`func render(into:)`, `View` is not `async`), so a store an actor
held could not be read from a body without `await`. mutation is the only write
door, it is serialized, and it bumps a monotonic `revision`.

| type | job |
|---|---|
| `Store<State>` | one page instance's committed state; `read()`, `mutate`/`commit`, `revision` |
| `StatefulPage` | `initialState()` + `body(_ state: State)` — the body receives the only state it may see, by value |
| `StatefulPageSession<Page>` | the render loop: `patch(in:)` renders, diffs the region digest and returns the bytes plus the regions that moved. it begins the router session itself, so a caller must not wrap it in `EventRouter.begin` |
| `SessionStores` | one store per `(page, session)`, bounded; eviction is **idle-only** — a live session is never reaped |
| `PageSubscription` | a commit becomes at most one patch, in revision order |
| `.onClick(binding)` / `.onSubmit(binding)` | the handler mutates and returns nothing; it never authors html |

what a consumer writes:

```swift
struct Counter: StatefulPage {
    struct State: Sendable { var count = 0 }
    func initialState() -> State { State() }
    func body(_ state: State) -> some View {
        VStack {
            Text("count \(state.count)")
            Button("+1").onClick(binding) { store in store.mutate { $0.count += 1 } }
        }
    }
}
```

`binding` is non-nil only inside the loop: a page rendered by hand (`.markup`)
still registers an identical control and logs what is missing when it fires,
rather than silently mutating a store nobody observes.

**honest limits.** a mutation the body does not read produces no visible patch,
because the body is the only thing that renders. and the sugar passes the store,
not the event: a control whose mutation depends on the value it carries (an
input's text, a selected row's key) cannot use `.onClick(binding)`/`.onInput(binding)`
yet — it needs the `(event) -> [FragmentUpdate]` handler, or a future
`(StateBinding, EventData)` overload.

### WebUIHost — principal, catalog, table, revocation

four ports, each naming the rule it makes unrepresentable:

| port | rule |
|---|---|
| `PrincipalResolver` | "a page renders without anyone having decided who asked" — `CookieSessionResolver` is the cookie → token hash → store → principal join |
| `PageCatalog` | "one global page table serves every identity" — `AuthenticatedCatalog` needs a path **and** a principal; `StaticCatalog` is the public-page table |
| `SessionRouterTable` | "a frame minted by session A dispatches into session B's handlers" — `RouterTable` keys routers by `(session, render token)` and keeps a forward chain across LRU eviction, so an evicted page migrates in place instead of losing its handlers |
| `RevocationBus` | "a logged-out session keeps a live socket" — `SocketRevocationBus` closes every connection tracked under the session |

`AuthenticatedHost` is a `struct` façade over those four plus `SessionRevocation`
(the store half of logout) and `IdentityDirectory` (roles). it is a `Responder`,
so it drops into a `Router` route; `dispatch(_:session:renderToken:)` answers one
websocket event with `EventDispatch` (outcome + the token a refresh should hand
the page), and `signOut` tears a session down in the one order that has no window:
sockets, then the handler table, then the store record.

### what these products do not yet carry

named here because the example still pays for them, and a doc that omitted them
would be the rot this file is supposed to avoid:

- **no auth flow.** `WebUIHost` resolves an existing session and revokes one; it
  does not sign anyone in. login/signup ceremony (csrf, throttle, password
  verification, session minting, cookie issuance) stays the application's — it
  is the 77-line `ceremony` section of `Sources/WebUIAuthExample/MainProgram.swift`
  and the only reason that file is not a page plus a `Service`.
- **no extra-route door on `AuthenticatedHostService`.** its primary init builds
  the server's route table from the declared `Page`s, so an app that also serves
  a login form assembles the host and the server itself and hosts them through
  `init(host:server:config:)`. that door also puts the `EventRouter` choice on
  the caller: the server must be handed `SessionPages.events`, or a rendered
  page's controls are unreachable from its socket.
- **no principal-aware initial state.** `SessionPages.render` seeds a session's
  store from `StatefulPage.initialState()`, which sees no request. a page whose
  first state derives from the identity seeds its own store first
  (`SessionPages.store(for:initial:)`) and then renders.
- **no transport peer on `HTTPRequest`.** there is no remote-address field and
  the server does not stamp one, so an app-level per-IP throttle is impossible
  without the client choosing its own key. the auth demo therefore keys its
  submit throttle on the account and its mint budget on a single process-wide
  bucket — a real deployment behind a proxy wants the address, and the field
  does not exist.
- **no upgrade-time authorization, and no Origin check.** `WebUIServer` upgrades
  `GET /ws` before it resolves a session, and never compares `Origin` to `Host`.
  the hand-rolled transport the auth example used to carry did both and answered
  `403`. what still holds is the dispatch gate: no frame drives a session
  without a live render token, so an anonymous socket can open and cannot act.
  restoring the handshake gate belongs in `WebUIServer` (`RequestAuthorizer` is
  already there; the upgrade does not consult it for admission), not in an app.
- **the render-token *refresh* has no transport.** `RouterTable` keeps a forward
  chain and `AuthenticatedHost.dispatch` reports `needsRefresh`, but the server
  dispatches through its own `EventRouter` and never consults the table, so no
  `token` frame reaches a socket. an evicted token keeps routing because its
  render session was never ended — the property holds, the migration notice does
  not.

## Security Architecture

| Threat | Mitigation |
|---|---|
| XSS via fragment injection | the fragment sanitizer parses each patch into a detached DOM subtree (target element as parse context), then strips `<script>` elements, `on*` event-handler attributes, and unsafe `href`/`src`/`action`/`formaction`/`xlink:href` values on the real nodes — the parser resolves character references and quoting, so entity-encoded (`jav&#x61;script:`, `java&Tab;script:`), unquoted, and space-less-handler payloads cannot reach the DOM. the client engine applies the same parse-and-strip to its own fragment writes, so a hostile fragment cannot ride in through a patch either |
| Prototype pollution | `State.set()` rejects keys `__proto__`, `constructor`, `prototype` |
| `javascript:` URLs | `sanitizeURL()` blocks `javascript:`, `data:`, `vbscript:` in Link, Image, Form, and the js Router — c0 controls and ascii whitespace are stripped before the scheme check, matching the browser's parser so padded/obfuscated schemes are caught |
| Attribute injection | `htmlEscape()` on every attribute key and value the framework emits — primitive `id`/`class`/`name`/`for`/`data-status`/`method` parameters included, not just modifiers |
| Accessibility-label injection | every `aria-*`/`role` emission escapes via `htmlEscape()`, including the chart empty-state figure — the one prior raw site, probe-verified fixed (2026-09) |
| SVG icon injection | `IconSanitizer.sanitize()` (applied to every `WebUIIconCustom` body) is a parse-and-reemit **allowlist** — only geometry elements (`path`/`line`/`circle`/`rect`/`polyline`/`polygon`/`ellipse`) and geometry/stroke/fill presentation attributes survive, self-closing and html-escaped; `script`, `foreignObject`, url-bearing attributes, and `on*` handlers are absent by construction, so whitespace- and entity-obfuscated `javascript:`/`data:` schemes cannot ride in (replaced a regex denylist 2026-09). icon `aria-label`/`class`/`data-icon` are `htmlEscape()`d, so a hostile title cannot break out of the attribute (see `Documentation/ICONS.md`) |
| CSP bypass | Auto-generated nonce per document, default CSP with `script-src 'nonce-...'` |
| CSRF | `CSRFProtection` enum with HMAC-SHA256 stateless tokens, optional `Form.csrfToken` parameter — secret/token minting throws on entropy or hmac failure (no prng fallback) and `validate` rejects on signing failure, never accepting an empty signature |
| Stack overflow via deeply nested json | `JSONValue.parse` caps container nesting at 128 (`JSONError.nestingTooDeep`); a nested-bracket frame inside NIO's 16 kb frame budget was probe-verified to segfault the process before the cap (2026-09) |
| Login-token exhaustion | `SingleUseTokenStore` budgets outstanding (reserved, unsubmitted) tokens per issuer key (`maxOutstandingPerKey`, default 5), and the auth demo throttles both the mint page (60/min) and submit attempts (20/min per account) — one caller cannot stockpile login tokens and flood the store past capacity. note: `HTTPRequest` carries no transport peer, so the mint bucket is process-wide rather than per-IP (see "what these products do not yet carry") |
| Cross-session ws replay | pages mint a per-render token (`RuntimeConfig.renderToken`) that the runtime echoes with every `event`/`ping`; the server resolves each message against the render token it names and — under `WebUIServerConfig.requireRenderToken` — answers an unknown or missing token with an `error` frame (`code: "token"`) and closes the socket, so a stale page from another user's (or a former) session cannot drive the current session's router. `RouterTable` additionally keeps a per-session render window with a bounded forward chain, and `AuthenticatedHost.dispatch` reports `needsRefresh` when a token resolved through it; the server's own socket path dispatches through its `EventRouter` and does not consult that table, so no `token` refresh frame reaches a client yet (the gap is named under "what these products do not yet carry"). `requireRenderToken` defaults off so a 1.x host is unaffected; the auth example turns it on |
| wasm compilation under a strict csp | island-capable pages carry `script-src 'self' 'wasm-unsafe-eval'` (still `'self'`, still no `'unsafe-inline'`); `'wasm-unsafe-eval'` only permits wasm compilation, narrowing the old blanket `'unsafe-eval'` risk. the delivered default carries it on every page today — a page that declares no island capability still gets it; scoping it to declared capabilities is a follow-up (`ClientBoot.defaultCSP`) |
| transmitted code | server→client updates carry data, never code: `WSOutgoing` has no script-message type, so a compromised or buggy server response cannot become executable in the page. the engine sanitizes every fragment it applies, so the patch path never bypasses the sanitizer either |
| Large-response truncation | http responses are written through the raw channel and the terminal write's promise is awaited before closing — the async channel writer does not await write promises, so a response larger than the socket send buffer silently lost its tail at close (probe-verified) |
| Data race | `Mutex` (Swift `Synchronization`) on all `EventRouter.State` and `ObserverList` mutations |
| Unbounded growth | Caps on `EventRouter.maxHandlers` (10K) and `ObserverList.maxObservers` (100) |
| Per-request render cost | `WebUIDocument` hoists the minified design sheet (layout rules + embedded css) to a startup constant and embeds it verbatim (`HTMLDocument.preMinifiedStyles`) instead of re-minifying ~350 kb of css per request — probe-measured 11 ms → <0.01 ms in release. `/__assets/css` likewise serves the minified sheet (comment-free; the first law now holds on every endpoint) |
| Event-loop CPU isolation | Argon2id runs on a dedicated `NIOThreadPool` (`--argon2-workers`, default 2), never on a connection's event loop; event handlers are `@Sendable async` and can hop off-loop for heavy work |
| Memory ceiling on small hosts | `ConnectionGate` caps concurrent connections (`--max-connections`, default 256) with admission enforced in the child channel initializer — bare connect-only sockets count toward the cap, so a connect-flood cannot sidestep it — and a 120 s read-idle reaper guards plain http and websockets alike (`--event-loops` sizes the nio group) |
> **note (post-deletion):** the wasm monolith client (`WebUIClientRuntime`,
> `WebUIClient`, the chamber + content-addressed artifact) has been deleted. the
> engine is the client runtime; wasm survives only as capability islands. any
> reference to the client boot below is historical.

## verification ladder

no CI in this repo's gate story (the five-step sketch in `STABILITY.md` is the
headline subset); the full ladder is **fourteen gates plus the byte pin**, each
self-contained and runnable by one human:

| gate | run as | passes expected |
|---|---|---|
| build | `swift build` | clean |
| test | `swift test` | 1774 tests in 9 runs / 0 issues — includes the frozen-surface gate and the showcase byte pin. re-measure rather than trust: the number is the sum of the `Test run with …` lines, because argument-parameterized tests expand and a `@Test` grep over-counts |
| smoke | `swift package --disable-sandbox plugin smoke` | 19/0 |
| fullstack smoke | `swift package --disable-sandbox plugin fullstack-smoke` | 24/0 |
| browser layout | `node designer/browser-smoke.mjs` | 50/0 |
| showcase ws dispatch | `node designer/showcase-ws-smoke.mjs` | 9/0 |
| blocks sweep | `node designer/blocks-sweep.mjs` | 107/0 |
| chart mobile audit | `node designer/chart-mobile-audit.mjs` | 77/0 |
| rtl audit | `node designer/rtl-audit.mjs` | 54/0 |
| acceptance demo | `node designer/acceptance-demo.mjs` | 8/0 |
| event deck probe | `node designer/event-deck-probe.mjs` | 33/33 browser · 32/32 socket · 35 other, 0 fail |
| a11y audit | `node designer/a11y-audit.mjs` | 26/0 |
| cascade probe | `node designer/cascade-probe.mjs` | 12/0 |
| theme default probe | `node designer/theme-default-probe.mjs` | 40/0 |
| engine theme default probe | `node designer/engine-theme-default-probe.mjs` | 5/0 |
| **the byte pin** | `swift run WebUIShowcase --generate <tmp file>` | exactly 168671 bytes — `showcaseArtifactByteCountIsPinned` asserts the count in-process too (`STABILITY.md`, "the showcase byte pin": the *count* is the enforced claim, never a hash of the raw bytes) |

`swift test` (the frozen surface + the byte pin) plus every gate above is run
end-to-end before a wave commits; the byte pin and the frozen surface can each
only move in a committing change that justifies them (`STABILITY.md`).
