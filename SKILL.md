---
name: no-webui
description: Work on the no-webui framework itself (maintainer): repo layout, swift build/test, the command-plugin verbs (serve/smoke/fullstack-smoke/probe/showcase/showcase-serve), asset embedding + icon pipeline, generated files, security invariants, house style, and maintainer pitfalls. For building an APP that uses the public API, load webui-design-system instead.
version: 1.3.0
author: Tanner D'silva, Hermes Agent
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [no-webui, swiftui-for-web, webui, swift, design-system, maintainer, internal]
    related_skills: [webui-design-system, agent-chat-ui]
---

# no-webui — developing the framework (maintainer)

This skill is for **working on the no-webui Swift package itself**: building it,
running its gates, editing its designer assets/icons, and fixing the framework.
If you're building an **app** that composes no-webui's public API (an agent
host, a dashboard, a demo), load **`webui-design-system`** — this is the
internal skill, and the consumer-facing guidance lives there (plus the repo's
`AGENTS.md` and `Documentation/*`, which are canonical).

## Repo layout (one Package.swift)

- **Library products:** `WebUI`, `WebUIDesignSystem`, `WebUIChart`, `WebUIAuth`.
- **Executables:** `WebUIExample` (:9090 demo), `WebUIAuthExample` (auth demo),
  `WebUIShowcase` (generates/serves the reference showcase),
  `WebUISmokeTest` (the interactive page the smoke gates drive),
  `WebUIShowcaseServer` (live swift-generated showcase on :9092).
- **`designer/`** — the design system's working dir: `assets/design-system.css`
  + `assets/webui-runtime.js` (canonical, read at build time), 
  `icons/icon-manifest.json`, `previews/` (regenerated artifacts).
- **Shared composition libs:** `WebUISmokeShared`, `WebUIShowcaseContent`
  (holds `ShowcasePage`, shared by the generator and the live server).

## Build & test

```bash
swift build        # plugins regenerate Assets+Generated.swift, DesignTokens+Generated.swift, IconLibrary.swift
swift test         # the always-on gate (asserts embedded css/js == designer/assets sources)
swift run WebUIExample   # example server on :9090
```

The wasm client product needs `source ~/.swiftly/env.sh` and the official
`swift-6.4-RELEASE_wasm` SDK (the Xcode frontend can't read its prebuilt
modules). Full stage map: `Documentation/ASSEMBLY.md`.

## Plugin verbs (command plugins)

| verb | run | what it does |
|---|---|---|
| `serve` | `swift package --disable-sandbox plugin serve` | hosts the WebUISmokeTest server on :9123 (Ctrl+C to stop) |
| `smoke` | `swift package --disable-sandbox plugin smoke` | self-contained gate: spawn server, check served bytes/asset integrity/page signatures/CSP/interactive count, tear down |
| `fullstack-smoke` | `swift package --disable-sandbox plugin fullstack-smoke` | drives live WS round-trips (click/echo/redirect/optimistic) |
| `probe` | `swift package plugin probe [port]` | connect-based port check |
| `showcase` | `swift package plugin showcase --allow-writing-to-package-directory` | regenerates `designer/previews/showcase.html` |
| `showcase-serve` | `swift package --disable-sandbox plugin showcase-serve` | hosts the live swift-generated showcase on :9092 |
| `wasm-island` | `swift package --disable-sandbox plugin wasm-island [--product TheirIsland] [--no-strip]` | cross-builds a capability island with the wasm SDK into the isolated `.build/wasm-island-scratch` root (strips name table + DWARF unless `--no-strip`) and copies it to `.build/out/Products/Release-webassembly-wasm32/<product>.wasm`; `WebUIWasmTool` strips and emits the `WebUIWasmInfo` metadata carrier |
| `budget` | `swift package plugin budget` | fails when any shipped surface (engine, design-system sheet, shell, island artifact) exceeds its pinned size ceiling. read-only, no sandbox flag |

- **`--disable-sandbox` is mandatory for `serve`/`smoke`/`fullstack-smoke`/`showcase-serve`/`wasm-island`**
  (and `probe`/`budget` need no flag). The command-plugin sandbox forbids `listen()` —
  `bind()` fails with `EPERM` even with the local-network permission (which is
  outbound-only). A forgotten flag surfaces as
  `server did not become ready — run with --disable-sandbox`.
