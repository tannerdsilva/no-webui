# no-webui

A SwiftUI-for-web framework: server-rendered HTML with a SwiftUI-like declarative
API, a design system with 174 CSS custom properties and 133 component types, and a JS runtime
for live UI updates.

## Modules

the package ships 55 targets — 35 in `Sources/` (14 library products, 12
executable products, 3 CLI tools, 1 macro, 5 internal), 11 plugins and 9 test
targets. the consumer-facing ones:

| Module (import) | what it is | depends on |
|---|---|---|
| `WebUI` | the framework: view protocol, primitives, layouts, modifiers, CSS system, `HTMLDocument`/`WebUIDocument` assembly, WebSocket protocol, and the embedded css/js assets | `WebUICore`, swift-log, rawdog |
| `WebUICore` | the render core *without* the embedded assets — view protocol, primitives, layouts, modifiers, `EventRouter`, `JSONValue`, `ClientBoot`. import this when you want the engine without the asset blob | `WebUISharedCore`, swift-log |
| `WebUIDesignSystem` | the design system: 174 CSS custom properties, 133 component types, `WebUITheme`/`ThemePalette`, the `@Theme` macro, `DesignSystemAssets` | `WebUIDesignSystemCore`, `WebUI`, `WebUIDesignSystemMacros` |
| `WebUIDesignSystemCore` | the wasm-clean component layer plus the generated `DesignToken` vocabulary. separate from `WebUIDesignSystem` because the island build reaches `DesignToken` through it precisely to stay rawdog-free | `WebUICore`, swift-log |
| `WebUIChart` | declarative server-rendered inline-SVG charts: 9 mark types (`BarMark`, `LineMark`, `AreaMark`, `PointMark`, `RectangleMark`, `RuleMark`, `SectorMark`, `RadarMark`, `RadialMark`), scales, axes, selection, palette tokens | `WebUICore` |
| `WebUIServer` | the NIO server hosting a page, its assets and the `/ws` socket | `WebUI`, `WebUIDesignSystem`, swift-nio, swift-service-lifecycle |
| `WebUIAuth` | authentication + sessions: identity model, session tokens, cookies, `AuthSessionStore` protocol + in-memory store, Argon2id verification, `AuthContext` | `WebUI`, swift-log, rawdog |
| `WebUIBuild` | host-side asset toolkit: gzip, emitter, manifest, cache headers | rawdog |
| `WebUIBlocks` | standalone page scaffolds — dashboard, login, signup, four sidebar variants, patterns — served one per process by `WebUIBlocksServer` | `WebUI`, `WebUIDesignSystem`, `WebUIChart` |
| `WebUIIslandWire` | the typed island contract (envelope + payload pair) implemented by both host and wasm | `WebUISharedCore` |

the remaining targets are the demo servers (`WebUIExample` :9090,
`WebUIAuthExample` :9091, `WebUIShowcase`, `WebUIShowcaseServer`, `WebUISmokeTest`,
`WebUIBlocksServer`, `WebUIValidateIsland`), the gate-hosting probes
(`WebUIEventDeck` — the event-deck gate's server; `WebUICascadeProbe` — the
cascade gate's two probe pages), the tools (`WebUIAssetTool`, `WebUIIconTool`,
`WebUIWasmTool`) and the shared bits they have in common
(`WebUISharedCore`, `WebUISmokeShared`, `WebUIShowcaseContent`).

the 11 plugins split into 3 **build tools** — `WebUIAssetPlugin` (embeds
`designer/assets` into the `WebUI` target and generates the design-token
vocabulary), `WebUIEmbedPlugin` (embeds a *consumer's* own
`Assets/webui-assets.json`) and `WebUIIconPlugin` (generates
`IconLibrary.swift`) — and 8 **command verbs**, exactly as
`swift package plugin --list` reports them:

```bash
swift package plugin --list
# ‘budget’  ‘fullstack-smoke’  ‘wasm-island’  ‘probe’
# ‘serve’   ‘showcase’         ‘showcase-serve’  ‘smoke’
```

the gate verbs (`serve`, `smoke`, `fullstack-smoke`, `probe`, `wasm-island`) need
`--disable-sandbox`, because the command-plugin sandbox denies `bind()`.

## Quick start

