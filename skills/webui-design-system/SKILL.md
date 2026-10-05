---
name: webui-design-system
description: "Use when BUILDING a frontend in your own Swift project with the no-webui public API: add the dependency, author views/components in Swift, wire live server round-trips, apply design tokens/theming, and serve + verify the page. For any kind of app UI — a shell, a dashboard, a chat-style page, a tool — see the 'Build your UI in Swift' section and the references index. (Maintaining the no-webui package itself — its designer assets, icon pipeline, showcase generation, smoke gates — is repo work documented in the repo's README/AGENTS.md, not this skill.)"
version: 1.16.0
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
- You want a capability island (wasm state + op stream) hosted on a page —
  see *Islands* below.

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

**Extended controls** (also `import WebUIDesignSystem`): a large set of
composite/niche components that previously existed only as designed css classes
are now public Swift views, grouped by category:

- navigation/chrome: `WebUINavbar`, `WebUIBottomNav`, `WebUIFab`,
  `WebUISpeedDial`, `WebUIWizard`, `WebUITransfer`, `WebUIButtonGroup`,
  `WebUISplitButton`, `WebUIToc`;
- overlays/surfaces: `WebUIAccordion`, `WebUICollapse`, `WebUIActionSheet`,
  `WebUIBottomSheet`, `WebUIDrawer`, `WebUIPopover`, `WebUIHoverCard`,
  `WebUILinkPreview`, `WebUILightbox`, `WebUIMenu`, `WebUIContextMenu`,
  `WebUIDropdown`, `WebUIComboBox`, `WebUICommandPalette`;
- data/rich display: `WebUICalendar`, `WebUIDatePicker`, `WebUITimeZonePicker`,
  `WebUICountryPicker`, `WebUIGantt`, `WebUIKanban`, `WebUIDataSheet`,
  `WebUIJsonTree`, `WebUIDiff`, `WebUITerminal`, `WebUICodeBlock`,
  `WebUIBarChart`, `WebUILineChart`, `WebUIDonut`, `WebUIMasonry`, `WebUIMap`,
  `WebUIQr`, `WebUIPayCard`;
- forms: `WebUISlider`, `WebUIToggle`, `WebUIStepper`, `WebUIOTP`, `WebUIMFA`,
  `WebUIRecurrence`, `WebUIMultiSelect`, `WebUIValidation`, `WebUIDropZone`,
  `WebUISignature`, `WebUIInlineEdit`, `WebUIMasked`, `WebUIRating`,
  `WebUITag`, `WebUIChipInput`, `WebUICardInput`;
- comms: `WebUIMention`, `WebUIReactions`, `WebUITypingIndicator`,
  `WebUINotification`, `WebUIToastStack`, `WebUIBell`;
- feedback/state: `WebUIStatCard`, `WebUIDelta`, `WebUICelebrate`,
  `WebUIConfetti`, `WebUICountdown`, `WebUICookieConsent`, `WebUIPullRefresh`,
  `WebUISkeletonCard`, `WebUIAppletCard`, `WebUIAvatarStack`,
  `WebUIBadgeStatus`, `WebUIBadgeCount`, `WebUIRadioGroup`,
  `WebUICheckboxGroup`.

Most of these are **presentational** display components; the **interactive
subset** self-wires through typed handlers (see the gotcha below). Pass a stable
`id` alongside a handler (`onToggle`/`onDismiss`/`onSelect`/`onChange`) and the
control routes to your Swift handler. Pick them over raw markup for any region
they express. The authoritative list + file groupings live in
`Documentation/DESIGN_SYSTEM.md` → "Extended Controls".

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

## Islands (run capability code in wasm)

A capability island is a small Foundation-free wasm module a page hosts: the
engine lazy-loads it, the island owns the region's state (op stream out, state
channel back), and an absent artifact degrades to `unmapped` with the
server-rendered page intact. the consumer path is **zero manual verbs**:

```bash
swift build            # compiles the app AND cross-builds + auto-pins every island
swift run App          # serves the page; the engine mounts the island regions
```

to author an island:

