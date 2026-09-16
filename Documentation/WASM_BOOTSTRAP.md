# WASM Bootstrap Notes — reactor shape, import surface, verification route

_date: 2026-09-15 · companion to `WASM_IMPLEMENTATION_PLAN.md` (P1-T0…T2)._

## reactor shape (verified on the built artifact)

- `WebUIClient` builds as a **wasi command** whose `_start` installs the runtime
  wiring and returns — it never calls `proc_exit`. all real work happens in
  exported `webui_*` entries (P1 render prove-out, P2 handle_event).
- `swift run -c release --swift-sdk swift-6.4.0-RELEASE_wasm WebUIClient
  --verify-render` runs under WasmKit and prints the hydration bytes.
- **debug builds are unusable under WasmKit at this size**: instantiation fails
  with `Error: The number of constant slots overflows` (the full-stdlib +
  618-glyph icon data debug module). verification and shipping use `-c release`.
- artifact path (SwiftPM 6.4 layout):
  `.build/out/Products/Release-webassembly-wasm32/WebUIClient.wasm`;
  debug at `Debug-webassembly-wasm32/`.

## import surface — P2 (parsed from the release binary, 2026-09-15)

`wasi_snapshot_preview1` — 34 functions:

args_get, args_sizes_get, environ_get, environ_sizes_get, clock_res_get,
clock_time_get, fd_close, fd_fdstat_get, fd_fdstat_set_flags, fd_filestat_get,
fd_filestat_set_size, fd_filestat_set_times, fd_pread, fd_prestat_get,
fd_prestat_dir_name, fd_read, fd_readdir, fd_seek, fd_sync, fd_tell, fd_write,
path_create_directory, path_filestat_get, path_filestat_set_times, path_link,
path_open, path_readlink, path_remove_directory, path_rename, path_symlink,
path_unlink_file, poll_oneoff, proc_exit, random_get.

`env` — the 8 chamber bridge imports (w§3.2):

setInnerHTML, removeElement, getElementValue, setElementValue,
setCustomValidity, wsSend, now, log.

## chamber-required note

once `env.*` imports are declared (p2-t4), the module **cannot be instantiated
by a host that does not provide them** — verified: `wasmkit run` fails with
`unknown import env.setInnerHTML`. the module is a browser product: only the
chamber (which implements all 8) can host it. wasm-side behavior gates move to
the browser (browser-smoke search probe); pure logic stays host-unit-tested;
the `--verify-*` CLI modes remain for debug builds of a bridge-less variant.
`@_extern(wasm, module:name:)` (the official import primitive) requires the
experimental `Extern` frontend feature, enabled on the `WebUIClientRuntime`
target; `@_used` does **not** keep import symbols dead-stripped — imports must
be referenced from a reachable root (webui_init → WebUIBridge.install).

## size

- release `WebUIClient.wasm`: 62,353,046 bytes (~59 MiB) — full static stdlib +
  icon data, debug-friendly driver. this is a **P6 concern** (tiering + embedded
  diet); P1/T2 carrier bytes embed it whole and serve it as a file.

## wasm-side test route (P1-T0-b decision, now confirmed live)

`swift test --swift-sdk …` is **not** used: SwiftPM builds every test target in
the package for the sdk, and `WebUITests` links `WebUIDesignSystem`/`WebUIChart`
→ rawdog, which is not a wasm compile target. wasm-side assertions run through
the executable's `--verify-*` modes under WasmKit (byte-identity in the release
build), and pure-logic specs run in the host `WebUIClientTests` suite (same
sources, same `render()` — the cross-host gate is the byte diff).
