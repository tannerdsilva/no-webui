# Substitution — customizing the live axes by conformance

> **A customization is a conforming type passed in.** for every seam this arc adds:
> **(1)** a protocol names the role; **(2)** the framework ships a default implementation;
> **(3)** an injection position exists (parameter, generic, or registry);
> **(4)** a **twin test** proves a *non-default* conformance passes the same gate the default passes.
>
> **The no-layer rule:** if a consumer must shadow framework CSS, re-implement a loop, or
> pre-register a control the framework could route, the seam is missing — fix the seam, not the
> consumer.

this document is the consumer-facing guide to the four live axes — **events, live data, themes,
components** — and to the one customization model they share. every example below is real code
from this repository; the file:line citations resolve at the live-dx integration head
(`c24857a` — i0's DX-12/DX-14 with lanes R (DX-13/DX-16) and T (DX-15a/DX-15b) merged). where the
reference demo (`Sources/WebUIExample/main.swift`) exercises the axis, the example is lifted from
it verbatim; the remaining shapes are fixed by the lane handoffs (`dx2-notes/r-to-g.md`,
`dx2-notes/t-to-g.md`) and mirrored by the committed twins/fixtures cited beside them.

## the pattern, per axis

| axis | protocol names the role | framework default | injection position |
|---|---|---|---|
| **events** | `EventOutcome` (`WebUICore/EventHandling.swift:47`) | six conformances: `FragmentUpdate`, `[FragmentUpdate]`, `ViewOutcome`, `RegionInvalidations`, `NoOutcome`, `CombinedOutcome` (`:71–121`); the pre-DX-14 `EventHandler` path unchanged | `control(_:event:handler:)` (`:307`) — the outcome-typed sibling of `controlAttributes(id:)` (`:288`) |
| **live data** | `LiveRegion` (`WebUIServer/LiveRegions.swift:19`); the state half `LiveState` (`WebUIServer/LiveState.swift:19`) | `ClosureLiveRegion` (`:39`), `StateLiveRegion` (`:65`), `LiveBox` (`LiveState.swift:125`), `LiveNotifier` (`:51`); `source` defaults `nil` (`:31–34`) | the `regions:` parameter on both `WebUIServer` inits (`WebUIServer.swift:306`, `:323`; `nil` = zero new work) |
| **themes** | `WebUIThemeProvider` (`WebUIDesignSystemCore/WebUITheme.swift:314`), collected by `ThemeCatalog` (`:354`); `@Theme` (`WebUIDesignSystem/Theme.swift:42`) generates conformances | `.standard` — the empty theme (`WebUITheme.swift:204`), byte-identical to an unthemed page; an empty catalog override list | build: attach `WebUIThemePlugin` to the target declaring the catalog (`Plugins/WebUIThemePlugin/WebUIThemePlugin.swift:28`); runtime: `WebUIThemeProvider.Type` positions (`WebUIDocument(theme:)`, the catalog) |
| **components** | `View` (`WebUICore/View.swift:2`), `ViewModifier` (`:36`) and the 133 design-system components | the design system itself | composition — `ModifiedView<Content>` wrapping and the view-builder DSL; styling substitution rides the theme surface (tokens + `@Theme(rules:)`), not a CSS fork |

## the three adjacent names, once

four names get confused in this neighborhood; here is the whole vocabulary, once:

| name | where it lives | role |
|---|---|---|
| `WebUI**Theme**` | `Sources/WebUIDesignSystemCore/WebUITheme.swift:143` — **runtime** | the theme **value**: palettes, mode, `rules`, `aliases`; a `struct`, what a provider returns and a document renders (`stylesheet(scope:)`). |
| `WebUI**ThemeProvider**` | `WebUITheme.swift:314` — **runtime** | the runtime **protocol** a theme *type* conforms to (`static var theme: WebUITheme`, plus the defaulted identity members); `@Theme` synthesizes it, a hand-written conformer compiles for free. "a theme" as a type is this pair: provider + value. |
| `WebUI**ThemeBuild**` | `Sources/WebUIThemeBuild/WebUIThemeBuild.swift:21` — **build-time, host-side** | the **build library**: renders a consumer catalog to a stamped, gzipped `WebUIShippedAsset` conformance (`emit(catalog:typeName:options:to:)`, `:37`). runs inside the plugin's build command; never ships to a page. |
| `WebUI**Build**` | `Sources/WebUIBuild/` — **build-time, host-side** | the **emitter** `WebUIThemeBuild` rides: `WebUIAssetBuilder.emit`, `.Options`, `Emitted`, deterministic gzip and the manifest (`Emit.swift:13`, `:83`, `:86`). the same machinery the framework's own sheet/engine/assets use. |

memory hooks: names beginning `WebUITheme…` are **runtime** vocabulary; the two `…Build` names are
**host-side build** vocabulary, and their direction is fixed — `WebUIThemeBuild` (theme-specific) sits
**on** `WebUIBuild` (the generic emitter), never beside it. neither build name ever appears in served
bytes (`WebUIThemeBuild.swift:15–17`).

---

## axis — events

**protocol.** `EventOutcome` (`Sources/WebUICore/EventHandling.swift:47–49`): a handler states *what
it yields* via `resolve(_ context: OutcomeContext) async -> [FragmentUpdate]`, and the framework
adapts each conformance to the one wire substrate.

**framework default.** six conformances ship (`EventHandling.swift:71–121`):

| conformance | what it yields |
|---|---|
| `FragmentUpdate` (`:71`) | one update |
| `[FragmentUpdate]` (`:76`) | several, verbatim |
| `ViewOutcome<Content: View>` (`:83`) | render the view and replace `#<component id>` |
| `RegionInvalidations` (`:93`) | declares the change; the live registry renders and pushes |
| `NoOutcome` (`:103`) | nothing |
| `CombinedOutcome<A, B>` (`:109`) | both, in order |

the pre-DX-14 shape is unchanged (additive only): a plain `EventHandler` is still
`@Sendable (EventData) async -> [FragmentUpdate]` (`:40`), and `controlAttributes(id:event:handler:)`
(`:288–298`) still emits byte-identical `data-component-id`/`data-event` attributes.

**injection position.** `control(_:event:handler:)` (`EventHandling.swift:307–319`) — the generic
sibling of `controlAttributes(id:)` (note the **label rule**: `control` takes its id unlabeled,
`controlAttributes` labeled `id:`, so the two never compete in overload resolution). both register
through the ambient `RenderContext`; the server establishes it around the page render *and* every
dispatch (`RenderContext.withCurrent(router:)`, `:249`/`:256`; the dispatch wrap is `dispatchOutcome`
in `Sources/WebUIServer/WebUIServer.swift:1134–1140`).

**a minimal conforming example — lifted from the demo** (`Sources/WebUIExample/main.swift:88–105`):

```swift
/// ViewOutcome (2) — `resolve` renders `Content` and replaces `#<component id>`.
/// contract (rev4/a2): the control's replaceable ROOT must carry that DOM id, so
/// the cell's root div carries `id="g-outcome"` beside the routing attributes.
/// the update's fragment id therefore appears in the served markup's id set.
func outcomeCellHTML() -> String {
	let wire = control("g-outcome", event: .click) { (event: EventData) -> ViewOutcome<Div> in
		ViewOutcome(
			Div(class: "demo-replaced") {
				Text("replaced by ViewOutcome — the update's fragment id (g-outcome) is in the served markup")
			}
		)
	}
	return """
	<div id="g-outcome" class="demo-cell demo-cell--outcome"\(wire)>
	  <p class="demo-note">idle — click to replace this cell with a View.</p>
	</div>
	"""
}
```

and the handler-rendered control, also lifted (`main.swift:64–74`) — a control first rendered
*inside* a handler works because dispatch runs inside the seam:

```swift
func swapStage1HTML() -> String {
	let wire = demoControl("swap in a stage-2 control", id: "g-swap") { (event: EventData) -> [FragmentUpdate] in
		[FragmentUpdate(id: "g-swap-panel", html: swapStage2HTML())]
	}
	return """
	<div class="demo-cell">
	  <p class="demo-note">stage 1 — click to swap in a stage-2 control rendered by this handler.</p>
	  \(wire)
	</div>
	"""
}
```

**the biting semantics, consumer-stated.**

- **overwrite-wins.** re-rendering a control under a *stable* id re-registers it — the router always
  holds the newest closure for that id (`EventHandling.swift:267–273`; pinned by
  `Tests/WebUITests/SubstitutionTests.swift:148–158`). stable ids are a pure function of component
  state, so a context-free fragment re-render keeps routing.
- **`ViewOutcome` requires the DOM id.** `resolve` replaces `#<OutcomeContext.component.value>` —
  the control's replaceable **root** must carry `id == data-component-id` (the demo does this at
  `main.swift:101`). **minted-id contexts are out of contract**: `Dismissible`'s and `WebUIButton`'s
  auto-minted `cN` ids are not in the document, so those handlers must return fragments instead
  (`EventHandling.swift:80–82`).
