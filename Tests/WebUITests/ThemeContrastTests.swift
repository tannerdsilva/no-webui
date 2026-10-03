import Testing
import WebUI
import WebUIDesignSystem

// MARK: - contrast sweep
//
// the sweep is the subject here, not these palettes: a consumer supplies their own themes
// and the loop is the same. hand-built `WebUITheme` values rather than `@Theme` fixtures,
// because this target does not link the macro plugin.

private let goodLight = ThemePalette(tokens: [
	.colorBg: "#FFFFFF",
	.colorText: "#111111",
	.colorTextMuted: "#5A5A5A",
	.colorPrimarySolid: "#7A4F00",
	.colorOnPrimarySolid: "#FFFFFF",
])

private let goodDark = ThemePalette(tokens: [
	.colorBg: "#101014",
	.colorText: "#F2F2F2",
	.colorTextMuted: "#A8A8B0",
	.colorPrimarySolid: "#B9A0FF",
	.colorOnPrimarySolid: "#14121F",
])

/// `#EDEDED` text on white is about 1.17:1 — the kind of palette that ships a bug.
private let illegibleLight = ThemePalette(tokens: [
	.colorBg: "#FFFFFF",
	.colorText: "#EDEDED",
])

@Suite("ThemeContrast")
struct ThemeContrastTests {

	@Test("ratio matches the WCAG anchors, and shorthand hex expands")
	func anchors() {
		#expect(abs((ThemeContrast.ratio("#000000", "#FFFFFF") ?? 0) - 21.0) < 0.01)
		#expect(abs((ThemeContrast.ratio("#FFFFFF", "#FFFFFF") ?? 0) - 1.0) < 0.01)
		#expect(ThemeContrast.ratio("#000", "#fff") == ThemeContrast.ratio("#000000", "#FFFFFF"))
	}

	@Test("an unresolvable colour reports nothing rather than guessing")
	func unresolvable() {
		#expect(ThemeContrast.ratio("var(--color-bg)", "#FFFFFF") == nil)
		#expect(ThemeContrast.ratio("rgba(0,0,0,0.5)", "#FFFFFF") == nil)
		#expect(ThemeContrast.ratio("#12345", "#FFFFFF") == nil)
	}

	@Test("the sweep clears a well-formed theme on BOTH palettes")
	func sweepPassesGoodTheme() {
		#expect(ThemeContrast.audit(WebUITheme(palette: goodLight, dark: goodDark)).isEmpty)
	}

	@Test("the sweep fails a theme that ships an illegible palette")
	func sweepFailsBadTheme() {
		let failures = ThemeContrast.audit(WebUITheme(palette: illegibleLight))
		#expect(!failures.isEmpty, "a ~1.17:1 pair must not pass AA")
		#expect(failures.contains { $0.contains("color-text") && $0.contains("light") },
			"the failure must name the mode and the pair: \(failures)")
	}

	@Test("a bad DARK palette is reported against the dark mode, not the light one")
	func darkFailuresAreAttributedToDark() {
		let failures = ThemeContrast.audit(WebUITheme(palette: goodLight, dark: illegibleLight))
		#expect(failures.allSatisfy { $0.hasPrefix("dark:") }, "got \(failures)")
	}

	@Test("a partial theme is audited only on the pairs it completes")
	func partialThemeSkipsIncompletePairs() {
		// only an accent: no ink-on-surface pair can be evaluated. substituting the shipped
		// sheet's values for the tokens it does not set would report failures the theme is
		// not responsible for, so nothing is reported.
		let accentOnly = WebUITheme(palette: ThemePalette(tokens: [.colorPrimarySolid: "#7A4F00"]))
		#expect(ThemeContrast.audit(accentOnly).isEmpty)
	}

	@Test("sweeping a catalog is a loop — which is the whole point of typing themes")
	func sweepOverACatalogIsALoop() {
		// arc's shape: many schemes, each with a light and a dark palette.
		let catalog: [WebUITheme] = [
			WebUITheme(palette: goodLight, dark: goodDark),
			WebUITheme(palette: goodLight),
			WebUITheme(palette: goodDark, defaultMode: .dark),
		]
		for (index, theme) in catalog.enumerated() {
			#expect(ThemeContrast.audit(theme).isEmpty, "scheme \(index) fails AA")
		}
		// and it still catches a bad one inside the same loop, so the sweep cannot pass
		// vacuously.
		let withBad: [WebUITheme] = catalog + [WebUITheme(palette: illegibleLight)]
		let failures = withBad.enumerated().flatMap { index, theme in
			ThemeContrast.audit(theme).map { "\(index): \($0)" }
		}
		#expect(failures.count == 1, "expected exactly one failing scheme, got \(failures)")
	}
}
