# lane E — wave 1 doc fragments (t1.1, t1.2, t1.4)

orchestrator folds these into `Documentation/CONTINUUM.md` + `CHANGELOG.md` at
integration; never edits the shared docs directly (deviation D-1).

## t1.1 — fragment ops complete (remove / attr / move)

the `FragmentOp` vocabulary is now six ops, additive over the landed
append/text/replace (absent `op` stays `replace`, pinned):

| op | wire (json inside `fragments[]`) | meaning | optimistic |
|---|---|---|---|
| `replace` | `{"id":"x","html":"…"}` | swap subtree | allowed (armed) |
| `append` | `{"id":"x","op":"append","html":"…","before":"child"?}` | insert child | allowed |
| `text` | `{"id":"x","op":"text","text":"…"}` | write textContent | forbidden v1 (skip + warn once) |
| `remove` | `{"id":"x","op":"remove"}` | delete `#x` | forbidden v1 |
| `attr` | `{"id":"x","op":"attr","name":"…","value":"…"}` | set ONE attribute | forbidden v1 |
| `move` | `{"id":"x","op":"move","before":"y"?}` | reorder within parent | forbidden v1 |

- swift constructors (beside the append/text precedent in
  `Sources/WebUICore/WebSocketProtocol.swift`): `.remove(id:)`,
  `.attr(id:name:value:)`, `.move(id:before:)`; `name`/`value` ride on the
  `FragmentUpdate` Codable + the data-free `jsonText` wire.
- engine apply lives in `applyFragments` (`webui-engine.js`). `remove` uses a
  real `element.remove()` (the empty-fragment-removes-element branch stays
  replace-only, pinned). `move` uses `parent.insertBefore`/`appendChild` on the
  existing node — a reorder, never a re-insert. `attr` validates the name
  against an allowlist then `setAttribute` (the DOM API handles escaping).
- unknown op / unknown attr name / optimistic + forbidden op: skip + warn once
  (keyed `warnOnce`, the engine's established warn-once pattern).

### attr allowlist — WAVE-1 STATIC SEED (handoff to lane B)

engine constant, clearly marked:

```js
var ATTR_ALLOW_EXACT = { 'class': true };
var ATTR_ALLOW_PREFIX = ['aria-', 'data-'];
```

this is the wave-1 static seed only — lane B's generated allowlist (t1.3,
`Continuum+Generated.swift` class inventory) replaces it at integration. the
allowlist deliberately keeps url-bearing attrs (`href`, `src`, `style`) and
`on*` handlers out of the hot plane (skip + warn once when a name isn't
listed).

## t1.2 — scheduling policy (documented + guaranteed)

the existing policy (landed f794267) is now explicit in the coalescer
(`enqueue` in `webui-engine.js`):

1. queued application: fragments enqueue and flush as one batch.
2. last-write-wins per target: a later non-append, non-remove op for an id
   collapses onto the newest queued entry with that id (scan from the tail,
   never across a queued `remove`).
3. never-animate hot ops: `wantsTransition` returns false for
   append/text/remove/attr/move — view transitions only ever animate plain
   replaces.

extended for the new ops:

- `remove` never coalesces — it always enqueues fresh and no later op for the
  same id may swallow a queued `remove` (a deletion must always execute).
- `attr`/`move` collapse to newest per target, exactly like replace/text.
- array order stays semantic: `append` is never reordered relative to ops on
  other targets.

probe `e-ops.mjs` sends 50 mixed ops and asserts exact applied counts (24 =
4 newest-per-target + 10 removes + 10 appends) plus newest-per-target DOM
wins.

## t1.4 — engine-local echo (the first lease)

contract attribute: `data-webui-echo="<id>"` on an element. on `input`, the
engine writes the element's value into `#<id>`'s text in the same turn —
locally, with zero websocket traffic. the authoritative patch always wins: a
`text` op or a `replace` for the echo target overwrites the local overlay and
clears the `echoOverlay` marker.

implementation:

- fragment patcher exposes `echo(id, value)` + `echoOverlay` (and
  `clearEcho`); a delegated document-level `input` listener (`echoInput` in
  the event delegator) calls `fragmentPatcher.echo` for any element carrying
  the contract attribute — before component lookup, so unwired echo sources
  work too.