- **`OutcomeContext.$current` is dispatch-scoped.** a handler (or an erased adapter) reads the
  firing component and the invalidate half from it; it is `nil` outside a dispatch
  (`EventHandling.swift:60–62`; pinned at `SubstitutionTests.swift:217–231`).
- **annotate the closure's return type — though on this toolchain it is already optional.** the
  closure's type fixes `O`; the demo's call sites annotate (`main.swift:65`, `:77`, `:93`, `:112`)
  as documented convention. measured during the s-sugar spike (against the real `WebUICore`): every
  probed call shape compiles **without** the annotation — single expression, multi-statement with
  `return`, with `await`, through the erased generic wrapper, and a bare `[]` literal. the
  annotation is convention, not a compiler requirement; what the seam itself still refuses is a
  handler body that yields nothing (a lone-effect body is a compile error at `control`). for the
  three effect-only handlers in that shape, the per-shape helpers below are the named way to say
  nothing.
- **two-push ordering.** when a handler's `RegionInvalidations` wakes a region, the dispatch frame is
  written to the socket **before** the region pushes — the registry marks dirty inside the seam and
  wakes only after the handler frame is on the wire (`WebUIServer.swift:1131–1133`;
  `LiveRegions.swift:220–249`).

**twin.** a custom `EventOutcome` struct the framework has never seen drives the same dispatch path
(`Tests/WebUITests/SubstitutionTests.swift:31–36`, run at `:187–202`).

