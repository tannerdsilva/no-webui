# lane-c → lane-e: the op-stream record contract (decoder side)

lane C owns the swift encoder; lane E owns the `webui-engine.js` decoder
(t2.3 engine half). this is the exact record layout C implemented and unit-
tested (`HotOpCodec`, `Sources/WebUISharedCore/Continuum.swift`). implement
the js decoder against THIS table so engine and island agree.

## record format v1 (frame buffer)

| field | bytes | endian | notes |
|---|---|---|---|
| version | u8 | — | always `1` |
| opcode | u8 | — | 1 text · 2 attr · 3 insert · 4 remove · 5 move |
| id len | u16 | little | utf-8 byte count of the id |
| id | n | — | the element the op targets |
| payload | opcode-specific | — | see below |

## payloads

- **text**: `u32 valueLen` + `valueLen` utf-8 bytes (the textContent value).
- **attr**: `u16 nameLen` + name bytes + `u32 valueLen` + value bytes.
- **insert**: `u16 beforeField` — `0xffff` = append at end (no anchor), else a
  `u16` length + that many anchor-id bytes — then `u32 htmlLen` + html bytes.
  **the record's `id` slot carries the parent** (the element the op operates
  on); the new element's id is not part of the v1 record — the engine
  allocates it on apply.
- **remove**: no payload.
- **move**: `u16 beforeField` — `0xffff` = move to end, else `u16` length +
  anchor-id bytes.

## rules the decoder must honor

1. **all multi-byte integers little-endian** (wasm32 + host assumption).
2. `before` sentinel is `0xffff` only in the *optional* `before` position; an
   `id`/`name` length field of `0xffff` (65,535 bytes) is a legal length.
3. invalid utf-8 in any string decodes to U+FFFD (never a trap).
4. C's `HotOpCodec.decode` consumes exactly **one** record and rejects
   trailing bytes (`trailingBytes`). if the engine wants multi-record frames
   with a single `webui_take_ops()` call, that needs a new call shape +
   codec API (wave-2 decision, open).
5. reserved opcodes/versions: reject, do not guess.

## trust table reminder (from §t2.3)

`text`/`attr`/`remove`/`move` carry no markup; `insert` carries html and is
sanitized once at the boundary.

## sizes to expect

| op | minimum record | typical |
|---|---|---|
| remove | 5 B | 5 + id |
| text | 9 B | + id + value |
| move | 5 B | + id (+ anchor) |
| attr | 9 B | + id + name + value |
| insert | 10 B | + parent (+ anchor) + html |

## wave-2 open items (C's side)

- multi-record op-stream call shape (`webui_take_ops`) — open.
- `webui_on_event` currently acks with json + a counter; wave 2 routes typed
  actions through `ContinuumIsland.reduce` → `HotEffect.ops` → this codec.

## WAVE 2 — the take_ops drain (RESOLVED) + event vocabulary (frozen)

### `webui_take_ops() -> u32` — the drain contract (the i1 freeze, implemented)

the call shape wave 1 flagged as open is now resolved and shipped in the probe
island (`Sources/WebUIProbeIsland/main.swift`, `WebUIIslandCore.ProbeIsland`):

- **each call returns the byte length of the next batch** sitting in the frame
  buffer (`webui_frame_ptr` / `webui_frame_len` agree with the return value);
  `0` = nothing pending. **the engine must drain until it sees 0** and never
  hold a reference across calls (copy out, don't alias).
- a batch is **whole records back-to-back** — zero padding, zero framing, each
  record exactly record-v1 above. multi-record batches are the norm when more
  than one event queued before the drain (one event → one record).
- records are served whole: a batch never splits a record across calls. the
  island serves as many records as fit the frame buffer (1<<18); a single
  record is input-bounded at 1<<16, so it always fits.
- `webui_on_event` **queues**, it does not serve: after delivering an event,
  the engine runs the drain loop above. after `webui_render_region` the stream
  is empty (mount produces no ops).

engine-side drain (reference):

```js
while ((n = exports.webui_take_ops()) > 0) {
  const bytes = new Uint8Array(memory.buffer, exports.webui_frame_ptr(), n);
  // decode records back-to-back until bytes is exhausted (each record-v1)
}
```

### the probe's event vocabulary (`webui_on_event` payload, `{type,key,data}` v1)

decode → `ProbeIsland.decodeEvent` → typed `ProbeAction` → `reduce` → ops.
unknown/malformed payloads reduce to `.noop` and the drain sees an empty stream.

| type | key | data | action → ops |
|---|---|---|---|
| `key` | `ArrowUp` | — | increment(1) → `text(probe-counter, c)` |
| `key` | `ArrowDown` | — | decrement(1) → `text(probe-counter, c)` |
| `click` | `probe-inc` | — | increment(1) → `text(probe-counter, c)` |
| `click` | `probe-dec` | — | decrement(1) → `text(probe-counter, c)` |
| `click` | `probe-clear` | — | clear → `remove(probe-item-kN)` per item |
| `input` | `probe-field` | `{"value":"…"}` (non-empty) | addItem(v) → `insert(parent: probe-list, before: nil, html: <li id="probe-item-kN">escaped</li>)` |

counter/list ids: `probe-counter`, `probe-list`, `probe-item-kN` (the same
ids the mount html stamps — mount html + op stream stay consistent).

### probe region mounts

`webui_render_region` receives the `{name, args}` envelope; it renders the
**current retained typed state** (already restored if the engine called
`webui_state_restore` before the remount render). element ids above are the
delta targets.

### size + budget (measured)

`WebUIProbeIsland.wasm` 173,846 B stripped / 80,620 B gzip —
`IslandBudget(maxBytes: 200_000, maxGzipBytes: 90_000)` declared on
`ProbeIsland` (kB tier, comparable to validate's 164,670).

## WAVE 3 — `webui_run_corpus() -> i32` (the parity export, ADDITIVE)

a new probe export (the t4.2 parity suite). the ABI surface is otherwise
unchanged — c-ops regression stays 15/15.

- **call:** `webui_run_corpus()` — no args. returns the frame pointer
  (`webui_frame_ptr`, same as the other exports); the payload is in the frame
  buffer (`webui_frame_len` bytes).
- **payload:** `KernelParity.resultsJSON()` — `{"format":"kernel-corpus",
  "count":N,"cases":[{"name":...,"hash":...},…]}` — an ORDERED array (order is
  part of the contract), each hash a 16-hex FNV-1a (lowercase). the corpus is
  compile-time-frozen in WebUISharedCore; the island never receives inputs.
- **the engine does not need this export** — it is for the lane-C probe
  (`designer/probes/c-parity.mjs` loads the wasm directly and compares with
  the native artifact). treat it as read-only diagnostics.

## CONTINUUM_DX W1 — runtime-slice conversion (ABI-neutral)

lane C converted the probe's wasm main to the `IslandRuntime` slice
(`WebUIIslandCore/IslandRuntime.swift`) + the slim main. the engine-facing
ABI is UNCHANGED for E:

- the same eight exports with the same signatures and return conventions;
  `webui_run_corpus` still additive. `_start` still exported (the engine's
  `_start()` try/catch at webui-engine.js:1704 stays a benign no-op — the
  embedded runtime never runs Swift entry code, which is measured and
  documented; the probe island binds lazily on the first stateful export call).
- `webui_on_event` still queues, never serves; the engine's take_ops drain
  loop (drain until 0, whole records) is unchanged. mount produces no ops.
- verified: node drives the converted wasm exactly as before (same input
  writing, same drain), c-ops 15/15 (state channel, remount, byte-exact
  records) and c-parity 25/25 (corpus hashes).
