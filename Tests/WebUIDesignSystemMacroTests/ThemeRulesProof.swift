import Testing
import WebUI
import WebUIDesignSystem
import WebUIDesignSystemCore

// MARK: - the DX-15b typed-rules proof (W1; lane T)
//
// the anti-shadow policy says chrome rides `@Theme(rules:)` as `[CSSRule]`
// (string-typed selectors, vetted by the lint) instead of a raw-string sheet.
// the proof: for the chip family, the typed `[CSSRule]` rendering is
// BYTE-IDENTICAL to the equivalent raw-string sheet — the same bytes a
// consumer's hand-written chrome sheet would have shipped.
//
// (typed is nominal — C4 — so the equality is the point: a consumer converts
// their raw chip sheet to CSSRule values and the shipped bytes must not move.
// the lint (WebUIContinuumTool `shadow`) vets the selector tokens.)

// MARK: - the chip family, two ways

/// the chip family as chrome historically wrote it: a raw CSS string. the
/// blank lines between rule blocks are part of the canonical CSSStylesheet
/// render — that IS the byte-identity contract.
let rawChipSheet = """
.chip {
  display: inline-flex;
  align-items: center;
  gap: 0.375rem;
  border-radius: 9999px;
}

.chip--primary {
  background: var(--color-primary-solid);
  color: var(--color-on-primary-solid);
}

.chip__label {
  font-size: 0.8125rem;
  line-height: 1;
}

.chip__remove {
  border: none;
  background: transparent;
  cursor: pointer;
}
"""

/// the same family as typed `[CSSRule]` values ride-able on `@Theme(rules:)`.
let chipRules: [CSSRule] = [
	CSSRule(".chip", [
		CSSDeclaration("display", "inline-flex"),
		CSSDeclaration("align-items", "center"),
		CSSDeclaration("gap", "0.375rem"),
		CSSDeclaration("border-radius", "9999px"),
	]),
	CSSRule(".chip--primary", [
		CSSDeclaration("background", "var(--color-primary-solid)"),
		CSSDeclaration("color", "var(--color-on-primary-solid)"),
	]),
	CSSRule(".chip__label", [
		CSSDeclaration("font-size", "0.8125rem"),
		CSSDeclaration("line-height", "1"),
	]),
	CSSRule(".chip__remove", [
		CSSDeclaration("border", "none"),
		CSSDeclaration("background", "transparent"),
		CSSDeclaration("cursor", "pointer"),
	]),
]

/// the raw-string sheet as the framework renders it (CSSStylesheet render is
/// the canonical form both sides must agree on for byte-identity).
let canonicalRawChipSheet = CSSStylesheet(chipRules).render()

/// the same family rode on `@Theme(rules:)` — file-scope (an extension macro
/// cannot attach to a local type).
@Theme
struct ChipTheme {
	static let rules: [CSSRule] = chipRules
}

@Suite("DX-15b: the chip-family typed-rules proof")
struct ThemeRulesProofTests {

	@Test("the typed rules render byte-identical to the raw-string sheet")
	func typedRulesByteIdenticalToRawSheet() {
		let typed = WebUITheme(rules: chipRules)
		// the theme's stylesheet embeds the rules exactly as CSSStylesheet
		// renders them — the same bytes the raw string ships.
		let rendered = typed.stylesheet(scope: .root)
		#expect(rendered.contains(canonicalRawChipSheet))
		if canonicalRawChipSheet != rawChipSheet {
			print("CANONICAL:<<" + canonicalRawChipSheet + ">>")
			print("RAW:<<" + rawChipSheet + ">>")
		}
		#expect(canonicalRawChipSheet == rawChipSheet, "the raw sheet must be the canonical render — that is the byte-identity contract")
		#expect(rendered == canonicalRawChipSheet, "a rule-only theme's stylesheet is exactly the sheet")
	}

	@Test("@Theme(rules:) rides the same typed values")
	func themeMacroRidesTypedRules() {
		#expect(ChipTheme.theme.rules == chipRules)
		#expect(ChipTheme.theme.stylesheet(scope: .root) == canonicalRawChipSheet)
	}

	@Test("the twin: a hand-written provider (no @Theme) + overlaying composes to the same bytes")
	func handWrittenProviderTwin() {
		// the twin is a WebUIThemeProvider written by hand — no macro — whose
		// theme layers the chip family over a base via `overlaying`.
		struct BaseProvider: WebUIThemeProvider {
			static let theme = WebUITheme(tokens: [.colorPrimarySolid: "#4f46e5"])
		}
		struct HandWrittenChips: WebUIThemeProvider {
			static let theme = BaseProvider.theme.overlaying(WebUITheme(rules: chipRules))
		}
		// the composition is a plain value; rendering it must equal rendering
		// the two layers in sequence — bytes identical to the layered theme.
		let layered = BaseProvider.theme.overlaying(WebUITheme(rules: chipRules))
		#expect(HandWrittenChips.theme == layered)
		#expect(HandWrittenChips.theme.rules == chipRules)
		#expect(HandWrittenChips.theme.palette.tokens[.colorPrimarySolid] == "#4f46e5")
		// the chip family survives the overlay byte-identically.
		#expect(HandWrittenChips.theme.stylesheet(scope: .root).contains(canonicalRawChipSheet))
	}
}
