# Architecture

## Overview

The framework has four layers that connect to form a complete server-rendered
web UI with live DOM updates:

```
┌─────────────────────────────────────────────────────────┐
│                    HTTP Server (your app)                │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │ View Tree   │→ │ HTMLDocument │→ │ HTTP Response  │  │
│  │ (structs)   │  │ (assembly)   │  │ (HTML string)  │  │
│  └─────────────┘  └──────────────┘  └────────────────┘  │
│                        │                                 │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │ EventRouter │← │ WebSocket    │← │ Client Event   │  │
│  │ (dispatch)  │  │ (upgrade)    │  │ (JSON message) │  │
│  └──────┬──────┘  └──────────────┘  └────────────────┘  │
│         │                                                │
│  ┌──────▼──────┐                                         │
│  │ Fragment    │──→ WS send → DOM patch (JS runtime)     │
│  │ Updates     │                                         │
│  └─────────────┘                                         │
└─────────────────────────────────────────────────────────┘
```

## Layer 1: View Tree

**Files:** `View.swift`, `ViewBuilder.swift`, `Primitives.swift`, `Layouts.swift`,
`ModifiedView.swift`, `Modifiers.swift`

Every UI is a tree of `View` conformers. Each view implements `render() -> String`,
producing an HTML fragment. Views are value types — constructed, rendered, and
discarded within a single request.

### View Protocol

```swift
public protocol View: Sendable {
    func render() -> String
}
```

A view's `render()` is a pure function: same inputs always produce the same HTML.
No side effects, no mutable state passed through the tree.

### ViewModifier Protocol

```swift
public protocol ViewModifier: Sendable {
    func apply(to html: String) -> String
}
```

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

It produces `[any View]` — an array of type-erased views. This is intentional:
it keeps the compiler happy without deep generic nesting.

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

### RenderContext

`RenderContext` is a `@TaskLocal` value that flows through the view tree during
rendering. It provides component ID generation and handler registration.

