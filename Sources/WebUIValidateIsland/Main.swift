import WebUIIslandCore
import WebUISharedCore

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
	let json = utf8Decode(ptr, len)
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
	let result = ValidateIsland.evaluate(json: utf8Decode(ptr, len))
	writeFrame("{\"ok\":\(result.ok),\"message\":\"\(JSONValue.escapeString(result.message))\"}")
	return Int(bitPattern: FrameBuffer.buffer)
}

/// strict-enough utf-8 decode into a `String` without touching the
/// normalization tables: `String(decoding:as:)` canonicalizes, which the
/// embedded runtime omits, so the island link would fail on the
/// `_swift_stdlib_nfd_*` symbols. invalid sequences become U+FFFD.
private func utf8Decode(_ ptr: UnsafeRawPointer, _ len: Int) -> String {
	let bytes = UnsafeRawBufferPointer(start: ptr, count: len)
	var out = ""
	var i = 0
	while i < len {
		let b = bytes[i]
		let scalar: UInt32
		let width: Int
		if b < 0x80 {
			scalar = UInt32(b)
			width = 1
		} else if (b & 0xE0) == 0xC0, i + 1 < len, (bytes[i + 1] & 0xC0) == 0x80 {
			scalar = (UInt32(b & 0x1F) << 6) | UInt32(bytes[i + 1] & 0x3F)
			width = 2
		} else if (b & 0xF0) == 0xE0, i + 2 < len, (bytes[i + 1] & 0xC0) == 0x80, (bytes[i + 2] & 0xC0) == 0x80 {
			scalar = (UInt32(b & 0x0F) << 12) | (UInt32(bytes[i + 1] & 0x3F) << 6) | UInt32(bytes[i + 2] & 0x3F)
			width = 3
		} else if (b & 0xF8) == 0xF0, i + 3 < len,
		          (bytes[i + 1] & 0xC0) == 0x80, (bytes[i + 2] & 0xC0) == 0x80, (bytes[i + 3] & 0xC0) == 0x80 {
			scalar = (UInt32(b & 0x07) << 18) | (UInt32(bytes[i + 1] & 0x3F) << 12)
				| (UInt32(bytes[i + 2] & 0x3F) << 6) | UInt32(bytes[i + 3] & 0x3F)
			width = 4
		} else {
			out.unicodeScalars.append("\u{FFFD}")
			i += 1
			continue
		}
		// `Unicode.Scalar(_:)` rejects exactly what utf-8 forbids here: values
		// above U+10FFFF and the surrogate range, so the failable init is the
		// validity check itself — no force unwrap, no separate range test.
		if let scalarValue = Unicode.Scalar(scalar) {
			out.unicodeScalars.append(scalarValue)
		} else {
			out.unicodeScalars.append("\u{FFFD}")
		}
		i += width
	}
	return out
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
