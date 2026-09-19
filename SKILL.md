---
name: no-webui
description: Build web UIs in Swift with the no-webui SwiftUI stack.
version: 1.1.0
author: Tanner D'silva, Hermes Agent
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [no-webui, swiftui-for-web, webui, swift, design-system, web-ui]
    related_skills: [webui-design-system, agent-chat-ui]
---

# no-webui Skill

**Your UI is written in Swift.** Every screen, every component, every
interaction is expressed as Swift view composition — the toolkit renders
the semantic HTML, applies the design system, and patches the DOM over a
WebSocket so you never have to. The web is only the delivery surface.

This package is a SwiftUI-shaped view model for the web: `View` types
compose like SwiftUI, `.render()` emits HTML, and a small JS runtime handles
event round-trips and DOM patching. A host app (like `arc-agent`) depends on
`no-webui` as a Swift package and expresses its entire UI in Swift.

The one rule that matters more than any other: **build the UI in Swift**,
not HTML/CSS/JS. If you are hand-writing raw markup, an inline `style`
attribute, a CSS class string, or a `Raw(...)` HTML blob in a host file,
stop — that is the anti-pattern. Express it as Swift. Reach for an existing
no-webui component first; if none fits, add a new **Swift component** so the
next UI reuses it, instead of pasting markup.

## When to Use

- You want to write (and own) a web UI **in Swift**, served by a Swift
  server (gateway, agent harness, tool dashboard, interactive demo).
- You want server-rendered HTML with live round-trip interactivity
  (click/input/submit → Swift handler → DOM patch) without a JS SPA.
- You want to reuse a design system (tokens, buttons, cards, tables, trees,
  tabs, badges, empty states…) from Swift-rendered views.
- You want to compose an app frame (nav rail / sidebar / panels) with Swift
  views, not markup.

Don't use for: a hand-written static HTML/CSS landing page (there's no JS
authoring here), or any client-side-only UI.

## Prerequisites

- macOS (the Package targets `.macOS(.v15)`), with a working `swift`
  toolchain (Swift 6.x line; the SwiftUI view-DSL and macros need it).
- Consumed as a **path dependency** from a host Package.swift:

```swift
.package(path: "../no-webui")
```

and linked via the library products:

```swift
.product(name: "WebUI", package: "no-webui"),
.product(name: "WebUIDesignSystem", package: "no-webui"),
.product(name: "WebUIAuth", package: "no-webui"),   // if you need login
```

Then `import WebUI` and `import WebUIDesignSystem` in your Swift files.
No external JS/CSS/npm — the design system and runtime are embedded at
build time.

## Write Your UI in Swift (the guiding principle)

- **Express every UI as Swift views.** Compose `VStack`/`HStack`/`ZStack`,
  `ScrollView`, `WebUIButton`, `WebUITree`, `WebUIPanel`, etc., then call
  `.render()` to get HTML. The toolkit owns the markup.
- **Prefer an existing component over any markup.** The design-system and
  shell components cover buttons, inputs, cards, badges, tabs, trees,
  tables, lists, segmented controls, sidebars, panels, composers, empty
  states. If you need something new, add it as a **Swift component** (a
  `struct …: View`) in `Sources/WebUIDesignSystemCore/`, so every future UI
  composes it — do not emit ad-hoc markup in a host.
- **Build the language up, not the markup down.** Favor the high-level
  shell components over the bare primitives, and the primitives over raw
  elements. A page should read as a SwiftUI view tree, not as an HTML dump.
- **The smell to avoid in a host file:** raw `<div>`/`<button>` strings,
  `class="…"` literals, inline `style=` attributes, or `Raw(...)`/`Div`
  blobs building markup. Refactor that into a reusable Swift `View` and
  keep the host declarative.
- **Interactivity is Swift too.** Write `@Sendable (EventData) async -> [FragmentUpdate]`
  handlers and wire them with `controlAttributes`/modifiers, not with
  hand-injected JS.

## Quick Reference

- **Products (library):** `WebUI`, `WebUIDesignSystem`, `WebUIChart`,
  `WebUIAuth`.
- **Products (executables):** `WebUIExample`, `WebUIAuthExample`,
  `WebUIShowcase` (generates the reference showcase), `WebUISmokeTest`
  (the live interactive page used by the smoke gates).
- **Design assets (canonical source):** `designer/assets/design-system.css`
  and `designer/assets/webui-runtime.js`. Read from directly at build time
  (no copy step).
- **Reference showcase:** `designer/previews/showcase.html` — regenerated,
  not hand-edited:
  `swift package plugin showcase --allow-writing-to-package-directory`.
