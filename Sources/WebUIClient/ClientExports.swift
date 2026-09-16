import WebUICore
import WebUISmokeShared

// the wasm export surface (P1 prove-out). the chamber calls
// `webui_render_page`, then reads the frame via `webui_frame_ptr`/`len` and
// patches the DOM. a fixed wasm-owned frame holds the last render's bytes;
// JS reads it with `new Uint8Array(memory.buffer, ptr, len)` — no copies
// across the boundary. the p2 handle_event surface lands alongside.
#if os(WASI)
private let frameCapacity = 1 << 20

private enum RenderFrame {
	nonisolated(unsafe) static let buffer = UnsafeMutableRawPointer.allocate(byteCount: frameCapacity, alignment: 16)
	nonisolated(unsafe) static var length = 0
}

@_expose(wasm, "webui_render_page")
func webuiRenderPage() -> Int {
	let html = HydrationView().render()
	let n = min(html.utf8.count, frameCapacity)
	html.withCString { c in
		RenderFrame.buffer.copyMemory(from: UnsafeRawPointer(c), byteCount: n)
	}
	RenderFrame.length = n
	return Int(bitPattern: RenderFrame.buffer)
}

@_expose(wasm, "webui_frame_ptr")
func webuiFramePtr() -> Int {
	Int(bitPattern: RenderFrame.buffer)
}

@_expose(wasm, "webui_frame_len")
func webuiFrameLen() -> Int {
	RenderFrame.length
}
#endif
