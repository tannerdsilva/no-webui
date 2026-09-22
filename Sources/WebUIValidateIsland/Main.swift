import WebUIIslandCore
import WebUICore

// the host build just needs a main (the target is wasm-only in practice);
// the real surface is the wasi exports below.
@main
struct WebUIValidateIsland {
	static func main() {}
}

#if os(WASI)
// the validate capability island — a wasi reactor exposing the same region
// contract the chamber/engine mount path uses (`webui_input_ptr` /
// `webui_frame_ptr` / `webui_frame_len`), plus a `webui_validate` entry for
// input-driven revalidation without a render round trip. `_start` (via
// `@main`) installs nothing and returns; all work happens through exports.
private let frameCapacity = 1 << 18
private let inputCapacity = 1 << 16

@_expose(wasm, "webui_input_ptr")
func webuiInputPtr() -> Int {
	Int(bitPattern: InputBuffer.buffer)
}

@_expose(wasm, "webui_frame_ptr")
func webuiFramePtr() -> Int {
	Int(bitPattern: FrameBuffer.buffer)
}

@_expose(wasm, "webui_frame_len")
func webuiFrameLen() -> Int {
	FrameBuffer.length
}

@_expose(wasm, "webui_render_region")
func webuiRenderRegion(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
	guard let ptr, len > 0 else { return 0 }
	let json = String(decoding: UnsafeRawBufferPointer(start: ptr, count: len), as: UTF8.self)
	// the mount envelope is `{name, args}` — unwrap the args payload the same
	// way the client's own `webui_render_region` does.
	let argsJSON: String
	if let root = try? JSONValue.parse(json),
	   case .object(let dict) = root,
	   let argsValue = dict["args"] {
		argsJSON = argsValue.serialize()
	} else {
		argsJSON = json
	}
	writeFrame(ValidateIsland.regionHTML(argsJSON: argsJSON))
	return Int(bitPattern: FrameBuffer.buffer)
}

@_expose(wasm, "webui_validate")
func webuiValidate(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
	guard let ptr, len > 0 else { return 0 }
	let json = String(decoding: UnsafeRawBufferPointer(start: ptr, count: len), as: UTF8.self)
	let result = ValidateIsland.evaluate(json: json)
	writeFrame("{\"ok\":\(result.ok),\"message\":\"\(JSONValue.escapeString(result.message))\"}")
	return Int(bitPattern: FrameBuffer.buffer)
}

private func writeFrame(_ text: String) {
	let n = min(text.utf8.count, frameCapacity)
	text.withCString { c in
		FrameBuffer.buffer.copyMemory(from: UnsafeRawPointer(c), byteCount: n)
	}
	FrameBuffer.length = n
}

private enum FrameBuffer {
	nonisolated(unsafe) static let buffer = UnsafeMutableRawPointer.allocate(byteCount: frameCapacity, alignment: 16)
	nonisolated(unsafe) static var length = 0
}

private enum InputBuffer {
	nonisolated(unsafe) static let buffer = UnsafeMutableRawPointer.allocate(byteCount: inputCapacity, alignment: 16)
}
#endif