- **Gates / demo (all need `--disable-sandbox`):**
  - `swift test` — always-on; asserts the embedded CSS/JS bytes are
    identical to `designer/assets/`.
  - `swift package --disable-sandbox plugin smoke` — served bytes == source.
  - `swift package --disable-sandbox plugin fullstack-smoke` — live WS
    round-trips.
  - `swift package --disable-sandbox plugin serve` — interactive demo on
    :9123 (foreground; Ctrl+C stops).
  - `node designer/browser-smoke.mjs` — real-DOM layout gate (headless
    Chromium).

## The View Model

Every UI element is a `View` whose `render() -> String` emits HTML. Compose
them like SwiftUI, then render the result into a document.

**Primitives (layout / elements):** `VStack`, `HStack`, `ZStack`, `Grid`,
`Spacer`, `ScrollView`, `Section`, `Navigation`, `Header`, `Footer`, `Main`,
`Aside`, `Div`, `Span`, `Text`, `Button`, `Link`, `Form`, `Input`,
`TextArea`, `Select`/`SelectOption`, `Image`, `Heading`, `Paragraph`,
`UnorderedList`, `OrderedList`, `Table`, `ForEach`, `Group`, `Raw`.

**Modifiers (chain onto a View):** `backgroundColor`, `foregroundColor`,
`font(size:weight:)`, `fontFamily`, `textAlign`, `padding`, `margin`,
`width`, `height`, `maxWidth`, `minWidth`, `minHeight`, `display`, `flex`,
`fill()` (grow to remaining space), `stretch()` (full height/width without
growing), `style(_:_:)` (arbitrary CSS escape hatch), `border`,
`cornerRadius`, `showIf`, `id(_:)`, `attribute`, and the event modifiers
(`onClick`, `onSubmit`, `onInput`, `onKeyDown`, `onOptimisticClick`, …).

**Icons:** `WebUIIcon(.name, size: .md)` — a 618-glyph `IconName` catalog
(Lucide/Feather geometry). Components take `IconName`, never emoji.

**Design-system components** (import WebUIDesignSystem): `WebUIButton`,
`WebUIInput`, `WebUIBadge`, `WebUIAvatar`, `WebUICard`, `WebUITabs`,
`WebUITree`, `WebUITable`, `WebUIEmptyState`, `WebUISpinner`,
`WebUIProgress`, `WebUIModal`, `WebUIToast`, `WebUITooltip`,
`WebUITimeline`, `WebUIBreadcrumb`, `WebUIStat`, `WebUISkeleton`,
`WebUIAlert`, `WebUIPagination`.

**Shell components** (app-frame building blocks): `WebUISidebar`
(`.full` or `.rail` nav, link items, active state + badge),
`WebUISegmentedControl`, `WebUISearchField`, `WebUIListView`/`WebUIListItem`,
`WebUIComposer`, `WebUIPanel` (`.leading`/`.trailing` divider).

### Compose and render a page (all Swift)

```swift
// imports: WebUI, WebUIDesignSystem
let body = VStack(spacing: 16) {
    Heading("Hi", level: .h2)
    WebUIButton("Go", variant: .primary, size: .md)
}
.padding(24)
.render()               // -> String HTML fragment

let doc = WebUIDocument(title: "Page", body: body,
                        runtimeConfig: RuntimeConfig(renderToken: "...")).render()
```

## Interactivity (Swift handlers, server round-trips)

The live layer: the runtime opens a WebSocket and forwards DOM events as
`{"type":"event","component":"c0","event":"click","data":{...}}`; the
server's `EventRouter` dispatches to a registered **Swift** handler and
returns `FragmentUpdate`s, which the runtime applies by replacing target
elements.

- Register handlers during page build with `controlAttributes(id:event:handler:)`
  inside `RenderContext.$current.withValue(RenderContext(router: router)) { … }`.
  The attributes it returns (`data-component-id`/`data-event`) go on the
  interactive element.
