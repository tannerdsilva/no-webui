# no-webui

A SwiftUI-for-web framework: server-rendered HTML with a SwiftUI-like declarative
API, a design system with 110 CSS tokens and 16 components, and a JS runtime
for live UI updates.

## Modules

| Module | Description | Dependencies |
|---|---|---|
| `WebUI` | View protocol, primitives, layouts, modifiers, CSS system, HTML document assembly, WebSocket protocol, JS runtime | swift-log |
| `WebUIDesignSystem` | design system: 110 CSS custom properties, 16 styled components | WebUI |
| `WebUIExample` | HTTP/WebSocket example server (SwiftNIO) | WebUI, WebUIDesignSystem, swift-nio |
| `WebUIShowcase` | showcase server + static HTML generator | WebUI, WebUIDesignSystem, swift-nio |

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
swift build           # plugin auto-generates Assets+Generated.swift
swift test            # 238 tests, 11 suites
swift run WebUIExample  # example server on :9090
swift package plugin showcase  # generate showcase HTML
```

## Project structure

```
no-webui/
├── Package.swift
├── Sources/
│   ├── WebUI/                    # web UI framework core
│   ├── WebUIDesignSystem/        # design system
│   ├── WebUIAssetTool/           # asset embedding tool
│   ├── WebUIExample/             # example server
│   └── WebUIShowcase/            # showcase server + generator
├── Plugins/
│   ├── WebUIAssetPlugin/         # build tool plugin for assets
│   ├── WebUIShowcasePlugin/      # command plugin for showcase generation
│   └── WebUIDesignerSync/        # command plugin for designer sync
├── Tests/WebUITests/             # web UI tests (238 tests)
├── Documentation/                # 7 documentation files
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

# Preview in browser:
open designer/previews/designer-preview.html

# Sync into framework:
swift package plugin designer-sync
```

See `designer/README.md` for the full designer guide.

## Documentation

- `Documentation/ARCHITECTURE.md` — framework architecture and design decisions
- `Documentation/API.md` — full API reference
- `Documentation/DESIGN_SYSTEM.md` — design system component reference
- `Documentation/GETTING_STARTED.md` — getting started guide
- `Documentation/JS_RUNTIME.md` — JavaScript runtime API
- `Documentation/LAYOUTS.md` — layout primitives reference

## Requirements

- Swift 6.2+
- macOS 15+
- No external dependencies beyond swift-log and swift-nio
