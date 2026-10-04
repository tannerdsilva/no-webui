# lane E → lane C handoff (wave 2) — the engine half of the island seam

everything below is implemented in `designer/assets/webui-engine.js` and proven by
`designer/probes/e-island-decoder.mjs` (19/19) + `designer/probes/e-island-e2e.mjs`
(17/17) against a synthetic wasm island that declares the full host import set. your
wave-2 island can implement against these contracts; the i2 reconciler resolves any
drift.

## 1. host import namespace is `continuum`, keyed by function NAME

`buildImports` accepts ANY import module namespace; capability imports are keyed by
the import function name. a `webui_*` name that is not in the engine's known set
THROWS (t2.6 defense in depth → island unmapped, page stays server-rendered). wasi/
other-namespace imports keep the wave-1 stub (`() -> 0`).

known host functions (JS signatures, name → behavior):

| import | JS | notes |
|---|---|---|
| `webui_log(ptr, len)` | `console.log('[island:<name>] ' + utf8(ptr,len))` | reads island memory |
| `webui_now_ms() -> f64` | `performance.now()` | fallback `Date.now()` |
| `webui_raf(callback_index) -> u32` | engine-owned rAF registry; on each frame calls **`webui_frame_tick(idx)`** (an island EXPORT, name negotiable) then drains ops | the call-back entry point is the one open name — see §3 |
| `webui_store_get(ptr, len) -> i32` | read key bytes → `localStorage.getItem` → **writes `[u32le len][value]` at the island's `webui_frame_ptr()` and returns that pointer**; 0 when missing | self-describing frame convention |
| `webui_store_set(kp, kl, vp, vl)` | key + value, typed per the two (ptr,len) pairs | JS is arity-tolerant |
| `webui_surface() -> u32` | `0` (declared, unimplemented — island degrades to region output) | |

`store_get`/`store_set` are the two signatures the wire table left open; these are my
conservative picks and the ONLY call sites likely to need reconciling at i2.

## 2. events in — the descriptor is a region attribute

additive contract: the region element carries
`data-webui-island-events='["keydown","click"]'` (JSON array of event kinds). the
engine delivers any delegated event that (a) bubbles from inside the region and
(b) is in that list to `webui_on_event(ptr, len)` with payload
`{"type": <normalized kind>, "key": <event.key>, "data": <the server's extractEventData shape>}`.
`focusin`/`focusout` normalize to `focus`/`blur`. unsubscribed kinds fall through to
the normal server-component path; the legacy `data-island-input` full-region re-render
is skipped for subscribed regions.

## 3. the rAF call-back export name (open, conservative pick)

the wire table says "engine-owned rAF registry calling back into the island" without
naming the entry. the engine calls **`webui_frame_tick(index) -> i32`** (exported by
the island) on each rAF frame for each registered index, then drains ops. if you chose
a different name, one call site in `islandRafTick` changes at i2.

## 4. op-stream drain — per the i1 freeze, no new call shape needed

`webui_take_ops() -> u32` = the next batch's byte length in the frame buffer (0 =
empty); records are back-to-back record-v1; the engine drains until 0, copying each
batch out of wasm memory before the next call (never holds a reference across calls).
a batch length over 262144 or a malformed record stops the drain with one warning.
your wave-2 island can emit MULTI-record batches in one call (my synthetic island
emits a text+attr pair in one 34-byte batch).

## 5. state channel — the engine uses the wave-1 signatures as-shipped

`webui_state_save() -> ptr` (value at ptr, length via `webui_frame_len()`),
`webui_state_restore(ptr, len)` (bytes engine-writes into the **input** buffer). the
engine keys a save map by island name + region element id; saves fire before a
fragment `replace` of a region root and on `webui:connected` (ws reconnect); restore
fires on every remount (initial mount and post-replace reconcile). no signature
tightening needed from C — the shipped probe island surface is exactly what the
engine calls.

## 6. what i could not test end-to-end (gets real at i2)

your wave-2 island compiled from Swift. the synthetic island covers the ABI surface;
the wasm-build + typed-`State` parity is your side. crate-check the localStorage
`store_get` length-prefix convention (the synthetic island reads len==10 then copies)
before C's encoder emits a differing read.
