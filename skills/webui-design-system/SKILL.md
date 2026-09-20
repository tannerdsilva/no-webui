---
name: webui-design-system
description: "Use when BUILDING a frontend in your own Swift project with the no-webui public API: add the dependency, author views/components in Swift, wire live server round-trips, apply design tokens/theming, and serve + verify the page. For any kind of app UI — a shell, a dashboard, a chat-style page, a tool — see the 'Build your UI in Swift' section and the references index. (Maintaining the no-webui package itself — its designer assets, icon pipeline, showcase generation, smoke gates — is repo work documented in the repo's README/AGENTS.md, not this skill.)"
version: 1.13.0
author: Hermes Agent
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [no-webui, swiftui-for-web, webui, design-system, public-api, frontend]
    related_skills: [no-webui, agent-chat-ui]
---

# WebUI Design System — build web UIs in your own Swift app

This skill is for **consumers** of the no-webui **public API**. You have your
own Swift executable/server (a dashboard, a console, a demo app) that
depends on no-webui as a package, and you want to author its frontend in Swift.
You do **not** edit the no-webui package — you compose its public views and
components.

Core idea: **your UI is written in Swift.** Views compose like SwiftUI,
`.render()` emits semantic HTML, and a small JS runtime patches the DOM over a
WebSocket. The web is only the delivery surface.

## When to use

- You are building or restyling a page of your own no-webui app in Swift.
- You want server-rendered HTML with live round-trips
  (click/input/submit → Swift handler → DOM patch).
- You want to reuse the design system: buttons, cards, inputs, tables, tabs,
  trees, badges, empty states, and the app-frame shell components.
- You are debugging a rendered page — content flush against a container edge,
  wrong theme, poor contrast, or a `/ws` console error.

Don't use for: hand-written static HTML/CSS/JS landing pages, client-only SPAs,
or maintaining the no-webui package itself (that's the repo's `README`/`AGENTS.md`).

## Add the dependency

Consume no-webui as a **path dependency** from your host Package.swift:

```swift
.package(path: "../no-webui")   // or a git url + version tag
```

and link the library products you need:

```swift
.product(name: "WebUI", package: "no-webui"),
.product(name: "WebUIDesignSystem", package: "no-webui"),
.product(name: "WebUIChart", package: "no-webui"),   // charts
.product(name: "WebUIAuth", package: "no-webui"),    // only if you need login/sessions
```

Then `import WebUI` and `import WebUIDesignSystem` in your Swift files. No
external JS/CSS/npm — the design system and runtime are embedded at build time.

## Build your UI in Swift (the guiding principle)

- **Express every region as a `View`.** Compose `VStack`/`HStack`/`ZStack`,
  `ScrollView`, `WebUIButton`, `WebUICard`, `WebUITable`, … then `.render()`.
  The toolkit owns the markup.
- **Prefer an existing component over any markup.** The design system covers
  buttons, inputs, cards, badges, tabs, trees, tables, lists, segmented
  controls, sidebars, panels, composers, empty states. Reach for one first.
