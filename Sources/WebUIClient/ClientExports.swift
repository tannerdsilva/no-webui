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
	// the boot envelope may carry an `authState` object (non-secret session
	// presence + roles) and a `persistence` flag (swap the localStorage
	// backend in). boot the resident router + the local-search vertical's
	// handlers, and publish the boot page markup through the frame.
	if let configPtr, len > 0 {
		let text = String(decoding: UnsafeRawBufferPointer(start: configPtr, count: len), as: UTF8.self)
		if let root = try? JSONValue.parse(text),
		   case .object(let dict) = root {
			if dict["persistence"] == .bool(true) {
				#if os(WASI)
				ClientRuntime.state = LocalStorageClientStateStore()
				#endif
			}
			if case .string(let token)? = dict["renderToken"] {
				ClientRuntime.sync = ClientSyncCoordinator(renderToken: token)
			}
			if let authRaw = dict["authState"] {
				ClientRuntime.applyAuthState(authRaw.serialize())
			}
		}
	}
	WebUIBridge.install()
	ClientRuntime.bootSearch()
	writeFrame(ClientRuntime.bootPageHTML)
}

@_expose(wasm, "webui_demote_auth")
func webuiDemoteAuth() {
	// server-directed revocation: a redirect/close on the transport demotes
	// the wasm authState mirror so ui gating flips immediately.
	ClientRuntime.demoteAuth()
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
