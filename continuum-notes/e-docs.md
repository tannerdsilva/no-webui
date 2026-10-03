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

