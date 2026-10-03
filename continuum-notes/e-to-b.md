# lane E → lane B handoff (wave 1)

## 1. attr allowlist — your generated allowlist replaces the wave-1 seed

the engine ships a WAVE-1 STATIC SEED attr allowlist for the new `attr`
fragment op, in `designer/assets/webui-engine.js` inside `createFragmentPatcher`:

```js
var ATTR_ALLOW_EXACT = { 'class': true };
var ATTR_ALLOW_PREFIX = ['aria-', 'data-'];
function attrNameAllowed(name) { ... }
```

your t1.3 `WebUIContinuumTool` inventory/allowlist (`Continuum+Generated.swift`)
should supersede `ATTR_ALLOW_EXACT`/`ATTR_ALLOW_PREFIX` at integration: per-component
declared attribute names join `class`/`aria-*`/`data-*`. unknown names are
already handled engine-side (skip + warn once keyed `attr-name:<name>`), so the
engine won't crash if the generated set ships later — it just stays conservative
until then. do not edit the seed in this branch; report the generated surface in
your handoff so the reconciler wires it.

## 2. no Package.swift change needed from lane E (wave 1)

- new test file `Tests/WebUITests/WebSocketProtocolTests.swift` — auto-globbed
  by the existing `WebUITests` testTarget (no manifest edit).
- probes live under `designer/probes/` (outside every target dir) — no resources
  declaration needed.
- no new products/targets were required: protocol + engine + probes only.

## 3. engine behavior your benches must not assume (yet)

- `applyFragments` now applies `remove`/`attr`/`move` (see `continuum-notes/e-docs.md`
  tables); `attr` values are set via `setAttribute` (escaped by the DOM API).
- coalescer: `remove` never coalesces; `attr`/`move` collapse to newest per
  target; `wantsTransition` returns false for append/text/remove/attr/move
  (hot ops never animate).
- if a bench drives optimistic patches: `text` is now forbidden optimistically
  (skip + warn once, per the parent §1.3.2 table).

## 4. lane ports used (do not collide)

e-ops on :9260, e-echo on :9261 (within the 9260-9279 lane block).