**the per-shape outcome helpers (new public API — `Sources/WebUICore/EventOutcomeBuilder.swift`).**
six typed entry points, one per outcome shape; each body is the shape's conformance spelled once, so
the protocol stays first-class (no builder, no hidden grouping, no hidden default). the helpers are
**additive** — the hand-written `control("id") { … }` spelling keeps compiling, keeps its bytes, and
keeps its lone-effect guard.

| helper | yields | abuse case it names |
|---|---|---|
| `noOutcome(_:event:_:)` | `NoOutcome()` | the effect-only handler — `await body(data); return NoOutcome()` in one step. the body is `Void` by signature, so *yields nothing* is the caller's named intent, not a silent default |
| `fragments(_:event:_:)` | `[FragmentUpdate]` | several updates, verbatim (a one-element array for one) |
| `replaceFragment(_:event:_:)` | `FragmentUpdate` | the single-update shape, sealed as a named entry point |
| `replaceView(_:event:_:)` | `ViewOutcome<Content>` | render `Content` and replace `#<id>` (its root must carry the DOM id, per the `ViewOutcome` contract above) |
| `invalidate(_:event:ids:)` | `RegionInvalidations(ids)` | declare the change only; static by design — ids cannot depend on the payload (the raw seam remains for that) |
| `updateThenInvalidate(_:ids:event:_:)` | `CombinedOutcome<FragmentUpdate, RegionInvalidations>` | one update AND an invalidation, in that order — the ordering the live-region demos depend on |

measured honestly (the s-sugar verdict, `dx2-notes/s-sugar-verdict.md`): the `O` annotation was
**already optional** on this toolchain, so the helpers do not remove a compiler requirement — they
remove the *residual* ceremony at the effect-only sites (`_ in`, `return NoOutcome()`) and name each
shape at the call site. they **do not replace the protocol**: a custom `EventOutcome` conformance, a
payload-dependent combination, or any novel shape still uses `control` directly. what they remove is
spelled in each body — `await body(data)` into the adapted conformance — so nothing is hidden.

---

## axis — live data

**protocol.** `LiveRegion` (`Sources/WebUIServer/LiveRegions.swift:19–29`) — four members, one
defaulted:

```swift
public protocol LiveRegion: Sendable {
	var id: String { get }                    // the DOM id AND the pushed fragment id
	var cadence: Duration? { get }            // nil = invalidation/state-driven only
	var source: (any LiveState)? { get }      // default nil — the registry's subscription hook
	func render() async -> String?            // nil = nothing to push
}
```

**framework default.** `ClosureLiveRegion` (`:39–58`, the ergonomic default), the state-bound
`StateLiveRegion<State: LiveState>` (`:65–86`), and the state half: `LiveState` (`LiveState.swift:19`),
`LiveBox` (`:125`, the Mutex-backed default), `LiveNotifier` (`:51`, the embeddable mixin for custom
state), `LiveSubscription` (`:25`, idempotent `cancel()`). the registry handle is `WebUILiveRegions`
(`LiveRegions.swift:97`; `invalidate` `:122`, `invalidateAll` `:137`, `currentHTML` `:148`).

**injection position.** the `regions:` parameter on **both** `WebUIServer` inits
(`WebUIServer.swift:306`, `:323`), defaulted `nil` — `nil` means zero new work: no subscriptions, no
baselines, no pumps, and the dispatch seam keeps its no-op invalidate provider (`:335–338`).

**a minimal conforming example — the attach** (shape fixed by `dx2-notes/r-to-g.md`; the region id is
the one the served demo already declares — its nudge control targets `g-region-a`,
`Sources/WebUIExample/main.swift:113`):

```swift
let regions = WebUILiveRegions([
	ClosureLiveRegion(id: "g-region-a") {
		"<span id=\"g-region-a\">…</span>"
	},
])
// both WebUIServer inits: regions: WebUILiveRegions? = nil  (nil = zero new work)
let server = WebUIServer(
	render: { renderExamplePage(state: state, router: router) },
	router: router,
	config: WebUIServerConfig(port: 9090),
	regions: regions
)
```

**the four driver forms** the demo ships (`r-to-g.md` §"what the demo must ship"; each form below
mirrors a committed twin in the W1 suite):

```swift
// (b) a custom LiveRegion STRUCT — the DX-13 twin (Tests/WebUITests/LiveRegionsTests.swift:38–49)
struct TwinRegion: LiveRegion {
	let id: String
	let cadence: Duration?
	let box: LiveBox<Int>
	var source: (any LiveState)? { box }
	func render() async -> String? {
		let value = box.value                 // one locked snapshot, before any await
		return "<span id=\"\(id)\">\(value)</span>"
	}
}

// (c) a LiveBox-backed region (the doc-comment shape, LiveState.swift:117–124)
let count = LiveBox(0)
let counterRegion = StateLiveRegion(id: "counter-region", state: count) { box in
	let value = box.value
	return "<span id=\"counter-region\">\(value)</span>"
}

// (d) a custom LiveState ACTOR — subscribe must be `nonisolated` (LiveRegionsTests.swift:79–95)
actor FeedState: LiveState {
	private let notifier = LiveNotifier()
	private var items: [String] = []
	nonisolated func subscribe(_ onChange: @escaping @Sendable () -> Void) -> LiveSubscription {
		notifier.add(onChange)
	}
	func append(_ item: String) { items.append(item); notifier.notify() }
}
```

**the biting semantics, consumer-stated** (the nine from `dx2-notes/r-to-d.md`):

1. **baseline silence.** `start()` renders every region's baseline eagerly and pushes **nothing**; a
   push happens only on a real change.
2. **byte minimality.** an unchanged render pushes **zero** frames; a changed one pushes **≤ its
   rendered html + 512 B**. the framework byte-compares; the consumer never diffs
   (`LiveRegions.swift:281`; socket-pinned at `LiveRegionsTests.swift:490`).
3. **render contract.** `render()` runs *inside the render context* (a control it emits
   self-registers) and returns `String?`; `nil` = nothing to push. **stable ids only** — a minted id
   (no DOM id) grows the router's handler map; the registry warns
   (`live region '<id>' grew the handler map across a render`, `LiveRegions.swift:289–301`).