- **The `.build` lock:** a running plugin invocation holds the package `.build`
  lock for its whole run, so never run a gate while `serve` (or any plugin) is
  up, and never expect a client-style plugin to query a server owned by another
  invocation.

## Asset embedding

- Edit `designer/assets/design-system.css` / `webui-runtime.js`, then
  `swift build` — the `WebUIAssetPlugin` regenerates `Assets+Generated.swift`
  (WebUI) and `DesignTokens+Generated.swift` (WebUIDesignSystemCore) from them.
- `designer/previews/designer-preview.html` links `assets/design-system.css`
  directly (live preview, no build step).
- `designer/previews/showcase.html` is a **generated** artifact — regenerate it
  (`showcase` verb), never hand-edit. Its live equivalent is
  `WebUIShowcaseServer` (renders the same page from Swift per request).

## Icon pipeline

- `designer/icons/icon-manifest.json` (name, category, title, tags, viewBox,
  inner svg geometry) → `WebUIIconPlugin` regenerates `IconLibrary.swift` →
  `IconName` cases.
- `swift run WebUIIconTool lint|list|stats|render-preview --manifest …` for
  validation/catalog tooling. See `Documentation/ICONS.md`.
- `IconSanitizer.sanitize()` is a parse-and-reemit allowlist for custom icons
  (only geometry elements + presentation attributes re-emit).

## Generated files (never hand-edited)

`Assets+Generated.swift`, `DesignTokens+Generated.swift`, `IconLibrary.swift`
live under `.build/` (gitignored) and are regenerated by `swift build`. If a
build fails on a plugin error, check `designer/assets/` still contains both
css/js files.

## Security invariants (never weaken)

CSP with per-document nonce; `sanitizeURL()` blocks `javascript:`/`data:`/
`vbscript:`; runtime HTML sanitization (strips `<script>`, `on*`, unsafe
`href`/`src`/`action`/`xlink:href` on real parsed nodes); prototype-pollution
guard in `State.set()`; `htmlEscape` on all emitted attributes; stateless
HMAC-SHA256 CSRF tokens (single-use pre-auth via `SingleUseTokenStore` with
`maxOutstandingPerKey`); `Mutex`-backed state; growth caps (EventRouter 10K,
ObserverList 100); SVG icon sanitization allowlist; bounded wire parsing
(`JSONValue.parse` caps nesting at 128); websocket render binding (per-render
token). The detailed table is in `Documentation/ARCHITECTURE.md`.

## House style for contributions

- **No-prefix BEM classes** (`.button`, `.button--primary`, `.card`,
  `.list__item`); `br-` appears only in keyframe names.
- **Token-only values** in component CSS; tokens single-sourced in the CSS
  (`design-system.css` is the vocabulary's source of truth — the Swift
  `WebUITheme`/`@Theme` surface is the *typed* way to restate them, not a second
  palette to keep in sync).
- **Cascade layers.** the sheet ships in `@layer webui, webui.utilities`, so
  *unlayered* css always wins: an app's own sheet, `rawStyles`, and the theme sheet
  outrank the framework by origin. restyling a component needs no `!important` and
  no matching specificity.
- **Comments**: `design-system.css` may carry designer notes (the build minifies
  them away); the served payloads — the minified sheet, the runtime, the engine,
  the shell — are comment-free, and `ProseGuard` fails the build if one appears.
  comments otherwise live in Swift and `Documentation/*.md`.
- **Dark mode** is engine-driven: the sheet's dark rules are re-keyed on
  `[data-theme="dark"]` and a pre-paint prelude applies the stored choice before
  first paint (the prelude is inline and carries the render nonce — the page's CSP
  names it). design and verify both themes.
- **Icons, never emoji**; each icon slot needs an explicit CSS box.

## Maintainer pitfalls

- **The `:not()` form-control reset out-specifies component classes.** The
  reset `input:not(.input):not(…):not(…)` (specificity 0,9,1) overrides a plain
  `.input`/`.search-field__input` padding — exclude the component class from the
  reset chain and verify the computed style.
