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
