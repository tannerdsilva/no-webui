# Substitution — customizing the live axes by conformance (no-webui)

The one model behind the framework's extensibility:

> **A customization is a conforming type passed in.** every seam ships **(1)** a protocol that
> names the role, **(2)** a framework default, **(3)** an injection position (parameter, generic,
> or registry), and **(4)** a twin test proving a *non-default* conformance passes the same gate.
>
> **No-layer rule:** if you must shadow framework CSS, re-implement a loop, or pre-register a
> control the framework could route — the seam is missing. fix the seam, not your app.

This is the packaged companion to `Documentation/SUBSTITUTION.md` in the no-webui checkout; the
same rules, condensed for use while building. The reference implementations it quotes live in
`Sources/WebUIExample/main.swift` (the demo) and `Tests/WebUITests/` in the package.

## The four axes at a glance

| axis | conform to | framework default | inject via |
|---|---|---|---|
| **events** | `EventOutcome` (`resolve(_:) -> [FragmentUpdate]`) | six conformances: `FragmentUpdate`, `[FragmentUpdate]`, `ViewOutcome`, `RegionInvalidations`, `NoOutcome`, `CombinedOutcome` | `control(_:event:handler:)` (generic) or `controlAttributes(id:)` (classic) |
| **live data** | `LiveRegion` (+ `LiveState` for state) | `ClosureLiveRegion`, `StateLiveRegion`, `LiveBox`, `LiveNotifier` | the `regions:` parameter on `WebUIServer` |
| **themes** | `WebUIThemeProvider` (or `@Theme`), collected by `ThemeCatalog` | `.standard` (empty, byte-identical) | attach `WebUIThemePlugin` to the target declaring the catalog; reference the emitted sheet |
| **components** | `View`, `ViewModifier` | the 133 design-system components | composition (`ModifiedView`, the DSL); styling via theme tokens/rules, never a CSS fork |

**Three names that get confused** (memorize once):

- `WebUITheme` — the runtime theme **value** (`struct`: palettes, mode, rules, aliases);
  `WebUIThemeProvider` — the **protocol** a theme type conforms to; `@Theme` generates it.
- `WebUIThemeBuild` — the **build-time library** (`emit(catalog:typeName:options:to:)`) that turns
  a catalog into a shipped asset.
- `WebUIBuild` — the generic **emitter** `WebUIThemeBuild` rides (`WebUIAssetBuilder`). Both are
  host-side build names; neither ships bytes to a page.

## Events — what a handler yields

A handler states *what it yields*; the framework adapts it to the wire:

```swift
// one update (classic shape — unchanged and always available)
controlAttributes(id: "btn", event: .click) { event in
    [FragmentUpdate(id: "counter-value", html: render(count))]
}

// render a view and replace the control's own element (ViewOutcome)
let wire = control("g-outcome", event: .click) { (event: EventData) -> ViewOutcome<Div> in
    ViewOutcome(Div(class: "demo-replaced") { Text("replaced") })
}
// the replaceable ROOT must carry id == data-component-id for ViewOutcome; minted ids (cN,
// Dismissible/WebUIButton) are out of contract — return fragments for those instead.
```

biting rules: the closure's return type fixes `O` — **annotate it**; a control first rendered
*inside* a handler self-registers (dispatch runs inside the render seam); a stable id re-registers
per render (overwrite-wins) so re-emitted fragments keep routing. `RegionInvalidations([id])` is
how a handler declares "a live region changed" (see `live-regions.md`).

## Live data — regions that push on their own

a region is a server-owned piece of the page that re-renders and pushes **only when it changed**.
See `live-regions.md` for the full recipe. Minimum:

```swift
let regions = WebUILiveRegions([
    ClosureLiveRegion(id: "g-region-a") { "<span id=\"g-region-a\">…</span>" },
])
let server = WebUIServer(render: { page() }, router: router, config: cfg, regions: regions)
```

## Themes — tokens in, shadowing out

```swift
@Theme
struct Light { static let colorPrimary500 = "#f97316" }
@Theme(base: Light.self)
struct Dark { static let colorPrimary600 = "#ea580c" }
struct Twin: WebUIThemeProvider {            // hand-written, no macro — same pipeline
    static let theme = Light.theme.overlaying(WebUITheme(tokens: [.colorDanger500: "#dc2626"]))
}
enum Catalog: ThemeCatalog {
    static var all: [any WebUIThemeProvider.Type] { [Light.self, Dark.self, Twin.self] }
    static var defaultTheme: any WebUIThemeProvider.Type { Light.self }
}
```

attach the plugin to the target that declares the catalog —
`plugins: [.plugin(name: "WebUIThemePlugin", package: "no-webui")]` — then reference the emitted
`<CatalogTypeName>Sheet` via `WebUIAsset(CatalogSheet.self, path:)`. The build emits a stamped,
gzipped asset through the framework path; **you write no tooling**. do not restyle design-system
classes by shadowing them (the `shadow` check in `WebUIContinuumTool` names collisions — the demo
target is 0).

## Components — compose, don't re-skin

Prefer an existing component; when none fits, add a Swift `View` (in your app). `.class("x")` on a
component **replaces** its own classes — wrap in `Div(class:)` instead. Interiors pad via the
`*__body` child. Token-only values (no raw px/hex). Styling substitution rides the theme surface.

## The twin discipline (why this is enforceable)

per seam, a type the framework has never seen must pass the same gate the default passes:

- events — a custom `EventOutcome` struct drives the same dispatch path (`SubstitutionTests`);
- live data — a custom `LiveRegion` struct + a custom `LiveState` actor run the same suite
  (the `twins` test in `LiveRegionsTests`);
- themes — a hand-written `WebUIThemeProvider` emits through the same pipeline (the probe twin);
- components — the demo is conform-only; the acceptance's no-layer audit asserts it.

if your customization cannot be expressed as a conformance, that is a framework gap worth
reporting — not something to solve with a layer in your app.