- `applyFragments` clears the overlay on authoritative `text` and `replace`.
- the debounced wire path is untouched: a component-wired echo source still
  sends its event at the debounce edge (one frame), never per keystroke.

probe `e-echo.mjs`: types 20 chars and asserts (a) the target updates per
keystroke, (b) 0 ws frames during the typing window — counted from OUTSIDE via
playwright's `page.on('websocket')`, the runtime is never patched under
measurement — and (c) an authoritative text/replace wins and clears the
overlay. a wired variant asserts frames still arrive at the debounce edge.

## conservative choices / notes

- `text` under optimistic patches is now forbidden (skip + warn once),
  matching the §1.3.2 table; no landed behavior depended on optimistic text
  (predictions are html-based replaces).
- engine bytes stay comment-free (ProseGuard scans them); the policy tables
  above are the documentation home.

---

## wave 2 — the island seam, engine half (t2.1, t2.2, t2.3, t2.4, t2.6)

### the open wire contracts

- `webui_store_get` / `webui_store_set` / the `webui_frame_tick` call-back entry are
  the wire-table gaps lane E resolved conservatively; the full contract is in
  `continuum-notes/e-to-c.md` (wave 2).
- region descriptor for event routing: `data-webui-island-events='["keydown","click"]'`.

### engine behavior (webui-engine.js)

- **typed host imports (t2.1).** `buildImports` keys on the import name; known set is
  `webui_log/now_ms/raf/store_get/store_set/surface`. unknown `webui_*` → throw
  (t2.6); other namespaces keep the `() => 0` stub.
