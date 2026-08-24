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

`WebUIDocument` includes the full design system CSS (303KB, ~110 CSS custom
properties, 16 styled components). See `Documentation/DESIGN_SYSTEM.md` for the
complete component catalog.
