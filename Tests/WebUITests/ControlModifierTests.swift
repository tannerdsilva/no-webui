import Testing
import WebUI
import WebUISharedCore

// MARK: - `.control` — the first-class stable-id modifier
//
// the defect this closes (G7 #2): `.onClick(id:)` emits its routing pair only
// inside a `RenderContext`, and a push edge re-renders a fragment *outside*
// one — so the first replacement dropped `data-component-id` and the control
// went dead. `.control` splits the two halves on purpose:
//
//   * the routing pair is a property of the CONTROL and ships on every render,
//     inside a pass or not;
//   * registration is a property of the PASS and happens when there is one.
//
// the three cases below are exactly the three that mattered: outside a pass
// (attributes, no registration, no crash), inside one (both), and a fragment
// re-rendered outside after a page-build registration (the pair survives and
// the handler is still reachable).

@Suite("control modifier")
struct ControlModifierTests {

	/// the outcome the registered handler answers, so "did it route" is read
	/// off a value rather than inferred from a handler count.
	private static let answer = HandlerOutcome.redirect(to: "/routed", replace: false)

	private func click(_ id: String) -> EventData {
		EventData(component: ComponentID(id), event: .click)
	}

	// MARK: outside a pass

	@Test("outside a render context the pair is emitted and nothing is registered")
	func outsideContextEmitsWithoutRegistering() async {
		let router = EventRouter()
		// no `RenderContext.$current.withValue` anywhere in this call: this is
		// the shape a handler takes when it re-renders a fragment for a push.
		let html = Div { Text("x") }
			.control(id: "fx-refresh") { _ in .refresh }
			.markup.html

		#expect(html == "<div data-component-id=\"fx-refresh\" data-event=\"click\">x</div>")
		#expect(router.handlerCount == 0, "a render outside a pass registers nothing")
		#expect(router.hostHandlerCount == 0, "and it must not leak into the host table")

		// nothing answers the id: the dispatch is the empty fragment list, not
		// a crash and not a wrong registration.
		let outcome = await router.dispatch(click("fx-refresh"), in: .default)
		#expect(outcome.fragments.isEmpty)
	}

	@Test("the event is the caller's, not always click")
	func outsideContextHonoursTheEvent() {
		let html = Div { Text("x") }
			.control(id: "fx-save", on: .submit) { _ in .refresh }
			.markup.html
		#expect(html == "<div data-component-id=\"fx-save\" data-event=\"submit\">x</div>")
	}

	// MARK: inside a pass

	@Test("inside a render context the pair is emitted and the handler is registered")
	func insideContextRegistersAndEmits() async {
		let router = EventRouter()
		let session = RenderSessionID("control-modifier-inside")
		let context = RenderContext(router: router, session: session)
		let answer = Self.answer

		let html: String = RenderContext.$current.withValue(context) {
			Div { Text("x") }.control(id: "fx-go") { _ in answer }.markup.html
		}

		#expect(html == "<div data-component-id=\"fx-go\" data-event=\"click\">x</div>")
		#expect(router.handlerCount(in: session) == 1, "the pass registered the control")

		// and the registration is the handler, not a placeholder: the outcome
		// the closure returned is the outcome dispatch answers with.
		let outcome = await router.dispatch(click("fx-go"), in: session)
		#expect(outcome.navigates)
		if case .redirect(let to, let replace) = outcome {
			#expect(to == "/routed")
			#expect(replace == false)
		} else {
			Issue.record("expected the registered handler's redirect, got \(outcome)")
		}
	}

	@Test("a control registered for one session does not answer in another")
	func registrationIsScopedToItsSession() async {
		let router = EventRouter()
		let rendered = RenderSessionID("control-modifier-a")
		let other = RenderSessionID("control-modifier-b")
		let answer = Self.answer
		_ = RenderContext.$current.withValue(RenderContext(router: router, session: rendered)) {
			Div { Text("x") }.control(id: "fx-go") { _ in answer }.markup.html
		}

		#expect(router.handlerCount(in: rendered) == 1)
		#expect(router.handlerCount(in: other) == 0)
		let outcome = await router.dispatch(click("fx-go"), in: other)
		#expect(outcome.fragments.isEmpty, "another session's id must not route here")
	}

	// MARK: the re-render that motivated the modifier

	@Test("a fragment re-rendered outside the pass keeps the pair and the registration")
	func reRenderOutsideThePassKeepsThePair() async {
		let router = EventRouter()
		let session = RenderSessionID("control-modifier-rerender")
		let context = RenderContext(router: router, session: session)
		let answer = Self.answer

		// the page build: registered.
		let first: String = RenderContext.$current.withValue(context) {
			Div { Text("first") }.control(id: "fx-go") { _ in answer }.markup.html
		}
		#expect(first.contains("data-component-id=\"fx-go\""))
		#expect(router.handlerCount(in: session) == 1)

		// the push edge: the same fragment, re-rendered from inside a handler
		// where no context is installed. the pair must survive byte for byte.
		let second = Div { Text("second") }
			.control(id: "fx-go") { _ in answer }
			.markup.html
		#expect(
			second == "<div data-component-id=\"fx-go\" data-event=\"click\">second</div>",
			"a fragment re-render must not drop the routing pair; got \(second)"
		)
		#expect(router.handlerCount(in: session) == 1, "the re-render must not re-register a copy")

		// and the id still routes to the handler the page build installed.
		let outcome = await router.dispatch(click("fx-go"), in: session)
		if case .redirect(let to, _) = outcome {
			#expect(to == "/routed")
		} else {
			Issue.record("the re-rendered pair stopped routing: \(outcome)")
		}
	}

	// MARK: the fragment-returning door

	@Test("the fragments door forwards a 1.x handler through .fragments")
	func fragmentsDoorForwards() async {
		let router = EventRouter()
		let session = RenderSessionID("control-modifier-fragments")
		let context = RenderContext(router: router, session: session)
		let update = FragmentUpdate(id: "out", html: "<p id=\"out\">ok</p>")

		let html: String = RenderContext.$current.withValue(context) {
			Div { Text("x") }
				.control(id: "fx-save", fragments: { _ in [update] })
				.markup.html
		}
		#expect(html == "<div data-component-id=\"fx-save\" data-event=\"click\">x</div>")

		let outcome = await router.dispatch(click("fx-save"), in: session)
		#expect(outcome.fragments.map(\.id) == ["out"])
	}
}
