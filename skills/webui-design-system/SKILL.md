---
name: webui-design-system
description: "Use when BUILDING a frontend in your own Swift project with the no-webui public API: add the dependency, author views/components in Swift, wire live server round-trips, apply design tokens/theming, and serve + verify the page. For any kind of app UI — a shell, a dashboard, a chat-style page, a tool — see the 'Build your UI in Swift' section and the references index. (Maintaining the no-webui package itself — its designer assets, icon pipeline, showcase generation, smoke gates — is repo work documented in the repo's README/AGENTS.md, not this skill.)"
version: 2.0.0
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
`render(into:)` writes each view's bytes into a shared `HTMLBuffer` that
becomes semantic HTML, and a small JS runtime patches the DOM over a
WebSocket. The web is only the delivery surface. (``render() -> String``
still exists as a **deprecated** convenience that materializes the buffer —
the sole protocol requirement is `render(into:)`.)

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
  `ScrollView`, `WebUIButton`, `WebUICard`, `WebUITable`, … then
  `render(into:)` them (see *Compose and render a page*).
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
    WebUIButton("Go", appearance: .primary, size: .md)
}
.padding(24)

// a rendered value hands its typed token straight to the document: `.markup`
// is the `BufferRendering` door, so no hand-materialized `String` is needed
// (the retired `HTMLBuffer` → `String(decoding:)` shim is gone).
let doc = WebUIDocument(
    title: "Page",
    body: body.markup,
    runtimeConfig: RuntimeConfig(renderToken: "...")   // optional
)