4. **state binding.** `LiveRegion.source` (defaulted `nil`) is the registry's subscription hook;
   `StateLiveRegion` returns its state. the registry subscribes every non-nil source at `start()`,
   **before** baselines, and cancels them at `stop()` (`LiveSubscription.cancel()` is idempotent and
   suppresses future delivery). a custom actor's `subscribe` witness **must be `nonisolated`** — a
   sync hop onto a busy actor can block `start()` (`LiveState.swift:16–18`).
5. **notify-after-unlock.** `LiveBox` (and `LiveNotifier`) notify strictly **after** the lock is
   released; a render closure must snapshot the value **once**, before any `await`
   (`LiveState.swift:93–100`, `:134–149`).
6. **`currentHTML` best-effort.** `currentHTML(id)` is the last committed render at the instant of
   the call — a host-scoped baseline, **not a per-client snapshot** (drift windows exist;
   `LiveRegions.swift:146–151`).
7. **invalidations.** `invalidate(id)` / `invalidateAll()` mark dirty + wake; a region woken by a
   **dispatch's** `RegionInvalidations` never pushes before the dispatch frame (two-push ordering,
   §events).
8. **lifecycle.** pumps stop with `stop()`; zero frames after stop; a per-start stop flag bounds the
   worker's wait by ≤ 1 cadence (`LiveRegions.swift:202–218`).
9. **overwrite-wins.** re-rendering a stable id re-registers (last-render-wins); it never grows the
   map.

**twins.** the custom struct (`TwinRegion`) and the custom actor (`TwinState`) above pass the same
suite the framework defaults pass — `Tests/WebUITests/LiveRegionsTests.swift:406–429`.

### live data, macro-spelled — the four declaration macros (`@LiveRegion` · `@RegionState` · `@LiveRegions` · `@LiveState`)

**the macros are optional.** this is the substitution law applied to sugar, and it is the spine of
everything below: every macro generates **only** members the frozen protocols already require; the
hand-written spelling keeps compiling and stays **byte-identical** on the wire; and a twin proves the
macro path equals the hand path (same ids, same frames, same bytes). the four declarations live in
`Sources/WebUIServer/LiveMacroDeclarations.swift` and resolve with `import WebUIServer`. misuse
yields diagnostics, never `fatalError`.

| macro | attaches to | generates (additive) |
|---|---|---|
| `@LiveRegion(id:cadence:)` | a struct/class/actor | the `LiveRegion` conformance: `id` from the attribute, `cadence` from the attribute (`nil` when omitted), and `source` from the property marked `@RegionState` |
| `@RegionState` | the ONE stored property that is the region's `source` | nothing alone — a marker the `@LiveRegion` member scan reads; marking none means `source == nil` (the protocol default), marking two is a diagnostic |
| `@LiveRegions` | the live-data group | `var registry: WebUILiveRegions` assembled from the group's region properties, in declaration order |
| `@LiveState` | an actor | the `LiveState` conformance: a `nonisolated subscribe` forwarding to an injected `LiveNotifier`, and `notify()` |

```swift
@LiveRegions
struct DemoRegions {
	// (2) a custom LiveRegion STRUCT — the conformance, id, cadence and source
	//     hook are generated; the marked property IS the source.
	@LiveRegion(id: "g-region-b")
	struct Tick {
		@RegionState let box: LiveBox<Int>
		func render() async -> String? {
			"<div id=\"g-region-b\">…\\(box.value)</div>"
		}
	}

	// (4) a custom LiveState ACTOR — subscribe (nonisolated, by construction)
	//     and notify() are generated; the state and its mutators stay yours.
	@LiveState
	actor Feed {
		private var value = 0
		func bump() { value += 1; notify() }
		func snapshot() -> Int { value }
	}

	// the framework defaults, unchanged — the macro layer is not required for them
	var tick = Tick(box: LiveBox(0))
	var feed = Feed()
	var clock = ClosureLiveRegion(id: "g-region-a") { "…" }
	var countBox = LiveBox(0)
	var count = StateLiveRegion(id: "g-region-c", state: countBox) { box in "<div id=\"g-region-c\">…</div>" }
}
// → registry is generated from the property list, in declaration order
```

**the generated surface, exactly** (frozen at i0, `macro-dx/i0-landing.md`):

