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

/// RegionInvalidations (3) — the handler declares the CHANGE (`g-region-a`);
/// `OutcomeContext.invalidate` reaches the live registry. at i0 the provider is
/// a no-op (no registry yet), so `resolve` carries no fragments; the end-to-end
/// registry push is asserted at i1 once lane R attaches `regions:`.
func regionNudgeHTML() -> String {
	let wire = demoControl("nudge g-region-a", id: "g-region-nudge") { (event: EventData) -> RegionInvalidations in
		RegionInvalidations(["g-region-a"])
	}
	return """
	<div class="demo-cell">
	  <p class="demo-note">region nudge — i0: the invalidate provider is a no-op, so resolve carries no fragments. i1 asserts the registry push.</p>
	  \(wire)
	</div>
	"""
}

// MARK: - Page assembly (renders interactive views, registers handlers)

func renderExamplePage(state: ExampleState, router: EventRouter) -> String {
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
						Heading("(3) RegionInvalidations — declares the change; i1 asserts the push", level: .h4)
						Raw(regionNudgeHTML())
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
	]).render()
}

// MARK: - HTTP / WebSocket server (WebUIServer)

@main
struct WebUIExample {
	static func main() async throws {
		let state = ExampleState()
		let router = EventRouter()
		let server = WebUIServer(
			render: { renderExamplePage(state: state, router: router) },
			router: router,
			config: WebUIServerConfig(
				port: intFlag(named: "--port", default: 9090),
				// the generated engine slice (continuum §1.5): the engine fetches
				// it at boot and swaps its conservative attr seed for it.
				assets: [
					WebUIAsset(ContinuumEngineManifest.self, path: "/ui/continuum-manifest.json").registration
				]
			)
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