- **Add a NEW Swift component before ever reaching for markup.** If no existing
  component fits, add a `struct …: View` (conforming to `View`, in your own app
  or, if it's generic enough, upstream in no-webui) so the next UI reuses it.
- **The smell to avoid:** raw `<div>`/`<button>` strings, `class="…"` literals,
  inline `style=` attributes, or `Raw(...)`/`Div` blobs building markup in your
  host. That's the anti-pattern. Keep the host declarative.
- **Interactivity is Swift too.** Write `@Sendable (EventData) async -> [FragmentUpdate]`
  handlers and wire them with `controlAttributes`/modifiers — never hand-inject JS.

## The design system you compose

High-level components (import `WebUIDesignSystem`): `WebUIButton`,
`WebUIInput`, `WebUIBadge`, `WebUIAvatar`, `WebUICard`, `WebUITabs`,
`WebUITree`, `WebUITable`, `WebUIEmptyState`, `WebUISpinner`, `WebUIProgress`,
`WebUIModal`, `WebUIToast`, `WebUITooltip`, `WebUITimeline`,
`WebUIBreadcrumb`, `WebUIStat`, `WebUISkeleton`, `WebUIAlert`,
`WebUIPagination`. Turn transparency (per-turn reasoning, tool steps, and a
summary line): `WebUIReasoningBlock`,
`WebUIToolStep`, `WebUITurnSummary` — all fields are HTML-escaped and the
`.turn-*` styling ships with the design system.

Shell / app-frame building blocks (in `WebUIShell.swift`): `WebUISidebar`
(`.full`/`.rail`), `WebUISegmentedControl`, `WebUISearchField`,
`WebUIListView`/`WebUIListItem`, `WebUIComposer`, `WebUIPanel`, `WebUISelect`.

If a region needs markup no component expresses, add a Swift component (see
`references/high-level-shell-components.md` for the composition conventions and
the escaping/quoting pitfalls).

## Compose and render a page (all Swift)

```swift
import WebUI
import WebUIDesignSystem

let body = VStack(spacing: 16) {
    Heading("Hi", level: .h2)
    WebUIButton("Go", variant: .primary, size: .md)
}
.padding(24)
.render()                       // -> String HTML fragment

let doc = WebUIDocument(
    title: "Page",
    body: body,
    runtimeConfig: RuntimeConfig(renderToken: "...")   // optional
).render()
```

`WebUIDocument` assembles the full HTML document with the design-system CSS
and JS runtime embedded, an auto-generated CSP + nonce, and the theme.

## Tokens & theming

- **SpaceToken**: `.one…` `.twentyFour` (values 1–24) → `var(--space-N)`.
  Use `.four` (16px) etc. for padding/gaps, never raw px.
- **ColorToken**: `.primary`, `.text`, `.textMuted`, `.textFaint`, `.border`,
  `.background`, `.backgroundRaised`, `.success`, `.warning`, `.danger`, …
  → `var(--color-*)`. `WebUITheme`'s Swift palette is legacy — the CSS tokens are
  the source of truth.
- **Semantic tokens** (in `design-system.css`): light bg `#f4f6f8`, raised
  `#ffffff`; dark bg `#060910`, raised `#0c111c`; primary indigo `#6366f1`
  (light action fill `#4f46e5`; dark link `#818cf8`); radii `--radius-md` 6px
  (buttons/inputs), `--radius-xl` 12px (cards).
- **Dark mode** is automatic via `@media (prefers-color-scheme: dark)` remapping
  the semantic tokens — there is **no** runtime toggle. Design and verify **both**
  themes; never hardcode a theme. On a page-scoped tweak, put it in
  `WebUIDocument.rawStyles` (lands after the sheet, so it extends without
  overriding the shared defaults).

### The `*__body` padding convention (key gotcha)

Container components carry their interior padding on a `__body` **child**, not
on the container:

```css
.card { padding: 0; … }                    /* the container has no padding */
.card__body { padding: var(--space-4); }   /* the interior pads */
```

`.panel__body`, `.alert__body`, `.list__body`, `.modal__body` work the same.
If a container renders its content **flush against a rounded/edged box**, the
fix is to wrap the children in the `__body` element — **not** to pad the
container. The padding is a CSS token **default**, overridable via the normal
cascade (a page-scoped style, a modifier, or a more-specific rule). Verify it's
a real default (not baked inline) by injecting a competing rule and reading
`getComputedStyle(...).padding`: `default 16px → .card__body { padding: var(--space-1) } → 4px`.

## Interactivity (Swift handlers, server round-trips)

The live layer: the runtime opens a WebSocket and forwards DOM events as
`{"type":"event","component":"c0","event":"click","data":{…}}`; your server's
`EventRouter` dispatches to a registered **Swift** handler and returns
`FragmentUpdate`s, which the runtime applies by replacing target elements.

- Register handlers during page build with
  `controlAttributes(id:event:handler:)` inside
  `RenderContext.$current.withValue(RenderContext(router: router)) { … }`. The
  attributes it returns (`data-component-id`/`data-event`) go on the element.
- An `EventHandler` is `@Sendable (EventData) async -> [FragmentUpdate]`.
  Read `event.string("value")` / `event.string("targetId")` / `event.string("key")`.
- `FragmentUpdate(id: "…", html: "…")` replaces the element whose `id` matches,
  so a re-rendered region must re-carry its routing anchor.
- **Stable-id discipline:** for regions fragment updates re-render, register
  handlers under a caller-chosen id and re-emit that same id on every
  re-render (the page-build registration persists in the router). Typed
  handlers (`WebUITable.onSort`, `WebUIPagination.onPageChange`, dismissibles)
  self-wire under stable ids via `controlAttributes`.
- For a list/segmented/sidebar, put **one** handler on the container and
  dispatch on `event.string("targetId")`; give each row a DOM `id`, and set
  `pointer-events: none` on row children so the click resolves to the row.
- **Render token binding** (optional security): mint a per-render token in
  `RuntimeConfig.renderToken` and have your server reject messages whose
  token doesn't match the session's current render set.

## Filling the space

- Inside `VStack(.leading)` everything **shrink-wraps**. Add `align-self: stretch`
  to panels/lists/grids/the page content so they fill the width, and `.fill()`
  panel bodies so content uses the full height.
- **`.fill()` vs `.stretch()`**: `fill()` = `flex:1` (grows on the main axis,
  takes remaining space); `stretch()` = full cross-axis height/width without
  growing. Use `stretch()` on fixed-width sidebars/rails, `fill()` on the region
  that should consume the rest. See `references/css-layout-shrink-stretch.md`.

## Serve your page (your server must do this)

Your server serves the rendered document and assets, and upgrades `/ws`:

- Serve the page (`WebUIDocument(...).render()`) plus the design-system assets
  (`DesignSystemAssets.minifiedCss`, `WebUIAssets.js`) — the `WebUIDocument`
  already inlines the CSS/runtime, so commonly only the document + `/ws` are
  needed.
- **`includeRuntime: true` requires a working `/ws`.** The JS runtime opens a
  `/ws` socket at load. Your server must upgrade `/ws` and answer `.ping`
  frames with `.pong` (and echo the close frame), or every load logs a
  failed-handshake console error. (A purely static/offline reference page can
  use `includeRuntime: false`.)
- **Reuse the page composition across executables:** executable targets aren't
  importable by other targets, so if a page is shared between a generator and a
  server, move it into a **library target** (make the struct `public` with a
  `public init()`). Model your NIO server on `WebUIExample/main.swift`
  (`NIOTypedWebSocketServerUpgrader` + `NIOUpgradableHTTPServerPipelineConfiguration`
  + an outbound `HTTPByteBufferResponsePartHandler`).
- Render the page per request to reflect current Swift source (each render mints
  a fresh CSP nonce); prewarm `DesignSystemAssets.prewarm()` before the first
  request. See `references/live-server-and-showcase.md`.

## Verify (both themes)

Serve the page and check it in a browser before shipping:

- It renders correctly in **both light and dark** (dark mode is automatic via
  prefers-color-scheme, so confirm the background actually flips — dark
  `rgb(6,9,16)` / light `rgb(244,246,248)` — not a white page).
- **No console errors at load** (a websocket failed-handshake is the classic one).
- **Populate a "used" state** before judging fullness — a live thread/panel
  after a few turns reads taller than an empty one.
- Use a **WCAG contrast** check on text/background pairs rather than eyeballing.
  See `references/contrast-audit.md`.

## House rules (consumer)

- Build the UI in Swift — never raw markup, `class="…"` literals, or inline
  `style=` in your host.
- **Token-only values** — use `SpaceToken`/`ColorToken`/CSS vars, never raw px/hex.
- Prefer an existing component; add a Swift component before reaching for markup.

## Reference index (read the deep guide only where relevant)

| Area | Reference |
|---|---|
| Shell / app-frame components + composition recipe | `references/high-level-shell-components.md` |
| CSS layout gotchas (shrink-to-content, stretch, center, full-height) | `references/css-layout-shrink-stretch.md` |
| Serve your page live (shared library + NIO server + `/ws`) & the `*__body` convention | `references/live-server-and-showcase.md` |
| Top-bar provider + thinking-effort (RuntimeSettings, `reasoning_effort`, `WebUISelect`) | `references/runtime-provider-effort-settings.md` |
| Interactive server-re-rendered regions (table sort/select/expand) | `references/interactive-table-recipe.md` |
| WCAG contrast audit + guardrail tests | `references/contrast-audit.md` |
| Render-token whitelist bounce (token-gated socket) | `references/render-token-whitelist-bounce.md` |
| Pitfalls & debugging (CSS cascade, Swift escape/arg-order) | `references/pitfalls-and-debugging.md` |

Everything else — **maintaining the no-webui package itself**: the designer
assets, the icon pipeline, class-namespace/type-scale/design-consistency
audits, showcase regeneration, and the serve/smoke/fullstack-smoke deployment
gates — is not this skill's audience. It belongs to the no-webui repo and lives
in its `README.md`, `AGENTS.md`, and `Documentation/*`; reach for those (or the
`no-webui` skill) when you're working *on* the package.

## Consumer gotchas

- **Content flush against a container edge** → missing `__body` wrapper (pad via
  `__body`, not the container). See the `*__body` section above.
- **`/ws` console error at load** → the runtime is on but your server doesn't
  upgrade `/ws` / answer pings.
- **String escaping in Swift HTML literals** — a doubled backslash (`\\`) renders
  a literal `\`; write single `\(…)`. Prefer multiline string literals.
- **Nested ternary inside interpolation** breaks the parser — compute the
  fragment into a `let` first.
- **Swift labeled-argument order = declaration order** — calling a component
  init with args out of order fails; read the init first.
- **The `:not()` form-control reset out-specifies component classes** — exclude
  the component class from the reset chain and verify the computed style.
- **Two host servers can share one port** (IPv4 vs IPv6 `localhost`); a browser
  can hit a stale instance. Diagnose with `lsof` + `pgrep`, md5 the served bytes.

## Committing (in your own app)

Conventional lowercase scope, sentence-case subject, dash-led bullets, closing
line with gate/test results (e.g. `test(webui):` / `fix(app):`). When you change
a component's look, verify it reaches the browser in both themes and that the
round-trip updates the DOM node (read the server-patched element, not the input
value).
