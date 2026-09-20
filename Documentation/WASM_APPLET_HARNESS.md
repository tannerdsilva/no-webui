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

## import surface (v2 target)

the environment imports are the **capability seam**: the chamber wires an
import only when the page's boot config grants it, so the module surface is
also the permission surface.

| import | v1 | v2 |
|---|---|---|
| `setInnerHTML`, `removeElement`, `getElementValue`, `setElementValue`, `setCustomValidity` | yes | yes |
| `wsSend`, `storageGet`, `storageSet`, `now`, `log` | yes | yes |
| `focusElement`, `clipboardWrite`, `fileRead`, `broadcastSubscribe`/`webui_broadcast` | — | planned |
| media-query, fullscreen, drag-drop metadata | — | planned |

## message shapes (v2 target)

v1 (unchanged, JSON text frames): `event`, `ping`/`pong` (+`token`),
`update` (`{type:"update", fragments:[{id,html}]}`), `redirect`, `error`,
`token`. v2 additions (binary length-prefixed envelope with JSON fallback):

| type | direction | shape |
|---|---|---|
| `viewspec` | server→module | declarative render descriptor for a region (the eventual `ClientRenderers`-era replacement for string fragments) |
| `data` | server→module | bulk payload (typed array; bypasses JSON string overhead) |
| `state` | both | sync snapshot/delta for `ClientStateStore` paths |
| `ack` | module→server | optimistic batch ack with the server seq |

the v1 `update` fragments stay valid: the chamber applies them sanitized;
v2 adds module-side `viewspec` resolution so a region's composition can be
**declared**, not only computed by the server.

## verification (in-repo ladder)

- host: serialized `ClientRuntimeTests` (renderer registry, region render,
  local dispatch) — same sources, host executor.
- gate: `browser-smoke.mjs` asserts, on the search-demo page: region state
  `mounted`, module-composed markup present, control click updates the
  region locally, websocket silent on the applet hot path.
- byte-identity: the p1 `HydrationView` cross-host gate stays; region
  composition must keep the same `render()`-on-both-sides invariant.
