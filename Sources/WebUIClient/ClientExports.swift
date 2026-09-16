import WebUICore
import WebUISmokeShared
import WebUIClientRuntime

// the wasm export surface. the chamber calls `webui_render_page` /
// `webui_init` / `webui_handle_event`, then reads the frame via
// `webui_frame_ptr`/`len` and patches the DOM. a fixed wasm-owned frame holds
// the last output's bytes; JS reads it with `new Uint8Array(memory.buffer,
// ptr, len)`. events arrive in a separate input staging buffer the chamber
// writes before calling `webui_handle_event`.
#if os(WASI)
private let frameCapacity = 1 << 20
private let inputCapacity = 1 << 16

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
	// resident router + the local-search vertical's handlers, and publish the
	// boot page markup through the frame so the chamber can mount it.
	WebUIBridge.install()
	ClientRuntime.bootSearch()
	writeFrame(ClientRuntime.bootPageHTML)
}

@_expose(wasm, "webui_handle_event")
func webuiHandleEvent(_ eventPtr: UnsafeRawPointer?, _ len: Int) -> Int {
	guard let eventPtr, len > 0 else { return Int(bitPattern: RenderFrame.buffer) }
	let text = String(decoding: UnsafeRawBufferPointer(start: eventPtr, count: len), as: UTF8.self)
	let updates = ClientRuntime.handleEvent(text)
	let json = "[" + updates.map { update -> String in
		"{\"id\":\"\(JSONValue.escapeString(update.id))\",\"html\":\"\(JSONValue.escapeString(update.html))\"}"
	}.joined(separator: ",") + "]"
	writeFrame(json)
	return Int(bitPattern: RenderFrame.buffer)
}

@_expose(wasm, "webui_input_ptr")
func webuiInputPtr() -> Int {
	// the chamber writes event envelope bytes here before webui_handle_event
	Int(bitPattern: InputBuffer.buffer)
}

@_expose(wasm, "webui_render_page")
func webuiRenderPage() -> Int {
	let html = HydrationView().render()
	writeFrame(html)
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

private func writeFrame(_ text: String) {
	let n = min(text.utf8.count, frameCapacity)
	text.withCString { c in
		RenderFrame.buffer.copyMemory(from: UnsafeRawPointer(c), byteCount: n)
	}
	RenderFrame.length = n
}

private enum RenderFrame {
	nonisolated(unsafe) static let buffer = UnsafeMutableRawPointer.allocate(byteCount: frameCapacity, alignment: 16)
	nonisolated(unsafe) static var length = 0
}

private enum InputBuffer {
	nonisolated(unsafe) static let buffer = UnsafeMutableRawPointer.allocate(byteCount: inputCapacity, alignment: 16)
}
#endif