```swift
import WebUI
import WebUIDesignSystem

let page = WebUIDocument(
    title: "My App",
    body: VStack(spacing: 16) {
        WebUIButton("Click me", appearance: .primary, size: .lg)
        WebUICard(elevation: .elevated) {
            Text("Hello, world!")
        }
    }.markup
)

print(page.markup.html)
```

See `Sources/WebUIExample/main.swift` and `Documentation/GETTING_STARTED.md`.

## Build and test

```bash
swift build          # WebUIAssetPlugin auto-generates Assets+Generated.swift
swift test           # 1774 tests, 9 test targets
swift run WebUIExample  # example server on :9090
```

all project tooling is command plugins — no shell scripts. see
`Documentation/ASSEMBLY.md` for the full stage map.

```bash
swift package plugin --list                     # the 8 command verbs
swift package --disable-sandbox plugin serve    # host the smoke/demo server on :9123 (Ctrl+C stops)
swift package --disable-sandbox plugin smoke    # self-contained smoke gate (server + checks + teardown)
swift package --disable-sandbox plugin fullstack-smoke  # self-contained full-stack gate (live WS round-trips)
node designer/browser-smoke.mjs                 # browser layout gate (playwright, self-contained)
swift package plugin probe 9123                 # is a port in use?
swift package plugin showcase --allow-writing-to-package-directory  # refresh designer/previews/showcase.html
```

## what this is — and what it deliberately is not

**this is** a security-hardened, server-authoritative swift web framework:

- the page is a swift `View` tree, rendered **on the server** into html; the
  shipped client is one framework-owned js module — the engine
  (`designer/assets/webui-engine.js`) — which delegates DOM events back over
  a websocket and patches the fragments the server sends. live updates are a
  round trip to the server's `EventRouter`, never a client-side re-render;
- real http on the wire: `HTTPMethod`/`HTTPStatus`, a typed `Router`
  (`Route.get`/`Route.post`/`Route.page`), forms (`FormMethod`, multipart
  uploads via `UploadedFile`), streaming and server-sent events, and
  status/headers/cookies (`HTTPResponse`, `HTTPCookie`);
- a typed design system (174 css custom properties + 133 component types)
  that ships as css compiled into the binary, plus a wasm **capability
  island** path for pure-swift client-side logic;
- zero npm, zero node_modules, zero client-side frameworks: the whole
  client surface is the engine plus the host's own css/script assets.

**this is not** a client-side SPA framework:

- there is no browser `fetch()` API by design. the only `fetch(` in the
  shipped engine (`designer/assets/webui-engine.js`) is the lazy
  capability-island loader — it fetches `webui-<name>.wasm` for a granted
  capability, and nothing else;
- client state is server-owned. the page is a snapshot of server state; the
  client holds a small optimistic mirror that the next authoritative
  `update` replaces and that rolls back on timeout;
