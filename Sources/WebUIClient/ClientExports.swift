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
private let fileCapacity = 1 << 20
private let dataCapacity = 1 << 20

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
	// presence + roles), a `persistence` flag (swap the localStorage
	// backend in), and `capabilities` (harness grants). boot the resident
	// router + the local-search vertical's handlers, and publish the boot
	// page markup through the frame.
	if let configPtr, len > 0 {
		let text = String(decoding: UnsafeRawBufferPointer(start: configPtr, count: len), as: UTF8.self)
		if let root = try? JSONValue.parse(text),
		   case .object(let dict) = root {
			let wantsPersistence: Bool
			if dict["persistence"] == .bool(true) {
				wantsPersistence = true
			} else if case .string(let mode)? = dict["persistence"], mode == "indexeddb" {
				wantsPersistence = true
			} else {
				wantsPersistence = false
			}
			if wantsPersistence {
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
			if case .array(let caps)? = dict["capabilities"] {
				let names = caps.compactMap { entry -> String? in
					if case .string(let value) = entry { return value }
					return nil
				}
				ClientRuntime.applyCapabilities(names)
			}
		}
	}
	WebUIBridge.install()
	ClientRuntime.bootSearch()
	ClientRuntime.bootApplets()
	writeFrame(ClientRuntime.bootPageHTML)
}

@_expose(wasm, "webui_demote_auth")
func webuiDemoteAuth() {
	// server-directed revocation: a redirect/close on the transport demotes
	// the wasm authState mirror so ui gating flips immediately.
	ClientRuntime.demoteAuth()
}

@_expose(wasm, "webui_apply_seq")
func webuiApplySeq(_ seqPtr: UnsafeRawPointer?, _ len: Int) -> Int {
	// an authoritative `update` arrived over the chamber's transport: advance
	// the sync ledger's authority seq so superseded local predictions
	// reconcile (the chamber applies the frame's fragments itself, sanitized,
	// because it owns the dom). returns how many local patches the server
	// state superseded — the chamber can use it for optimistic-cleanup math.
	guard let seqPtr, len > 0 else { return 0 }
	let text = String(decoding: UnsafeRawBufferPointer(start: seqPtr, count: len), as: UTF8.self)
	guard let seq = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
	return ClientRuntime.sync.applyAuthoritative(seq: seq)
}

