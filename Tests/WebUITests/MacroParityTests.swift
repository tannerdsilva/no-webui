import Foundation
import Synchronization
import Testing
import WebUI
import WebUIServer
@testable import WebUIServer

// MARK: - MacroParityTests — the substitution law's twins (MACRO_DX lane D, feature E)
//
// the substitution law, applied to live data: for the same input sequence, the
// macro-spelled variant and the hand-written variant must produce BYTE-EQUAL
// frames — same ids, same html, same order — through the SAME seam the hand path
// uses (the registry's start/render/push path), never a bespoke comparison
// harness. the WebUIExample executable is not importable, so both spellings are
// declared here one-for-one, mirroring the demo's `DemoStructRegion` /
// `DemoFeedState` / `DemoRegions` (the compiled runtime fixtures prove the same
// macro shapes in the macro test target).
//
// byte-equality is asserted two ways: the recorded `[FragmentUpdate]` batches
// must be `==` element-for-element (id + html + order — FragmentUpdate is
// Equatable), and the frames re-encoded through the SAME encoder the wire uses
// (`WSOutgoing.update(...)` → jsonText) must be string-identical.

// MARK: - the shared markup template (ONE spelling, both variants render it)

private enum ParityHTML {
	/// one template both variants render — different spellings, identical bytes.
	static func region(id: String, label: String, value: Int) -> String {
		"<div id=\"\(id)\" class=\"parity-region\">\(label) — value \(value)</div>"
	}
}

// MARK: - the HAND-WRITTEN variant (the control group's shapes, hand-spelled)

/// a `LiveRegion` STRUCT by hand — the `DemoStructRegion` twin (id/cadence/source
/// + conformance, written out).
private struct HandTwinRegion: LiveRegion {
	let id: String
	let cadence: Duration?
	let box: LiveBox<Int>

	var source: (any LiveState)? { box }

	func render() async -> String? {
		let value = box.value
		return ParityHTML.region(id: id, label: "custom LiveRegion struct", value: value)
	}
}

/// a `LiveState` ACTOR by hand — the `DemoFeedState` twin (nonisolated subscribe
/// forwarding to its own `LiveNotifier`, d-x7).
private actor HandTwinState: LiveState {
	private let notifier = LiveNotifier()
	private var value = 0

	nonisolated func subscribe(_ onChange: @escaping @Sendable () -> Void) -> LiveSubscription {
		notifier.add(onChange)
	}

	func bump() {
		value += 1
		notifier.notify()
	}

	func snapshot() -> Int { value }
}

/// a monotonic render counter for the twins' closure default — one per VARIANT,
/// so the two spellings advance in lockstep from the same seed (a shared counter
/// would make them diverge; an instance one is unreachable from a macro-injected
/// stored initializer — the i0 note's sibling rule).
private final class HandTick: Sendable {
	private let state = Mutex(0)
	func next() -> Int { state.withLock { $0 += 1; return $0 } }
	func reset() { state.withLock { $0 = 0 } }
}

// MARK: - the MACRO variant — the same four mechanisms, macro-spelled

/// the macro assembly: `registry` is GENERATED from the property list (a computed
/// var, by the frozen syntactic classification), and `@LiveRegion`/@RegionState`
/// generate `StructTwin`'s conformance + witnesses while `@LiveState` generates
/// `StateTwin`'s subscribe/notify plumbing.
@LiveRegions
struct MacroParityRegions: Sendable {
	// (1) the closure default — a fresh value per render from a monotonic source
	// (the demo uses `RegionTick`); a STATIC because a stored initializer cannot
	// reference a sibling and the assembly skips statics (i0 note). exposed reset
	// keeps the twin test deterministic across runs in one process.
	private static let tick = HandTick()
	static func next() -> Int { tick.next() }
	static func resetTick() { tick.reset() }

	// (2) a custom `LiveRegion` STRUCT — the `DemoStructRegion` twin, macro-spelled.
	@LiveRegion(id: "parity-b")
	struct StructTwin {
		@RegionState let box: LiveBox<Int>

