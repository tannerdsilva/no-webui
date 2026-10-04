import WebUISharedCore

// MARK: - DX-1 — the island runtime slice (CONTINUUM_DX §2.1)
//
// the generic runtime that owns the ENTIRE wasm export surface so a consumer's
// island main shrinks to a bind shim plus (optionally) per-island EXTRA export
// shims. absorbs the plumbing the probe used to carry by hand (`utf8Decode`,
// `writeFrame`, the frame-buffer discipline) — all scalar-clean for the
// embedded wasm runtime.
//
// export surface (all eight, runtime-owned):
//   webui_input_ptr · webui_frame_ptr · webui_frame_len  — buffer accessors
//   webui_render_region · webui_on_event · webui_take_ops · webui_state_save ·
//   webui_state_restore                                    — the reactor calls
//
// parameterization: `IslandRuntime<I>` + `IslandRuntimeCore<I>` run against a
// `ContinuumIsland`-typed island (`I: IslandRuntimeSurface`), which declares the
// four runtime hooks (`decodeEvent`, `regionHTML`, `stateToJSON`,
// `stateFromJSON`) beside the frozen `ContinuumIsland.reduce`.
//
// EXTRA exports (red-team: `webui_run_corpus` must survive): `@_expose(wasm:)`
// is accepted by this toolchain only on GLOBAL functions, and the embedded
// wasip1 `_start` never executes Swift entry code (measured), so per-island
// extras stay one-line global shims in the island's main that call
// `IslandRuntime<I>.writeExport(_:)`; the standard surface is bound lazily on
// the first stateful export call through the island's `webui_island_bind`
// symbol (resolved at wasm link time).

// MARK: - the runtime surface hook (per-island, additive)

/// a `HotState` an island can construct from nothing — the reactor core needs a
/// fresh empty state on instantiation. additive (`HotState` is frozen in
/// WebUISharedCore; this refinement lives beside the runtime).
public protocol IslandEmptyState: HotState {
	init()
}

/// the four runtime hooks an island must declare beside `ContinuumIsland`.
/// probe-shaped by design (`ProbeIsland`'s hand-written equivalents, so the
/// conversion is a pure conformance).
public protocol IslandRuntimeSurface: ContinuumIsland where State: IslandEmptyState {
	/// the island's `{type, key, data}` v1 event decoder → typed action.
	static func decodeEvent(json: String) -> Action

	/// mount html for the current retained state (ids the ops target).
	static func regionHTML(state: State, renderCount: Int, eventCount: Int) -> String

	/// the full retained snapshot — typed state plus the reactor counters.
	static func stateToJSON(state: State, renderCount: Int, eventCount: Int) -> JSONValue

	/// rebuilds the retained state; nil = malformed (caller keeps live state).
	static func stateFromJSON(_ json: String) -> (state: State, renderCount: Int, eventCount: Int)?

	// DX-2 (validated additive): the mount-envelope hook. the runtime decodes
	// the `{name, args}` envelope `webui_render_region` carries and hands it
	// here BEFORE rendering, so an args-derived island (validate) can fold the
	// mount args into its retained state. the probe's default ignores the
	// envelope (its region is retained-state-only) — the hook is strictly
	// additive and the default keeps every existing conformance unchanged.
	static func consumeMountEnvelope(_ envelopeJSON: String, state: inout State)

	// DX-9 (CONTINUUM_ID_CHECK builds only): the island's element-id vocabulary
	// — the surface the runtime's op dev check validates against. production
	// builds compile it out entirely (zero runtime tax, I4); W3's @HotView
	// macro emits the `elementIDs` mirror (d-docs §DX-9).
	#if CONTINUUM_ID_CHECK
	/// the literal element ids this island's ops may target. over-collection
	/// is permissive-safe (the check ignores ids the island never emits); a
	/// missed literal is the only bug class.
	static var elementIDs: Set<ElementID> { get }

