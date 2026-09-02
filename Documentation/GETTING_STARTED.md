# Getting Started

This guide walks through building a complete server-rendered page with live
WebSocket updates — a click counter.

## 1. Define a View

```swift
import WebUI

struct CounterPage: View {
    let count: Int

    func render() -> String {
        VStack(spacing: 16) {
            Text("Count: \(count)")
                .font(size: 32, weight: "700")

            Button("Increment")
                .onClick { event in
                    // handler registered during rendering
                    return []
                }
        }
        .padding(32)
        .render()
    }
}
```

## 2. Create an EventRouter

```swift
let router = EventRouter()
```

The router stores handler closures keyed by component ID. During rendering,
`EventHandlerModifier` reads the `RenderContext`, generates IDs, and registers
handlers.

## 3. Render with Context

```swift
var context = RenderContext(router: router)
let html = RenderContext.$current.withValue(context) {
    CounterPage(count: 0).render()
}
```

The `@TaskLocal` `RenderContext` flows through the view tree. Any
`EventHandlerModifier` in the tree will register its handler with the router.

## 4. Assemble the Document

```swift
let doc = HTMLDocument(
    title: "Counter",
    body: html
)
let pageHTML = doc.render()
```

`HTMLDocument` wraps the body in a full HTML document with:
- Auto-generated CSP with a unique nonce
- Nonce attribute on the inline `<script>` tag
- The WebUI JS runtime embedded
- Default meta tags

## 5. Serve Over HTTP

```swift
// Using SwiftNIO (see Sources/WebUIExample/main.swift for full code)
let bootstrap = ServerBootstrap(group: group)
    .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
            channel.pipeline.addHandler(HTTPHandler(pageHTML: pageHTML))
        }
    }
let channel = try await bootstrap.bind(host: "0.0.0.0", port: 9090).get()
```

## 6. Handle WebSocket Events

the client sends a wrapped `{type:"event", component, event, data}` frame.
decode it as `WSIncoming`, route it through `router.handle`, and wrap the
resulting fragments in `WSOutgoing.update(fragments:)` so the runtime patches
the targets:

```swift
func onMessage(_ text: String) async {
    guard let data = text.data(using: .utf8),
          let msg = try? JSONDecoder().decode(WSIncoming.self, from: data)
    else { return }

    switch msg {
    case .event(let component, let event, let data):
        let eventData = EventData(component: ComponentID(component), event: event, data: data)
        let updates = await router.handle(eventData)
        let out = WSOutgoing.update(fragments: updates)
        // encode(out) and send — see Sources/WebUIExample/main.swift
    case .ping:
        // reply with WSOutgoing.pong
        break
    case .navigate:
        break
    }
}
```

## 7. Wire Up Event Handlers

the framework auto-generates `data-component-id` for every `.onClick` /
`.onInput` modifier and registers the handler in one step — you never hand-
manage it. state lives in a class, and the handler re-renders the fragment it
patches:

```swift
struct CounterPage: View {
    let state: CounterState

    func render() -> String {
        var context = RenderContext(router: state.router)
        return RenderContext.$current.withValue(context) {
            VStack(spacing: 16) {
                Raw(counterValueHTML(state.count))
                Button("Increment")
                    .onClick { _ in
                        state.count += 1
                        return [FragmentUpdate(id: "counter-value", html: counterValueHTML(state.count))]
                    }
            }
            .render()
        }
    }
}
```

`EventHandlerModifier` (the thing behind `.onClick`) assigns the element its
auto `data-component-id` during render and registers the handler — the two
halves of the wiring are one step. the `id:` initializer / `.id(...)` modifier
is what names the element your `FragmentUpdate` patches; keep the two strings
in lockstep.

### Escape Hatches

the manual path is only for cases the modifier style can't express:

- `context.register(handler:, for:)` registers under a `ComponentID` of your
  choosing. the client echoes back whatever `data-component-id` is on the
  element, so a manually-registered id must match an element's *auto* id — not
  the HTML `id:` you picked for patches.
- `context.nextComponentID()` returns the next auto id (`c0`, `c1`, ...) if you
  need to register a handler for an element without using a modifier.

### How IDs Work (the three kinds)

