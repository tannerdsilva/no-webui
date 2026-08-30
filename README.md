# no-webui

A SwiftUI-for-web framework: server-rendered HTML with a SwiftUI-like declarative
API, a design system with 225 CSS tokens and 22 components, and a JS runtime
for live UI updates.

## Modules

| Module | Description | Dependencies |
|---|---|---|
| `WebUI` | View protocol, primitives, layouts, modifiers, CSS system, HTML document assembly, WebSocket protocol, JS runtime | swift-log, rawdog |
| `WebUIDesignSystem` | design system: 225 CSS custom properties, 22 styled components | WebUI |
| `WebUIAuth` | authentication + sessions: identity model, session tokens, cookies, in-memory + LMDB session stores, Argon2id password verification, `AuthContext` | WebUI, swift-log, QuickLMDB, rawdog |
| `WebUIAssetTool` | build-time executable that embeds CSS + JS as Swift string constants | — |
| `WebUIExample` | HTTP/WebSocket example server (SwiftNIO) | WebUI, WebUIDesignSystem, swift-nio |
| `WebUIAuthExample` | login-gated interactive demo (`admin` / `password`), runs on :9091 | WebUI, WebUIDesignSystem, WebUIAuth, swift-nio |
| `WebUIShowcase` | showcase server + static HTML generator | WebUI, WebUIDesignSystem, swift-nio |
| `WebUISmokeTest` | smoke/demo server hosted by the `serve`/gate plugins on :9123 | WebUI, WebUIDesignSystem, swift-nio |

## Quick start

```swift
import WebUI
import WebUIDesignSystem

let page = WebUIDocument(
    title: "My App",
    body: VStack(spacing: 16) {
        WebUIButton("Click me", variant: .primary, size: .lg)
        WebUICard(variant: .elevated) {
            Text("Hello, world!")
        }
    }
)

print(page.render())
```

See `Sources/WebUIExample/main.swift` and `Documentation/GETTING_STARTED.md`.

## Build and test

```bash
swift build          # WebUIAssetPlugin auto-generates Assets+Generated.swift
swift test           # 398 tests, 35 suites
swift run WebUIExample  # example server on :9090
```

all project tooling is command plugins — no shell scripts. see
`Documentation/ASSEMBLY.md` for the full stage map.

```bash
swift package --disable-sandbox plugin serve    # host the smoke/demo server on :9123 (Ctrl+C stops)
swift package --disable-sandbox plugin smoke    # self-contained smoke gate (server + checks + teardown)
swift package --disable-sandbox plugin fullstack-smoke  # self-contained full-stack gate (live WS round-trips)
node designer/browser-smoke.mjs                 # browser layout gate (playwright, self-contained)
swift package plugin probe 9123                 # is a port in use?
swift package plugin showcase --allow-writing-to-package-directory  # refresh designer/previews/showcase.html
```

## Project structure

```
no-webui/
├── Package.swift
├── Sources/
│   ├── WebUI/                    # web UI framework core
│   ├── WebUIDesignSystem/        # design system
│   ├── WebUIAuth/                # authentication + sessions (LMDB stores)
│   ├── WebUIAssetTool/           # asset embedding tool
│   ├── WebUIExample/             # example server (:9090)
│   ├── WebUIAuthExample/         # login-gated demo server (:9091)
│   ├── WebUIShowcase/            # showcase server + generator
│   └── WebUISmokeTest/           # smoke/demo server (hosted by the plugins)
├── Plugins/
│   ├── WebUIAssetPlugin/         # build tool plugin: embeds designer/assets at build time
│   ├── WebUIServePlugin/         # command plugin `serve`: hosts the server on :9123
│   ├── WebUISmokePlugin/         # command plugin `smoke`: self-contained asset/page gate
│   ├── WebUIFullstackSmokePlugin/# command plugin `fullstack-smoke`: live WS gate
│   ├── WebUIProbePlugin/         # command plugin `probe`: port check
│   └── WebUIShowcasePlugin/      # command plugin `showcase`: regenerates designer/previews/
├── Tests/
│   ├── WebUITests/               # web UI tests
│   └── WebUIAuthTests/           # authentication + session tests
├── Documentation/                # 10 documentation files (incl. ASSEMBLY.md)
├── designer/                     # designer sandbox (CSS/JS only)
├── README.md
└── AGENTS.md
```

## Designer workflow

The `designer/` directory is a CSS/JS-only sandbox for UI design work:

```bash
# Edit assets:
designer/assets/design-system.css
designer/assets/webui-runtime.js

# Preview in browser (instant, no build step):
open designer/previews/designer-preview.html

# See your work in the real framework:
swift package --disable-sandbox plugin serve    # live server on :9123
swift package --disable-sandbox plugin smoke    # asset + page-integrity gate
swift package --disable-sandbox plugin fullstack-smoke  # live WS gate
node designer/browser-smoke.mjs                 # browser layout gate
```

See `designer/README.md` for the full designer guide.

## Documentation

- `Documentation/ARCHITECTURE.md` — framework architecture and design decisions
- `Documentation/ASSEMBLY.md` — project tooling and the build/verification stage map
- `Documentation/API.md` — full API reference
- `Documentation/DESIGN_SYSTEM.md` — design system component reference
- `Documentation/GETTING_STARTED.md` — getting started guide
- `Documentation/JS_RUNTIME.md` — JavaScript runtime API
- `Documentation/LAYOUTS.md` — layout primitives reference
- `Documentation/AUTH_SESSIONS.md` — authentication + sessions design and decisions
- `Documentation/IMPLEMENTATION_PLAN.md` — auth/session implementation plan and status

## Requirements

- Swift 6.2+ (verified on macOS 15 and Ubuntu 24.04 with Swift 6.3.3)
- macOS 15+ **and** Linux — cross-platform from day one
- Dependencies: swift-log, swift-nio, rawdog (v21+ — official sha-256 / hmac suite),
  and QuickLMDB (WebUIAuth's persistent session store; currently a local-path
  dependency until the `rawdog21` branch/tag is pushed)
- node + playwright only for the browser layout gate (`designer/browser-smoke.mjs`)
