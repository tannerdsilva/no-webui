import Testing
import WebUICore
import WebUIState

// stage 0's fragment seam: the loop answers a patch with the per-control bytes
// that moved, and keeps the previous render's region hashes — never its html.
//
// the page under test splits its state on purpose: one value lives inside a
// control, one outside every control. the differ must patch the first and hand
// back the whole page for the second, and the loop must say which happened.

private struct SplitPage: StatefulPage {
	struct State: Sendable, Equatable {
		var label = "zero"
		var heading = "split"
	}

	func initialState() -> State { State() }

	func body(_ state: State) -> some View {
		VStack {
			Text(state.heading)
			Button(state.label).onClick(perform: { _ in [] })
		}
	}
}

@Suite("stage 0 — page patch fragments")
struct SpineFragmentTests {
	private func makeLoop(
		_ session: String
	) -> (StatefulPageSession<SplitPage>, RenderContext) {
		let context = RenderContext(router: EventRouter(), session: RenderSessionID(session))
		return (StatefulPageSession(SplitPage()), context)
	}

	@Test("a change confined to one control is one fragment, not a page")
	func controlChangeIsOneFragment() throws {
		let (loop, context) = makeLoop("spine-fragment-confined")
		let first = try #require(loop.patch(in: context))
		#expect(first.fragments.isEmpty, "a first render has nothing to diff against")
		#expect(first.isFullPage)
		#expect(first.html.contains("zero"))

		try loop.store.mutate { $0.label = "one" }
		let patch = try #require(loop.patch(in: context))

		#expect(!patch.isFullPage)
		#expect(patch.fragments.count == 1)
		#expect(patch.fragments.first?.id == "c0")
		#expect(patch.fragments.first?.html.contains("one") == true)
		#expect(patch.html.contains("one"), "html stays the whole page for a caller that wants it")
		#expect(loop.store.revision == 1)
	}

	@Test("a change outside every control cannot be a fragment")
	func outOfRegionChangeCarriesNoFragment() throws {
		let (loop, context) = makeLoop("spine-fragment-residue")
		let first = try #require(loop.patch(in: context))

		try loop.store.mutate { $0.heading = "renamed" }
		let patch = try #require(loop.patch(in: context))

		// no fragment can carry bytes the client has no element for, so the
		// honest answer is the page itself — `html` is it, and the caller sends
		// that instead of patching.
		#expect(patch.fragments.isEmpty)
		#expect(patch.html.contains("renamed"))

		// the reason is the differ's own, not a shortcut taken here: the same
		// bytes diffed against the first render's baseline are a full page.
		let prior = RenderSnapshot.derived(fromMarkup: first.html).baseline
		let verdict = RenderDiffer(previous: prior)
			.patch(RenderSnapshot.derived(fromMarkup: patch.html))
		#expect(verdict.isFullPage)
	}

	@Test("a re-render that changes nothing carries no fragments")
	func unchangedRenderCarriesNoFragments() throws {
		let (loop, context) = makeLoop("spine-fragment-unchanged")
		_ = try #require(loop.patch(in: context))

		let patch = try #require(loop.patch(in: context))
		#expect(patch.fragments.isEmpty)
		#expect(!patch.isFullPage)
	}

	@Test("the baseline is a per-session hash set, and a second session starts empty")
	func baselineIsPerSession() throws {
		let (first, firstContext) = makeLoop("spine-fragment-session-a")
		let (second, secondContext) = makeLoop("spine-fragment-session-b")

		_ = try #require(first.patch(in: firstContext))
		try first.store.mutate { $0.label = "one" }
		let patched = try #require(first.patch(in: firstContext))

		// the second session never rendered, so its first patch is a full page
		// however alike the two pages are — no baseline is shared between them.
		let fresh = try #require(second.patch(in: secondContext))
		#expect(fresh.isFullPage)
		#expect(fresh.fragments.isEmpty)
		#expect(patched.fragments.count == 1)
	}
}
