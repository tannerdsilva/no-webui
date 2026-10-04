import WebUIIslandCore
import WebUISharedCore

// MARK: - probe island — the wasi reactor (CONTINUUM_DX DX-1, W1)
//
// the 231-line hand-written ABI plumbing is gone: the runtime slice
// (`WebUIIslandCore/IslandRuntime.swift`) owns the ENTIRE export surface
// (`webui_input_ptr` · `webui_frame_ptr` · `webui_frame_len` ·
// `webui_render_region` · `webui_on_event` · `webui_take_ops` ·
// `webui_state_save` · `webui_state_restore`) and the scalar-clean plumbing
// (`utf8Decode`/`writeFrame`/the frame-buffer discipline). all logic lives in
// `WebUIIslandCore.ProbeIsland` (pure, placement-free, natively tested).
//
// this file keeps only the two per-island attachments the runtime cannot
// synthesize for a CONCRETE island type:
//
//   webui_island_bind  — the extra-exports binding hook: the runtime's export
//                        trampolines call this symbol on the first stateful
//                        call (lazily — the embedded wasip1 `_start` never
//                        executes Swift entry code, so there is no main body
//                        to run); it installs ProbeIsland as the handler.
//   webui_run_corpus   — the probe's EXTRA export (t4.2 parity, the c-parity
//                        gate 25/25): a global `@_expose` shim beside the
//                        runtime call, serving `KernelParity.resultsJSON()`
//                        through the runtime's extra-exports helper.

@main
struct WebUIProbeIsland {
	static func main() {}
}

#if os(WASI)
@_silgen_name("webui_island_bind")
func webuiIslandBind() {
	IslandRuntime<ProbeIsland>.run()
}

@_expose(wasm, "webui_run_corpus")
func webuiRunCorpus() -> Int {
	IslandRuntime<ProbeIsland>.writeExport(KernelParity.resultsJSON())
}
#endif