	/// ids derived at runtime that the literal set cannot carry (keyed rows:
	/// `probe-item-k<n>`). consulted after `elementIDs`; the default below
	/// consults `elementIDs` only.
	static func isKnownElementID(_ id: ElementID) -> Bool
	#endif
}

/// the mount-envelope default: not consumed (the probe renders retained state
/// only). `writeExport`-style defaults live beside the runtime so a slim island
/// conformance stays one declared `static func` short of complete.
public extension IslandRuntimeSurface {
	static func consumeMountEnvelope(_ envelopeJSON: String, state: inout State) {
		_ = envelopeJSON
		_ = state
	}
}

#if CONTINUUM_ID_CHECK
public extension IslandRuntimeSurface {
	/// the empty-vocabulary default: an island that declares nothing fails
	/// loudly on any emitted op — declaration is the point of the check, and a
	/// silently-skipped island would hollow it out (d-docs §DX-9).
	static var elementIDs: Set<ElementID> { [] }

	/// the literal-set default; islands with runtime-derived id families
	/// override this (probe: the `probe-item-k<n>` rows).
	static func isKnownElementID(_ id: ElementID) -> Bool { elementIDs.contains(id) }
}
#endif

// MARK: - the reactor core (buffer-free, native-testable)

/// the shared reactor state + the op-stream discipline: everything that
/// survives across export calls. buffer-free — methods return the exact frame
/// payload bytes (or nil for "no frame write" / drained), so the SAME code is
/// driven natively (behavior-equivalence tests) and inside wasm (the bridge
/// copies the payload into the physical frame buffer).
public struct IslandRuntimeCore<I: IslandRuntimeSurface> {
	public var probe: I.State
	public var renderCount = 0
	public var eventCount = 0
	/// byte length of the last successful `webui_state_restore` (bookkeeping,
	/// preserved for parity with the hand-written reactor).
	public var restoredBytes = 0

	/// frame capacity for `webui_take_ops` batching (the engine's drain
	/// contract: whole records, never split, 0 = empty). mirrors the wasm
	/// frame buffer size.
	public var frameCapacity: Int

	private var pendingRecords: [[UInt8]] = []

	public init(frameCapacity: Int = 1 << 18) {
		probe = I.State()
		self.frameCapacity = frameCapacity
	}

	// MARK: webui_render_region — mount: render the retained state to region html.
	//
	// returns the frame payload (region html bytes), or nil when the input is
	// empty (the wasm export returns 0 without touching the frame, matching the
	// hand-written probe).
	@discardableResult
	public mutating func renderRegion(input: [UInt8]) -> [UInt8]? {
		guard !input.isEmpty else { return nil }
		renderCount += 1
		// the mount envelope `{name, args}` is folded into the retained state
		// via the island's mount hook (DX-2 additive: validate retains the args
		// it must render; the probe's default ignores the envelope, so the
		// mount path for retained-state islands is unchanged).
		let envelopeJSON = utf8Decode(input)
		I.consumeMountEnvelope(envelopeJSON, state: &probe)
		return Array(I.regionHTML(state: probe, renderCount: renderCount, eventCount: eventCount).utf8)
	}

	// MARK: webui_on_event — events in: decode → reduce → queue encoded records.
	//
	// returns whether the payload was dispatched (false = empty input, the wasm
	// export returns 0). the frame is untouched — op delivery is exclusively via
	// the webui_take_ops drain loop (the i1 freeze).
	@discardableResult
	public mutating func onEvent(input: [UInt8]) -> Bool {
		guard !input.isEmpty else { return false }
		eventCount += 1
		let payload = utf8Decode(input)
		let action = I.decodeEvent(json: payload)
		var state = probe
		var ops: [HotOp] = []
		for effect in I.reduce(state: &state, action: action) {
			if case .ops(let batch) = effect { ops.append(contentsOf: batch) }
		}
		probe = state
		#if CONTINUUM_ID_CHECK
		// DX-9 dev assertion (build-flag gated; compiled out in production):
		// every op this event emitted must target a known element id — an
		// unknown one is a dev-time failure naming the id (frame diagnostic +
		// trap), never a silent engine drop.
		IslandIDCheck.enforce(ops, isKnown: I.isKnownElementID)
		#endif
		// an encode failure is unreachable for probe-produced ops (ids/values
		// are small and well-formed); a dropped record is safer than a torn frame.
		if !ops.isEmpty, let record = try? HotOpCodec.encodeBatch(ops) {
			pendingRecords.append(record)
		}
		return true
	}

