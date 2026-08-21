# JS Runtime

The WebUI JS runtime (`designer/assets/webui-runtime.js`, ~822
lines) is a vanilla JavaScript module that runs in the browser. It has no
dependencies — no React, no jQuery, no build step.

## Module: createLogger

Creates a logger with configurable log levels.

**Parameters:** `logLevel` — one of `debug`, `info`, `warn`, `error`, `silent`

**Returns:** `{ debug, info, warn, error }`

Each method checks the configured minimum level before printing to `console`.

## Module: createEventDelegator

Captures DOM events on elements with `data-component-id` and sends them to the
server over WebSocket.

**Events captured:** `click`, `input`, `change`, `submit`, `keydown`, `focus`,
`blur`, `dblclick`, `contextmenu`, `mouseenter`, `mouseleave`, `touchstart`,
`touchend`, `scroll`, `wheel`

**Mounting:** Adds a single event listener on `document.body` for each event type
(event delegation pattern). Filters to elements with `data-component-id`.

**Input debouncing:** `input` events are debounced (default 300ms, max wait 1000ms)
to avoid flooding the server on every keystroke.

**Submit handling:** On `submit` events, collects all named form fields into a
`{ fieldName: value }` data object and sends as an `event` message.

**Message format:**
```json
{
    "type": "event",
    "component": "c0",
    "event": "click",
    "data": {}
}
```

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

**Patching:** For each fragment, finds the element by `id` and replaces it using
`createContextualFragment()` + `replaceChild()`. This preserves the element's
position and surrounding DOM.

**HTML sanitization:** Before insertion, the HTML is sanitized:
- `<script>` tags are stripped (including content)
- Event handler attributes (`onclick`, `onerror`, `onload`, etc.) are stripped
- `javascript:` URLs in `href`, `src`, `action`, `formaction`, `xlink:href` are
  replaced with empty strings

**Input state preservation:** Before replacing an element, if the element is an
`<input>`, `<textarea>`, or `<select>`, the current value is saved and restored
after replacement. This prevents cursor position loss during live updates.

## Module: createStateStore

A simple key-value store with dot-path access and change subscriptions.

**API:**

| Method | Description |
|---|---|
| `get(path)` | Read a value by dot path (e.g., `"user.name"`). Returns `undefined` for missing paths. |
| `set(path, value)` | Write a value by dot path. Creates intermediate objects as needed. Rejects paths containing `__proto__`, `constructor`, or `prototype`. |
| `subscribe(path, callback)` | Register a change listener. Returns an unsubscribe function. |
| `clear()` | Reset store and remove all subscribers. |

**Security:** The `set()` method checks every path segment against a denylist
(`__proto__`, `constructor`, `prototype`) to prevent prototype pollution attacks.

**Subscriber errors:** Individual subscriber errors are caught and logged — a
failing subscriber does not prevent other subscribers from receiving the event.

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
| `debounceInputMs` | 300ms | Input event debounce delay |
| `debounceMaxWaitMs` | 1000ms | Maximum input debounce wait |

**Reconnection:** Uses exponential backoff starting at 1 second, doubling each
attempt, capped at `wsMaxReconnectDelay`. Jitter is not applied.

**Ping/pong:** Sends `{ type: "ping" }` at `wsPingInterval`. If no `{ type: "pong" }`
response within `wsPongTimeout`, disconnects and reconnects.

**Message queue:** When disconnected, messages are queued (up to `maxQueueSize`).
On reconnect, queued messages are sent in order.

**Lifecycle:**
- `connect()` — opens the WebSocket
- `disconnect()` — closes the WebSocket and clears the queue
- `send(msg)` — sends immediately if connected, queues if disconnected

## Router

A small utility object for client-side navigation:

| Method | Description |
|---|---|
| `navigate(url)` | Push state via `history.pushState` |
| `redirect(url, replace)` | Navigate via `location.href` (or `location.replace` if `replace` is true). Blocks `javascript:`, `data:`, `vbscript:` URLs. |

## Initialization

```javascript
WebUIRuntime.init({
    logLevel: 'warn',
    wsReconnect: true,
    wsMaxReconnectDelay: 30000
});
```

The runtime auto-initializes when the page loads (via the inline `<script>` tag
at the end of `<body>`). It auto-destroys on `beforeunload`.

## Public API

```javascript
WebUIRuntime.init(opts)      // Initialize the runtime
WebUIRuntime.destroy()       // Clean up all resources
WebUIRuntime._reset()        // For testing: reset singleton
WebUIRuntime._getInstance()  // For testing: get current instance
```