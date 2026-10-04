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
