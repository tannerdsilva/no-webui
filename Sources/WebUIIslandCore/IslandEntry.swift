// MARK: - the shared wasi entry harness
//
// every island artifact exposes the same four entry points: a writable input
// buffer, a writable output frame, the frame's length, and the region render
// call. this file holds them once, in the zero-dep island core, so a product's
// entry is an assignment plus its own extra exports — not ~120 lines of
// copied wasi boilerplate.
//
// host builds compile this file to nothing: the exports only exist on
// wasm32-wasi.

#if os(WASI)
import WebUISharedCore

/// the shared wasi entry harness behind every capability island artifact.
///
/// a product assigns ``render`` from its `main` (which the engine invokes as
/// `_start` before calling any export) and the four standard exports route
/// through it. the render closure receives the mount envelope's `args`
/// payload as json — the `{name, args}` wrapper is already unwrapped.
public enum IslandEntry {
	/// the product's region renderer. `nil` until the product's `main` runs;
	/// the export then reports an empty frame and the engine keeps the
	/// server-rendered fallback.
	nonisolated(unsafe) public static var render: ((String) -> String)?

	/// the frame buffer's base pointer, for the exports.
	public static var framePointer: Int { Int(bitPattern: FrameBuffer.buffer) }

	/// the input buffer's base pointer, for the exports.
	public static var inputPointer: Int { Int(bitPattern: InputBuffer.buffer) }

	/// the current frame length, in bytes.
	public static var frameLength: Int { FrameBuffer.length }

	/// decode `len` utf-8 bytes at `ptr` into a `String`.
	///
	/// the lenient policy lives in `IslandUTF8` (the island core's single
	/// scanner): invalid sequences become U+FFFD, and normalization tables are
	/// never touched — `String(decoding:as:)` canonicalizes, which the
	/// embedded runtime omits, so the island link would fail on the
	/// `_swift_stdlib_nfd_*` symbols.
	public static func decode(_ ptr: UnsafeRawPointer, _ len: Int) -> String {
		IslandUTF8.decodeReplacingInvalid(UnsafeRawBufferPointer(start: ptr, count: len))
	}

	/// write `text` into the frame buffer (truncated at the frame capacity)
	/// and return the frame's base pointer — the value every render export
	/// returns to the engine.
	@discardableResult
	public static func writeFrame(_ text: String) -> Int {
		let n = min(text.utf8.count, frameCapacity)
		text.withCString { c in
			FrameBuffer.buffer.copyMemory(from: UnsafeRawPointer(c), byteCount: n)
		}
		FrameBuffer.length = n
		return Int(bitPattern: FrameBuffer.buffer)
	}
}

private let frameCapacity = 1 << 18
private let inputCapacity = 1 << 16

// MARK: - the four standard exports

@_expose(wasm, "webui_input_ptr")
func webuiInputPtr() -> Int {
	IslandEntry.inputPointer
}

@_expose(wasm, "webui_frame_ptr")
func webuiFramePtr() -> Int {
	IslandEntry.framePointer
}

@_expose(wasm, "webui_frame_len")
func webuiFrameLen() -> Int {
	IslandEntry.frameLength
}

@_expose(wasm, "webui_render_region")
func webuiRenderRegion(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
	guard let ptr, len > 0 else { return 0 }
	guard let render = IslandEntry.render else { return 0 }
	let json = IslandEntry.decode(ptr, len)
	// the mount envelope is `{name, args}` — unwrap the args payload the same
	// way the validate product always has.
	let argsJSON: String
	if let root = try? JSONValue.parse(json),
	   case .object(let dict) = root,
	   let argsValue = dict["args"] {
		argsJSON = argsValue.serialize()
	} else {
		argsJSON = json
	}
	return IslandEntry.writeFrame(render(argsJSON))
}

private enum FrameBuffer {
	nonisolated(unsafe) static let buffer = UnsafeMutableRawPointer.allocate(byteCount: frameCapacity, alignment: 16)
	nonisolated(unsafe) static var length = 0
}

private enum InputBuffer {
	nonisolated(unsafe) static let buffer = UnsafeMutableRawPointer.allocate(byteCount: inputCapacity, alignment: 16)
}
#endif