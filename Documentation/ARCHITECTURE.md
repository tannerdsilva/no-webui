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
| `Button` | `<button>label</button>` | `disabled`, `loading`, `fullWidth` |
| `Input` | `<input type="...">` | Supports text, password, email, number, checkbox, radio, file, date |
| `TextArea` | `<textarea>value</textarea>` | `rows`, `placeholder` |
| `Select` | `<select><option>...</select>` | `options: [(label, value)]` |
| `Link` | `<a href="...">text</a>` | URL sanitization blocks javascript: |
| `Image` | `<img src="..." alt="...">` | URL sanitization, `loading` attribute |
| `Form` | `<form action="...">...</form>` | Optional CSRF token hidden field |
| `Raw` | raw HTML passthrough | No escaping — use with care |
| `Spacer` | `<div class="spacer">` | Flexible space in layouts |
| `Divider` | `<hr>` | Thematic break |

### Layouts

| Layout | CSS Display | Behavior |
|---|---|---|
| `VStack` | `flex-direction: column` | Children stacked vertically |
| `HStack` | `flex-direction: row` | Children arranged horizontally |
| `ZStack` | `position: relative` + absolute | Children layered on z-axis |
| `Grid` | `display: grid` | CSS Grid with `columns` parameter |
| `ScrollView` | `overflow: auto` | Scrollable container |

All layouts accept `spacing`, `alignment`, `padding`, and `width`/`height`
parameters. See `Documentation/LAYOUTS.md` for examples.

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

`ObserverList` is a thread-safe collection of `Observable` protocol conformers.
Observers receive `ObservableEvent` values for every framework event (rendering,
event handling, WebSocket state changes). Use for logging, metrics, or debugging.

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

### WebUIDocument

Extends `HTMLDocument` with the full WebUI design system CSS embedded as a
raw style string. Use this for apps that want the complete design system.

### WebUIRuntime

A Swift enum with a static `source` property containing the embedded JS runtime
(compiled into the binary via `Assets+Generated.swift`).

## Layer 4: WebSocket Protocol

**Files:** `WebSocketProtocol.swift`, `Assets/webui-runtime.js`

### Message Types (Server → Client)

| Type | Payload | Effect |
|---|---|---|
| `update` | `{ fragments: [{id, html}], seq }` | Patch DOM elements |
| `redirect` | `{ url, replace }` | Navigate via `location.href` or `history.replaceState` |

### Message Types (Client → Server)

| Type | Payload | Effect |
|---|---|---|
| `event` | `{ component, event, data }` | DOM event forwarded to handler |
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

## Security Architecture

| Threat | Mitigation |
|---|---|
| XSS via fragment injection | `sanitizeFragmentHTML()` strips `<script>`, event handlers, javascript: URLs before DOM insertion |
| Prototype pollution | `State.set()` rejects keys `__proto__`, `constructor`, `prototype` |
| `javascript:` URLs | `sanitizeURL()` blocks `javascript:`, `data:`, `vbscript:` protocols in Link, Image, Form, Router |
| Attribute injection | `htmlEscape()` on all attribute keys and values in modifiers |
| CSP bypass | Auto-generated nonce per document, default CSP with `script-src 'nonce-...'` |
| CSRF | `CSRFProtection` enum with HMAC-SHA256 stateless tokens, optional `Form.csrfToken` parameter |
| Data race | `NSLock` on all `EventRouter.State` and `ObserverList` mutations |
| Unbounded growth | Caps on `EventRouter.maxHandlers` (10K) and `ObserverList.maxObservers` (100) |