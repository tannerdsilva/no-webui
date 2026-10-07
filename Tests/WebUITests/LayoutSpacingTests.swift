import Testing
import WebUI

// MARK: - G1 — the typed-layout spacing correctness fix (MACRO_DX)
//
// `VStack`/`HStack` emit `class="… spacing-N …"` but only the scale
// `LayoutStyles.spacingScale` ships rules — so an off-scale value (e.g.
// spacing: 7) used to render silently gapless. the fix: in-scale values keep
// the class emission byte-for-byte; off-scale values drop the dead class and
// carry `gap:Npx` inline, the same shape `Grid` already emits.
//
// these fixtures are the proof the brief demands: `spacing: 7` renders a real
// 7px gap AND every in-scale value stays byte-unchanged.

@Suite("G1 spacing: off-scale renders a real gap, in-scale stays byte-unchanged")
struct LayoutSpacingTests {

	// the shipped scale, mirrored here so a change to `LayoutStyles.spacingScale`
	// fails this suite until its fixture rows are updated deliberately.
	private let scale = [0, 2, 4, 8, 12, 16, 20, 24, 32]

	@Test("off-scale VStack(spacing: 7) renders a real inline gap")
	func offScaleVStackGap() {
		let html = VStack(spacing: 7) { Text("a"); Text("b") }.render()
		#expect(html.contains("style=\"gap:7px;\""), "expected an inline 7px gap, got: \(html)")
		#expect(!html.contains("spacing-7"), "the dead spacing-7 class must not ship: \(html)")
		#expect(html.contains("class=\"vstack align-flex-start\""), "base+alignment classes must stay: \(html)")
	}

	@Test("off-scale HStack(spacing: 7) renders a real inline gap")
	func offScaleHStackGap() {
		let html = HStack(spacing: 7) { Text("a"); Text("b") }.render()
		#expect(html.contains("style=\"gap:7px;\""), "unexpected html: \(html)")
		#expect(!html.contains("spacing-7"))
		#expect(html.contains("class=\"hstack align-center\""))
	}

	@Test("every in-scale value renders byte-identically to the class emission")
	func inScaleByteUnchanged() {
		for n in scale {
			let vhtml = VStack(spacing: n) { Text("a") }.render()
			#expect(
				vhtml == "<div class=\"vstack spacing-\(n) align-flex-start\">\na\n</div>",
				"in-scale spacing \(n) must keep the class form byte-for-byte, got: \(vhtml)"
			)
			#expect(!vhtml.contains("style="), "in-scale values carry no inline style")
			let hhtml = HStack(spacing: n) { Text("a") }.render()
			#expect(
				hhtml == "<div class=\"hstack spacing-\(n) align-center\">\na\n</div>",
				"in-scale HStack spacing \(n) must stay byte-identical, got: \(hhtml)"
			)
		}
	}

	@Test("the default spacing (8) is unchanged")
	func defaultSpacingUnchanged() {
		#expect(VStack { Text("a"); Text("b") }.render()
			== "<div class=\"vstack spacing-8 align-flex-start\">\nab\n</div>")
	}

	@Test("the shipped sheet ships the scale rules and no off-scale rule")
	func shippedSheetHasOnlyScaleRules() {
		let sheet = CSSStylesheet(LayoutStyles.complete).render()
		for n in scale {
			#expect(sheet.contains(".spacing-\(n) {"), "missing .spacing-\(n) rule in the shipped sheet")
		}
		#expect(!sheet.contains(".spacing-7 {"), "no .spacing-7 rule may ship — the gap is inline")
		#expect(!sheet.contains(".spacing-3 {"), "no .spacing-3 rule may ship — the gap is inline")
		#expect(!sheet.contains(".spacing-6 {"), "no .spacing-6 rule may ship — the gap is inline")
	}

	@Test("Grid keeps emitting its inline gap as before (regression)")
	func gridUnchanged() {
		#expect(Grid(spacing: 9) { Text("g") }.render()
			== "<div class=\"grid\" style=\"display:grid;grid-template-columns:repeat(2, 1fr);gap:9px;\">\ng\n</div>")
	}
}

// MARK: - G2 — the five typed-surface gaps (MACRO_DX)
//
// measured zero-coverage in the consumer sheet (justify-content 55 · flex-basis
// 27 · align-self · position 39 · z-index 17) — these are the named modifiers a
// migration writes instead of an inline `style="…"`. token-typed where a scale
// exists: flex-basis rides the `SpaceToken` scale.

@Suite("G2 typed layout gaps: the five named modifiers")
struct TypedSurfaceGapsTests {

	@Test("justifyContent emits justify-content inline")
	func justifyContent() {
		#expect(Text("x").justifyContent(.spaceBetween).render()
			== "<span style=\"justify-content: space-between;\">x</span>")
		#expect(Text("x").justifyContent(.flexEnd).render()
			== "<span style=\"justify-content: flex-end;\">x</span>")
		// the raw-string overload stays for values outside the enum.
		#expect(Text("x").justifyContent("safe center").render()
			== "<span style=\"justify-content: safe center;\">x</span>")
	}

	@Test("flexBasis emits flex-basis in px, token-typed on the space scale")
	func flexBasis() {
		#expect(Text("x").flexBasis(200).render()
			== "<span style=\"flex-basis: 200px;\">x</span>")
		// the token form references the shipped space variable, like padding.
		#expect(Text("x").flexBasis(.sixteen).render()
			== "<span style=\"flex-basis: var(--space-16);\">x</span>")
	}

	@Test("alignSelf emits align-self inline")
	func alignSelf() {
		#expect(Text("x").alignSelf(.flexEnd).render()
			== "<span style=\"align-self: flex-end;\">x</span>")
		#expect(Text("x").alignSelf(.stretch).render()
			== "<span style=\"align-self: stretch;\">x</span>")
	}

	@Test("position emits position inline")
	func position() {
		#expect(Text("x").position(.relative).render()
			== "<span style=\"position: relative;\">x</span>")
		#expect(Text("x").position(.absolute).render()
			== "<span style=\"position: absolute;\">x</span>")
	}

	@Test("zIndex emits z-index inline")
	func zIndex() {
		#expect(Text("x").zIndex(10).render()
			== "<span style=\"z-index: 10;\">x</span>")
		#expect(Text("x").zIndex(-1).render()
			== "<span style=\"z-index: -1;\">x</span>")
	}

	@Test("the five gaps compose with the existing style chain")
	func composesWithStyle() {
		#expect(
			Text("x").justifyContent(.center).zIndex(3).padding(4).render()
				== "<span style=\"justify-content: center; z-index: 3; padding: 4px;\">x</span>"
		)
	}

	@Test("fill() and stretch() still emit align-self: stretch (byte-unchanged)")
	func fillStretchKeepBytes() {
		#expect(Div { Text("x") }.fill().render()
			== "<div style=\"flex: 1 1 0%; min-width: 0; min-height: 0; align-self: stretch;\">x</div>")
		#expect(Div { Text("x") }.stretch().render()
			== "<div style=\"align-self: stretch; min-width: 0; min-height: 0;\">x</div>")
	}
}