@_expose(wasm, "webui_handle_event")
func webuiHandleEvent(_ eventPtr: UnsafeRawPointer?, _ len: Int) -> Int {
	guard let eventPtr, len > 0 else { return Int(bitPattern: RenderFrame.buffer) }
	let text = String(decoding: UnsafeRawBufferPointer(start: eventPtr, count: len), as: UTF8.self)
	let updates = ClientRuntime.handleEvent(text)
	writeFrame(updatesJSON(updates))
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

@_expose(wasm, "webui_render_region")
func webuiRenderRegion(_ regionPtr: UnsafeRawPointer?, _ len: Int) -> Int {
	// an applet-region request (`{name, args}`): resolve the registered
	// renderer in the module and emit its html through the frame. an empty
	// frame signals "unmapped" so the chamber leaves the placeholder.
	guard let regionPtr, len > 0 else { return 0 }
	let text = String(decoding: UnsafeRawBufferPointer(start: regionPtr, count: len), as: UTF8.self)
	guard let root = try? JSONValue.parse(text),
	      case .object(let dict) = root,
	      case .string(let name)? = dict["name"] else {
		writeFrame("")
		return Int(bitPattern: RenderFrame.buffer)
	}
	let args: String
	if case .object? = dict["args"], let serialized = dict["args"]?.serialize() {
		args = serialized
	} else {
		args = "{}"
	}
	let html = ClientRuntime.regionHTML(name: name, argsJSON: args) ?? ""
	writeFrame(html)
	return Int(bitPattern: RenderFrame.buffer)
}

@_expose(wasm, "webui_broadcast")
func webuiBroadcast(_ channelPtr: UnsafeRawPointer?, _ channelLen: Int, _ dataPtr: UnsafeRawPointer?, _ dataLen: Int) {
	// an inbound broadcast channel message (harness v2 capability
	// `broadcast`): the chamber's BroadcastChannel listener re-enters here.
	guard let channelPtr, channelLen > 0, let dataPtr, dataLen > 0 else { return }
	let channel = String(decoding: UnsafeRawBufferPointer(start: channelPtr, count: channelLen), as: UTF8.self)
	let payload = String(decoding: UnsafeRawBufferPointer(start: dataPtr, count: dataLen), as: UTF8.self)
	ClientRuntime.handleBroadcast(channel: channel, payload: payload)
}

@_expose(wasm, "webui_file_alloc")
func webuiFileAlloc(_ maxLen: Int) -> Int {
	// reserve the module-owned file buffer for an inbound file (harness v3,
	// capability `files`). the chamber writes the bytes there, then calls
	// `webui_file_commit`. returns 0 when the file exceeds the cap.
	guard maxLen > 0, maxLen <= fileCapacity else { return 0 }
	return Int(bitPattern: FileBuffer.buffer)
}

@_expose(wasm, "webui_file_commit")
func webuiFileCommit(_ dataPtr: UnsafeRawPointer?, _ dataLen: Int, _ metaPtr: UnsafeRawPointer?, _ metaLen: Int) -> Int {
	// bytes + `{name, mime}` meta: run the registered file handler and emit
	// its fragments through the frame (the chamber applies them after).
	guard let dataPtr, dataLen > 0, dataLen <= fileCapacity else { return 0 }
	let bytes = Array(UnsafeRawBufferPointer(start: dataPtr, count: dataLen))
	var name = "file"
	var mime = "application/octet-stream"
	if let metaPtr, metaLen > 0,
	   let root = try? JSONValue.parse(String(decoding: UnsafeRawBufferPointer(start: metaPtr, count: metaLen), as: UTF8.self)),
	   case .object(let dict) = root {
		if case .string(let value)? = dict["name"] { name = value }
		if case .string(let value)? = dict["mime"] { mime = value }
	}
	let updates = ClientRuntime.handleFile(name: name, mime: mime, bytes: bytes)
	writeFrame(updatesJSON(updates))
	return Int(bitPattern: RenderFrame.buffer)
}

@_expose(wasm, "webui_state_apply")
func webuiStateApply(_ payloadPtr: UnsafeRawPointer?, _ payloadLen: Int) -> Int {
	// a server `state` message (`{path, value}`): apply to the client state
	// store and run the registered handler (its fragments ride the frame).
	guard let payloadPtr, payloadLen > 0 else { return Int(bitPattern: RenderFrame.buffer) }
	let text = String(decoding: UnsafeRawBufferPointer(start: payloadPtr, count: payloadLen), as: UTF8.self)
	guard let root = try? JSONValue.parse(text),
	      case .object(let dict) = root,
	      case .string(let path)? = dict["path"],
	      let value = dict["value"] else {
		writeFrame("")
		return Int(bitPattern: RenderFrame.buffer)
	}
	let updates = ClientRuntime.applyState(path: path, value: value)
	writeFrame(updatesJSON(updates))
	return Int(bitPattern: RenderFrame.buffer)
}

@_expose(wasm, "webui_data_alloc")
func webuiDataAlloc(_ maxLen: Int) -> Int {
	// reserve the module-owned buffer for an inbound bulk payload (harness
	// v2.1, kind 0x01 frames): the chamber writes raw bytes there, then calls
	// `webui_data_commit`. returns 0 when the payload exceeds the cap.
	guard maxLen > 0, maxLen <= dataCapacity else { return 0 }
	return Int(bitPattern: DataBuffer.buffer)
}

@_expose(wasm, "webui_data_commit")
func webuiDataCommit(_ dataPtr: UnsafeRawPointer?, _ dataLen: Int, _ namePtr: UnsafeRawPointer?, _ nameLen: Int) -> Int {
	// raw bytes + name (input staging): run the registered bulk handler and
	// emit its fragments through the frame (the chamber applies after).
	guard let dataPtr, dataLen > 0, dataLen <= dataCapacity else { return 0 }
	let bytes = Array(UnsafeRawBufferPointer(start: dataPtr, count: dataLen))
	let name: String
	if let namePtr, nameLen > 0 {
		name = String(decoding: UnsafeRawBufferPointer(start: namePtr, count: nameLen), as: UTF8.self)
	} else {
		name = "data"
	}
	let updates = ClientRuntime.handleDataBytes(name: name, bytes: bytes)
	writeFrame(updatesJSON(updates))
	return Int(bitPattern: RenderFrame.buffer)
}

@_expose(wasm, "webui_data_apply")
func webuiDataApply(_ payloadPtr: UnsafeRawPointer?, _ payloadLen: Int) -> Int {
	// a binary `data` message (`{name, payload}`): run the registered data
	// handler (its fragments ride the frame; the chamber applies after).
	guard let payloadPtr, payloadLen > 0 else { return Int(bitPattern: RenderFrame.buffer) }
	let text = String(decoding: UnsafeRawBufferPointer(start: payloadPtr, count: payloadLen), as: UTF8.self)
	guard let root = try? JSONValue.parse(text),
	      case .object(let dict) = root,
	      case .string(let name)? = dict["name"] else {
		writeFrame("")
		return Int(bitPattern: RenderFrame.buffer)
	}
	let payload: String
	if let raw = dict["payload"] {
		payload = raw.serialize()
	} else {
		payload = ""
	}
	let updates = ClientRuntime.handleData(name: name, payload: payload)
	writeFrame(updatesJSON(updates))
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

private func updatesJSON(_ updates: [FragmentUpdate]) -> String {
	"[" + updates.map { update -> String in
		"{\"id\":\"\(JSONValue.escapeString(update.id))\",\"html\":\"\(JSONValue.escapeString(update.html))\"}"
	}.joined(separator: ",") + "]"
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

private enum FileBuffer {
	nonisolated(unsafe) static let buffer = UnsafeMutableRawPointer.allocate(byteCount: fileCapacity, alignment: 16)
}

private enum DataBuffer {
	nonisolated(unsafe) static let buffer = UnsafeMutableRawPointer.allocate(byteCount: dataCapacity, alignment: 16)
}
#endif