- **`.fill()` vs `.stretch()`**: `fill()` = `flex:1` (grows); `stretch()` = full
  cross-axis without growing. `stretch()` for fixed-width sidebars/rails,
  `fill()` for the region that should consume the rest.
- **Stale binaries:** `swift build --target` refreshes
  `.build/<triple>/debug/<Name>-tool`, not `.build/debug/<Name>`; a running
  server keeps serving the old page until restarted after a full `swift build`.
- **`Logger` methods take `Logger.Message`**, not `String`; prefer unconditional
  `Logger.warning()` over `#if DEBUG` for security-relevant warnings.
- **Smoke pins the interactive count** (26 `data-component-id` attributes on the
  smoke page: 3 counter + 2 progress + 1 echo + 12 routed table controls
  [3 sort + select-all + 4 select + 4 expand] + 6 routed chart bars + 1 upload
  form) — add/remove a component there and update `WebUISmokePlugin.swift`.
- **A rendered artifact showing something the source lacks = stale artifact** —
  regenerate the showcase, don't hand-edit; don't treat it as a framework bug.

## Verification — the fourteen-gate ladder plus the byte pin

every change ships on all fourteen rungs, run in order. each gate hosts its own
server and tears it down — never run one while `serve` or another gate is up
(the `.build` lock forbids concurrency). counts are the current measured
totals, not assertions — re-measure rather than trust:

1. `swift build` — plugins regenerate `Assets+Generated.swift`,
   `DesignTokens+Generated.swift`, `IconLibrary.swift`.
2. `swift test` — currently **1406 tests / 0 issues**.
3. `swift package --disable-sandbox plugin smoke` — currently **19** ok-pass
   assertions: served bytes, page signatures, CSP, the 26 interactive
   components.
4. `swift package --disable-sandbox plugin fullstack-smoke` — live WS
   round-trips (click/echo/redirect/optimistic), currently **24**.
5. `node designer/browser-smoke.mjs` — real-DOM layout gate, headless
   Chromium, currently **50**.
6. `node designer/showcase-ws-smoke.mjs` — stable-id dispatch gate against
   the showcase server (a raw client, never patches the runtime), currently **9**.
7. `node designer/blocks-sweep.mjs` — every standalone block at
   320/768/1440, both themes, no overflow, currently **107**.
8. `node designer/chart-mobile-audit.mjs` — chart text ≥ 11px and fully
   visible plots across six viewports × both themes, currently **77**.
9. `node designer/rtl-audit.mjs` — both directions × both themes × three
   widths, mirrored-order assertions against an ltr control, currently **54**.
10. `node designer/acceptance-demo.mjs` — the four acceptance routes (dashboard,
    click round-trip, form POST, file upload) end to end, currently **8**.
11. `node designer/event-deck-probe.mjs` — every deck event through a real
    browser (layer A) and the probe's own socket (layer B), currently
    **33/33 browser · 32/32 socket · 35 other, 0 fail**.
12. `node designer/a11y-audit.mjs` — the six-rule accessibility gate over raw
    http (with a self-test that the rules fire), currently **26**.
13. `node designer/cascade-probe.mjs` — a host `StyleSheet` wins the cascade
    by origin with zero `!important`, currently **12**.
14. `node designer/theme-default-probe.mjs` + `engine-theme-default-probe.mjs`
    — the typed-theme and engine theme-default contracts on computed style,
    currently **40** and **5**.

plus the **byte pin**: `swift run WebUIShowcase --generate <tmp file>` renders
exactly **168671 bytes**; a docs-only change must not move it (asserted
in-process by the showcase byte-pin suite).

- After a CSS/component change, regenerate the showcase and confirm it shows
  the change in **both** light and dark.

## Canonical docs

`AGENTS.md` is authoritative for build/test/verbs/pitfalls; `Documentation/*`
covers `ASSEMBLY.md` (stage map), `API.md`, `DESIGN_SYSTEM.md`, `ICONS.md`,
`ARCHITECTURE.md`. **Consumers** of the public API → `webui-design-system`.
