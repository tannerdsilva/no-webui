import Foundation
import Testing
import WebUICore
import WebUIState

// the byte win, measured — not asserted as a shape.
//
// stage 0 proved the *shape* of a fragment (`SpineFragmentTests`: one control in,
// one fragment out). this suite proves the *size*: a page carrying thirty-eight
// controls ships one control's bytes when one control changes, and the number is
// reported so a regression reads as a number rather than a boolean.
//
// the page is a dashboard on purpose: real content around the controls, so the
// ratio means what the product gate means — the fragment is a sliver of the page,
// not a sliver of a three-element toy.

/// a page with thirty-eight controls over a body of static rows.
private struct DashboardPage: StatefulPage {
	struct State: Sendable, Equatable {
		/// the one control's own value: mutating it changes exactly one of the
		/// thirty-eight controls and nothing else.
		var label = "select"
		/// outside every control: this value's bytes are residue, and the
		/// differ must refuse to patch it.
		var heading = "fleet"
	}

	func initialState() -> State { State() }

	func body(_ state: State) -> some View {
		VStack {
			Heading(state.heading)
			Paragraph("thirty-eight controls over four hundred rows of text.")
			ForEach(0..<38) { index in
				Div {
					Span { Text("node \(index)") }
					Button(index == 7 ? state.label : "select")
						.onClick(perform: { _ in [] })
				}
			}
			ForEach(0..<400) { row in
				Paragraph("row \(row): a line of text that no click touches.")
			}
		}
	}
}

/// how often `needle` occurs in `text`.
private func occurrences(of needle: String, in text: String) -> Int {
	text.components(separatedBy: needle).count - 1
}

/// a ratio as a percentage with three decimals, for an assertion's message.
private func percent(_ part: Int, of whole: Int) -> String {
	String(format: "%.3f", 100 * Double(part) / Double(max(whole, 1)))
}

@Suite("the fragment budget — 38 controls")
struct FragmentByteBudgetTests {
	private func makeLoop(
		_ session: String
	) -> (StatefulPageSession<DashboardPage>, RenderContext) {
		let context = RenderContext(router: EventRouter(), session: RenderSessionID(session))
		return (StatefulPageSession(DashboardPage()), context)
	}

	@Test("a one-control mutation ships under 2 % of the page's bytes")
	func oneControlMutationIsUnderTwoPercent() throws {
		let (loop, context) = makeLoop("byte-budget-control")
		let first = try #require(loop.patch(in: context))
		#expect(first.fragments.isEmpty, "a first render has nothing to diff against")
		#expect(first.isFullPage)
		#expect(occurrences(of: "data-component-id=", in: first.html) == 38)

		try loop.store.mutate { $0.label = "selected" }
		let patch = try #require(loop.patch(in: context))

		let shipped = patch.fragments.reduce(0) { $0 + $1.html.utf8.count }
		let page = patch.html.utf8.count
		#expect(patch.fragments.count == 1, "one control moved, so one fragment")
		#expect(patch.fragments.first?.id == "c7")
		#expect(shipped > 0)
		// shipped * 50 < page is "under 2 %" without floating point.
		#expect(
			shipped * 50 < page,
			"one control shipped \(shipped) B of a \(page) B page — \(percent(shipped, of: page)) %, ceiling 2 %"
		)

		// small is not the whole claim: the fragment applied to the previous
		// render reproduces the new one byte for byte, so the client's patched
		// DOM and a full re-render are the same bytes.
		let snapshot = RenderSnapshot.derived(fromMarkup: first.html)
		let previousBytes = try #require(snapshot.regionHTML(RegionID(rawValue: "c7")))
		let shippedHTML = try #require(patch.fragments.first).html
		#expect(first.html.replacingOccurrences(of: previousBytes, with: shippedHTML) == patch.html)
	}

	@Test("a change outside every control cannot be shipped as fragments")
	func outOfRegionChangeIsAFullPage() throws {
		let (loop, context) = makeLoop("byte-budget-residue")
		let first = try #require(loop.patch(in: context))

		try loop.store.mutate { $0.heading = "fleet (renamed)" }
		let patch = try #require(loop.patch(in: context))

		#expect(patch.fragments.isEmpty, "no fragment can carry bytes the client has no element for")
		#expect(patch.html.contains("fleet (renamed)"))

		// the reason is the differ's own, not a shortcut taken here: the same
		// bytes diffed against the first render's baseline are a full page.
		let verdict = RenderDiffer(previous: RenderSnapshot.derived(fromMarkup: first.html).baseline)
			.patch(RenderSnapshot.derived(fromMarkup: patch.html))
		#expect(verdict.isFullPage)
		#expect(verdict.changed.isEmpty)
	}
}
