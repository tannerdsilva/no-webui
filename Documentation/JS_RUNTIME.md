# JS Runtime

The WebUI JS runtime (`designer/assets/webui-runtime.js`, ~750 lines) is a
vanilla JavaScript module that runs in the browser. It has no dependencies —
no React, no jQuery, no build step. It ships embedded in every rendered page
and auto-initializes on load.

## Module: createLogger

Creates a logger with configurable log levels.

**Parameters:** `logLevel` — one of `debug`, `info`, `warn`, `error`, `silent`

**Returns:** `{ debug, info, warn, error }`

each method checks the configured minimum level before printing to `console`.

## Module: createEventDelegator

Captures DOM events on elements with `data-component-id` and sends them to the
server over WebSocket.

**Events captured:** `click`, `input`, `change`, `submit`, `keydown`, `keyup`,
`keypress`, `focus`, `blur`, `focusin`, `focusout`, `mouseover`, `mouseout`,
`mousedown`, `mouseup`

**Event filtering:** each interactive element carries a declared `data-event`
(the event its handler was registered for). only events matching the declared
type are dispatched — a `click`-only component never receives the `mousedown`/
`mouseup`/`mouseover` events that a real click also fires. `focus`/`blur` do
not bubble, so the runtime listens for the bubbling `focusin`/`focusout` and
normalizes them: a component declaring `data-event="focus"` receives focusin,
`data-event="blur"` receives focusout, and `data-event="focusin"/"focusout"`
components receive the raw event. events are echoed back to the server under
the declared name, so the swift handler always sees the modifier it attached.

**Enter key:** a `keydown` Enter on an interactive component is
`preventDefault()`-ed to suppress double form submission — unless the target
is a `TEXTAREA` or `contentEditable` (newlines keep working) or the component
declares `data-prevent-enter="false"` (settable from swift via
`.attribute("data-prevent-enter", "false")`).

**Mounting:** adds a single event listener on `document` for each event type
(event delegation pattern). filters to the nearest element carrying
`data-component-id`. `findComponent` walks `composedPath()` (capped at 20
hops) and, when the target has no component ancestor, falls back to the
element's `labels` / `label[for=id]` so inputs whose `data-component-id` sits
on the surrounding `<label>` still route.

**Input debouncing:** `input` events are debounced with trailing + max-wait
semantics. the trailing delay is `debounceInputMs` (default 300ms) and the
max-wait cap is `debounceMaxWaitMs` (default 1000ms). a burst of keystrokes on
a field coalesces into a single trailing send, and the max-wait guarantees a
send even while the user keeps typing. `change`, `blur`, and `submit` are not
debounced — they send immediately so no input is lost when typing stops, the
field loses focus, or the form submits.

**Submit handling:** on `submit` events, collects all named form fields into a
`{ fieldName: value }` data object and sends as an `event` message. checkbox
and radio values are only included when checked, `select-multiple` values are
joined into a comma-separated string, and file inputs are skipped — so every
value on the wire stays a string (the server's `EventData.data` is
`[String: String]`).

**Message format:**
```json
{
    "type": "event",
    "component": "c0",
    "event": "click",
    "data": { "targetId": "btn-inc", "targetClass": "button button--primary button--md" }
}
```

`click` sends `targetId` and `targetClass` for the clicked element, so a
single container `.onClick` handler can tell *what* was clicked (for example
which `data-dismiss` button). other events send the standard `{ value: ... }`
or `{}` payloads.

## Module: createFragmentPatcher

Receives fragment updates from the server and patches the DOM.

**Input format:**
```json
{
    "type": "update",
    "fragments": [
        { "id": "counter-value", "html": "<span>42</span>" }
    ],
    "seq": 1
}
```

**Patching:** for each fragment, finds the element by `id` and replaces it
using `createContextualFragment()` + `replaceChild()`. this preserves the
element's position and surrounding DOM.

**HTML sanitization:** before insertion, the HTML is sanitized:
- numeric and named character references (`&#x61;`, `&#97;`, `&colon;`) are
  decoded first — the DOM would decode them anyway — so entity-encoded
  `javascript:` URLs cannot slip past the checks
- `<script>` tags are stripped (including content)
- event handler attributes (`onclick`, `onerror`, `onload`, etc.) are stripped
- `javascript:` URLs in `href`, `src`, `action`, `formaction`, `xlink:href` are
  replaced with empty strings

**Input state preservation:** before replacing an element, if the element
contains an `<input>`, `<textarea>`, or `<select>`, the current value, checked
state, and selection range are saved and restored after replacement. this
prevents value and caret loss during live updates.