		func render() async -> String? {
			let value = box.value
			return ParityHTML.region(id: "parity-b", label: "custom LiveRegion struct", value: value)
		}
	}

	// (4) a custom `LiveState` ACTOR — the `DemoFeedState` twin, macro-spelled.
	@LiveState
	actor StateTwin {
		private var value = 0

		func bump() {
			value += 1
			notify()
		}

		func snapshot() -> Int { value }
	}

	// the four drivers, in the same declaration order as the hand assembly.
	let clock = ClosureLiveRegion(id: "parity-a") { () async -> String? in
		ParityHTML.region(id: "parity-a", label: "closure default", value: MacroParityRegions.next())
	}
	let structTwin = StructTwin(box: LiveBox(0))
	let boxDefault = StateLiveRegion(id: "parity-c", state: LiveBox(0)) { box in
		let value = box.value
		return ParityHTML.region(id: "parity-c", label: "StateLiveRegion<LiveBox>", value: value)
	}
	let actorDefault = StateLiveRegion(id: "parity-d", state: StateTwin()) { state in
		let value = await state.snapshot()
		return ParityHTML.region(id: "parity-d", label: "custom LiveState actor", value: value)
	}
}

// MARK: - the registry harness (the SAME seam the hand path uses)

/// starts a registry against an injected push recorder and runs its workers as
/// tasks — the identical harness `LiveRegionsTests` uses for the hand path.
private final class ParityHarness: Sendable {
	let registry: WebUILiveRegions
	let recorder: PushRecorder
	private let tasks: [Task<Void, Never>]

	init(_ regions: [any LiveRegion]) async {
		let router = EventRouter()
		let recorder = PushRecorder()
		let registry = WebUILiveRegions(regions)
		let work = await registry.start(router: router, push: { updates in
			recorder.record(updates)
		})
		self.registry = registry
		self.recorder = recorder
		self.tasks = work.map { closure in Task { await closure() } }
	}

	func stop() async {
		registry.stop()
		for task in tasks { await task.value }
	}
}

/// records every batch of fragments the registry pushes, thread-safely.
private final class PushRecorder: Sendable {
	private let state = Mutex<[[FragmentUpdate]]>([])

	func record(_ updates: [FragmentUpdate]) { state.withLock { $0.append(updates) } }
	var count: Int { state.withLock { $0.count } }
	var fragments: [FragmentUpdate] { state.withLock { $0.flatMap { $0 } } }
	var batches: [[FragmentUpdate]] { state.withLock { $0 } }
}

private func paritySettle(_ milliseconds: Int = 90) async {
	try? await Task.sleep(for: .milliseconds(milliseconds))
}

// MARK: - the twins

@Suite("the macro twins — parity (MACRO_DX feature E)", .serialized)
struct MacroParityTests {

	@Test("the generated types conform — @LiveRegion · @LiveState · @LiveRegions resolve")
	func conformance() {
		// the extension macro emitted `: LiveRegion` and `: LiveState` — these
		// conversions compile only if the conformance exists.
		let group = MacroParityRegions()
		let regionValue: any LiveRegion = group.structTwin
		let stateValue: any LiveState = MacroParityRegions.StateTwin()
		let registryValue: WebUILiveRegions = group.registry
		#expect(regionValue.id == "parity-b")
		#expect(registryValue.currentHTML("parity-a") == nil, "nothing is committed before start")
		#expect(stateValue is MacroParityRegions.StateTwin)
	}

