# Live regions — server-owned updating regions (no-webui)

When a part of your page must update **without** an inbound event — a clock, a counter another
client bumped, a feed, a status panel — register it as a **live region**: a protocol value the
framework renders, change-detects, and pushes. You never poll, never diff, never wire a timer.

## Attach

```swift
import WebUIServer

let regions = WebUILiveRegions([
    ClosureLiveRegion(id: "counter-region") {          // the ergonomic default
        let value = state.count                        // snapshot ONCE, before any await
        return "<span id=\"counter-region\">\(value)</span>"
    },
])
// both WebUIServer inits take `regions:` (defaulted nil — nil means zero new work)
let server = WebUIServer(
    render: { renderPage() },
    router: router,
    config: WebUIServerConfig(port: 9090),
    regions: regions
)
```

the **region id is the DOM id and the pushed fragment id**: render the element with
`id="counter-region"` in the page, and the framework replaces exactly that element when the region
changes.

## The four driver forms (pick one per region)

```swift
// 1. closure default — no state binding; drive it with invalidate(_:)
ClosureLiveRegion(id: "clock", cadence: .seconds(1)) { renderClock() }

// 2. a custom LiveRegion struct — your own state, your own markup
struct TwinRegion: LiveRegion {
    let id: String
    let cadence: Duration?
    let box: LiveBox<Int>
    var source: (any LiveState)? { box }               // non-nil → subscribed at start
    func render() async -> String? {
        let v = box.value                              // one locked snapshot, before any await
        return "<span id=\"\(id)\">\(v)</span>"
    }
}

// 3. LiveBox-backed — the framework's Mutex value is the source of truth
let count = LiveBox(0)
StateLiveRegion(id: "count", state: count) { box in
    "<span id=\"count\">\(box.value)</span>"
}
count.value = 1                                        // → dirty → wake → render → push

// 4. a custom LiveState actor — subscribe MUST be nonisolated (it forwards to a LiveNotifier)
actor FeedState: LiveState {
    private let notifier = LiveNotifier()
    private var items: [String] = []
    nonisolated func subscribe(_ onChange: @escaping @Sendable () -> Void) -> LiveSubscription {
        notifier.add(onChange)
    }
    func append(_ item: String) { items.append(item); notifier.notify() }
}
```

## How updates reach the wire

- **state change** → `source` fires → dirty → wake → `render()` → byte-compare → push.
- **manual** → `regions.invalidate("<id>")` (or `invalidateAll()`), incl. from inside an event
  handler via `RegionInvalidations(["<id>"])` — the handler declares the change and the registry
  renders it; the dispatch frame goes out first (two-push ordering).
- **cadence** → `cadence:` re-renders on a timer through the same dedupe (late ticks skip, never
  stack).

region pushes ride the existing `update` frame + `replace` op — the client runtime needs no new
behavior.

## The semantics that bite (from the framework's own pinned contract)

1. **baseline silence** — `start()` renders every region's baseline and pushes **nothing**.
2. **byte minimality** — an unchanged render pushes **zero** frames; a change pushes **≤ its
   rendered html + 512 B**. the framework byte-compares; you never diff.
3. **stable ids only** — a render closure must use caller-stable DOM ids; a minted id (no DOM id)
   grows the router's handler map and logs a warning. re-rendering a stable id is overwrite-wins.
4. **`source` + stop** — the registry subscribes non-nil sources at `start()`, before baselines,
   and cancels at `stop()`; `LiveSubscription.cancel()` is idempotent. a custom actor's
   `subscribe` witness must be `nonisolated` — a sync hop onto a busy actor can block start.
5. **`nil` render = nothing to push** — use it when a region has no content yet.
6. **notify-after-unlock** — `LiveBox`/`LiveNotifier` deliver strictly after the lock releases;
   your render closure snapshots the value **once**, before any `await`.
7. **`currentHTML(id)` is best-effort** — the last committed render at the instant of the call, a
   host-scoped baseline, **not** a per-client snapshot. do not build per-client logic on it.
8. **zero frames after `stop()`**; unknown ids and a not-yet-started registry are debug no-ops.

## Gotchas

- **declaring the region id without rendering it**: the push targets `#<id>`; if the served page
  does not contain that element the update is a no-op in the browser. render it once server-side.
- **renders run inside the render context** — a control a region emits self-registers; keep its
  ids stable or you grow the handler map (warning: `live region '<id>' grew the handler map`).
- **don't reach for `Timer`/`Task.sleep` loops** — that is exactly the layer the region seam
  hosts. a `cadence` re-renders; a `source` wakes on change; `invalidate` wakes on demand.