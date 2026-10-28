import Testing
import WebUICore
import WebUIState

// `PageDiffer` is the consumer-facing door: one value owns the baseline, the
// exclusions, the transition flag and the root-replace fallback, so a consumer
// (arc's web UI) never re-implements the differ's tail.
//
// the fixture is the live-turn page: the two spans a token writer owns are
// excluded, and everything else is structural. that shape is the one that
// makes a differ useful at all — a streaming token must not force a page
// replace, and a structural render inside the same node must not drag the
// whole root along with it.

private let policy = RegionPolicy(
	identity: .elementID, coverage: .finest,
	escalation: .nearestTrackedAncestor,
	excluded: ["live-turn-text", "live-turn-thinking"],
	transition: false)

private func page(text: String = "a", busy: String = "0") -> String {
	#"<div id="app" data-component-id="app"><div id="live-turn" data-component-id="live-turn" data-busy="\#(busy)"><span id="live-turn-text" data-component-id="live-turn-text">\#(text)</span><b id="live-turn-thinking" data-component-id="live-turn-thinking">t</b></div><div id="panel" data-component-id="panel">p</div></div>"#
}

@Test("an unseeded differ sends the root")
func unseededSendsRoot() {
	let differ = PageDiffer(policy: policy)
	let frames = differ.messages(forMarkup: page(), root: "app")
	#expect(frames.count == 1, "a first render has no baseline to patch against")
	#expect(frames.first?.id == "app")
	#expect(frames.first?.html == page())
	#expect(frames.first?.transition == false)
}

@Test("seeded + unchanged sends nothing")
func seededUnchangedSendsNothing() {
	let differ = PageDiffer(policy: policy)
	differ.seed(withMarkup: page())
	let frames = differ.messages(forMarkup: page(), root: "app")
	#expect(frames.isEmpty, "a byte-identical render must put nothing on the wire")
}

@Test("a token-only change in an excluded span sends nothing")
func excludedTokenChangeSendsNothing() {
	let differ = PageDiffer(policy: policy)
	differ.seed(withMarkup: page(text: "a"))
	let frames = differ.messages(forMarkup: page(text: "abc"), root: "app")
	#expect(
		frames.isEmpty,
		"#live-turn-text is written by op:text on every streaming token; an html replace would fight that writer")
}

@Test("a structural change inside the live node sends only that node")
func structuralChangeInsideLiveNodeShipsOnlyThatNode() {
	let differ = PageDiffer(policy: policy)
	differ.seed(withMarkup: page(busy: "0"))
	let frames = differ.messages(forMarkup: page(busy: "1"), root: "app")
	#expect(
		frames.map(\.id) == ["live-turn"],
		"the excluded children must not drag #app into the patch")
}

@Test("an unexpressible change falls back to the root")
func unexpressibleChangeFallsBackToRoot() {
	let differ = PageDiffer(policy: policy)
	let before = page()
	differ.seed(withMarkup: before)
	// bytes outside every region move the residue, and no region can carry
	// them: only a whole-root replace puts them on screen.
	let after = before + "<p>tail</p>"
	let frames = differ.messages(forMarkup: after, root: "app")
	#expect(frames.count == 1)
	#expect(frames.first?.id == "app")
	#expect(frames.first?.html == after)
}

@Test("reset makes the next render a whole-root replace")
func resetForcesWholeRootReplace() {
	let differ = PageDiffer(policy: policy)
	differ.seed(withMarkup: page())
	#expect(differ.messages(forMarkup: page(), root: "app").isEmpty)
	differ.reset()
	let frames = differ.messages(forMarkup: page(), root: "app")
	#expect(frames.map(\.id) == ["app"], "a forgotten baseline must resend, never under-send")
}
