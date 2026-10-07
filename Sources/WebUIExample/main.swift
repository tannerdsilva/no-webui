import Foundation
import Synchronization
import WebUI
import WebUIDesignSystem
import WebUIServer

// MARK: - Shared state

final class ExampleState: Sendable {
	private struct Values {
		var count = 0
		var echo = ""
	}
	private let values = Mutex(Values())

	var count: Int {
		get { values.withLock { $0.count } }
		set { values.withLock { $0.count = newValue } }
	}
	var echo: String {
		get { values.withLock { $0.echo } }
		set { values.withLock { $0.echo = newValue } }
	}
}

// MARK: - Display-element renderers (stable ids, no event handlers)

func counterValueHTML(_ n: Int) -> String {
	"<div id=\"counter-value\" class=\"counter-value\" role=\"status\"><span>\(n)</span></div>"
}

func echoOutHTML(_ text: String) -> String {
	let safe = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
	return "<div id=\"echo-out\" class=\"echo-out\" role=\"status\"><span class=\"echo-out__text\">\(safe)</span></div>"
}

// MARK: - the substitution demo — DX-12 seam + DX-14 outcomes (conforming types, no layers)
//
// every control below is wired through the framework's generic entry point
// `control(_:event:handler:)`. the handler states *what it yields* (one update,
// several, a `View`, region invalidations, nothing, or a combination) and the
// framework adapts it to the one wire substrate. nothing here re-implements a
// layer the framework now hosts — the no-layer audit's evidence.

/// render a stable button-like control through the generic seam. the handler's
/// RETURN TYPE fixes `O` — a bare `{ _ in [] }` cannot infer it (rev4/A2), so
/// every call site annotates.
func demoControl<O: EventOutcome>(
	_ label: String,
	id: String,
	variant: String = "button--secondary",
	handler: @escaping @Sendable (EventData) async -> O
) -> String {
	let attributes = control(id, event: .click, handler: handler)
	return "<button type=\"button\" class=\"button \(variant) button--md\"\(attributes)>\(label)</button>"
}

/// SWAP (1) — the control the page serves initially. its handler renders a
/// NEW control (`g-swap-stage2`) inside the handler body; because dispatch
/// runs inside the seam (`RenderContext.withCurrent`), that render has a
/// render context and the nested control self-registers. the pre-i0 state
/// cannot do this: the dispatch path had no render context, so a control
/// first rendered by a handler was dead (`WebUIServer.swift:661`).
func swapStage1HTML() -> String {
	let wire = demoControl("swap in a stage-2 control", id: "g-swap") { (event: EventData) -> [FragmentUpdate] in
		[FragmentUpdate(id: "g-swap-panel", html: swapStage2HTML())]
	}
	return """
	<div class="demo-cell">
	  <p class="demo-note">stage 1 — click to swap in a stage-2 control rendered by this handler.</p>
	  \(wire)
	</div>
	"""
}

func swapStage2HTML() -> String {
	let wire = demoControl("back to stage 1", id: "g-swap-stage2", variant: "button--primary") { (event: EventData) -> [FragmentUpdate] in
		[FragmentUpdate(id: "g-swap-panel", html: swapStage1HTML())]
	}
	return """
	<div class="demo-cell">
	  <p class="demo-note">stage 2 — I was rendered inside a handler; a later click reaches me anyway.</p>
	  \(wire)
	</div>
	"""
}

/// ViewOutcome (2) — `resolve` renders `Content` and replaces `#<component id>`.
/// contract (rev4/a2): the control's replaceable ROOT must carry that DOM id, so
/// the cell's root div carries `id="g-outcome"` beside the routing attributes.
/// the update's fragment id therefore appears in the served markup's id set.
func outcomeCellHTML() -> String {
	let wire = control("g-outcome", event: .click) { (event: EventData) -> ViewOutcome<Div> in
		ViewOutcome(
			Div(class: "demo-replaced") {
				Text("replaced by ViewOutcome — the update's fragment id (g-outcome) is in the served markup")
			}
		)
	}
	return """
	<div id="g-outcome" class="demo-cell demo-cell--outcome"\(wire)>
	  <p class="demo-note">idle — click to replace this cell with a View.</p>
	</div>
	"""
}

