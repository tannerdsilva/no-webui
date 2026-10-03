import WebUIIslandCore
import WebUISharedCore

// MARK: - probe island logic
//
// the stateful probe skeleton (DESKTOP_GRADE t2.5). wave 1 ships the mount +
// event + state surfaces with minimal bodies; wave 2 fills them with typed
// state and the op stream (`HotOpCodec`, record format v1 — §t2.3). the island
// is a wasi reactor: `@main` installs nothing (the host build just needs a
// main; the real surface is the wasi exports below).

/// the probe's retained state + the pure helpers the exports call. survives
/// across calls and, via `webui_state_save` / `webui_state_restore`, across
/// region remounts (the RETAINED_OPEN precedent generalized, t2.4).
public enum ProbeIsland {

	/// wave-1 self-describing mount html; wave 2 renders typed `State`.
	public static func regionHTML(renderCount: Int, eventCount: Int) -> String {
		return "<div class=\"island island--probe\" data-island-state=\"mounted\""
			+ " data-island-renders=\"\(renderCount)\" data-island-events=\"\(eventCount)\">"
			+ "<span class=\"island__msg\">probe island · renders \(renderCount) · events \(eventCount)</span>"
			+ "</div>"
	}

	/// wave-1 state snapshot as json; wave 2 serializes typed `State`.
	public static func snapshotJSON(renderCount: Int, eventCount: Int) -> String {
		return "{\"renderCount\":\(renderCount),\"eventCount\":\(eventCount)}"
	}
}

@main
struct WebUIProbeIsland {
	static func main() {}
}

#if os(WASI)
// the stateful probe capability island — abi v2's minimal skeleton: the same
// region contract as the validate island (`webui_input_ptr` /
// `webui_frame_ptr` / `webui_frame_len`) plus `webui_render_region` (mount
// html), `webui_on_event` (events in), and the `webui_state_save` /
// `webui_state_restore` pair that makes state survive remounts.
private let frameCapacity = 1 << 18
private let inputCapacity = 1 << 16

private struct RetainedState {
	var renderCount = 0
	var eventCount = 0
	var restoredBytes = 0
}
nonisolated(unsafe) private var retained = RetainedState()

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
	retained.renderCount += 1
	// the mount envelope is `{name, args}` — read it now so a wave-2 typed
	// mount can seed state from args; wave 1 only proves the input path.
	let json = utf8Decode(ptr, len)
	_ = json
	writeFrame(ProbeIsland.regionHTML(renderCount: retained.renderCount, eventCount: retained.eventCount))
	return Int(bitPattern: FrameBuffer.buffer)
}

@_expose(wasm, "webui_on_event")
func webuiOnEvent(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
	guard let ptr, len > 0 else { return 0 }
	retained.eventCount += 1
	let payload = utf8Decode(ptr, len)
	// wave 1: acknowledge + surface the count as the frame payload; wave 2
	// feeds typed actions through `ContinuumIsland.reduce` and emits the op
	// stream via `HotOpCodec`.
	writeFrame("{\"ok\":true,\"events\":\(retained.eventCount),\"payload\":\"\(JSONValue.escapeString(payload))\"}")
	return Int(bitPattern: FrameBuffer.buffer)
}

@_expose(wasm, "webui_state_save")
func webuiStateSave() -> Int {
	// wave 1: snapshot the retained counters as json in the frame; wave 2
	// serializes typed `State` through the island's own codec.
	writeFrame(ProbeIsland.snapshotJSON(renderCount: retained.renderCount, eventCount: retained.eventCount))
	return Int(bitPattern: FrameBuffer.buffer)
}

@_expose(wasm, "webui_state_restore")
func webuiStateRestore(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
	guard let ptr, len > 0 else { return 0 }
	retained.restoredBytes = len
	// wave 1: parse the snapshot json into the retained counters so a remount
	// continues where the previous region left off; wave 2 decodes typed State.
	let snapshot = utf8Decode(ptr, len)
	if let root = try? JSONValue.parse(snapshot),
	   case .object(let dict) = root {
		if case .number(let renders)? = dict["renderCount"] { retained.renderCount = Int(renders) }
		if case .number(let events)? = dict["eventCount"] { retained.eventCount = Int(events) }
	}
	writeFrame("{\"ok\":true,\"restored\":\(len)}")
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