- write the island logic as a `@HotView` struct in your app (one declaration
  emits the server path, the generated adapter, and the id vocabulary), and
  give it a `Sources/<Name>/main.swift` that imports `WebUIIslandCore` (the
  scanner's text rule) — or generate both with the scaffold:
  `webui-continuum scaffold --package-dir . --add-island <Name>` (the tool
  binary lives in the framework's `.build`; inside the framework home use
  `swift package --disable-sandbox plugin scaffold --add-island <Name>`).
  `scaffold --bootstrap --name <App> --framework <path>` adds the once-per-app
  inert block (framework dependency + `WebUIAutobuildPlugin`) to an existing
  app; `--print` previews without writing.
- declare the region with `WebUIIsland(id:name:args:)` (or the derived
  `WebUIIsland("feed", args:)` form). a pre-emitted region receives events
  ONLY through its descriptor — splice
  `data-webui-island-events='["click"]'` beside the view's markup. keep the
  island self-contained: the `@HotView` struct is not yet the island's
  source — the logic lives in `Sources/<Name>/`.
- when you want an explicit one-shot check of the whole verification path —
  build → wasm cross-build → measure/pin → the budget row — the **single**
  verb is `verify`:
  `<no-webui path>/.build/…/WebUIContinuumTool verify --package-dir . --framework <no-webui path>`
  (inside the framework home: `swift package --disable-sandbox plugin verify`).
  it prints a per-stage verdict and fails on any budget breach.
- `plugin wasm-island` is an **internal** framework verb (the in-repo ladder);
  consumers never name it, and consumer packages cannot invoke a dependency's
  command plugins — that is why `verify`/`scaffold` surface as the tool
  binary from a consumer app.
- **if you came here for a wasm *client* app: that path is gone.** the engine
  plus per-page capability islands is the client architecture now; migrate to
  the engine, or to an island for the specific local behaviour you needed.

## Tokens & theming

- **SpaceToken**: `.one…` `.twentyFour` (values 1–24) → `var(--space-N)`.
  Use `.four` (16px) etc. for padding/gaps, never raw px.
- **ColorToken**: `.primary`, `.text`, `.textMuted`, `.textFaint`, `.border`,
  `.background`, `.backgroundRaised`, `.success`, `.warning`, `.danger`, …
  → `var(--color-*)`. the CSS file is the vocabulary's source of truth; the Swift
  `WebUITheme`/`@Theme` surface (`DesignToken` keys) is the typed way to restate
  them — a token override there is compiler-checked.
- **Semantic tokens** (in `design-system.css`): light bg `#f4f6f8`, raised
  `#ffffff`; dark bg `#060910`, raised `#0c111c`; primary indigo `#6366f1`
  (light action fill `#4f46e5`; dark link `#818cf8`); radii `--radius-md` 6px
  (buttons/inputs), `--radius-xl` 12px (cards).
- **Dark mode** is engine-driven at runtime: the sheet's dark rules are
  re-keyed on `[data-theme="dark"]` and the engine resolves the effective
  theme at boot (saved `webui-theme` choice, else `prefers-color-scheme`) in
  `<head>` before the sheet applies — no flash for system default, and a user
  override beats the OS either way. `WebUIThemeToggle` (System/Light/Dark)
  drives it client-side with `localStorage` persistence, no round trip.
  Design and verify **both** themes; never hardcode a theme. On a page-scoped
  tweak, put it in `WebUIDocument.rawStyles` — and note that **unlayered css
  always wins**: the sheet ships in `@layer webui, webui.utilities`, so rawStyles,
  an app stylesheet, and the theme sheet outrank the framework by cascade origin.
  no `!important`, no matching specificity.

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

## Substitution: conform, don't layer (events · live data · themes · components)

the framework's customization model: **a customization is a conforming type passed in** — every
seam ships a protocol, a default, an injection position, and a twin test. If you find yourself
shadowing framework CSS, re-implementing a loop, or pre-registering a control the framework could
route, the seam is missing — use the seam.

- **events** — a handler may yield more than `[FragmentUpdate]`: `control(_:event:handler:)` takes
  any `EventOutcome` (`ViewOutcome` replaces the control's element — its root must carry
  `id == data-component-id`; `RegionInvalidations` declares a live region changed; `NoOutcome` /
  `CombinedOutcome` compose). annotate the closure's return type.
- **live data** — a `LiveRegion` (closure / custom struct / `LiveBox`- or custom-`LiveState`-bound)
  is passed as `regions:` to `WebUIServer` and re-renders + pushes only when it changed. full
  recipe: `references/live-regions.md`.
- **themes** — `@Theme` / hand-written `WebUIThemeProvider` types in a `ThemeCatalog`; attach
  `WebUIThemePlugin` to that target and reference the emitted sheet. `WebUITheme` (value) vs
  `WebUIThemeProvider` (protocol) vs `WebUIThemeBuild` (build library) vs `WebUIBuild` (emitter).
- **components** — compose; `.class("x")` replaces a component's classes, so wrap in `Div(class:)`
  instead of re-skinning.

full guide: `references/substitution.md`.

## Filling the space

- Inside `VStack(.leading)` everything **shrink-wraps**. Add `align-self: stretch`
  to panels/lists/grids/the page content so they fill the width, and `.fill()`
  panel bodies so content uses the full height.
- **`.fill()` vs `.stretch()`**: `fill()` = `flex:1` (grows on the main axis,
  takes remaining space); `stretch()` = full cross-axis height/width without
  growing. Use `stretch()` on fixed-width sidebars/rails, `fill()` on the region
  that should consume the rest. See `references/css-layout-shrink-stretch.md`.

## Charts (`WebUIChart`)

`WebUIChart` is a separate product — add it beside `WebUI` in your dependencies.
It renders inline SVG inside a `<figure class="chart">`, styled entirely by the
design-system tokens, with no client charting library.

- **declare the width you designed for.** A chart lays out for
  `height × aspectRatio` (default `320 × 2 = 640`) and renders at that width: it
  does not scale up, may compress to 92%, and **pans** below that, so labels
  never paint under 11px at any container width. Choose the design width from the
  placement — `chartHeight(150)` = a 300-unit plot that fits a phone card, while
  the 640-unit default inside a 390px card shows only ~39% of the plot.
- **a chart contributes no intrinsic width** (its plot owns its inline size), so
  a container that sizes to its content — a `VStack(.leading)`, a content-sized
  grid track — collapses to the width of its own text. Give chart containers a
  declared width or an explicit grid track: the same trap as *Filling the space*,
  with a bigger blast radius.
- **interactive marks:** `.chartID("sales")` plus `.onSelectMark { me, category in … }`
  wires each painted bar/sector as its own routed component and hands you the
  clicked category with an `ElementRef` to the chart root — no `targetId`
  string-matching, and re-rendered figures keep routing.
- deep guide (marks, scales, axes, selection, gradients, the full width
  contract): `Documentation/CHARTS.md` in the package checkout.

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
| Substitution — conforming types for events / live data / themes / components | `references/substitution.md` |
| Live regions — server-owned updating regions (`regions:`, state binding, semantics) | `references/live-regions.md` |
| CSS layout gotchas (shrink-to-content, stretch, center, full-height) | `references/css-layout-shrink-stretch.md` |
| Serve your page live (shared library + NIO server + `/ws`) & the `*__body` convention | `references/live-server-and-showcase.md` |
| Top-bar provider + thinking-effort (RuntimeSettings, `reasoning_effort`, `WebUISelect`) | `references/runtime-provider-effort-settings.md` |
| Interactive server-re-rendered regions (table sort/select/expand) | `references/interactive-table-recipe.md` |
| Engine-first delivery: documents, routes, capability islands | `references/engine-delivery.md` |
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

- **A bare `WebUIIsland("feed")` region mounts but receives no delegated
  events** — island delivery is descriptor-gated; splice
  `data-webui-island-events='["click"]'` beside the region. keep consumer
  islands self-contained (`Sources/<Name>/main.swift` importing
  `WebUIIslandCore`) until `@HotView` island discovery lands.
- **Content flush against a container edge** → missing `__body` wrapper (pad via
  `__body`, not the container). See the `*__body` section above.
- **`/ws` console error at load** → the runtime is on but your server doesn't
  upgrade `/ws` / answer pings.
- **A chart collapses to the width of its own text** → charts contribute no
  intrinsic width; give the container a declared width or a grid track, and pick
  the design width (`chartHeight`) for the smallest placement (see *Charts*).
- **`.class("x")` on a component replaces its own classes** → the attribute merge
  keeps the *later* value, so a `VStack(spacing: 32).class("mine")` loses
  `vstack spacing-32 align-flex-start` and its layout silently changes. wrap it
  in `Div(class: "mine") { … }` instead, or scope the rule in css to the classes
  the component already emits (`.parent > .vstack { … }`).
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
- **Interactive extras self-wire; display-only extras are presentational.**
  The interactive subset self-wires a typed handler via `controlAttributes` —
  pass a stable `id` plus the handler and the control routes clicks/inputs to
  your Swift handler (dispatch on `event.string("targetId")`; each interactive
  child carries a derived `id`, e.g. `"<id>-item-0"` / `"<id>-inc"`). Wired so
  far: accordion/collapse (`onToggle`), drawer/bottom-sheet/action-sheet
  (`onDismiss`/`onSelect`), menu/context-menu/dropdown/combo/command-palette
  (`onSelect`), navbar/bottom-nav/fab/split-button/lightbox
  (`onNavigate`/`onSelect`/`onTap`), calendar/date-picker/timezone/country
  (`onChange`/`onSelect`), stepper/toggle/slider/multi-select/otp/rating/
  inline-edit/recurrence/chip-input/tag (`onChange`/`onSave`/`onRemove`),
  reactions/notification/bell/mention/cookie-consent/pull-refresh
  (`onChange`/`onTap`/`onSelect`/`onRefresh`). The rest are pure display
  (badges, tags, avatars, charts, skeletons, stat/celebrate/countdown, …) or
  drag/edit widgets whose interaction contract isn't designed yet (kanban,
  transfer, datasheet, signature) — those stay modifier-drivable via `.onClick`.

## Committing (in your own app)

Conventional lowercase scope, sentence-case subject, dash-led bullets, closing
line with gate/test results (e.g. `test(webui):` / `fix(app):`). When you change
a component's look, verify it reaches the browser in both themes and that the
round-trip updates the DOM node (read the server-patched element, not the input
value).
