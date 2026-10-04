---
name: no-webui
description: "Work on the no-webui framework itself (maintainer): repo layout, swift build/test, the command-plugin verbs (serve/smoke/fullstack-smoke/probe/showcase/showcase-serve/wasm-island/budget/scaffold/verify), asset embedding + icon pipeline, generated files, security invariants, house style, and maintainer pitfalls. For building an APP that uses the public API, load webui-design-system instead."
version: 1.2.0
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
swift build        # plugins regenerate Assets+Generated.swift, DesignTokens+Generated.swift, IconLibrary.swift; islands cross-build + auto-pin in-build (WebUIAutobuildPlugin)
swift test         # the always-on gate (asserts embedded css/js == designer/assets sources)
swift run WebUIExample   # example server on :9090
```

Island artifacts build **automatically**: a plain `swift build` cross-builds
every island (`WebUIAutobuildPlugin` + the `wasm-cross` two-stage swiftc) and
auto-pins its budget (`measure`, DX-3) — zero manual verbs. `verify` is the
ONE explicit island-verification verb
(`swift package --disable-sandbox plugin verify`: build → wasm cross-build →
measure/pin → the budget row, with a per-stage verdict); `wasm-island` is the
internal ladder verb. The wasm toolchain is the swiftly-hosted
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
| `wasm-island` | `swift package --disable-sandbox plugin wasm-island [--product N]` | internal ladder verb: cross-build one island into `.build/wasm-island-scratch`, copies the stripped artifact to the `.build/out` path |
| `budget` | `swift package --disable-sandbox plugin budget` | per-island budget enforcement gate (declared pins vs the DX-3 measured rows, tightening-only) |
| `scaffold` | `swift package --disable-sandbox plugin scaffold --add-island <Name>` | DX-2: append the island product+target entries + generate the runtime-form main (also `--bootstrap`/`--print`) |
| `verify` | `swift package --disable-sandbox plugin verify` | DX-8: the full island verification path (build → cross-build → measure/pin → budget row), one verb |

- **`--disable-sandbox` is mandatory for `serve`/`smoke`/`fullstack-smoke`/`showcase-serve`**
  (and `probe` needs no flag). The command-plugin sandbox forbids `listen()` —
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

## Islands (the continuum)

The seam vocabulary, the `IslandRuntime` slice, the `@HotView`/`@HotClass`
macros, the `WebUIIsland` region view, the manifest v2 (`islands[]` rows with
`name/maxBytes/maxGzipBytes` + additive `raw/gz/sha/url`), and the
scaffold/verify/auto-pin verbs are documented in `Documentation/CONTINUUM.md`
(the living reference). Maintainer-side essentials:

- **autobuild**: `WebUIAutobuildPlugin` cross-builds every island inside a
  plain `swift build` (artifacts land in the plugin work dir — never
  `.build/out/Products/…`, which a build command cannot write on home-dir
  checkouts) and the `measure` command auto-pins budgets into the work-dir
  manifest. warm rebuilds are ~0 (llbuild-declared inputs/outputs).
- **the runtime slice**: islands are slim mains — an inert `@main` stub + a
  `webui_island_bind` shim (`IslandRuntime<<Type>Island>.run()`) + one-line
  extra-export shims. the probe's 233,952 B size is the byte-identity
  backstop (SIZE + section layout, never a full-sha claim). never add a NEW
  source file to `WebUIIslandCore` when byte-neutrality is required — the
  link layout is compilation-unit-set sensitive; add to `IslandRuntime.swift`.
- **the id dev check**: `-DCONTINUUM_ID_CHECK` compiles the check into the
  runtime (`static var elementIDs` + `isKnownElementID`); production compiles
  it out (zero trace — binary-grep the artifact to verify). natively testable
  via `swift test -Xswiftc -DCONTINUUM_ID_CHECK`.
- **the one consumer-facing verb is `verify`** (build → cross-build →
  measure/pin → budget row); `scaffold --add-island` is the one manifest
  editor; `wasm-island` is internal. command plugins are NOT invocable from a
  consumer package — the consumer surfaces are the `webui-continuum` tool
  binary forms (`webui-continuum verify --package-dir . --framework <path>`,
  `webui-continuum scaffold --package-dir . --add-island <Name>`).

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
- **Smoke pins the interactive count** (24 `data-component-id` attributes on the
  smoke page) — add/remove a component there and update `WebUISmokePlugin.swift`.
- **A rendered artifact showing something the source lacks = stale artifact** —
  regenerate the showcase, don't hand-edit; don't treat it as a framework bug.

## Verification

- `swift test` (byte-identity of embedded css/js vs `designer/assets/`),
  `smoke` (served bytes == source), `fullstack-smoke` (live WS round-trips),
  `plugin budget` (per-island pins vs the measured DX-3 rows),
  `plugin verify` (the full island path), `node designer/browser-smoke.mjs`
  (real-DOM layout gate, headless Chromium). the continuum gates:
  `node designer/d3-gate.mjs`, `dx-content-pin.mjs`, `dx-acceptance.mjs`,
  and `bash designer/gates/dx5-demo.sh` / `scaffold-demo.sh`.
- After a CSS/component change, regenerate the showcase and confirm it shows
  the change in **both** light and dark.

## Canonical docs

`AGENTS.md` is authoritative for build/test/verbs/pitfalls; `Documentation/*`
covers `ASSEMBLY.md` (stage map), `API.md`, `DESIGN_SYSTEM.md`, `ICONS.md`,
`ARCHITECTURE.md`. **Consumers** of the public API → `webui-design-system`.
