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

When a WebSocket message arrives, decode it as `EventData` and pass to the router:

```swift
func onMessage(_ text: String) async {
    guard let data = text.data(using: .utf8),
          let event = try? JSONDecoder().decode(EventData.self, from: data)
    else { return }

    let updates = await router.handle(event)
    // Send updates as JSON over WebSocket
    let json = try? JSONEncoder().encode(updates)
    ws.send(String(data: json, encoding: .utf8)!)
}
```

## 7. Wire Up Event Handlers

The counter needs actual state:

```swift
struct CounterPage: View {
    let count: Int
    let router: EventRouter

    func render() -> String {
        var context = RenderContext(router: router)

        // Register the increment handler
        context.register(handler: { event in
            let newCount = self.count + 1
            let newHTML = CounterPage(count: newCount, router: self.router).render()
            return [FragmentUpdate(id: "counter", html: newHTML)]
        }, for: "increment-btn")

        return RenderContext.$current.withValue(context) {
            VStack(spacing: 16) {
                Text("Count: \(count)")
                    .id("counter")
                    .font(size: 32, weight: "700")

                Button("Increment")
                    .onClick { _ in [] }
            }
            .padding(32)
            .render()
        }
    }
}
```

## Complete Example

See `Sources/WebUIExample/main.swift` for a working HTTP/WebSocket server
that implements a click counter with the full pipeline.

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

`WebUIDocument` includes the full design system CSS (311KB, ~110 CSS custom
properties, 16 styled components). See `Documentation/DESIGN_SYSTEM.md` for the
complete component catalog.