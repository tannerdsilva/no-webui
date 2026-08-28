# WebUI Web UI Framework

no-webui is a SwiftUI-for-web framework that renders HTML on the server side and
updates the DOM over WebSocket. zero client-side state management, zero npm,
zero external CSS/JS frameworks — the entire UI compiles into the binary.

## Modules

| Module | Path | Purpose |
|---|---|---|
| `WebUI` | `Sources/WebUI/` | Core: View protocol, ViewBuilder, primitives, layouts, modifiers, CSS system, HTML document assembly, WebSocket protocol, JS runtime |
| `WebUIDesignSystem` | `Sources/WebUIDesignSystem/` | Design system: ~110 CSS custom properties (tokens), 16 styled components (Button, Card, Input, Modal, etc.) |
| `WebUIAuth` | `Sources/WebUIAuth/` | Authentication + sessions: identity model, session tokens, cookies, in-memory + LMDB session stores, Argon2id password verification, constant-time compare, `AuthContext` |
| `WebUIAssetTool` | `Sources/WebUIAssetTool/` | Build-time executable that embeds CSS + JS as Swift string constants |
| `WebUIExample` | `Sources/WebUIExample/` | HTTP/WebSocket example server (SwiftNIO-based counter app) |
| `WebUIAuthExample` | `Sources/WebUIAuthExample/` | Login-gated interactive demo: native-POST login page + authenticated dashboard (admin / password) |

## Quick Start

```swift
import WebUI
import WebUIDesignSystem

// Build a view tree
let page = WebUIDocument(
    title: "Hello",
    body: VStack {
        WebUIButton("Click me", variant: .primary)
        Text("Hello, world!")
    }
)

// Render to HTML
let html = page.render()
// → "<!DOCTYPE html><html lang=\"en\">..."
```

For the full pipeline (HTTP server + WebSocket event handling), see
`Sources/WebUIExample/main.swift` and `Documentation/GETTING_STARTED.md`.

## Rendering Pipeline

```
View tree → render() → HTML string → HTMLDocument → HTTP response
                                              ↓ (WebSocket)
Client event → EventRouter.handle() → [FragmentUpdate] → WS send → DOM patch
```

See `Documentation/ARCHITECTURE.md` for the complete flow. For the login page +
session authentication design (protocols, cookie layer, WebSocket binding,
hardening deltas), see `Documentation/AUTH_SESSIONS.md`; for the item-by-item
execution breakdown, see `Documentation/IMPLEMENTATION_PLAN.md`.

## Tooling

every developer action is a single command — there are no shell scripts. see
`Documentation/ASSEMBLY.md` for the stage map (`swift build`, `swift test`,
`serve`, `smoke`, `fullstack-smoke`, `probe`, `showcase`, and the node browser
gate).

## Design Principles

1. **Server-side rendering** — all HTML is produced on the server. the browser
   receives pre-rendered HTML, not a JS shell.
2. **No client-side state** — the server is the single source of truth. the JS
   runtime only patches DOM fragments and sends events back.
3. **Value types everywhere** — views are structs, rendered and discarded per
   request. no mutable shared state.
4. **Zero JS framework** — the JS runtime is ~800 lines of vanilla JS. no React,
   no Vue, no build step.
5. **Dependency-light** — only swift-log for the core framework. SwiftNIO for
   the example server (not required by the library).