```swift
var context = RenderContext(router: router)
let html = RenderContext.$current.withValue(context) {
    myView.render()
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
and `View.render()` is a pure function by contract, so a render-timing emission
cannot live inside `render()` without violating that invariant. adopters whose
transport/render layer emits these should route them through
`logger.emit(event, observers:)` so logging and notification stay on the single
funnel. use the stack for logging, metrics, or debugging.

## Layer 3: HTML Document Assembly

**Files:** `HTMLDocument.swift`, `WebUIDocument.swift`, `WebUIRuntime.swift`

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

A `RuntimeConfig?` parameter changes the runtime bootstrap: with a non-empty
config the page emits `WebUIRuntime.init({...})` with only the set keys;
otherwise the default `WebUIRuntime.init();` is emitted byte-for-byte.

### WebUIDocument

Extends `HTMLDocument` with the full WebUI design system CSS embedded as a
raw style string (minified on the wire as above). Use this for apps that want
the complete design system.

### WebUIRuntime

A Swift enum with a static `source` property containing the embedded JS runtime
(compiled into the binary via `Assets+Generated.swift`).

## Layer 4: WebSocket Protocol

**Files:** `WebSocketProtocol.swift`, `Assets/webui-runtime.js`

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
| `navigate` | `{ url }` | Client-side navigation (popstate) |

### JS Runtime Modules

The JS runtime (`webui-runtime.js`) is organized around a set of factory
functions plus a `Router` helper and a `createMessageDispatcher` that routes
incoming WebSocket messages to the patcher, state store, and router. the core
factories:

| Module | Lines | Responsibility |
|---|---|---|
| `createLogger` | ~15 | Configurable log levels (debug, info, warn, error, silent) |
| `createEventDelegator` | ~190 | Captures DOM events on `[data-component-id]` elements, coalesces input into a single trailing send (trailing + max-wait debounce), and forwards to the WebSocket |
| `createFragmentPatcher` | ~120 | Receives fragment updates and patches the DOM via `createContextualFragment()` + `replaceChild()`. Sanitizes HTML before insertion (strips `<script>`, event handlers, javascript: URLs). Preserves input value, checked state, selection, and keyboard focus across a patch. |
| `createStateStore` | ~75 | Key-value store with dot-path access, change subscriptions, and prototype-pollution protection |
| `createWSClient` | ~140 | WebSocket connection with exponential backoff + jitter reconnect, ping/pong keepalive (a pong clears the pending reconnect timer), message queue, and disconnect handling |

See `Documentation/JS_RUNTIME.md` for detailed documentation of each module.

## Layer 5: Client Mode (wasm)

client mode compiles the same render core (`WebUICore`) plus the design-system
components (`WebUIDesignSystemCore`) and charts (`WebUIChart`) with the official
swift 6.4 wasm sdk into `WebUIClient.wasm` — a chamber-hosted browser product
(`designer/assets/webui-client.js`). three modes coexist:

| mode | rendering brain | event routing | ws |
|---|---|---|---|
| server (default) | NIO + `WebUI` | server `EventRouter` over ws | round trip per event |
| **client** | wasm (same `render()`) | resident `EventRouter` in the page | silent on the hot path |
| static | `includeRuntime: false` | none (warn-and-drop) | none |

adoption is one argument: `HTMLDocument(…, clientMode: ClientBoot(wasmURL: …))`
emits the `webui-wasm` meta contract + external chamber/boot scripts + the
client csp; `WebUIBoot` hashes the release artifact for the immutable route.
the bridge is a hand-rolled `[UInt8]` JSONValue ABI (trajectory w§3.2): wasm
owns linear memory; the chamber writes event envelopes at `webui_input_ptr`,
calls `webui_handle_event`, reads fragments from the frame, and patches by id.
async handlers run through `swift_task_donateThreadToGlobalExecutorUntil` (the
6.4 cooperative executor's blessed pump) — one call drains spawned tasks and
their awaits to quiescence. full detail: `Documentation/WASM_BOOTSTRAP.md` +
`Documentation/WASM_IMPLEMENTATION_PLAN.md`.

## Security Architecture

| Threat | Mitigation |
|---|---|
| XSS via fragment injection | the fragment sanitizer parses each patch into a detached DOM subtree (target element as parse context), then strips `<script>` elements, `on*` event-handler attributes, and unsafe `href`/`src`/`action`/`formaction`/`xlink:href` values on the real nodes — the parser resolves character references and quoting, so entity-encoded (`jav&#x61;script:`, `java&Tab;script:`), unquoted, and space-less-handler payloads cannot reach the DOM. the wasm chamber applies the same parse-and-strip to its own fragment writes (`applyUpdates`/`setInnerHTML`) and to authoritative fragments arriving over the client transport |
| Prototype pollution | `State.set()` rejects keys `__proto__`, `constructor`, `prototype` |
| `javascript:` URLs | `sanitizeURL()` blocks `javascript:`, `data:`, `vbscript:` in Link, Image, Form, and the js Router — c0 controls and ascii whitespace are stripped before the scheme check, matching the browser's parser so padded/obfuscated schemes are caught |
| Attribute injection | `htmlEscape()` on every attribute key and value the framework emits — primitive `id`/`class`/`name`/`for`/`data-status`/`method` parameters included, not just modifiers |
| Accessibility-label injection | every `aria-*`/`role` emission escapes via `htmlEscape()`, including the chart empty-state figure — the one prior raw site, probe-verified fixed (2026-09) |
| SVG icon injection | `IconSanitizer.sanitize()` (applied to every `WebUIIconCustom` body) is a parse-and-reemit **allowlist** — only geometry elements (`path`/`line`/`circle`/`rect`/`polyline`/`polygon`/`ellipse`) and geometry/stroke/fill presentation attributes survive, self-closing and html-escaped; `script`, `foreignObject`, url-bearing attributes, and `on*` handlers are absent by construction, so whitespace- and entity-obfuscated `javascript:`/`data:` schemes cannot ride in (replaced a regex denylist 2026-09). icon `aria-label`/`class`/`data-icon` are `htmlEscape()`d, so a hostile title cannot break out of the attribute (see `Documentation/ICONS.md`) |
| CSP bypass | Auto-generated nonce per document, default CSP with `script-src 'nonce-...'` |
| CSRF | `CSRFProtection` enum with HMAC-SHA256 stateless tokens, optional `Form.csrfToken` parameter — secret/token minting throws on entropy or hmac failure (no prng fallback) and `validate` rejects on signing failure, never accepting an empty signature |
| Stack overflow via deeply nested json | `JSONValue.parse` caps container nesting at 128 (`JSONError.nestingTooDeep`); a nested-bracket frame inside NIO's 16 kb frame budget was probe-verified to segfault the process before the cap (2026-09) |
| Login-token exhaustion | `SingleUseTokenStore` budgets outstanding (reserved, unsubmitted) tokens per issuer key (`maxOutstandingPerKey`, default 5), and the auth demo throttles both the mint page (60/min/ip) and submit attempts (20/min/ip) — one caller cannot stockpile login tokens and flood the store past capacity |
| Cross-session ws replay | pages mint a per-render token (`RuntimeConfig.renderToken`) that the runtime echoes with every `event`/`ping`; the server resolves each message against the session's current render tokens and answers unknown/missing ones with a redirect + close — a stale page from another user's (or a former) session cannot drive the current session's router. a token this session minted but LRU-evicted resolves through the registry's bounded forward chain: the server pushes the live token as an in-place `token` refresh (no reload) and the runtime adopts it for subsequent echoes |
| wasm compilation under a strict csp | client-mode pages substitute `script-src 'self' 'wasm-unsafe-eval'` (still `'self'`, still no `'unsafe-inline'`); `'wasm-unsafe-eval'` only permits wasm compilation, narrowing the old blanket `'unsafe-eval'` risk |
| transmitted code | structurally impossible in client mode: server→client updates are data into a fixed, pinned wasm (no script-message type). the chamber sanitizes its fragment writes (parse-and-strip, same defense as the server patcher) even though they originate in the pinned binary, so the client path never bypasses the sanitizer |
| import surface | the shipped module imports exactly 34 `wasi_snapshot_preview1` + 8 `env` functions, pinned by `WasmIntegrityTests` — the chamber must implement all of them or instantiation fails |
| Large-response truncation | http responses are written through the raw channel and the terminal write's promise is awaited before closing — the async channel writer does not await write promises, so a response larger than the socket send buffer silently lost its tail at close (probe-verified) |
| Data race | `Mutex` (Swift `Synchronization`) on all `EventRouter.State` and `ObserverList` mutations |
| Unbounded growth | Caps on `EventRouter.maxHandlers` (10K) and `ObserverList.maxObservers` (100) |
| Per-request render cost | `WebUIDocument` hoists the minified design sheet (layout rules + embedded css) to a startup constant and embeds it verbatim (`HTMLDocument.preMinifiedStyles`) instead of re-minifying ~300 kb of css per request — probe-measured 11 ms → <0.01 ms in release. `/__assets/css` likewise serves the minified sheet (comment-free; the first law now holds on every endpoint) |
| Event-loop CPU isolation | Argon2id runs on a dedicated `NIOThreadPool` (`--argon2-workers`, default 2), never on a connection's event loop; event handlers are `@Sendable async` and can hop off-loop for heavy work |
| Memory ceiling on small hosts | `ConnectionGate` caps concurrent connections (`--max-connections`, default 256) with admission enforced in the child channel initializer — bare connect-only sockets count toward the cap, so a connect-flood cannot sidestep it — and a 120 s read-idle reaper guards plain http and websockets alike (`--event-loops` sizes the nio group) |