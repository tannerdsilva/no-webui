import Testing
import WebUICore
import WebUIState

// b5's gate (plan §6.6, read with §10.4's freeze): the store-aware modifier is
// proved on ten controls here, not in `Sources/WebUIAuthExample` — the example is
// frozen in stage 1 and agent F moves it onto this API in stage 2.
//
// the second half of the gate is negative: converting a handler to a mutation
// must not move a byte. `markupMatchesPlainHandler` renders the same page twice —
// once with `.onClick(binding)` and once with `.onClick(perform:)` — and compares
// the bytes, which is the local reading of "showcase byte-identical" (§14 N21).

@Suite("design b — state-mutating handlers")
struct DesignBModifierTests {
	/// ten controls, ten mutation-only handlers, zero bytes of html authored by a
	/// handler. every control mutates a *different* field so a crossed wire is
	/// visible.
	struct TenControlPage: StatefulPage {
		struct State: Sendable, Equatable {
			var increments = 0
			var decrements = 0
			var resets = 0
			var toggles = 0
			var flag = false
			var submitted = 0
			var typed = ""
			var changed = ""
			var keyed = 0
			var stepped = 0
		}

		func initialState() -> State { State() }

		func body(_ state: State) -> some View {
			VStack {
				// the page renders from its state, which is what gives a patch
				// bytes to move: without this the ten mutations would be real but
				// invisible, and the region hash would (correctly) not change.
				Text("increments \(state.increments) submitted \(state.submitted) typed \(state.typed) flag \(state.flag)")
				Button("increment").onClick(binding) { store in
					store.mutate { $0.increments += 1 }
				}
				Button("decrement").onClick(binding) { store in
					store.mutate { $0.decrements -= 1 }
				}
				Button("reset").onClick(binding) { store in
					store.mutate { $0.resets = 1 }
				}
				Button("toggle").onClick(binding) { store in
					store.mutate { $0.flag.toggle() }
				}
				Button("toggle-count").onClick(binding) { store in
					store.mutate { $0.toggles += 1 }
				}
				Button("submit").onSubmit(binding) { store in
					store.mutate { $0.submitted += 1 }
				}
				Input(placeholder: "typed").onInput(binding) { store in
					store.mutate { $0.typed = "typed" }
				}
				Input(placeholder: "changed").onChange(binding) { store in
					store.mutate { $0.changed = "changed" }
				}
				Button("keyed").on(.keydown, binding) { store in
					store.mutate { $0.keyed += 1 }
				}
				Button("stepped").onClick(binding) { store in
					store.mutate { $0.stepped += 1 }
				}
			}
		}
	}

	/// the same ten controls with the pre-design-b handler shape, for the
	/// byte-identity comparison.
	struct TenControlLegacyPage: StatefulPage {
		func initialState() -> TenControlPage.State { TenControlPage.State() }

		func body(_ state: TenControlPage.State) -> some View {
			VStack {
				Text("increments \(state.increments) submitted \(state.submitted) typed \(state.typed) flag \(state.flag)")
				Button("increment").onClick(perform: { _ in [] })
				Button("decrement").onClick(perform: { _ in [] })
				Button("reset").onClick(perform: { _ in [] })
				Button("toggle").onClick(perform: { _ in [] })
				Button("toggle-count").onClick(perform: { _ in [] })
				Button("submit").onSubmit(perform: { _ in [] })
				Input(placeholder: "typed").onInput(perform: { _ in [] })
				Input(placeholder: "changed").onChange(perform: { _ in [] })
				Button("keyed").on(.keydown, perform: { _ in [] })
				Button("stepped").onClick(perform: { _ in [] })
			}
		}
	}

	private func render<P: StatefulPage>(_ page: P, session: String) -> String {
		let router = EventRouter()
		let context = RenderContext(router: router, session: RenderSessionID(session))
		return StatefulPageSession(page).patch(in: context)?.html ?? ""
	}

	/// b5's gate: ten controls, each one a mutation, each one routable, and not a
	/// fragment authored anywhere.
	@Test("ten controls mutate state with zero manual html")
	func tenControlsMutateState() async throws {
		let router = EventRouter()
		let session = RenderSessionID("b5-ten")
		let context = RenderContext(router: router, session: session)
		let loop = StatefulPageSession(TenControlPage())

		let first = try #require(loop.patch(in: context))
		#expect(first.html.components(separatedBy: "data-component-id=").count - 1 == 10)
		#expect(router.handlerCount(in: session) == 10)

		// every control is its own minted id, in body order.
		let events: [(String, HTMLEvent)] = [
			("c0", .click), ("c1", .click), ("c2", .click), ("c3", .click), ("c4", .click),
			("c5", .submit), ("c6", .input), ("c7", .change), ("c8", .keydown), ("c9", .click),
		]
		for (id, event) in events {
			let fragments = await router.handle(EventData(component: ComponentID(id), event: event), in: session)
			#expect(fragments.isEmpty, "\(id) authored a fragment; a mutation-only handler cannot")
		}

		let state = loop.store.read()
		#expect(state.increments == 1)
		#expect(state.decrements == -1)
		#expect(state.resets == 1)
		#expect(state.flag)
		#expect(state.toggles == 1)
		#expect(state.submitted == 1)
		#expect(state.typed == "typed")
		#expect(state.changed == "changed")
		#expect(state.keyed == 1)
		#expect(state.stepped == 1)
		#expect(loop.store.revision == 10)

		// one patch for the ten commits, and the bytes carry the new state.
		let patch = try #require(loop.patch(in: context))
		#expect(patch.revision == 10)
		#expect(patch.changedRegions == [RegionID(rawValue: "body")])
	}

	/// the negative half: the modifier emits exactly the bytes the plain handler
	/// emits, so a handler change cannot move the showcase pin.
	@Test("the state modifier emits the same markup as the plain handler")
	func markupMatchesPlainHandler() {
		let stateHTML = render(TenControlPage(), session: "b5-state")
		let legacyHTML = render(TenControlLegacyPage(), session: "b5-legacy")
		#expect(stateHTML == legacyHTML)
	}

	/// a binding's revision is the one the render started from, and a mutation
	/// through it moves the store's revision — the loop's settle check depends on
	/// exactly that.
	@Test("a control's mutation moves the store revision the render saw")
	func controlMutationMovesRevision() async {
		struct OneButton: StatefulPage {
			func initialState() -> Int { 0 }
			func body(_ state: Int) -> some View {
				Button("bump").onClick(binding) { store in
					store.mutate { $0 += 1 }
				}
			}
		}

		let router = EventRouter()
		let session = RenderSessionID("b5-revision")
		let loop = StatefulPageSession(OneButton())
		_ = loop.patch(in: RenderContext(router: router, session: session))
		#expect(loop.store.revision == 0)

		_ = await router.handle(EventData(component: "c0", event: .click), in: session)
		#expect(loop.store.revision == 1)
		#expect(loop.store.read() == 1)
	}
}