- An `EventHandler` is Swift: `@Sendable (EventData) async -> [FragmentUpdate]`.
  Read fields via `event.string("value")` / `event.string("targetId")`
  (the clicked element's id) / `event.string("key")`.
- `FragmentUpdate(id: "...", html: "...")` replaces the element whose id
  matches, so a re-rendered region must re-carry its routing anchor.
- **Stable-id discipline:** for regions that fragment updates re-render,
  register handlers under a caller-chosen id and re-emit that same id on
  every re-render (the page-build registration persists in the router).
- For a list/segmented/sidebar, put one handler on the container and
  dispatch on `event.string("targetId")` — give each row a DOM `id` (the
  row's bare item id) and set `pointer-events: none` on row children so the
  click resolves to the row element.

## Procedure

1. **Add the dependency** (Prerequisites) and `import WebUI`,
   `import WebUIDesignSystem`.
2. **Compose a page shell in Swift** — a nav rail (`WebUISidebar(.rail)`)
   + content, or an app frame of `WebUIPanel`s. Build it from components,
   then `.render()`.
3. **Assemble the document** with `WebUIDocument(title:body:)`. For
   multi-pane scroll layouts (chat), render the shell flow with `body` at
   `100vh` and let inner panes own their scroll.
4. **Wire interactivity in Swift** (see Interactivity) so `EventHandler`s
   are registered at page build.
5. **Build** `swift build`, **run** your server, and **verify** (below).
6. **Regenerate the showcase** after any component/CSS change so
   `showcase.html` stays in sync.

## Design Rules (the house style)

- **No-prefix BEM classes** — `.button`, `.button--primary`, `.card`,
  `.list__item`. `br-` appears only in CSS keyframe/animation names.
- **Token-only values** in component CSS — never raw hex/px; always
  `var(--color-*)`, `var(--space-*)`, `var(--font-size-*)`.
- **No comments in shipped assets** — `design-system.css`,
  `webui-runtime.js`, and every generated document go over the wire
  verbatim. Comments stay in Swift and `Documentation/*.md`.
- **Design tokens must be single-sourced in the CSS**; the Swift
  `WebUITheme` palette is legacy — don't trust or duplicate it.
- **Dark mode** is handled via `@media (prefers-color-scheme: dark)` that
  remaps the semantic tokens — design both themes, verify both.
- **Icons, never emoji**, in component icon slots; each icon slot needs an
  explicit CSS box.

## Pitfalls

- **Writing raw markup in a host** is the number-one mistake. If you catch
  yourself emitting `<div…>`/`class="…"`/inline `style=` or a `Raw(...)`
  blob in a consumer, refactor it into a reusable Swift `View` component —
  that is the no-webui way, and it's what keeps a UI "world class".
- **String-escaping in Swift HTML literals.** When building HTML strings,
  a doubled backslash (`\\`) renders a literal `\`, so `\\(htmlEscape(x))`
  emits the source text instead of the value. Write single `\(…)`.
  Prefer Swift multiline string literals to reduce the `\"` escaping.
- **Nested ternary inside interpolation** (`"…\(a == b ? "x" : "y")…"`)
  breaks the parser — compute the fragment into a `let` first.
- **Swift labeled-argument order = declaration order** — a WebUIShell init
  called with args out of order fails with "argument X must precede
  argument Y"; read the init first.
- **The `:not()` form-control reset out-specifies component classes.** The
  reset rule `input:not(.input):not(…):not(…)` (specificity 0,9,1) overrides
  a plain `.input`/`.search-field__input` padding. Exclude the component
  class from the reset chain (`:not(.search-field__input)`) and verify the
  computed style.
- **`.fill()` vs `.stretch()`.** `fill()` = `flex:1` (grows on the main
  axis, takes remaining space); `stretch()` = full cross-axis height/width
  without growing. Use `stretch()` on fixed-width sidebars/rails and
  `fill()` on the region that should consume the rest.
- **`showcase.html` is a generated artifact.** A rendered artifact that
  shows something the source lacks = stale artifact, not a framework bug;
  regenerate, don't hand-edit.
- **The `.build` lock.** A running plugin invocation holds the package
  `.build` lock, so never run a gate while `serve` (or another plugin) is
  up. Gates and `serve` need `--disable-sandbox` (bind is sandbox-denied).
- **Preview `file://` in Playwright.** `browser_navigate` blocks `file://`,
  but `browser_run_code_unsafe` with `page.goto('file:///…')` works; open
  previews that way.
- **Verify the theme, not the file.** Dark captures need
  `page.emulateMedia({colorScheme:'dark'})` and a computed body
  `background-color` check (`rgb(6,9,16)` dark / `rgb(244,246,248)` light);
  never infer theme from a non-white-pixel fraction.
- **Two host servers can share one port** (IPv4 vs IPv6 `localhost`); a
  browser can hit the stale instance. Diagnose with `lsof` + `pgrep` and
  md5 the served asset bytes.

## Verification

- `swift test` passes (asserts embedded CSS/JS are byte-identical to the
  `designer/assets/` sources).
- `swift package --disable-sandbox plugin smoke` reports served bytes ==
  source.
- `swift package --disable-sandbox plugin fullstack-smoke` exercises live
  WS round-trips.
- Read the page source and confirm it was produced by Swift views — the
  markup should carry the framework's no-prefix component classes
  (`.list__item`, `.composer`, `.tree`, `.panel__header`, …), never a raw
  ad-hoc `class="my-custom-thing"` that a host invented.
- For the UI: build + run your server, then drive it with Playwright —
  assert the page renders (title + computed body background), your target
  classes/elements are present, and a click/input/submit round-trips to an
  updated DOM node (read the server-patched element, not the input value).
- After any CSS/component change, regenerate the showcase and confirm it
  shows the new output in **both** light and dark.