let html = doc.markup.html
```

(`render() -> String` still compiles and is byte-identical — it is the
deprecated 1.x convenience that materializes the same buffer — but a type that
implements *only* `render()` does **not** satisfy `View`: the buffer method is
the requirement.)

`WebUIDocument` assembles the full HTML document with the design-system CSS
and JS runtime embedded, an auto-generated CSP + nonce, and the theme.

## Client mode (run the same UI in wasm)

The same `View`/`ViewModifier` core can run **inside the browser** — the
- **the client runtime is the engine** (`/ui/webui-engine.js`, shipped by the
  framework): a consumer app links `WebUICore` and nothing else. the published
  `WebUIClientRuntime` / `.wasm` client product **was deleted** — the engine plus
  per-page wasm capability islands is the client architecture now.
- **capability islands are the wasm path**: cross-build one with
  `swift package --disable-sandbox plugin wasm-island --product TheirIsland`
  (isolated scratch root; custom sections stripped by default; needs
  `--disable-sandbox`), declare the capability on the page, and the engine
  lazy-loads it — degrading to the base path when the artifact is absent. the
  repo's `WebUIValidateIsland` is the reference island: one Foundation-free core,
  compiled to wasm and exercised natively by the same tests.
- **declare an island, don't wire it**: `IslandRegion<MyIsland>(input)`
  (`MyIsland: Island` with `static let name` + `static func render(_:)`, same
  Swift both sides) renders the engine's mount point, and `WebUIDocument`
  collects the name out of the body into the emitted config — declaring the
  view is the whole wiring, no manual `capabilities:` entry. an absent
  artifact degrades to the server-rendered fallback.
- **if you came here for a wasm *client* app: that path is gone.** migrate to the
  engine, or to an island for the specific local behaviour you needed.

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

### The typed theme stack (2.0)

`WebUITheme`/`@Theme` is the *typed* restatement of the vocabulary — a token
override there is compiler-checked against the generated `DesignToken` enum:

- **`DesignTheme`** — a complete five-axis theme (`palette`, `spacing`,
  `radii`, `typography`, `motion`), every axis **mandatory** (a conformer that
  omits one does not compile); `DefaultDesignTheme` changes nothing,
  `DerivedTheme<Base>` + `.overriding([.colorPrimary500: "#6c8cff"])` moves a
  few tokens on top of a base theme.
- **`@Theme`** — the conformance macro: flat token members synthesize a full
  five-axis conformance (`static let colorPrimarySolid = "#6c8cff"`), and
  `@Theme(base: SomeTheme.self)` layers them on another provider — the shape a
  many-scheme app wants. a mistyped token name is a compile error.
- **`StyleSheet`** — host css with framework guarantees: `StyleSheet(name:layer:rules:)`
  emits a placement-independent layered artifact (`CascadeLayer.host` beats the
  framework by cascade origin — equal *or* lower specificity, zero
  `!important`; `cascade-probe` proves it on computed style). wire it with
  `WebUIDocument.styleSheets` / `stylesheetURL` (a cacheable `<link>`).
- **`TokenOverrides`** — the axis value type (a `[DesignToken: String]` in
  dictionary-literal form), shared by spacing/radii/typography/motion.

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

### The event deck (2.0)

`HTMLEvent` now spans **seven families** — pointer, touch, drag & drop,
clipboard, wheel/scroll, misc (dblclick/context-menu/animation-end/
transition-end), and media — each with a typed modifier (`.onPointerDown`,
`.onDragStart`, `.onDrop`, `.onCopy`/`.onCut`/`.onPaste`, `.onWheel`,
`.onScroll`, `.onPlay`/`.onPause`/`.onEnded`/`.onTimeUpdate`/`.onLoadedMetadata`/`.onError`)
and a **typed payload**: read `event.pointer()?.x`, `event.touch()`, `event.drag()`
(`data` map + `files`), `event.paste()` (`text`/`html`), `event.wheel()`,
`event.scroll()`, `event.animation()`, `event.transition()`, `event.media()`
instead of `event.number("x")` magic strings. `.on(_:perform:)` attaches any
event including `HTMLEvent.custom("…")` for one the vocabulary does not name.

- **`.onFocus`/`.onBlur` are delivered via the bubbling `focusin`/`focusout`** and
  normalized to the declared event name, so a focus/blur handler works even
  when the actual browser event fires on a descendant.
- **`targetId` (`event.targetID`) resolves to the nearest id-bearing element
  *inside* the component boundary** — a click usually lands on a label or icon
  child, and clicking the component's own root reports `nil`.

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

- Serve the page (`WebUIDocument(...).render(into: &buffer)` + materialize)
  plus the design-system assets
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

## The 2.0 contract (what changed)

the full old→new mapping, one table per wave, lives in
`Documentation/MIGRATION_2_0.md` in the package checkout — read it before
migrating a 1.x host. the short version a 2.0 host writes against:

- **`render(into:)` is the sole `View` requirement.** `render() -> String` is
  a deprecated default materialized from the buffer; a type implementing only
  `render()` does not satisfy `View`. `ViewModifier` likewise requires
  `decorate(_:into:)` in addition to `apply(to:)` (defaulted through the buffer).
- **`class:` merges now.** `.class("x")`/`.classes(...)`/`.addClass(...)` and
  the `class:` parameters keep the content's own classes — call order,
  duplicates folded. the 1.x replace semantics are gone, and there is **no
  replace escape**: a host that must take a framework class off an element
  does it through the cascade (unlayered host css / a `StyleSheet` outranks
  the layered sheet).
- **the retired slot vocabulary.** 15 nested `Size` enums → `ControlSize`
  (`sm`/`md`/`lg`/`xl`); `WebUIButton.Variant`/`WebUITag.Variant`/
  `WebUIAccordion.Variant` → a shared `Appearance` + `appearance:`; the seven
  tone components' `Variant` → `tone: Tone`; `WebUICard.Variant` — the fused
  elevation/flag enum — split into `elevation: Elevation?` plus the typed
  flags `interactive:`/`horizontal:`/`hover:`/`compact:`/`disabled:` (and the
  nested `State`/`Status`/`Trend`/`Side`/`Edge`/`Brand` slots → the shared
  top-level vocabulary). every 1.x spelling keeps a deprecated shim through
  the one minor; removal lands in 2.0.0.
- **capability protocols** — conformance is a one-word change and no capability
  adds a `View` requirement: `Interactive`, `Identified` (`stableID`),
  `StreamingContent`, `AsyncContent`, `Recoverable`. `ErrorBoundary` is the
  shipped `Recoverable` conformer.
- **typed aria.** `Aria` (one case per attribute: `.label`, `.expanded(.yes)`,
  `.checked(.mixed)`, `.live(.polite)`, `.sort(.ascending)`, …) and `AriaRole`
  replace hand-written `aria-*`/`role=` strings; `.role(_:)`/`.aria(_:)`/
  `.ariaLabel(_:)`/`.ariaLive(_:)`/`.focusable()` attach them to any view.
  `A11yAudit.audit(_:)` applies the same six rules the browser gate runs.
- **`ErrorBoundary`** + `.errorBoundary { … }` answer a *failing handler*
  inside the guarded subtree with a rendered fallback — and the honest
  boundary: a swift **trap** (`precondition`, a force unwrap, an out-of-bounds
  index) cannot be caught in-process, and no boundary here pretends otherwise
  (`Documentation/STABILITY.md` item 8). pass exactly ONE content view — not
  `@ViewBuilder` (see the gotcha below).
- **typed media primitives** — `Video`, `Audio`, `Picture`, `Source`, `Track`
  (`TrackKind`), `Iframe` (`IframeSandbox`, `.strict` is the **empty** set),
  `Canvas`, `LoadingStrategy`; `sanitizeURL` guards every src-bearing path.
- **localisation** — `WebUIStrings` is the catalog of the framework's own
  strings (67 properties, English default; override any subset), resolved
  through the render context; `WebUIDocument` takes `locale:` (feeds `<html lang>`)
  and typed `direction: Directionality` (`ltr`/`rtl`, wins over the deprecated
  `dir:` string). the Arabic catalog ships as the reference override.

## Consumer gotchas

- **Content flush against a container edge** → missing `__body` wrapper (pad via
  `__body`, not the container). See the `*__body` section above.
- **`/ws` console error at load** → the runtime is on but your server doesn't
  upgrade `/ws` / answer pings.
- **A chart collapses to the width of its own text** → charts contribute no
  intrinsic width; give the container a declared width or a grid track, and pick
  the design width (`chartHeight`) for the smallest placement (see *Charts*).
- **`class("x")` on a component *merges* with its own classes (2.0)** — the old
  replace semantics are gone, so `WebUIButton("Go").class("mine")` keeps
  `button button--primary button--md` and adds `mine`. there is **no**
  replace-escape modifier. to override a framework class, scope a rule (a
  `StyleSheet`, or `.parent > .vstack { … }`) — unlayered host css outranks
  the framework by cascade origin.
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
- **`Text` emits a bare text node, not an element.** it frames no element at
  all, so a grid/flex container that renders texts directly has no items to
  lay out (shared by the chart-width trap above). wrap text content in
  `Span`/`Div` whenever CSS layout depends on it.
- **The array-shaped `ViewBuilder` cannot infer a single-view generic.** this
  package's `ViewBuilder` wraps every view into `[any View]`, so an API with a
  `@ViewBuilder` closure and one generic `Content: View` parameter can never
  infer `Content` from a single view expression. any API wanting exactly ONE
  view takes a plain closure (`ErrorBoundary.init`, `Route.page`) — follow that
  model in your own components, and compose a multi-view subtree as one view
  (`VStack { … }`).

## Committing (in your own app)

Conventional lowercase scope, sentence-case subject, dash-led bullets, closing
line with gate/test results (e.g. `test(webui):` / `fix(app):`). When you change
a component's look, verify it reaches the browser in both themes and that the
round-trip updates the DOM node (read the server-patched element, not the input
value).
