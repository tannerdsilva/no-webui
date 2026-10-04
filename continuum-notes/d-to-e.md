# lane D → lane E: `.lease` placement hints (wave 2 landed; the behaviors are yours)

## what landed (lane D owns the file)

`Sources/WebUI/ContinuumLease.swift`:

- `public enum LeaseHint: Sendable, Hashable, CaseIterable { case viewport, echo }`
- `LeaseModifier: ViewModifier` + `View.lease(_:) -> ModifiedView<Self, LeaseModifier>`
- semantics NOW: inert. `apply(to:)` returns the html untouched; `decorate` is a
  buffer pass-through. pinned byte-identical in `Tests/WebUITests/APISurfaceTests.swift`
  ("placement hints are additive and byte-identical"): no markup, no attribute,
  no ws bytes — by design; placement is a precompile decision (§1.1), and the
  wave-2 contract is "no hints = today's behavior".
- the hint survives in the TYPE (`ModifiedView.modifier.hint`), which is the
  handle a build scan or a runtime bootstrap can read.

## what's yours (engine behaviors, wave 3 / t3.3+)

- `.viewport` → windowing support (t3.3): window size from the viewport rect +
  overscan, keyed identity, scroll anchoring. the hint is currently NOT
  serialized into the page — decide with B whether the continuum scan emits it
  into the served manifest (recommended; zero byte change) or the server adapter
  emits a `data-webui-lease` attribute (byte change → needs its own pin + it is
  inside the wave-1 attr seed's `data-*` allowlist, so the engine can read it).
- `.echo` → the t1.4 echo contract (`data-webui-echo="<id>"`) is yours already.
  `.lease(.echo)` is the *declaration* side; the delivery wiring (who emits the
  attribute) is t3.4/input-parity (D+C) — do NOT read `.lease(.echo)` as
  "attribute present" today.
- neither behavior may change today's bytes until the consuming slice lands and
  the pins move deliberately.

## contact surface

- file: `Sources/WebUI/ContinuumLease.swift` — lane D owns; coordinate before editing.
- tests: `Tests/WebUITests/APISurfaceTests.swift` — additive pin only, lane D owns edits.
## wave 3 — the t3.3 `Viewport` DOM contract (landed; the engine half is yours)

`Sources/WebUIDesignSystemCore/Viewport.swift` lands the consumer surface —
the component + the pure windowing spec (`ViewportSizing`/`ViewportWindow`/
`ViewportAnchor`, pinned by `ViewportTests`). the engine's JS twin implements
these semantics; D does not wait for it. `designer/probes/d-viewport.mjs`
cross-checks source ⇄ sheet ⇄ this note.

### what the engine must find

- **discovery**: `[data-webui-viewport]` — one `<ul id="<id>" class="list list--virtual">` perimeter per windowed region.
- **the lease (W1, DX-7d)**: the component now ALSO emits the engine's
  windowing lease `data-webui-lease="viewport"` on that same container (right
  after `data-webui-viewport`), so your pooler's
  `LSEL = '[data-webui-lease="viewport"]'` selects D-rendered regions with no
  host bridge. this wave the component emits BOTH name sets — `data-webui-lease`
  (yours) and `data-viewport-*`/`data-webui-viewport` (styling/numeric) — so
  the engine may read either; the bench's string-replace server-adapter lease
  becomes a no-op duplicate and can retire at integration (tell B).
- **numeric inputs** (the engine's window math reads these, not guesses):
  `data-viewport-total="<N>"` · `data-viewport-rowsize="<px>"` (52 default =
  the sheet's `.list--virtual` 3.25rem) · `data-viewport-overscan="2"`.
- **row id scheme**: every row is a direct child `<li id="<id>-r<i>" …
  data-viewport-row data-key="<key>">` — `<i>` is the row's GLOBAL index
  (stable across window shifts), `<key>` is its keyed identity (reconcile by
  key, never by position); keys must be unique within a list.
- **windowed slice** (server renders a window): pads `<li … viewport-pad …>`
  carry the unrendered height + the container adds
  `data-viewport-slice="<first>..<last>"` (inclusive).
- **server degrade**: full list by default; past `data-viewport-safe` (10_000,
  the d0 measured 10k full-render ceiling) the server paginates — `nav`
  `[data-viewport-page][data-viewport-pages]` with `[data-viewport-goto]`
  controls.

### the math the JS twin must match

- window = `visible × overscan`, `visible = ceil(rectHeight / rowHeight)`,
  `overscan = 2` (≈ one band above + one below the anchor), clamped to
  `[0, total)`; lead depth = `(window − visible) / 2` (`ViewportSizing`).
- anchoring on patch: `scrollDelta = (oldFirst − newFirst) × rowHeight`
  (`ViewportAnchor.scrollDelta`) applied to the scroll container after the
  window patch so the anchor row stays visually put — the generalization of
  the engine's landed scroll survival; the anchor is the first survivor at or
  above the previous first row (`ViewportWindow.anchorRow`).

## wave 3 / polish — the t3.4 input-parity contract (for the engine half)

D's delivery surface (now re-pointed onto C's real `KeyEvent`, polish unit
`7d5aa80`) declares input-parity channels via `data-webui-input='["key",…]'`
— the declared SIBLING of your `data-webui-island-events` array spell (one
parser reads both). its five tokens map 1:1 onto `InputParity.wireName`:
`key`/`selection`/`clipboard`/`undo`/`composition`.

- **next-slice (yours):** wire `data-webui-input` into
  `islandRegionSubscribed`/`deliverIslandEvent` alongside
  `data-webui-island-events`. until then the descriptor is declaration-side
  only; regions reachable today still declare via `data-webui-island-events`.
- **key payload, v1** (frozen in c-to-e; proven by your real-island probe):
  `{"type":"key","key":"<Key.identifier>"}` — `data` OMITTED on the key
  channel. the `data` you already forward for keydown (the four modifier
  booleans as strings) stays INFORMATIONAL at v1: D's `KeyEvent.modifiers`/
  `isRepeat` have no v1 wire field; the island reduces on `key` alone. keep
  the booleans — they pre-seed the v2 modifier field. full mapping + the
  space friction (`" "` parses to printable, not `.space`) in
  `continuum-notes/d-docs.md` (polish section) + `designer/probes/d-transport.mjs`.


## W3 — the acceptance template's App target needs consumer-graph exposure (the codec swap-in landed)

D's W3 swap-in (`9d298fa`) makes the generated codec bodies name the runtime
accessor spell — `IslandRuntime<<Type>Island>.encodedState()` /
`.decodePendingOps()` (d-to-c.md W3, c-to-d W3 addendum). **consequence for
your template:** the §0.3 lone-@HotView path (the acceptance harness's step-1
`Sources/App/Feed.swift`, and any `@HotView` consumer) now must be able to
NAME `IslandRuntime` and have its generated adapter satisfy
`IslandRuntimeSurface`. two deltas, both package-level (D/B's owed work, c-to-d
W3 item 2 — D did the macro-test-target half):

1. **the App target gains `WebUIIslandCore`** (plus `WebUISharedCore` if the
   template's surface hooks use `JSONValue`/`ElementID` directly — `WebUI`'s
   re-export chain already surfaces the shared-core vocabulary, so
   `WebUIIslandCore` alone may suffice for `IslandRuntime`). in
   `templates/app/Package.swift` App target dependencies, alongside the
   existing `WebUI`/`WebUIDesignSystem`/`WebUIServer` products.
2. **the lone `@HotView` Feed needs the author-supplied `IslandRuntimeSurface`
   conformance** (the template-feed shape, c-to-d W3 item 3): the four hooks
   (`decodeEvent`/`regionHTML`/`stateToJSON`/`stateFromJSON`) beside the
   generated `Feed.FeedIsland` — mirror `MacroCounter.MacroCounterIsland`'s
   fixture conformance in `Tests/WebUIContinuumMacroTests/
   ContinuumCompiledFixture.swift` for the exact shape.

until the template lands these, a harness `Swift build` of the step-1 Feed will
fail to resolve `IslandRuntime`; the framework-side compiled fixture (which
carries both deltas) is the working proof. the wasm-side `feed` target's
hand-written `FeedIsland` already conforms — only the App-side lone-@HotView
path is affected.