	// MARK: webui_take_ops — op-stream out: whole records back-to-back, 0 = empty.
	//
	// copies as many whole records into the payload as fit; a single record that
	// exceeds the frame is still served whole (records are input-bounded at
	// 1<<16 by the event buffer, the frame is 1<<18).
	public mutating func takeOps() -> [UInt8]? {
		var out: [UInt8] = []
		out.reserveCapacity(frameCapacity)
		while let first = pendingRecords.first, out.count + first.count <= frameCapacity {
			out.append(contentsOf: first)
			pendingRecords.removeFirst()
		}
		if out.isEmpty, let first = pendingRecords.first {
			out = first
			pendingRecords.removeFirst()
		}
		guard !out.isEmpty else { return nil }
		return out
	}

	// MARK: webui_state_save — the full snapshot json as the frame payload.
	public mutating func stateSave() -> [UInt8] {
		Array(I
			.stateToJSON(state: probe, renderCount: renderCount, eventCount: eventCount)
			.serialize()
			.utf8)
	}

	// MARK: webui_state_restore — rebuild the retained state; a malformed
	// snapshot keeps the live state (a restore must never wipe progress).
	// returns the ack frame payload, or nil on empty input (wasm export → 0).
	public mutating func stateRestore(input: [UInt8]) -> [UInt8]? {
		guard !input.isEmpty else { return nil }
		let snapshot = utf8Decode(input)
		if let restored = I.stateFromJSON(snapshot) {
			probe = restored.state
			renderCount = restored.renderCount
			eventCount = restored.eventCount
			restoredBytes = input.count
		}
		return Array("{\"ok\":true,\"restored\":\(input.count)}".utf8)
	}
}

// MARK: - scalar-clean primitives (absorbed from the probe/validate mains)

