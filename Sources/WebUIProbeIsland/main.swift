import WebUIIslandCore
import WebUISharedCore

// MARK: - probe island — the wasi reactor (DESKTOP_GRADE t2.5, wave 2)
//
// the wave-1 skeleton becomes real. all logic lives in the typed island core
// (`WebUIIslandCore.ProbeIsland` — pure, placement-free, natively tested);
// this file is only the ABI plumbing between the engine and that logic:
//
//   webui_render_region  mount: render the retained typed state to region html
//   webui_on_event       events in: decode {type,key,data} v1 → typed action →
//                        reduce → encode record-v1 → queue for the op stream
//   webui_take_ops       op-stream out: serve whole records back-to-back from
//                        the frame buffer; 0 = empty (the wave-2 freeze shape)
//   webui_state_save / webui_state_restore   state channel across remounts
//
// scalar-clean (the embedded runtime's rules): no Foundation, no
// `Character(...)` by-value construction, no `String(decoding:as:)` —
// `utf8Decode`/`writeFrame` are copied verbatim from the validate template.

@main
struct WebUIProbeIsland {
	static func main() {}
}

#if os(WASI)
private let frameCapacity = 1 << 18
private let inputCapacity = 1 << 16

// MARK: - retained state

/// everything that survives across calls and, via the state channel, across
/// region remounts: the typed probe state plus the reactor's bookkeeping.
private struct RetainedState {
	var probe = ProbeState()
	var renderCount = 0
	var eventCount = 0
	var restoredBytes = 0
}
nonisolated(unsafe) private var retained = RetainedState()

// MARK: - the op stream (webui_take_ops drain)

/// the island's out-queue. `webui_on_event` appends one encoded record per
/// event; `webui_take_ops` serves whole records back-to-back into the frame
/// buffer and the engine drains until it returns 0 — the interface freeze
/// recorded at i1 ("records back-to-back, each record-v1; the engine drains
/// until 0 and never holds references across calls").
private struct OpStream {
	private var pending: [[UInt8]] = []

	mutating func append(_ record: [UInt8]) {
		pending.append(record)
	}

	/// copies as many whole records into the frame as fit; a single record that
	/// exceeds the frame is still served whole (records are input-bounded at
	/// 1<<16 by the event buffer, the frame is 1<<18). returns the byte count
	/// served, 0 when nothing is pending.
	mutating func takeBatch() -> Int {
		var out: [UInt8] = []
		out.reserveCapacity(frameCapacity)
		while let first = pending.first, out.count + first.count <= frameCapacity {
			out.append(contentsOf: first)
			pending.removeFirst()
		}
		if out.isEmpty, let first = pending.first {
			out = first
			pending.removeFirst()
		}
		guard !out.isEmpty else { return 0 }
		writeFrameBytes(out)
		return out.count
	}
}
nonisolated(unsafe) private var opStream = OpStream()

// MARK: - the export surface

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
	// the mount envelope is `{name, args}`; the restored typed state (via
	// webui_state_restore before the remount render) is already in `retained`.
	_ = utf8Decode(ptr, len)
	writeFrame(ProbeIsland.regionHTML(state: retained.probe, renderCount: retained.renderCount, eventCount: retained.eventCount))
	return Int(bitPattern: FrameBuffer.buffer)
}

@_expose(wasm, "webui_on_event")
func webuiOnEvent(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
	guard let ptr, len > 0 else { return 0 }
	retained.eventCount += 1
	let payload = utf8Decode(ptr, len)
	let action = ProbeIsland.decodeEvent(json: payload)
	var state = retained.probe
	let ops = ProbeIsland.reduceOps(state: &state, action: action)
	retained.probe = state
	// an encode failure is unreachable for probe-produced ops (ids/values are
	// small and well-formed); a dropped record is safer than a torn frame.
	if !ops.isEmpty, let record = try? HotOpCodec.encodeBatch(ops) {
		opStream.append(record)
	}
	return Int(bitPattern: FrameBuffer.buffer)
}

@_expose(wasm, "webui_take_ops")
func webuiTakeOps() -> UInt32 {
	UInt32(opStream.takeBatch())
}

@_expose(wasm, "webui_state_save")
func webuiStateSave() -> Int {
	let json = ProbeIsland
		.stateToJSON(state: retained.probe, renderCount: retained.renderCount, eventCount: retained.eventCount)
		.serialize()
	writeFrame(json)
	return Int(bitPattern: FrameBuffer.buffer)
}

@_expose(wasm, "webui_state_restore")
func webuiStateRestore(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
	guard let ptr, len > 0 else { return 0 }
	let snapshot = utf8Decode(ptr, len)
	if let restored = ProbeIsland.stateFromJSON(snapshot) {
		retained.probe = restored.state
		retained.renderCount = restored.renderCount
		retained.eventCount = restored.eventCount
		retained.restoredBytes = len
	}
	writeFrame("{\"ok\":true,\"restored\":\(len)}")
	return Int(bitPattern: FrameBuffer.buffer)
}

// MARK: - scalar-clean primitives (verbatim from the validate template)

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

private func writeFrameBytes(_ bytes: [UInt8]) {
	bytes.withUnsafeBufferPointer { buf in
		FrameBuffer.buffer.copyMemory(from: UnsafeRawPointer(buf.baseAddress!), byteCount: buf.count)
	}
	FrameBuffer.length = bytes.count
}

private enum FrameBuffer {
	nonisolated(unsafe) static let buffer = UnsafeMutableRawPointer.allocate(byteCount: frameCapacity, alignment: 16)
	nonisolated(unsafe) static var length = 0
}

private enum InputBuffer {
	nonisolated(unsafe) static let buffer = UnsafeMutableRawPointer.allocate(byteCount: inputCapacity, alignment: 16)
}
#endif