| id | who sets it | who consumes it | example |
|---|---|---|---|
| `data-component-id` | auto, by `EventHandlerModifier` via `context.nextComponentID()` | the js runtime reads it and echoes it back as `component`; the router looks up the handler | `data-component-id="c0"` |
| HTML `id` | you, via `id:` / `.id(...)` | `FragmentUpdate(id:)` -> `getElementById` | `id="counter-value"` |
| manual `ComponentID` | you, via `context.register(handler:for:)` | `EventRouter.handle` | `"increment-btn"` |

### One Router Per Render Pass

component ids (`c0`, `c1`, ...) are assigned in render order, and handlers are
registered by id. a single `EventRouter` shared across concurrent page renders
interleaves registrations, so a fresh render against the same router re-uses
stale ids. the rule: render once per page load and keep that router, or call
`router.reset()` before rendering a fresh page. servers that render per
request should give each request its own `EventRouter`.

## Complete Example

See `Sources/WebUIExample/main.swift` for the working HTTP + WebSocket server:
it renders the live counter + echo page, upgrades `/ws`, and round-trips events
end to end. run it with `swift run WebUIExample` and open http://localhost:9090.

## Using the Design System

```swift
import WebUIDesignSystem

let page = WebUIDocument(
    title: "Styled Page",
    body: VStack(spacing: 24) {
        WebUIButton("Primary Action", variant: .primary, size: .lg)
        WebUIButton("Delete", variant: .danger, disabled: true)
        WebUICard {
            Text("Card content")
        }
        WebUIInput(placeholder: "Enter text...")
    }
    .padding(32)
)
```

`WebUIDocument` includes the full design system CSS (~300KB source, 225 CSS
custom properties, 22 styled components). shipped pages minify the css at
render time (comments and blank lines stripped), so the wire payload is
smaller than the source. See `Documentation/DESIGN_SYSTEM.md` for the complete
component catalog.

### Dismissible Components

`WebUIAlert(dismissible:)`, `WebUIToast(dismissible:)`, `WebUIModal`, and
`WebUIChip(removable:)` are all `Dismissible` views. attach a handler with
`.onDismiss { me, _ in ... }` and the close button becomes a routed component —
the framework allocates its component id, registers the handler, and hands you
an `ElementRef` (`me`) to the component's own root element. no container
handler, no class-string matching, no id strings:

```swift
WebUIDocument(
    title: "Notifications",
    body: Div {
        WebUIToast(message: "Saved", id: "toast-saved")
            .onDismiss { me, _ in
                // server truth: drop it from state
                state.toasts.removeAll { $0.id == "toast-saved" }
                // DOM truth: remove the element itself
                return [me.remove()]
            }
    }
)
```

each `.onDismiss` wires exactly its own close button, so N dismissibles in one
container route independently — no disambiguation strings, ever. the handler
receives `me` even when the component carries no `id:`; the framework mints an
element id (`e0`, `e1`, ...) for the render pass. `me` also supports
`replace(with:)` and `update(view)` for swapping the element's contents.

`me.remove()` emits `FragmentUpdate(id:, html: "")`; the runtime treats an
empty fragment as element removal (`el.remove()`). this is a pinned, documented
contract (see `JS_RUNTIME.md`) and the preferred way to clear a dismissed
component — no container re-render needed.

the legacy container-handler pattern is still supported unchanged: without an
`.onDismiss` handler the close button renders the static `data-dismiss`/
`data-remove` marker exactly as before, and a container `.onClick` can match
`event.data["targetClass"]`/`event.data["targetId"]` to decide what dismissal
means. prefer `.onDismiss` — it removes the class-string matching entirely.

the same typed-handle medicine extends to the interactive data components:
`WebUITable` (`.onSort { me, column in }`, `.onSelectAll`, `.onSelect`,
`.onToggleExpand`), `WebUIPagination` (`.onPageChange { me, page in }`,
`.onRowsPerPageChange`), and `WebUIChart` (`.onSelectMark { me, category in }`)
all self-wire their controls as routed components and hand the handler an
`ElementRef` + typed payload — no `targetId`/`targetClass` string matching
anywhere. see `DESIGN_SYSTEM.md`, `CHARTS.md`, and `API.md` for the full
before/after. the legacy container pattern remains available for all of them.