/// strict-enough utf-8 decode into a `String` without touching the
/// normalization tables: `String(decoding:as:)` canonicalizes, which the
/// embedded runtime omits, so the island link would fail on the
/// `_swift_stdlib_nfd_*` symbols. invalid sequences become U+FFFD. copied
/// verbatim from the hand-written probe template (the behavior-equivalence
/// fixture) and now owned by the runtime.
func utf8Decode(_ bytes: [UInt8]) -> String {
	var out = ""
	var i = 0
	let len = bytes.count
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

#if os(WASI)
// MARK: - the wasm export surface (runtime-owned, global funcs)
//
// `@_expose(wasm:)` accepts ONLY global functions on this toolchain, so the
// surface lives here as global trampolines; the concrete island type is bound
// through `webui_island_bind` — a symbol the island module MUST define (its
// main declares a matching `@_silgen_name("webui_island_bind")` shim calling
// `IslandRuntime<I>.run()`). binding is lazy: the first stateful export call
// touches the unbound handler and triggers the shim, so NO entry-point
// execution is required (the embedded `_start` is a no-op stub — measured).

/// the buffer discipline: one frame + one input buffer per wasm instance,
/// lazily allocated on first export call like the hand-written probe.
enum IslandRuntimeBuffers {
	static let frameCapacity = 1 << 18
	static let inputCapacity = 1 << 16
	nonisolated(unsafe) static let frame = UnsafeMutableRawPointer.allocate(byteCount: frameCapacity, alignment: 16)
	nonisolated(unsafe) static let input = UnsafeMutableRawPointer.allocate(byteCount: inputCapacity, alignment: 16)
	nonisolated(unsafe) static var frameLength = 0

	/// writeFrame(text): the region/ack/json path (clamped at capacity).
	static func writeText(_ text: String) {
		let n = min(text.utf8.count, frameCapacity)
		text.withCString { c in
			frame.copyMemory(from: UnsafeRawPointer(c), byteCount: n)
		}
		frameLength = n
	}

	/// writeFrameBytes: the op-stream batch path.
	static func writeBytes(_ bytes: [UInt8]) {
		bytes.withUnsafeBufferPointer { buf in
			frame.copyMemory(from: UnsafeRawPointer(buf.baseAddress!), byteCount: buf.count)
		}
		frameLength = bytes.count
	}
}

/// the runtime-facing, non-generic export handler — erases the per-island core
/// behind an existential so the global trampolines stay generic-free.
protocol IslandExportHandler {
	func renderRegion(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int
	func onEvent(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int
	func takeOps() -> UInt32
	func stateSave() -> Int
	func stateRestore(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int
}

/// reference box for the reactor core: the handler methods mutate it from a
/// non-mutating existential call (embedded Swift forbids mutating `self`
/// through `any P`, and a value copy would leak cross-call state).
final class IslandRuntimeCoreBox<I: IslandRuntimeSurface> {
	var core: IslandRuntimeCore<I>
	init() { core = IslandRuntimeCore<I>() }
}

/// the per-island bridge: holds the reactor core and copies payloads into the
/// physical frame buffer.
struct IslandRuntimeBridge<I: IslandRuntimeSurface>: IslandExportHandler {
	let box: IslandRuntimeCoreBox<I>

	init() { box = IslandRuntimeCoreBox() }

	func renderRegion(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
		guard let ptr, len > 0 else { return 0 }
		if let payload = box.core.renderRegion(input: Self.copyBytes(ptr: ptr, len: len)) {
			IslandRuntimeBuffers.writeBytes(payload)
		}
		return Int(bitPattern: IslandRuntimeBuffers.frame)
	}

	func onEvent(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
		guard let ptr, len > 0 else { return 0 }
		_ = box.core.onEvent(input: Self.copyBytes(ptr: ptr, len: len))
		return Int(bitPattern: IslandRuntimeBuffers.frame)
	}

	func takeOps() -> UInt32 {
		guard let batch = box.core.takeOps() else { return 0 }
		IslandRuntimeBuffers.writeBytes(batch)
		return UInt32(batch.count)
	}

	func stateSave() -> Int {
		IslandRuntimeBuffers.writeBytes(box.core.stateSave())
		return Int(bitPattern: IslandRuntimeBuffers.frame)
	}

	func stateRestore(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
		guard let ptr, len > 0 else { return 0 }
		if let payload = box.core.stateRestore(input: Self.copyBytes(ptr: ptr, len: len)) {
			IslandRuntimeBuffers.writeBytes(payload)
		}
		return Int(bitPattern: IslandRuntimeBuffers.frame)
	}

	private static func copyBytes(ptr: UnsafeRawPointer, len: Int) -> [UInt8] {
		UnsafeRawBufferPointer(start: ptr, count: len).map { $0 }
	}
}

nonisolated(unsafe) var islandHandler: (any IslandExportHandler)? = nil

/// the binding hook the island module provides (defined in the island's main
/// via `@_silgen_name("webui_island_bind")`; resolved at wasm link time).
@_silgen_name("webui_island_bind")
func webuiIslandBind()

@inline(never)
private func ensureBound() {
	if islandHandler == nil {
		webuiIslandBind()
	}
}
#endif

// MARK: - the public runtime entry

/// the DX-1 runtime slice, parameterized by a `ContinuumIsland`-typed island
/// (via `IslandRuntimeSurface`).
public enum IslandRuntime<I: IslandRuntimeSurface> {
	/// installs the per-island export handler. the island's main declares a
	/// `@_silgen_name("webui_island_bind")` shim calling this; the first
	/// stateful export call triggers it lazily (idempotent).
	public static func run() {
		#if os(WASI)
		if islandHandler == nil {
			islandHandler = IslandRuntimeBridge<I>()
		}
		#endif
	}

	/// the EXTRA-exports helper: writes `payload` to the frame buffer and
	/// returns the frame pointer (`webui_frame_ptr`), matching the other
	/// exports' return convention. per-island EXTRA exports (e.g. the parity
	/// gate's `webui_run_corpus`) are one-line global `@_expose` shims in the
	/// island's main that call this — the red-team's extensibility requirement:
	/// the runtime's export surface is open, extras survive the conversion.
	///
	/// stateful extras that need the retained core go through the handler in
	/// lockstep overloads of this entry; stateless diagnostics like the corpus
	/// use this direct path.
	@discardableResult
	public static func writeExport(_ payload: String) -> Int {
		#if os(WASI)
		IslandRuntimeBuffers.writeText(payload)
		return Int(bitPattern: IslandRuntimeBuffers.frame)
		#else
		_ = payload
		return 0
		#endif
	}

	/// the lockstep EXTRA-export entry for INPUT-DRIVEN extras (DX-2:
	/// `webui_validate`). the island's shim hands the raw input buffer
	/// (`webui_input_ptr`-style pointer + length, exactly like the standard
	/// exports receive), the runtime decodes it scalar-clean and calls
	/// `compute`, then writes the returned payload to the frame. empty input
	/// returns 0 without touching the frame — matching the hand-written
	/// validate export's `guard let ptr, len > 0 else { return 0 }`.
	@discardableResult
	public static func writeExport(
		input ptr: UnsafeRawPointer?, _ len: Int,
		compute: (String) -> String
	) -> Int {
		#if os(WASI)
		guard let ptr, len > 0 else { return 0 }
		let bytes = UnsafeRawBufferPointer(start: ptr, count: len).map { $0 }
		return writeExport(compute(utf8Decode(bytes)))
		#else
		_ = (ptr, len, compute)
		return 0
		#endif
	}
}

// MARK: - the standard export trampolines (all eight, runtime-owned)

#if os(WASI)
@_expose(wasm, "webui_input_ptr")
func webuiInputPtr() -> Int {
	Int(bitPattern: IslandRuntimeBuffers.input)
}

@_expose(wasm, "webui_frame_ptr")
func webuiFramePtr() -> Int {
	Int(bitPattern: IslandRuntimeBuffers.frame)
}

@_expose(wasm, "webui_frame_len")
func webuiFrameLen() -> Int {
	IslandRuntimeBuffers.frameLength
}

@_expose(wasm, "webui_render_region")
func webuiRenderRegion(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
	ensureBound()
	return islandHandler?.renderRegion(ptr, len) ?? 0
}

@_expose(wasm, "webui_on_event")
func webuiOnEvent(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
	ensureBound()
	return islandHandler?.onEvent(ptr, len) ?? 0
}

@_expose(wasm, "webui_take_ops")
func webuiTakeOps() -> UInt32 {
	ensureBound()
	return islandHandler?.takeOps() ?? 0
}

@_expose(wasm, "webui_state_save")
func webuiStateSave() -> Int {
	ensureBound()
	return islandHandler?.stateSave() ?? 0
}

@_expose(wasm, "webui_state_restore")
func webuiStateRestore(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
	ensureBound()
	return islandHandler?.stateRestore(ptr, len) ?? 0
}
#endif

// MARK: - DX-9 — the runtime-side element-id dev check (CONTINUUM_DX §2.9)
//
// every op an island emits must target an element id its render/reduce pair
// actually knows: a drifted id (a typo like `probe-coutner`) is silently
// dropped by the engine at runtime, which is exactly the bug class this check
// catches at dev time, on the island side.
//
// the check is a dev-time assertion, NOT a type guarantee (d-docs §DX-9): an
// op's target is only knowable against the island's declared id vocabulary
// (`IslandRuntimeSurface.elementIDs` + the `isKnownElementID` dynamic-family
// override; W3: the @HotView macro emits `elementIDs`), and interpolated ids
// (`probe-item-k<n>`) can only be validated by the island's own family
// predicate — never at compile time.
//
// ENFORCEMENT IS BUILD-FLAG GATED: `-DCONTINUUM_ID_CHECK` (or
// `.define("CONTINUUM_ID_CHECK")` in a consumer manifest / package) compiles
// the assertion AND the vocabulary surface into the build; production builds
// omit them entirely (zero runtime tax, I4). the pure detection logic below
// compiles either way, so the native suite covers the same code the gated
// builds execute (d-docs §DX-9: "the check is a dev-time assertion").
//
// failure mode in a check build: the diagnostic (naming the id) is written
// into the wasm frame buffer — readable from a harness after the trap — then
// the runtime traps. a loud dev-time failure, never a silent drop.
//
// WHY IN THIS FILE: the probe artifact is byte-anchored (the DX-1/DX-2
// regression anchor, 233,952 B) and the island objlib's link layout is
// sensitive to its compilation-unit set — adding a new source file (even a
// comment-only one) shifts the stripped artifact (measured: -229 B). this
// check therefore lives in the runtime slice's own unit; the always-compiled
// members below are dead-stripped from production builds unchanged.

public enum IslandIDCheck {
	/// the diagnostic prefix — grep-able in a dev harness's output.
	public static let diagnosticPrefix = "CONTINUUM_ID_CHECK"

	/// whether this build has the check compiled in. the enforcement entry
	/// (`enforce`/`fail`) only exists in check builds; this constant reflects
	/// the gating for dev tooling and the native suite.
	#if CONTINUUM_ID_CHECK
	public static let enforced = true
	#else
	public static let enforced = false
	#endif

	/// the element id an op operates on. insert targets its parent (the v1
	/// record's id slot carries the parent; the new element's id is
	/// engine-allocated on apply), text/attr/remove/move target the element.
	///
	/// `before` anchors are references, not targets, and are deliberately NOT
	/// checked — an over-eager check would false-positive on legitimate order
	/// anchors (conservative; the emitted-op contract is target-based).
	public static func target(of op: HotOp) -> ElementID {
		switch op {
		case .text(let id, _): return id
		case .attr(let id, _, _): return id
		case .insert(let parent, _, _): return parent
		case .remove(let id): return id
		case .move(let id, _): return id
		}
	}

	/// the first op whose target is not a known id, as a diagnostic naming the
	/// id — or nil when every target is known. pure (no side effects), so the
	/// native suite drives exactly this function.
	public static func firstViolation(ops: [HotOp], isKnown: (ElementID) -> Bool) -> String? {
		for op in ops {
			let id = target(of: op)
			if !isKnown(id) {
				return "\(diagnosticPrefix): op targets unknown element id '\(id.raw)' — not in the island's id vocabulary (elementIDs + isKnownElementID families). fix the id or declare it (dev-time check; compiled out in production)."
			}
		}
		return nil
	}
}

#if CONTINUUM_ID_CHECK
public extension IslandIDCheck {
	/// the gated enforcement entry: traps on the first unknown op target. the
	/// runtime calls this after `reduce` collects an event's ops; any future
	/// mount-op path must route through it too.
	static func enforce(_ ops: [HotOp], isKnown: (ElementID) -> Bool) {
		if let violation = firstViolation(ops: ops, isKnown: isKnown) {
			fail(violation)
		}
	}

	/// the dev-time failure: write the diagnostic into the frame buffer so a
	/// harness can read it after the trap, then trap. (`fatalError` prints on
	/// a native check build and is a plain trap inside wasm.)
	static func fail(_ message: String) -> Never {
		#if os(WASI)
		IslandRuntimeBuffers.writeText(message)
		#endif
		fatalError(message)
	}
}
#endif