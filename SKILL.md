---
name: no-webui
description: Work on the no-webui framework itself (maintainer): repo layout, swift build/test, the command-plugin verbs (serve/smoke/fullstack-smoke/probe/showcase/showcase-serve), asset embedding + icon pipeline, generated files, security invariants, house style, and maintainer pitfalls. For building an APP that uses the public API, load webui-design-system instead.
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
- **Token-only values** in component CSS; tokens single-sourced in the CSS (the
  Swift `WebUITheme` palette is legacy — don't trust or duplicate it).
- **No comments in shipped web assets** (`design-system.css`,
  `webui-runtime.js`, generated documents); comments live in Swift and
  `Documentation/*.md`.
- **Dark mode** via `@media (prefers-color-scheme: dark)` remapping the
  semantic tokens — design and verify both themes.
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
  `node designer/browser-smoke.mjs` (real-DOM layout gate, headless Chromium).
- After a CSS/component change, regenerate the showcase and confirm it shows
  the change in **both** light and dark.

## Canonical docs

`AGENTS.md` is authoritative for build/test/verbs/pitfalls; `Documentation/*`
covers `ASSEMBLY.md` (stage map), `API.md`, `DESIGN_SYSTEM.md`, `ICONS.md`,
`ARCHITECTURE.md`. **Consumers** of the public API → `webui-design-system`.