// MARK: - the four live-region drivers (DX-13 regions + DX-16 state)
//
// every driver below is a conforming type passed in — the substitution law
// applied to live data. the registry owns rendering, change detection, cadence
// and pump lifetime; the demo owns only the region definitions.

/// a monotonic render counter for the closure default: each render is a NEW
/// value, so an invalidate produces a frame. the other three drivers render
/// state, so an unchanged render pushes nothing — that silence is what the
/// demo's I7 probe asserts against them.
final class RegionTick: Sendable {
	private let state = Mutex(0)
	func next() -> Int { state.withLock { $0 += 1; return $0 } }
}

/// (2) a custom `LiveRegion` STRUCT the framework has never seen, over a
/// `LiveBox`. it publishes the box as its `source`, so a write wakes it through
/// the registry's subscribe hook with no consumer wiring.
struct DemoStructRegion: LiveRegion {
	let id: String
	let box: LiveBox<Int>

	/// invalidation-driven: no cadence, and the box is the subscription hook.
	var cadence: Duration? { nil }
	var source: (any LiveState)? { box }

	func render() async -> String? {
		let value = box.value
		return DemoRegions.html(id: id, label: "custom LiveRegion struct", value: value)
	}
}

/// (4) a custom `LiveState` ACTOR the framework has never seen. its `subscribe`
/// witness is `nonisolated` (d-x7): the actor forwards to an embedded
/// `LiveNotifier`, so the registry's synchronous subscribe never hops onto the
/// actor and cannot block `start()`.
actor DemoFeedState: LiveState {
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

/// the demo's live-data surface: four drivers — one per mechanism — and the
/// states their controls mutate.
struct DemoRegions: Sendable {
	let tick = RegionTick()
	let structBox = LiveBox(0)
	let stateBox = LiveBox(0)
	let feed = DemoFeedState()

	static func html(id: String, label: String, value: Int) -> String {
		"<div id=\"\(id)\" class=\"demo-region\">\(label) — value \(value)</div>"
	}

	/// protocol values in, framework machinery out: the closure default, the
	/// custom struct, the state-bound default over a `LiveBox`, and the custom
	/// `LiveState` actor.
	var registry: WebUILiveRegions {
		let tick = self.tick
		let structBox = self.structBox
		let stateBox = self.stateBox
		let feed = self.feed
		return WebUILiveRegions([
			ClosureLiveRegion(id: "g-region-a") { () async -> String? in
				DemoRegions.html(id: "g-region-a", label: "closure default", value: tick.next())
			},
			DemoStructRegion(id: "g-region-b", box: structBox),
			StateLiveRegion(id: "g-region-c", state: stateBox) { box in
				let value = box.value          // one snapshot, before any await
				return DemoRegions.html(id: "g-region-c", label: "StateLiveRegion<LiveBox>", value: value)
			},
			StateLiveRegion(id: "g-region-d", state: feed) { state in
				let value = await state.snapshot()
				return DemoRegions.html(id: "g-region-d", label: "custom LiveState actor", value: value)
			},
		])
	}

	/// the regions' baseline markup, drawn into the page so the fragment ids
	/// exist in the DOM before any push arrives. the registry pushes nothing at
	/// start (baselines are internal), so the page owns this.
	var baselineHTML: String {
		DemoRegions.html(id: "g-region-a", label: "closure default", value: 0)
			+ DemoRegions.html(id: "g-region-b", label: "custom LiveRegion struct", value: structBox.value)
			+ DemoRegions.html(id: "g-region-c", label: "StateLiveRegion<LiveBox>", value: stateBox.value)
			+ DemoRegions.html(id: "g-region-d", label: "custom LiveState actor", value: 0)
	}

	/// lane D additive: the four hand-written region definitions as an array, so
	/// the server's ONE registry can carry the macro twin beside the control
	/// group (WebUIServer takes a single `WebUILiveRegions`). `registry` above is
	/// unchanged — the hand path keeps its exact spelling and byte behavior.
	var regionList: [any LiveRegion] {
		[
			ClosureLiveRegion(id: "g-region-a") { () async -> String? in
				DemoRegions.html(id: "g-region-a", label: "closure default", value: tick.next())
			},
			DemoStructRegion(id: "g-region-b", box: structBox),
			StateLiveRegion(id: "g-region-c", state: stateBox) { box in
				let value = box.value
				return DemoRegions.html(id: "g-region-c", label: "StateLiveRegion<LiveBox>", value: value)
			},
			StateLiveRegion(id: "g-region-d", state: feed) { state in
				let value = await state.snapshot()
				return DemoRegions.html(id: "g-region-d", label: "custom LiveState actor", value: value)
			},
		]
	}

	/// one control per driver. (a) is invalidate-driven — its handler declares the
	/// change through `RegionInvalidations`, which reaches the registry through
	/// the dispatch seam's `OutcomeContext.invalidate`; (b)–(d) mutate their own
	/// state, so the registry's `source` subscription wakes them.
	var controlsHTML: String {
		let structBox = self.structBox
		let stateBox = self.stateBox
		let feed = self.feed
		var html = demoControl("nudge g-region-a", id: "g-region-nudge") { (_: EventData) -> RegionInvalidations in
			RegionInvalidations(["g-region-a"])
		}
		// the d-k ordering control: a COMBINED outcome — one update AND an
		// invalidation. the registry defers the wake until the handler frame is on
		// the wire, so the fragment must arrive BEFORE the region's push.
		html += demoControl("fragment + invalidate", id: "g-region-combined") {
			(_: EventData) -> CombinedOutcome<FragmentUpdate, RegionInvalidations> in
			CombinedOutcome(
				FragmentUpdate(id: "g-combined-out", html: "<span id=\"g-combined-out\">fragment written first</span>"),
				RegionInvalidations(["g-region-a"])
			)
		}
		html += demoControl("bump g-region-b", id: "g-region-b-bump") { (_: EventData) -> NoOutcome in
			structBox.value += 1
			return NoOutcome()
		}
		html += demoControl("bump g-region-c", id: "g-region-c-bump") { (_: EventData) -> NoOutcome in
			stateBox.value += 1
			return NoOutcome()
		}
		html += demoControl("bump g-region-d", id: "g-region-d-bump") { (_: EventData) -> NoOutcome in
			await feed.bump()
			return NoOutcome()
		}
		return html
	}
}

// MARK: - the macro twin (MACRO_DX lane D) — the same four mechanisms, macro-spelled
//
// the substitution law's demonstration on the demo page: every mechanism the
// hand path spells above has a macro-driven twin here, attached BESIDE it in the
// server's one registry. the twins share the page and are driven in the same run
// (g-regions.mjs's macro drivers) and are asserted byte-equal by MacroParityTests.
// the hand-written control group is untouched; nothing here is required by the
// framework — the macros are a veneer over the frozen protocols.

/// the macro-driven variant of `DemoRegions`, declared with the four macros:
/// `@LiveRegions` generates the assembly (`registry`), `@LiveRegion(id:) +
/// @RegionState` generate the custom-struct conformance and its `source` hook,
/// `@LiveState` generates the actor's nonisolated `subscribe`/`notify` plumbing.
@LiveRegions
struct MacroDemoRegions: Sendable {
	/// the monotonic render counter for the closure twin — reached through the
	/// type, because a stored property's initializer cannot reference a sibling
	/// (i0 note), and a static is skipped by the assembly's classification.
	static let tick = RegionTick()

	/// (2) a custom `LiveRegion` STRUCT, macro-spelled: the conformance, `id`,
	/// `cadence` and the `source` hook are generated; the marked property IS the
	/// source — the same contract `DemoStructRegion` spells by hand.
	@LiveRegion(id: "g-mreg-b")
	struct MacroStructRegion {
		@RegionState let box: LiveBox<Int>

		func render() async -> String? {
			let value = box.value
			return MacroDemoRegions.html(id: "g-mreg-b", label: "custom LiveRegion struct", value: value)
		}
	}

	/// (4) a custom `LiveState` ACTOR, macro-spelled: `subscribe` (nonisolated,
	/// by construction) and `notify()` are generated — the same contract
	/// `DemoFeedState` spells by hand.
	@LiveState
	actor MacroDemoFeed {
		private var value = 0

		func bump() {
			value += 1
			notify()
		}

		func snapshot() -> Int { value }
	}

	// (1) the closure default twin — invalidate-driven, a fresh value per render.
	let clock = ClosureLiveRegion(id: "g-mreg-a") { () async -> String? in
		MacroDemoRegions.html(id: "g-mreg-a", label: "closure default", value: MacroDemoRegions.tick.next())
	}
	// (2) the custom struct twin, state bound inline (a stored initializer cannot
	// reference a sibling property — i0 note).
	let structRegion = MacroStructRegion(box: LiveBox(0))
	// (3) the `StateLiveRegion<LiveBox>` twin, state inline for the same reason.
	let boxRegion = StateLiveRegion(id: "g-mreg-c", state: LiveBox(0)) { box in
		let value = box.value
		return MacroDemoRegions.html(id: "g-mreg-c", label: "StateLiveRegion<LiveBox>", value: value)
	}
	// (4) the `StateLiveRegion<LiveState>` twin over the generated actor.
	let feedRegion = StateLiveRegion(id: "g-mreg-d", state: MacroDemoFeed()) { state in
		let value = await state.snapshot()
		return MacroDemoRegions.html(id: "g-mreg-d", label: "custom LiveState actor", value: value)
	}

	/// the macro regions' markup — the SAME template the hand path renders, so a
	/// macro frame differs from its hand twin only in the id substring (the
	/// page-level twin: byte-equal under the g-mreg-* ↔ g-region-* mapping).
	static func html(id: String, label: String, value: Int) -> String {
		DemoRegions.html(id: id, label: label, value: value)
	}
}

// MARK: - the macro twin's page surface (rendering lives in an extension — the
// `@LiveRegions` assembly inspects the group's stored properties only)

extension MacroDemoRegions {
	/// lane D additive: the four macro region instances, in the assembly's
	/// declaration order — composed with the hand control group's `regionList`
	/// into the server's ONE `WebUILiveRegions` (the same members the generated
	/// `registry` classifies and assembles; listing them here only because the
	/// frozen server takes a single registry).
	var regionList: [any LiveRegion] {
		[clock, structRegion, boxRegion, feedRegion]
	}

	/// the twin baselines, drawn beside the hand ones so the macro fragment ids
	/// exist in the DOM before any push arrives.
	var baselineHTML: String {
		MacroDemoRegions.html(id: "g-mreg-a", label: "closure default", value: 0)
			+ MacroDemoRegions.html(id: "g-mreg-b", label: "custom LiveRegion struct", value: structRegion.box.value)
			+ MacroDemoRegions.html(id: "g-mreg-c", label: "StateLiveRegion<LiveBox>", value: boxRegion.state.value)
			+ MacroDemoRegions.html(id: "g-mreg-d", label: "custom LiveState actor", value: 0)
	}

	/// one control per macro twin driver, ids read by g-regions.mjs's macro
	/// siblings (same push/quiet contract as the hand controls: an unchanged
	/// render pushes nothing, a change pushes exactly one update).
	var controlsHTML: String {
		var html = demoControl("nudge g-mreg-a", id: "g-mreg-nudge") { (_: EventData) -> RegionInvalidations in
			RegionInvalidations(["g-mreg-a"])
		}
		html += demoControl("fragment + invalidate", id: "g-mreg-combined") {
			(_: EventData) -> CombinedOutcome<FragmentUpdate, RegionInvalidations> in
			CombinedOutcome(
				FragmentUpdate(id: "g-mreg-combined-out", html: "<span id=\"g-mreg-combined-out\">macro fragment written first</span>"),
				RegionInvalidations(["g-mreg-a"])
			)
		}
		html += demoControl("bump g-mreg-b", id: "g-mreg-b-bump") { (_: EventData) -> NoOutcome in
			self.structRegion.box.value += 1
			return NoOutcome()
		}
		html += demoControl("bump g-mreg-c", id: "g-mreg-c-bump") { (_: EventData) -> NoOutcome in
			self.boxRegion.state.value += 1
			return NoOutcome()
		}
		html += demoControl("bump g-mreg-d", id: "g-mreg-d-bump") { (_: EventData) -> NoOutcome in
			await self.feedRegion.state.bump()
			return NoOutcome()
		}
		return html
	}
}

// MARK: - Page assembly (renders interactive views, registers handlers)

func renderExamplePage(state: ExampleState, router: EventRouter, regions: DemoRegions, macroRegions: MacroDemoRegions) -> String {
	// the seam (DX-12): the framework establishes the render context for the
	// whole page build, exactly as it does for the dispatch path — the demo
	// host must not re-implement what the framework now hosts.
	let body = RenderContext.withCurrent(router: router) {
		Div(class: "app") {
			Header(class: "app__header") {
				Heading("WebUI Live Demo", level: .h1)
			}
			Main(class: "app__content") {
				WebUICard(variant: .elevated) {
					Heading("Counter", level: .h3)
					Raw(counterValueHTML(state.count))
					Div(class: "app__actions") {
						WebUIButton("−", variant: .secondary, size: .md, id: "btn-dec", onTap: { _ in
							state.count -= 1
							return [FragmentUpdate(id: "counter-value", html: counterValueHTML(state.count))]
						})
						WebUIButton("+", variant: .primary, size: .md, id: "btn-inc", onTap: { _ in
							state.count += 1
							return [FragmentUpdate(id: "counter-value", html: counterValueHTML(state.count))]
						})
						WebUIButton("Reset", variant: .ghost, size: .sm, id: "btn-reset", onTap: { _ in
							state.count = 0
							return [FragmentUpdate(id: "counter-value", html: counterValueHTML(0))]
						})
					}
				}
				WebUICard(variant: .outlined) {
					Heading("Echo (input → server → DOM)", level: .h3)
					WebUIInput(placeholder: "Type something…", id: "echo-input", label: "Input")
						.onInput { event in
							state.echo = event.string("value") ?? ""
							return [FragmentUpdate(id: "echo-out", html: echoOutHTML(state.echo))]
						}
					Raw(echoOutHTML(state.echo))
				}
				WebUICard(variant: .outlined) {
					Heading("The substitution demo — DX-12 seam + DX-14 outcomes", level: .h3)
					Div(class: "demo-stack") {
						Heading("(1) SWAP — a handler renders a NEW control", level: .h4)
						Raw(swapStage1HTML())
						Heading("(2) ViewOutcome — replace my tagged root with a View", level: .h4)
						Raw(outcomeCellHTML())
						Heading("(3) RegionInvalidations — the handler declares the change", level: .h4)
						Div(class: "demo-cell") {
							Raw(regions.controlsHTML)
						}
						Heading("(4) four live-region drivers — closure · struct · LiveBox · custom LiveState", level: .h4)
						Div(class: "demo-cell") {
							Raw(regions.baselineHTML)
						}
						Heading("(5) the macro twin — the same four mechanisms, macro-spelled (@LiveRegions)", level: .h4)
						Div(class: "demo-cell") {
							Raw(macroRegions.controlsHTML)
						}
						Div(class: "demo-cell") {
							Raw(macroRegions.baselineHTML)
						}
					}
				}
			}
			Footer(class: "app__footer") {
				Text("every click and keystroke round-trips over the WebSocket and repaints.")
			}
		}.render()
	}
	// page-scoped layout: the shared sheet leaves the example's shell classes
	// unstyled, so give them token-based defaults here (after the sheet, so a
	// host can still override them via its own cascade without touching the
	// design system).
	return WebUIDocument(title: "WebUI Live Demo", body: body, rawStyles: [
		".app { max-width: 960px; margin: 0 auto; padding: var(--space-8); }",
		".app__header { padding-bottom: var(--space-4); }",
		".app__content { display: flex; flex-direction: column; gap: var(--space-4); }",
		".app__footer { padding-top: var(--space-4); color: var(--color-text-muted); }",
		".app__actions { display: flex; align-items: center; gap: var(--space-2); }",
		".demo-stack { display: flex; flex-direction: column; gap: var(--space-4); }",
		".demo-cell { border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: var(--space-3); }",
		".demo-cell--outcome { min-height: 72px; }",
		".demo-note { color: var(--color-text-muted); font-size: var(--font-size-sm); margin-bottom: var(--space-2); }",
		".demo-replaced { color: var(--color-accent-600); font-weight: 500; }",
		".demo-region { color: var(--color-text-muted); font-size: var(--font-size-sm); padding: var(--space-1) 0; }",
	], themeStylesheetURL: demoThemeSheet().url).render()
}

/// the emitted sheet as a value: the document links `url`, the server serves those
/// exact bytes at it, and the address is computed from the bytes — so the two
/// cannot disagree (a mismatch would be a stylesheet 404, silent in the cascade).
/// `DemoCatalogSheet` is generated from `DemoCatalog` by the framework's
/// `WebUIThemePlugin` on every build: mechanism (a), where the whole consumer
/// surface is one plugin line plus the catalog.
func demoThemeSheet() -> ThemeSheet {
	ThemeSheet(
		css: String(decoding: DemoCatalogSheet.body, as: UTF8.self),
		gzip: DemoCatalogSheet.gzip
	)
}

// MARK: - HTTP / WebSocket server (WebUIServer)

@main
struct WebUIExample {
	static func main() async throws {
		let state = ExampleState()
		let router = EventRouter()
		let regions = DemoRegions()
		let macroRegions = MacroDemoRegions()
		let server = WebUIServer(
			render: { renderExamplePage(state: state, router: router, regions: regions, macroRegions: macroRegions) },
			router: router,
			config: WebUIServerConfig(
				port: intFlag(named: "--port", default: 9090),
				// the emitted theme sheet, served at its content address (paired with
				// the document's `themeStylesheetURL` above).
				themeSheet: demoThemeSheet(),
				// the generated engine slice (continuum §1.5): the engine fetches
				// it at boot and swaps its conservative attr seed for it.
				assets: [
					WebUIAsset(ContinuumEngineManifest.self, path: "/ui/continuum-manifest.json").registration
				]
			),
			// the live-region registry (DX-13 + MACRO_DX lane D): the hand-written
			// control group (g-region-a..d) and the macro twin (g-mreg-a..d) ride
			// the SAME server as one WebUILiveRegions — the substitution law's two
			// spellings, driven in the same run. the hand path's `registry` above
			// stays byte-identical; `regionList` is the additive composition seam.
			regions: WebUILiveRegions(regions.regionList + macroRegions.regionList)
		)
		try await server.start()
	}

	/// parse a positive-integer flag (`--name N`) with a fallback.
	static func intFlag(named name: String, default fallback: Int) -> Int {
		if let i = CommandLine.arguments.firstIndex(of: name),
		   i + 1 < CommandLine.arguments.count,
		   let v = Int(CommandLine.arguments[i + 1]), v > 0 {
			return v
		}
		return fallback
	}
}
