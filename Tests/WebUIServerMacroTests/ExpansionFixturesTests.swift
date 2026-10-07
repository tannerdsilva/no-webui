import Testing

// the live-data macro suite — the byte-exact expansion fixtures.
//
// the "expected" text in every fixture is the REAL expander's output,
// captured to disk and frozen verbatim (never hand-written): `assertMacroExpansion`
// compares after re-indenting with `.spaces(4)`, so the captured bytes are the
// authoritative value. a divergence between the macro and its frozen contract
// fails here — see the harness-can-fail demonstration (dx2-notes/m-macros.md).

@Suite("the live-data macros — the frozen expansions (captured, byte-exact)")
struct ExpansionFixturesTests {
	@Test(arguments: frozenFixtures)
	func expansionMatchesTheFrozenCapture(fixture: FrozenFixture) {
		assertExpansion(fixture.source, expanded: fixture.expanded)
	}
}