	@Test("byte-equal frames: the macro variant and the hand variant under the same sequence")
	func byteEqualFrames() async {
		// ── the two spellings, carrying the same four mechanisms in the same order ──
		MacroParityRegions.resetTick()
		let handTick = HandTick()
		let handBoxB = LiveBox(0)
		let handBoxC = LiveBox(0)
		let handActor = HandTwinState()
		let handRegions: [any LiveRegion] = [
			ClosureLiveRegion(id: "parity-a") { () async -> String? in
				ParityHTML.region(id: "parity-a", label: "closure default", value: handTick.next())
			},
			HandTwinRegion(id: "parity-b", cadence: nil, box: handBoxB),
			StateLiveRegion(id: "parity-c", state: handBoxC) { box in
				ParityHTML.region(id: "parity-c", label: "StateLiveRegion<LiveBox>", value: box.value)
			},
			StateLiveRegion(id: "parity-d", state: handActor) { state in
				let value = await state.snapshot()
				return ParityHTML.region(id: "parity-d", label: "custom LiveState actor", value: value)
			},
		]
		let macro = MacroParityRegions()
		let macroRegions: [any LiveRegion] = [
			macro.clock,
			macro.structTwin,
			macro.boxDefault,
			macro.actorDefault,
		]

		let handHarness = await ParityHarness(handRegions)
		let macroHarness = await ParityHarness(macroRegions)

		// baseline silence on both spellings (r-to-d 1): nothing is pushed at start.
		#expect(handHarness.recorder.count == 0)
		#expect(macroHarness.recorder.count == 0)

		// ── the SAME input sequence through the registry's own seam ──
		// (1) invalidate the closure default  ·  (2)+(3) box writes reach the
		// `source` subscription  ·  (4) an actor bump wakes the actor-bound region.
		for seq in 1...4 {
			switch seq {
			case 1:
				handHarness.registry.invalidate("parity-a")
				macroHarness.registry.invalidate("parity-a")
			case 2:
				handBoxB.value += 1
				macro.structTwin.box.value += 1
			case 3:
				handBoxC.value += 1
				macro.boxDefault.state.value += 1
			case 4:
				await handActor.bump()
				await macro.actorDefault.state.bump()
			default:
				break
			}
			await paritySettle()

			let handFragments = handHarness.recorder.fragments
			let macroFragments = macroHarness.recorder.fragments

			// SAME ids, SAME html, SAME order — content equality first…
			#expect(macroFragments == handFragments, "seq \(seq): macro frames == hand frames (ids + html + order)")

			// …then byte-for-byte equality of the frames as encoded. `FragmentUpdate`
			// is the wire type; a deterministic encoder (sorted keys) proves the two
			// variants produce IDENTICAL bytes for the same sequence (the server's own
			// `jsonText` is not a stable comparison target — it emits dictionary keys
			// in hash order, so its byte output is not reproducible per call).
			let handWire = try? sortedBytes(handFragments)
			let macroWire = try? sortedBytes(macroFragments)
			#expect(macroWire != nil && macroWire == handWire, "seq \(seq): the frames encode to byte-identical json")
		}

		// the whole recorded batch-by-batch streams are byte-equal, and both sides
		// pushed the same number of frames (the recording order is the push order).
		#expect(macroHarness.recorder.batches == handHarness.recorder.batches)
		#expect(macroHarness.recorder.count == handHarness.recorder.count)

		// I7 quiet, on both spellings alike: an unchanged render pushes NOTHING.
		let quietHand = handHarness.recorder.count
		let quietMacro = macroHarness.recorder.count
		handHarness.registry.invalidate("parity-b")
		macroHarness.registry.invalidate("parity-b")
		await paritySettle()
		#expect(handHarness.recorder.count == quietHand, "hand: unchanged render pushes nothing")
		#expect(macroHarness.recorder.count == quietMacro, "macro: unchanged render pushes nothing")

		await handHarness.stop()
		await macroHarness.stop()
	}
}

/// the wire type's bytes under a deterministic (sorted-keys) encoder — byte-equal
/// across the two variants even though the server's own jsonText orders dictionary
/// keys by hash (non-reproducible per call).
private func sortedBytes(_ fragments: [FragmentUpdate]) throws -> [UInt8] {
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.sortedKeys]
	return try [UInt8](encoder.encode(fragments))
}
