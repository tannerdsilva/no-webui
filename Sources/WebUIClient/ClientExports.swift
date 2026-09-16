import WebUICore
import WebUISmokeShared
import WebUIClientRuntime

// the wasm export surface (P1 prove-out). the chamber calls
// `webui_render_page`, then reads the frame via `webui_frame_ptr`/`len` and
// patches the DOM. a fixed wasm-owned frame holds the last render's bytes;
// JS reads it with `new Uint8Array(memory.buffer, ptr, len)` — no copies
// across the boundary. the p2 handle_event surface lands alongside.
#if os(WASI)
private let frameCapacity = 1 << 20

@_expose(wasm, "webui_pump")
func webuiPump() -> Bool {
	// drains the runtime job queue to quiescence; returns true so the chamber
	// reschedules a bounded number of times (trajectory w§3.3).
	ClientExecutor.pump()
	return true
}

@_expose(wasm, "webui_init")
func webuiInit(_ configPtr: UnsafeRawPointer?, _ len: Int) {
	// config bytes (renderToken + authState envelope) arrive at p3; boot the
	// resident router + page handlers now.
	ClientRuntime.boot()
}

@_expose(wasm, "webui_handle_event")
func webuiHandleEvent(_ eventPtr: UnsafeRawPointer?, _ len: Int) -> Int {
	guard let eventPtr, len > 0 else { return Int(bitPattern: RenderFrame.buffer) }
	let text = String(decoding: UnsafeRawBufferPointer(start: eventPtr, count: len), as: UTF8.self)
	let updates = ClientRuntime.handleEvent(text)
	let json = "[" + updates.map { update -> String in
		"{\"id\":\"\(JSONValue.escapeString(update.id))\",\"html\":\"\(JSONValue.escapeString(update.html))\"}"
	}.joined(separator: ",") + "]"
	let n = min(json.utf8.count, frameCapacity)
	json.withCString { c in
		RenderFrame.buffer.copyMemory(from: UnsafeRawPointer(c), byteCount: n)
	}
	RenderFrame.length = n
	return Int(bitPattern: RenderFrame.buffer)
}

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