- a trapping handler is not contained. `ErrorBoundary` catches *failures*
  (thrown errors, answered as the host's error page or fallback markup); it
  cannot catch a swift *trap* — a `precondition` or force-unwrap takes the
  process down, and process isolation for a trapping handler is explicitly
  not offered (`Documentation/STABILITY.md`).

## Project structure

```
no-webui/
├── Package.swift                  # one manifest: 55 targets, 11 plugins, 9 test targets
├── Sources/                       # 26 target directories
│   ├── WebUI/                     # framework entry: re-exports core + embedded assets
│   ├── WebUICore/                 # render core (view protocol, router, JSONValue, ClientBoot)
│   ├── WebUISharedCore/           # the zero-dependency leaf (shared with island builds)
│   ├── WebUIDesignSystemCore/     # wasm-clean components + generated DesignToken vocabulary
│   ├── WebUIDesignSystem/         # host-facing design system (themes, @Theme macro, documents)
│   ├── WebUIDesignSystemMacros/   # the @Theme macro implementation
│   ├── WebUIChart/                # declarative inline-SVG charts
│   ├── WebUIServer/               # the NIO server + ServiceGroup integration
│   ├── WebUIAuth/                 # authentication + sessions
│   ├── WebUIBuild/                # host-side asset toolkit (gzip, emitter, manifest)
│   ├── WebUIBlocks/               # page scaffolds — also the block-sweep harness
│   ├── WebUIBlocksServer/         # serves one block per process
│   ├── WebUIIslandWire/           # typed island contract (host + wasm)
│   ├── WebUIIslandRuntime/        # the wasi harness (wasm-only)
│   ├── WebUIExample/              # example server (:9090)
│   ├── WebUIAuthExample/          # login-gated demo server (:9091)
│   ├── WebUIShowcase/             # showcase server + static generator
│   ├── WebUIShowcaseServer/       # the served showcase
│   ├── WebUIShowcaseContent/      # the showcase page content (shared by both)
│   ├── WebUISmokeTest/            # smoke/demo server (hosted by the plugins)
│   ├── WebUISmokeShared/          # helpers shared by the smoke + block harnesses
│   ├── WebUIEventDeck/            # event-deck probe server (the event-deck gate's host)
│   ├── WebUICascadeProbe/         # host-cascade probe pages (the cascade gate's host)
│   ├── WebUIValidateIsland/       # the reference capability island
│   └── WebUIAssetTool · WebUIIconTool · WebUIWasmTool   # build tools (CLIs)
├── Plugins/                       # 11 plugin target directories
│   ├── WebUIAssetPlugin/          # build tool: embeds designer/assets; generates tokens
│   ├── WebUIIconPlugin/           # build tool: generates the icon catalog
│   ├── WebUIEmbedPlugin/          # build tool: embeds a consumer's own asset manifest
│   └── WebUIServePlugin/ · WebUISmokePlugin/ · WebUIFullstackSmokePlugin/
│       WebUIProbePlugin/ · WebUIShowcasePlugin/ · WebUIShowcaseServePlugin/
│       WebUIBudgetPlugin/ · WebUIIslandPlugin/         # the 8 command verbs
├── Tests/                         # 9 test targets
│   ├── WebUITests/                # the bulk of the suite (+ WebUIAuthTests, the tool suites)
│   └── WebUIAuthTests/ · WebUIBuildTests/ · WebUIAssetToolTests/
│       WebUIWasmToolTests/ · WebUIIslandFixturesTests/ · WebUIDesignSystemMacroTests/
│       WebUIStateTests/ · WebUIHostTests/
├── Documentation/                 # 18 documentation files (see below)
├── designer/                      # designer sandbox: css/js, icon manifest, node gates, previews
├── CHANGELOG.md
└── AGENTS.md
```

## Designer workflow

The `designer/` directory is a CSS/JS-only sandbox for UI design work:

```bash
# Edit assets:
designer/assets/design-system.css
designer/assets/webui-engine.js

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
- `Documentation/STABILITY.md` — versioning policy, the frozen surface, the deprecation rule
- `Documentation/API.md` — full API reference
- `Documentation/DESIGN_SYSTEM.md` — design system component reference
- `Documentation/CHARTS.md` — charting guide (marks, scales, axes, the responsive width contract)
- `Documentation/LAYOUTS.md` — layout primitives reference
- `Documentation/MIGRATION_2_0.md` — the 2.0 migration guide: every 1.x spelling that changed, wave by wave
- `Documentation/DESIGN_NOTES.md` — decisions made on the strength of a measurement, with the measurement written down
- `Documentation/GETTING_STARTED.md` — getting started guide
- `Documentation/ASSEMBLY.md` — project tooling and the build/verification stage map
- `Documentation/ASSETS.md` — the asset toolkit for hosts (`WebUIBuild`, embed plugin, budgets)
- `Documentation/AUTH_SESSIONS.md` — authentication + sessions design and decisions
- `Documentation/ICONS.md` — icon catalog, tooling and SVG sanitization
- `Documentation/SHEETS_CLASS.md` — the emitted class vocabulary
- `Documentation/NEXT_ARCHITECTURE.md` — the engine + capability-island target architecture
- `Documentation/README.md` — the docs index
- `CHANGELOG.md` (repo root) — all notable changes

## Requirements

- swift-tools-version 6.0; verified on Swift 6.4 (macOS) and the 6.x Linux toolchains
- macOS 15+ **and** Linux — cross-platform from day one
- Dependencies: swift-log (1.x), swift-nio (2.x), swift-service-lifecycle (2.6.x),
  swift-syntax (603.x, for the `@Theme` macro), and rawdog
  (`22.0.0..<23.0.0` — the official sha-256 / hmac / argon2 suite).
  session storage is protocol-driven (`AuthSessionStore`); the core ships an
  in-memory store and no database dependency.
- node + playwright only for the browser layout gate (`designer/browser-smoke.mjs`)
- the wasm island build additionally needs the officially hosted Swift 6.4 wasm
  SDK (the Xcode frontend cannot read its prebuilt modules)