- **two roles per macro.** `@LiveRegion` and `@LiveState` are each both `@attached(member, names:)`
  (the witnesses) and `@attached(extension, conformances:)` (the `extension T: LiveRegion {}` /
  `extension T: LiveState {}`). a member macro cannot declare conformances and an extension cannot
  add stored properties — `@LiveState`'s `liveNotifier` storage is a member for exactly that reason.
- **computed witnesses.** `var id: String { "…" }`, never stored — a macro-injected stored property
  would join the memberwise initializer and change every call site (`Tick(box:)` still constructs).
- **`@LiveRegions` classifies by syntax, not type** (a macro sees syntax): a property is a region
  when its written type — or its initializer's callee — names a nested type carrying `@LiveRegion`,
  or `ClosureLiveRegion`/`StateLiveRegion`; a nested `@LiveState` type, `LiveBox` or `LiveNotifier`
  is skipped; **anything else is a diagnostic, never a silent skip** (a silently dropped region is
  the failure this arc exists to remove). the generated `registry` is computed
  (`WebUILiveRegions([tick, clock, count])`), declaration order, no ordering knob.
- the full diagnostic set (missing `render()`, a hand-written `id`/`cadence`/`source`/`subscribe`
  colliding with a generated one, `@LiveState` on a non-actor, empty or unclassifiable groups,
  duplicate ids as a warning) is pinned by `Tests/WebUIServerMacroTests/NegativeFixturesTests.swift`,
  and the expansions themselves are frozen byte-exact (`FrozenFixtures.swift`, captured from the
  real expander).

**the three footguns the macros retire:**

1. **`source` is the registry's subscription hook** — omit it by hand and state changes silently
   never wake the region; nothing at compile time says so. `@LiveRegion` + `@RegionState` make the
   marked property the source.
2. **a custom actor's `subscribe` witness must be `nonisolated`** — write it the natural way and the
   registry's *synchronous* subscribe hops onto the actor; a busy actor then blocks `start()`. the
   failure is a stall, not an error. `@LiveState` generates `nonisolated` by construction; it
   cannot be written wrong.
3. **the registry array assembly** — `var registry { WebUILiveRegions([…]) }`, measured at **20
   code lines** on the demo — is generated from the property list.

**when the hand path is clearer:**

- **you are composing the framework defaults.** a `ClosureLiveRegion` or `StateLiveRegion<LiveBox>`
  needs no conformance at all — `regions:` on the server is the whole surface. reach for the macros
  when a custom struct or actor conformance is what you would otherwise write by hand.
- **you have a member the classifier cannot read** — the classification diagnoses rather than
  guesses, so anything not syntactically a region stays in a hand-written group.
- **a runtime-computed id** — the attribute takes a literal; a conformance whose `id` must be
  computed belongs in the hand path.
- **you cannot take a macro-target dependency** (a library product consumed by tools) — the hand
  path has no compiler-plugin dependency at all.
- **you want the conformance spelled out in your source** — generated code is real code, but it is
  a tool's text, not your text; if a reviewer or a generator needs the conformance in the source
  tree, write it by hand (byte-identical on the wire either way).

**the measured net is the honest half** (the re-measure, `dx2-notes/m-consumer-deletion-ladder.md`
· `designer/probes/m-ladder.sh`): the demo's live-data surface — four mechanisms + five controls +
the registry — was **89 code lines** hand-written and is **72 code lines** macro-spelled (the hand
path, untouched, still compiles to the identical surface). the macros remove the conformance
declarations, the notifier plumbing, and the registry assembly; they **cannot** remove the
`render()` bodies and their markup, the states' own properties and mutators, or the choice of
mechanisms and ids — that is content, identical in both spellings.

**parity is gate-executed, not asserted.** `Tests/WebUITests/MacroParityTests.swift` drives the two
spellings through the same registry seam (`start`/render/push) and asserts byte-equal frames for the
same input sequence, and `designer/gates/dx12-16-acceptance.mjs` step 9c runs the same twin against
the live demo while step 9b asserts **both** spellings stay in the source.

---

## axis — themes

**protocol.** `WebUIThemeProvider` (`Sources/WebUIDesignSystemCore/WebUITheme.swift:314–346`) — all
members defaulted, so a hand-written conformer compiles for free; `@Theme`
(`Sources/WebUIDesignSystem/Theme.swift:42`) generates the conformance from a type's `static let`
members. a catalog collects providers: `ThemeCatalog` (`WebUITheme.swift:354–370`) with `all` +
`defaultTheme` and the rendering helpers `entries` / `stylesheet()` / `theme(for:)` (`:371–427`).