**Focus preservation:** the patcher also records which control had keyboard
focus before the patch. if the replacement fragment contains that same control
(identified by id, name, or position), focus and caret are restored after the
swap. this keeps the user's typing position intact when a re-rendered fragment
includes the field they are editing — a common source of perceived jitter.

## Module: createStateStore

A simple key-value store with dot-path access and change subscriptions.

**API:**

| Method | Description |
|---|---|
| `get(path)` | Read a value by dot path (e.g., `"user.name"`). returns `undefined` for missing paths. |
| `set(path, value)` | Write a value by dot path. creates intermediate objects as needed. rejects paths containing `__proto__`, `constructor`, or `prototype`. |
| `subscribe(path, callback)` | Register a change listener. returns an unsubscribe function. |
| `clear()` | Reset store and remove all subscribers. |

**Security:** the `set()` method checks every path segment against a denylist
(`__proto__`, `constructor`, `prototype`) to prevent prototype pollution
attacks.

**Subscriber errors:** individual subscriber errors are caught and logged — a
failing subscriber does not prevent other subscribers from receiving the
event.

## Module: createWSClient

Manages the WebSocket connection with automatic reconnection.

**Configuration:**

| Option | Default | Description |
|---|---|---|
| `wsUrl` | auto-detected | WebSocket URL (derived from page URL if omitted) |
| `wsReconnect` | `true` | Auto-reconnect on disconnect |
| `wsMaxReconnectDelay` | 30000ms | Maximum delay between reconnection attempts |
| `wsPingInterval` | 30000ms | Interval for ping messages |
| `wsPongTimeout` | 60000ms | Time to wait for pong before reconnecting |
| `maxQueueSize` | 1000 | Maximum queued messages when disconnected |
| `debounceInputMs` | 300ms | Input event trailing debounce delay |
| `debounceMaxWaitMs` | 1000ms | Maximum input debounce wait |
| `optimisticSettleMs` | 5000ms | Unconfirmed optimistic patch rollback timeout |
| `logLevel` | `warn` | One of `debug`, `info`, `warn`, `error`, `silent` |

**Reconnection:** uses exponential backoff starting at 1 second, doubling each
attempt, capped at `wsMaxReconnectDelay`. a jitter multiplier of 0.5–1.5× is
applied to the computed delay so simultaneous clients do not reconnect in
lockstep.

**Ping/pong:** sends `{ type: "ping" }` at `wsPingInterval`. if no
`{ type: "pong" }` response arrives within `wsPongTimeout`, the connection is
considered dead and reconnected. when a pong does arrive, the pending
reconnect timer is cleared, so a healthy connection never triggers a spurious
reconnect.

**Message queue:** when disconnected, messages are queued (up to
`maxQueueSize`). on reconnect, queued messages are sent in order.

**Lifecycle:**
- `connect()` — opens the WebSocket. a safe no-op (warns and returns) when the
  environment has no `WebSocket` global.
- `disconnect()` — closes the WebSocket and clears the queue
- `send(msg)` — sends immediately if connected, queues if disconnected

## Router

A small utility object for client-side navigation:

| Method | Description |
|---|---|
| `navigate(url)` | Push state via `history.pushState` |
| `redirect(url, replace)` | Navigate via `location.href` (or `location.replace` if `replace` is true). blocks `javascript:`, `data:`, `vbscript:` URLs. c0 controls and ascii whitespace are stripped from the url before the protocol check — mirroring the browser's own parser — so padded/obfuscated schemes are blocked too. |
| `reload()` | Reload the page via `location.reload()` |

## Initialization

```javascript
WebUIRuntime.init({
    logLevel: 'warn',
    wsReconnect: true,
    wsMaxReconnectDelay: 30000
});
```

The runtime auto-initializes when the page loads (via the inline `<script>` tag
at the end of `<body>`). the default bootstrap is `WebUIRuntime.init();`. when
a swift `RuntimeConfig` is passed to `HTMLDocument`/`WebUIDocument`, the
bootstrap instead carries an options object with only the set keys
(`WebUIRuntime.init({"wsUrl":...,"debounceInputMs":150,...})`). it auto-destroys
on `beforeunload`, which disconnects the WebSocket, unmounts event delegation,
resets the fragment patcher, clears the state store, and removes the
`popstate` listener it registered.

## Public API

```javascript
WebUIRuntime.init(opts)      // Initialize the runtime
WebUIRuntime.destroy()       // Clean up all resources
WebUIRuntime._reset()        // For testing: reset singleton
WebUIRuntime._getInstance()  // For testing: get current instance
```