- **events in (t2.2).** delegated events bubbling inside a region whose descriptor
  lists the kind are delivered to `webui_on_event(ptr, len)` as
  `{type, key, data}` (the server's extract shape); the island owns those events
  (no server round-trip, no legacy region re-render for subscribed regions).
- **op stream (t2.3).** `webui_take_ops() -> u32` per the i1 freeze: next batch byte
  length in the frame buffer, 0 = empty, records back-to-back record-v1
  (c-to-e.md), drain until 0, batch copied out before the next call, length cap
  262144, malformed record stops the drain with one warning. ops apply through the
  fragment patcher's `applyHotOp` (attr allowlist enforced; insert sanitized once).
- **state channel (t2.4).** save map keyed `name|regionId`; saves on `replace` of a
  region root (pre-replace hook) and on ws reconnect (`webui:connected`); restores
  on every remount via `webui_state_restore` (engine writes into the input buffer).
- **defense in depth (t2.6).** unknown host import throws; every island export call
  is try/catch'd; `_start` failures degrade; missing artifact (404) → unmapped;
  page stays server-rendered and the engine instance stays alive in every failure
  path (probe-verified).

### probes

- `designer/probes/e-island-decoder.mjs` — decoder + drain as pure functions;
  crafted byte sequences incl. invalid utf-8 → U+FFFD, reserved version/opcode,
  truncation (19/19).
- `designer/probes/e-island-wasm.mjs` — a loop-free synthetic wasm island
  (hand-assembled; bulk memory.copy) declaring the full host import set and the
  merged probe surface + `webui_take_ops` + `webui_frame_tick`; `buildBogusWasm`
  for the unknown-import module.
- `designer/probes/e-island-e2e.mjs` — the engine's real loader/instantiate path
  against the synthetic island in a real browser (ports 9262): mount, unknown
  import + 404 degrade, keydown/click events → `{type,key,data}`, op drain applied,
  clock + rAF + store_set/get, resource replace → save → restore → count continues,
  ws reconnect keeps regions mounted (17/17).

### budget

the engine grew to **68,188 raw / 16,185 gz** (measured on this branch head) from
56,818 / 13,602 at i1. this is the expected wave-2 second trip of the shipped-surface
gate — the mechanism working as designed. the i1 pin (60,000 / 14,500) needs a
deliberate re-pin at i2 (orchestrator/B decision, ~5-6% headroom over these numbers).

---

## wave 3 — the live handshake, t3.3 windowing, the served allowlist slice

### the real-island handshake (i2 gate completion; reconcile-what-differs)

`designer/probes/e-island-e2e-real.mjs` drives C's actual
`WebUIProbeIsland.wasm` (173,846 B) through the engine's real loader on :9263.
the live vocabulary works end-to-end (21/21): mount html, ArrowUp/Down keydowns,
clicks on probe-inc/dec/clear, input on probe-field → insert, take_ops drain,
state channel across a region replace (counter + keyed list survive).

two engine reconciliations surfaced by the real artifact (both are the c-to-e.md
frozen vocabulary — the synthetic wave-2 island had simply not exercised them):

1. **event type normalization.** the island decodes keyboard events as
   `type: "key"` (c-to-e.md table), the engine was sending `keydown/keyup/
   keypress`. `deliverIslandEvent` now normalizes keyboard kinds to `key`
   (island-delivery path only — the shared `effectiveTypes` used by component
   routing is untouched).
2. **click key = element id.** clicks carry `key: <nearest id within the region>`
   (probe-inc/dec/clear), matching the frozen table; previously `key` was absent
   for clicks (event.key is undefined), which real-island clicks reduced to
   `.noop`.

verified-moot (not assumed): the artifact imports NO `webui_*` host fns and
exports NO `webui_frame_tick` — so `webui_frame_tick` (rAF call-back) and
`webui_store_get|set` remain unused conventions; the state channel is
`webui_state_save/restore` only. the synthetic e-island-e2e (17/17) assertion
was updated to the normalized `key` type.

### t3.3 engine-local windowing (the d3 gate's load-bearing piece)

engine support: `createWindowManager` in webui-engine.js. a container carrying
`data-webui-lease="viewport"` is windowed at boot (and re-windowed after every
whole-container replace): pool = direct children (detached), attached = the
viewport ± overscan rows positioned absolutely at `i × rowHeight`, total height
held by an engine-injected `<data-webui-window-spacer>`. scroll re-windowing is
engine-local (the d0 page-side observer is replaced); only entering/leaving
window rows are inserted/removed per scroll. two scroll models (document-flow,
and self-scrolling container) are auto-detected. the full DOM contract and
D-side `Viewport` requirements are in `continuum-notes/e-to-d.md` (wave 3).

**bench (e-windowed, 22/22 on :9266; recipe math mirrors continuum-bench):**
10k-row feed, 30 Hz host display (CoreGraphics `refreshRate == 30` — the rAF
metric's floor is one refresh, ~33 ms, for ANY page on this host):

| metric | loopback | throttled (80 ms rtt) |
|---|---|---|
| rAF p95 (10k full-render control, d0) | 62.4 ms | 61.5 ms |
| rAF p95 (engine-windowed) | **35.8 ms** (= floor, no jank) | **35.8 ms** |
| engine scroll-work p95 (scroll→rewind→mutations) | **2.30 ms** | **2.20 ms** |
| mutation census (windowed) | childList only (1.1k), 0 char/attr | same |
| attached rows (windowed, 10k pool) | 45–71 (≤ 90) | 45–70 |

the t3.3 "≤ 20 ms" claim is carried by the display-independent **engine
scroll-work p95 (2.2–2.3 ms)**; the rAF metric sits at the 30 Hz host floor and
2× below the d0 full-render wall. memory flat over 60 s (heap delta 0%, attached
bounded). scroll anchoring: a whole-region replace of the windowed container
keeps scroll position and reforms the same visible row.

### served allowlist slice (consuming B's `/ui/continuum-manifest.json`)

the engine fetches `/ui/continuum-manifest.json` at boot; when the response
carries `attributeAllowlist`, it **replaces** `ATTR_ALLOW_EXACT` /
`ATTR_ALLOW_PREFIX` (entries ending `*` or `-` become prefixes, others exact);
a missing/malformed manifest falls back to the seed silently (no warning).
probe `e-manifest.mjs` (10/10 on :9267, mocked route): manifest exact + prefix
entries apply, a seed-only name drops out (replace, not union), and the 404 page
keeps the seed with zero manifest warnings.

### budget — the fourth trip (flagged, deliberate re-pin at/after i3)

the engine measured **73,094 raw / 17,595 gz** on this branch head (t3.3
windowing + manifest slice + handshake reconciliations), against the i2 pin
**72,000 / 17,000** — +1.5% raw / +3.5% gz. the additions are the mandated
wave-3 scope; the mechanism is the designed trip-and-rein. recommend the i3/i4
re-pin at ~**74,500 raw / 18,000 gz** (~2-3% headroom) — orchestrator/B decision,
recorded here. `swift package plugin budget` will report this breach until then.

---

## CONTINUUM_DX wave 1 (lane E, DX-7e + DX-8e) — the junction reconciliations

commits `fa9cce0` (DX-7e) + `3f27072` (DX-8e) on `task/e-engine`, base `ec1bcbc`.
net engine growth within the I3 arc budget: **+1,601 raw / +368 gz** (ceiling
+2,048 / +512). measured 74,735 raw / 17,924 gz.

### DX-7e — discovery + windowing-parameter reconciliation (engine side)

`createWindowManager` now accepts **both** discovery spellings:
`[data-webui-lease="viewport"]` (today) and `[data-webui-viewport]` (D's
component marker) — `LSEL` carries both, and `init` gates on either. the
junction is robust whichever side lands first at i1.

windowing parameters read from **both name sets**, declared-value-first:

| parameter | E spelling | D spelling |
|---|---|---|
| row height | `data-webui-row-height` | `data-viewport-rowsize` |
| overscan | `data-webui-overscan` | `data-viewport-overscan` |

precedence now: declared (E name, then D name) → first-row `offsetHeight` →
24 px. the **offsetHeight fallback runs only when NEITHER name set is present**
(the red-team finding: the engine silently ran on fallbacks — 24 px rows and the
default overscan band — because it read only `data-webui-*`).

`e-windowed.mjs` grew the DX-7e section (30/30 on :9266 + a :9270 reconciliation
page, self-scrolling containers): declared `data-viewport-rowsize="37"` is
honored over the rendered 40 px measurement (spacer = 2000×37); declared
`data-viewport-overscan="2"` holds the window to visible+2+2 ≈ 11 rows (vs the
undeclared fallback band ≈ 19); lease discovery + `data-webui-row-height` +
the neither-present offsetHeight fallback are all pinned.

**recorded divergence for i1 (lane D / reconciler):** the D spelling's unit is
a *factor* (`ViewportSizing`: window = visible × overscan, `overscan=2` ⇒
window ≈ 2× visible) while the engine's `w.ov` is an absolute *row count*
pasted above/below (default = one visible band each side, ≈ 3× visible). W1
aliases the D attr to the engine's unit (declared 2 ⇒ 2 rows each side) — the
declared value is consumed, which is the red-team's requirement — but a
factor-vs-count semantic match is NOT reproduced. if D's factor reading must
survive, the reconciler should convert (`w.ov = visible × (N−1)/2`) or empty
out the D attr from the component (the lease emission makes the params
redundant). recorded, not silently claimed.

### DX-8e — `data-webui-input` delivery wiring (red-team gap closed)

`islandRegionSubscribed`/`deliverIslandEvent` accept the descriptor as a
**sibling** of `data-webui-island-events` (same JSON-array parser; union of
both). tokens are InputParity channel names mapped from DOM event types by the
new `INPUT_CHAN` table:

| channel | DOM events | delegated at W1 |
|---|---|---|
| `key` | `keydown` **only** | yes (already) |
| `composition` | `compositionstart/update/end` | yes (added to `EVENT_TYPES`) |
| `selection` / `clipboard` / `undo` | `select·selectionchange` / `copy·cut·paste` / `undo·redo` | subscribed only — DOM events NOT delegated at W1 |

**key = keydown only** — `keypress` (legacy) and `keyup` (double-counts releases)
would triple every `KeyEvent`; `KeyEvent`/`isRepeat` is a press channel. the
keydown/keyup/keypress→`key` normalization inside `deliverIslandEvent` is
unchanged for legacy `data-webui-island-events` spellings.

**modifier booleans ride `data`** — the key payload already carries
`ctrlKey/shiftKey/altKey/metaKey` (booleans-as-strings) from `extractEventData`;
that is the **v2 modifier pre-seed** (no v1 wire field; the island keys on
`key` alone). pinned by `e-input-desc.mjs`.

**I4 guard (per-page cost):** composition events must reach islands ONLY —
`handleEvent` short-circuits any `composition*` event to the island-region path
and returns, so a non-opted page (or a component without `data-event`) cannot
start emitting `{type:'event', event:'compositionupdate'}` ws round-trips. zero
new per-page network on non-opted pages; +3 document listeners (the delegator
already had 15) with no observable behavior change.

**space normalization (the recorded choice):** the DOM spacebar's
`event.key === " "` is kept as the single space scalar `" "` — the wire form of
`Key.printable(" ")` per d-to-e's transport table — and `"Spacebar"` (legacy)
is normalized to it. the engine deliberately does **not** rewrite `" "` →
`"Space"`: `.space`/`"Space"` will not fire from a real browser (d-docs
boundary #3). probe pins `{type:"key", key:" "}`.

`e-input-desc.mjs` (new, 7/7 on :9271): descriptor-only region receives
`{type:"key", key:"a", data:{...modifiers}}`; space arrives as `key:" "`;
`["key","composition"]` receives `{type:"composition", key:"composition",
data:{data,isComposing}}`; a click in a key-only region is NOT delivered
(descriptor-gated). regressions: `e-island-e2e` 17/17, `e-island-e2e-real`
21/21, `e-windowed` 30/30.

### handoffs

- **to lane D / reconciler:** (1) the overscan unit divergence (above) — decide
  factor-vs-count before W2 or accept the W1 alias; (2) Viewport emits BOTH
  `data-webui-viewport` (styling marker) and `data-webui-lease="viewport"`
  (discovery) after this wave — the engine accepts either; (3) composition is
  island-only at W1 (guard is deliberate, not a bug).
- **to lane B:** `plugin budget` will flag the engine at 74,735/17,924 vs the
  i2 pin 72,000/17,000 — the arc budget authorizes it; the i3 re-pin
  (~74,500/18,000 advice above) absorbs both.

---

## CONTINUUM_DX wave 2 (lane E) — the A1 overscan ruling, DX-6e, the template + acceptance, DX-4e wiring

commits `7d3d4e8` (A1 overscan), `d517cc7` (DX-6e), `b308484` (templates/app +
designer/dx-acceptance.mjs) on `task/e-engine`, base `95ba7b7`.

### A1 — the overscan-unit adjudication (binding ruling, applied engine-side)

i1 recorded: `data-viewport-overscan` reads as a **FACTOR** (window = visible ×
factor, `ViewportSizing` in `Viewport.swift:29,46-48`), `data-webui-overscan`
stays **ABSOLUTE rows**. the engine now tracks the two spellings separately
(`w.ovA`/`w.ovF` in `createWindowManager`) and `wnd()` converts per-side:

```
vis = max(1, ceil(v / w.h))
per-side = ovA>0 ? ovA : (ovF>0 ? ceil(vis*(ovF-1)/2) : vis)   // factor 1 -> 0
```

`e-windowed.mjs` now DISCRIMINATES at mid-scroll (row ~1000 of 2000):
`data-viewport-overscan=2` windows to **12-13** (vis=6 at 200px/37px, per-side
ceil(6×1/2)=3; the window band's ceil((t+v)/h) makes it 13 on this fixture),
`data-webui-overscan=2` (new `dx-a` container) windows to **10-11**, and the
undeclared default band stays **16-20** (one visible band per side ≈ 18). the
ranges were tightened to reject unit conflation in both directions (an engine
that lumped the spellings fails one of `dx-c`/`dx-a`). the stale `[8,13] ~=
visible+2+2` assertion and comment are gone. 31/31.

### DX-6e — the engine consumes islands[] (content-addressed URLs)

`loadIsland` chains on the shared manifest promise (`manifestReady`) and
resolves the URL from `islandUrlMap[name]` (populated from `/ui/
continuum-manifest.json`'s `islands[]` `{name,url}` entries) with the
name-convention `/__assets/webui-<name>.wasm` fallback (v1 payload / 404).
`e-manifest.mjs` extended to v1+v2+404: the allowlist replace semantics per
version are unchanged, and the feed region now mounts through the
content-addressed URL in v2 (the convention URL is NOT hit) vs the convention
fallback in v1/404. **20/20** (was 10/10). regressions green: e-island-e2e
17/17, e-island-e2e-real 21/21, e-input-desc 7/7.

### DX-4e wiring — folded into the acceptance path

the registry → routes → view primitive chain is now closed end-to-end by the
template: the app serves a **v2 manifest with `islands[]`** (content-addressed
URL) + the artifact at both URLs, and the acceptance asserts the region loaded
_via the content-addressed URL_ — proving DX-6e + both-discovery-spellings
(DX-7e, W1) on a real consumer page. the server-side built-in route stays B's
DX-6b (WebUIServer is B-owned); the bench string-replace lease adapter is B's
to retire.

### templates/app/ + designer/dx-acceptance.mjs (appendix A; landed at W2 start — the "committed by i1" slip is the orchestrator's §7 record)

template = minimal consumer: the once-per-app inert block (framework dep +
`WebUIAutobuildPlugin` on the page target + one island executable target
`feed`, mirroring the demo app's shape), one page target (`App`, `swift run`
first product), one PRE-EMITTED `WebUIIsland("feed")` region, **no capability
allowlist**. the island (`Sources/feed/main.swift`) is a self-contained
`IslandRuntimeSurface` (counter + pick ops + state channel).

harness `designer/dx-acceptance.mjs` runs in a **home-directory project**
(`~/dx-accept`, never /tmp) with the appendix-A preflight/prep/step1-4/
asserts/teardown, plus the DX-11 dogfood assertion.

### assumptions / conservative choices (report)

1. **the Package.swift framework path is materialized at PREP** — the template
   ships `__FRAMEWORK_PATH__`; the harness substitutes the checkout path into
   the copied manifest once, before step 1. assert (b) then proves the manifest
   is byte-stable from prep through teardown (zero edits during the test).
2. **the pre-emitted region rides the click subscription** — a bare
   `WebUIIsland("feed")` mounts but receives NO delegated events (the frozen
   t2.2 contract: delivery is descriptor-gated). the template splices
   `data-webui-island-events='["click"]'` beside the D-owned view's markup.
3. **the DOGFOOD table handler emits ops app-side** — DX-11b (op-emitting
   built-in handlers) is W3 lane-D; the acceptance asserts the same contract
   with the app's typed handler returning `FragmentUpdate.attr/.text` (the
   FragmentOp plane, engine-applied). green today, stays green when DX-11b
   lands.
4. **the step-1 @HotView struct compiles but is not yet the island's source**
   at this base (codec stubs + the autobuild plugin identifies islands by
   `Sources/<name>/main.swift importing WebUIIslandCore`). the feed island is
   self-contained until B's DX-5-real + D's codec-bodies close the gap.

### budget

engine measured on this branch head: **75,438 raw / 18,195 gz** (base
95ba7b7 measured identically: 74,735 / 18,014) → **cumulative E2 deltas +703
raw / +181 gz** (gzipSync, method-consistent; vs the W1-recorded 17,924 gz
baseline the gz delta reads +271 — both within the +512 gz arc ceiling).
`plugin budget` (served measure) reports engine 75,438 / 18,087 ok/ok under
the 77,000 / 18,500 pin. **do NOT re-pin** — the orchestrator re-pins at i3.

### handoffs

- **to lane D:** (1) DX-11b (W3) — pull op emission INTO the built-in table/
  chart/pagination handlers; the acceptance's dogfood assert already passes via
  app-side emission, unblocked either way; (2) consider an `events:` parameter
  on `WebUIIsland` so the region view can emit the click/keydown descriptor
  itself (the template currently splices it); (3) the A1 ruling now pins
  `data-viewport-overscan`'s factor semantics engine-side — the Viewport
  emission is correct as-is, keep it.
- **to lane B:** (1) the acceptance's `assert (c)`: a consumer package CANNOT
  invoke a dependency's command plugin — `swift package plugin budget` from
  ~/dx-accept fails with "Unknown subcommand or plugin name 'budget'"
  (measured). the harness proves the island-budget ROW machinery from the
  framework checkout and flags the feed row's dependency on DX-3's merged
  manifest emission (consumer-side budget invocation needs B's DX-8 `verify`
  consolidation); (2) retire the bench string-replace lease adapter; (3) DX-6b's
  WebUIServer built-in routes will cover the template's hand-served routes —
  at i2 the template should be able to drop its own (framework-route-win +
  registry); (4) the `islands[]` merge into the served manifest (DX-3/DX-6b)
  is what removes the template's own manifest construction.
- **to orchestrator:** appendix A promised the template + harness "committed by
  i1" — they land at W2 start (this branch); record the slip in §7. the
  reference-surface pin re-check (assert d) is yours at i2/i3, not the
  template's (the template server cannot see the reference hosts).

### next-slice

- canonical bench re-run + final reconciliations (W3).