**framework default.** `.standard` — the empty `WebUITheme` (`WebUITheme.swift:204`), byte-identical
to an unthemed document; a type that conforms without providing `theme` renders exactly like the
unthemed document (the lifeline default, `:339–341`).

**injection position.** the build side is a **plugin attach**, not a tool: attach
`WebUIThemePlugin` to the app target that declares the catalog (`Plugins/WebUIThemePlugin/WebUIThemePlugin.swift:28`),
and the framework's `WebUIThemeTool` runs a direct `swiftc` over your theme sources on every
`swift build` (`dx2-notes/t-theme-spike-verdict.md` — mechanism **(a)**, spike-verified). **no
consumer tool target, no shim, no script.** the runtime side is the `WebUIThemeProvider.Type`
positions (`WebUIDocument(theme:)` and friends).

**a minimal conforming example — the committed fixture catalog**
(`designer/probes/fixtures/t-theme-catalog/Catalog.swift:8–30`; its header records it "mirrors the
demo catalog shape"):

```swift
@Theme
struct ProbeLight {
	static let colorPrimary500 = "#f97316"
	static let colorPrimary50 = "#fff7ed"
}

@Theme(base: ProbeLight.self)
struct ProbeDark {
	static let colorPrimary600 = "#ea580c"
}

struct ProbeTwin: WebUIThemeProvider {
	static let theme = ProbeLight.theme.overlaying(
		WebUITheme(tokens: [.colorDanger500: "#dc2626"])
	)
}

enum ProbeCatalog: ThemeCatalog {
	static var all: [any WebUIThemeProvider.Type] {
		[ProbeLight.self, ProbeDark.self, ProbeTwin.self]
	}
	static var defaultTheme: any WebUIThemeProvider.Type { ProbeLight.self }
}
```

attach it (your app's `Package.swift` — one line):

```swift
plugins: [.plugin(name: "WebUIThemePlugin", package: "no-webui")]
```

and serve the emitted asset: the plugin writes `<CatalogTypeName>Sheet` (here
`ProbeCatalogSheet`) into its work dir as a `WebUIShippedAsset` conformance, which SwiftPM compiles
into your target — reference it exactly like any other registered asset
(`Sources/WebUIServer/WebUIServer.swift:180–186`):

```swift
WebUIAsset(ProbeCatalogSheet.self, path: "/ui/theme.css")
```

**the biting semantics, consumer-stated.**

- **tokens and typed rules in, shadowing out.** chrome may ride `@Theme(rules:)` as `[CSSRule]`
  (string-typed, vetted); a consumer sheet must not restyle the design system by shadowing its
  class vocabulary — the `WebUIContinuumTool shadow` verb names any collision with its owning
  component (`Sources/WebUIContinuumTool/ShadowCheck.swift:36–38`; the demo target is zero).
- **build-time and content-addressed.** emission happens at build; the asset carries a
  `stamp` = first 12 hex of the sha256 of its bytes, and is **stamp-stable across rebuilds**
  (`WebUIThemeBuild.swift:33–35` — the receipt; `WebUIShippedAsset.stamp`, `Sources/WebUICore/Assets.swift:20`, `:26`; `dx2-notes/t-theme-spike-verdict.md` — byte-identical second run).
- **the twin emits through the same path.** a hand-written `WebUIThemeProvider` (no `@Theme`) +
  `overlaying` composition is the fixture's `ProbeTwin` — same pipeline, same gate.

---

## axis — components

**protocol.** `View` (`Sources/WebUICore/View.swift:2`, `func render() -> String` — a pure function)
and `ViewModifier` (`:36`), plus the 133 design-system component types.

**framework default.** the design system itself: compose an existing component before reaching for
markup (`skills/webui-design-system/SKILL.md` — "Prefer an existing component over any markup").

**injection position.** **composition.** a customization is a new type built out of the existing
ones — `ModifiedView<Content>` wrapping (`ViewModifier.apply(to:)`), the view-builder DSL, and, when
nothing fits, a new `struct …: View` in your app. styling substitution is not a component-layer
concern: it rides the theme surface (tokens + typed `rules`), per the axis above.

**a minimal conforming example — lifted from the demo** (`Sources/WebUIExample/main.swift:139–159`)
— the demo wires two standard components' events with the standard modifier surface, and composes its
page from `WebUICard`/`Heading`/`Div` (`main.swift:135–172`):

```swift
// main.swift:143–146 — the counter's increment button
WebUIButton("+", variant: .primary, size: .md, id: "btn-inc", onTap: { _ in
	state.count += 1
	return [FragmentUpdate(id: "counter-value", html: counterValueHTML(state.count))]
})

// main.swift:155–159 — the echo input
WebUIInput(placeholder: "Type something…", id: "echo-input", label: "Input")
	.onInput { event in
		state.echo = event.string("value") ?? ""
		return [FragmentUpdate(id: "echo-out", html: echoOutHTML(state.echo))]
	}
```

the demo's own control helper shows the other direction — a consumer composing the framework's
generic seam into a reusable control (`main.swift:48–56`):

```swift
func demoControl<O: EventOutcome>(
	_ label: String,
	id: String,
	variant: String = "button--secondary",
	handler: @escaping @Sendable (EventData) async -> O
) -> String {
	let attributes = control(id, event: .click, handler: handler)
	return "<button type=\"button\" class=\"button \(variant) button--md\"\(attributes)>\(label)</button>"
}
```

**the biting semantics, consumer-stated.**

- **`.class("x")` replaces a component's own classes** (the attribute merge keeps the later value) —
  wrap in `Div(class:)` instead of replacing (`SKILL.md` gotcha).
- **container interiors pad via `*__body`** — wrap children, don't pad the container
  (`SKILL.md` — "The `*__body` padding convention").
- **token-only values** — `SpaceToken`/`ColorToken`/`var(--…)`, never raw px/hex.

---

## the law, enforced

| seam | twin (a conformance the framework has never seen) | where it is gated |
|---|---|---|
| events | custom `EventOutcome` struct | `Tests/WebUITests/SubstitutionTests.swift:31–36`, `:187–202` |
| events | `ViewOutcome` through the erased adapter | `SubstitutionTests.swift:204–215` |
| live data | custom `LiveRegion` struct + custom `LiveState` actor | `Tests/WebUITests/LiveRegionsTests.swift:38–49`, `:79–95`, `:406–429` |
| themes | hand-written `WebUIThemeProvider` + `overlaying` (`ProbeTwin`) | `designer/probes/fixtures/t-theme-catalog/Catalog.swift:19–23`; the t-emission probe |
| components | the demo's conform-only surface (no-layer audit) | `designer/gates/dx12-16-acceptance.mjs` step 9 |

the acceptance's **no-layer audit** is the consumer-side proof: the demo enumerates its required
conformances (the `ViewOutcome` control · the `RegionInvalidations` control · the region drivers ·
the catalog + hand-written provider) and asserts the banned-construct set is empty by exact token —
no `Timer.publish`, no `Task.sleep` polling loops, no hand-registration before serve. if you find
yourself writing one of those, re-read the top of this document: the seam is missing.

## where to read next

- `Documentation/API.md` — the complete symbol reference (Event Handling, WebUIServer, Theme, WebUIBuild sections).
- `Documentation/DESIGN_SYSTEM.md` — the cascade, tokens, and the component catalog.
- `Documentation/JS_RUNTIME.md` — the browser side (unchanged by this arc: region pushes ride the
  existing `update` frame + `replace` op).
- `skills/webui-design-system/` — the consumer skill: `references/substitution.md` (this document,
  packaged), `references/live-regions.md` (the live-data recipe), and the new
  `references/live-data-declarations.md` (the macro spellings, consumer-stated).
- the macro layer's own words: `Sources/WebUIServer/LiveMacroDeclarations.swift` (the shipped doc
  comments) · the twinning proof `Tests/WebUITests/MacroParityTests.swift` · the measured finding
  `dx2-notes/s-sugar-verdict.md` · the ladder re-measure `dx2-notes/m-consumer-deletion-ladder.md`.
- `dx2-notes/r-to-d.md` · `dx2-notes/r-to-g.md` · `dx2-notes/t-to-g.md` — the lane handoffs this
  guide is built from.