import WebUIIslandCore
import WebUISharedCore

// MARK: - validate island — the wasi reactor (CONTINUUM_DX DX-2)
//
// the 121-line hand-written ABI plumbing is gone: the runtime slice
// (`WebUIIslandCore/IslandRuntime.swift`) owns the ENTIRE export surface
// (`webui_input_ptr` · `webui_frame_ptr` · `webui_frame_len` ·
// `webui_render_region` · `webui_on_event` · `webui_take_ops` ·
// `webui_state_save` · `webui_state_restore`) and the scalar-clean plumbing
// (`utf8Decode`/`writeFrame`/the frame-buffer discipline). all logic lives in
// `WebUIIslandCore.ValidateIsland` (the d3 rule evaluator, pure and natively
// tested) — the conversion made it a concrete `IslandRuntimeSurface` exactly
// as the probe was.
//
// this file keeps only the two per-island attachments the runtime cannot
// synthesize for a CONCRETE island type:
//
//   webui_island_bind  — the binding hook: the runtime's export trampolines
//                        call this symbol on the first stateful call (lazily —
//                        the embedded wasip1 `_start` never executes Swift
//                        entry code), installing ValidateIsland as the handler.
//   webui_validate     — the validate island's EXTRA export (the d3 input→
//                        output contract): a global `@_expose` shim beside the
//                        runtime call, serving the evaluation verdict through
//                        the runtime's lockstep input-driven extras helper —
//                        reading the same input buffer the standard exports
//                        use, exactly like the hand-written export did.

@main
struct WebUIValidateIsland {
	static func main() {}
}

#if os(WASI)
@_silgen_name("webui_island_bind")
func webuiIslandBind() {
	IslandRuntime<ValidateIsland>.run()
}

@_expose(wasm, "webui_validate")
func webuiValidate(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
	IslandRuntime<ValidateIsland>.writeExport(input: ptr, len) { json in
		ValidateIsland.validationResponse(json: json)
	}
}
#endif
