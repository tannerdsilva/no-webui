# WASM Applet Harness — v2 contract (draft as shipped)

_date: 2026-09-20 · status: implemented first slice · the v1 JSON/text wire
shape and the 9-export ABI remain (v1 epoch = STABILITY.md's 1.0.0); this
document is the target contract for the 2.0 epoch. `STABILITY.md` and
`CHANGELOG.md` will carry the epoch cut when the harness is complete.

## model

one wasm module instance per page. applets are **named, module-resident
capability groups** — not separate instances (a per-applet instance would
cost the module's full memory per widget; isolation is by namespace +
capability token, not by memory sandbox).

- a page declares a **region** the module owns:
  `<div data-webui-applet="applet:view" data-webui-args='{"…":"…"}'></div>`
- the **chamber** (browser glue) mounts regions after boot by asking the
  module to render them; the module's own boot page can also declare regions
  (the smoke vertical does — `#applet-region` inside the boot tree).
- a region's renderer **self-wires**: it renders inside a `RenderContext`
  bound to the resident router, so its controls route through
  `webui_handle_event` exactly like page-built controls, and fragment updates
  it returns are applied by the chamber through the same sanitized path.

## export surface (v2 additions)

| export | purpose |
|---|---|
| `webui_render_region(ptr, len) -> framePtr` | render `{name, args}` through `ClientRenderers`; empty frame = unmapped |
| (v1, unchanged) | `webui_init`, `webui_pump`, `webui_handle_event`, `webui_apply_seq`, `webui_render_page`, `webui_demote_auth`, `webui_input_ptr`, `webui_frame_ptr`, `webui_frame_len` |

input staging is still the chamber-written 64 KiB buffer (`webui_input_ptr`);
region envelopes are small and fit with the same guard, the frame carries
the emitted html.

## import surface (v2 — implemented)

the environment imports are the **capability seam**: the chamber wires an
import only when the page's boot config grants it, so the module surface is
also the permission surface. `RuntimeConfig.capabilities` carries the grants
in the boot envelope; un-granted imports no-op in the chamber.

| import | v1 | v2 |
|---|---|---|
| `setInnerHTML`, `removeElement`, `getElementValue`, `setElementValue`, `setCustomValidity` | yes | yes |
| `wsSend`, `storageGet`, `storageSet`, `now`, `log` | yes | yes |
| `focusElement` (grant: `focus`) | — | yes |
| `clipboardWrite` (grant: `clipboard`) | — | yes |
| `broadcastSubscribe` / `broadcastPublish` (grant: `broadcast`; inbound re-enters `webui_broadcast` → `ClientRuntime.handleBroadcast`) | — | yes |
| `fullscreenElement` (grant: `fullscreen`) | — | yes |
| `mediaQuery` (grant: `media`) | — | yes |
| inbound files (drag-drop; grant: `files` → `webui_file_alloc` + `webui_file_commit` → `ClientRuntime.onFile`) | — | yes |
| media-change subscription, `fileRead` via picker, drag metadata | — | planned |

## message shapes (v2 — implemented)

v1 (unchanged, JSON text frames): `event`, `ping`/`pong` (+`token`),
`update` (`{type:"update", fragments:[{id,html}]}`), `redirect`, `error`,
`token`. v2 adds binary **frames** — `[0x64][u32 len][json bytes]` — the
chamber's ws listener accepts both text and binary (`binaryType =
'arraybuffer'`; `handleBinaryFrame` also exposed for hosts/gates):

| type | direction | shape |
|---|---|---|
| `viewspec` | server→module | `{type, id, name, args}` — compose a region declaratively through `webui_render_region` |
| `state` | server→module | `{type:"state", path, value}` — `webui_state_apply` → client state store + handler fragments |
| `data` | server→module | `{type:"data", name, payload}` — `webui_data_apply` → handler fragments (typed-array/binary envelope; JSON payload inside the frame for now) |
| `update` | server→module | v1 fragments (unchanged, also accepted in binary frames) |

the v1 `update` fragments stay valid: the chamber applies them sanitized;
binary frames just move the envelope from text to bytes without a new
dialect. bulk typed-array payloads (no JSON wrapper) are next on the data
plane.

## client-state persistence (harness v4)

`RuntimeConfig.persistence`: `"localstorage"` (default) or `"indexeddb"`.
with `"indexeddb"` the chamber hydrates the state from IndexedDB **before**
wasm instantiation, and the `storageGet`/`storageSet` imports serve the
hydrated cache + async-persist writes — the module-side store contract is
unchanged (same `LocalStorageClientStateStore`, different backing). the
gate proves durability across a reload with `localStorage` untouched.

## verification (in-repo ladder)

- host: serialized `ClientRuntimeTests` (renderer registry, region render,
  local dispatch) — same sources, host executor.
- gate: `browser-smoke.mjs` asserts, on the search-demo page: region state
  `mounted`, module-composed markup present, control click updates the
  region locally, websocket silent on the applet hot path.
- byte-identity: the p1 `HydrationView` cross-host gate stays; region
  composition must keep the same `render()`-on-both-sides invariant.
