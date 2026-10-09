import Testing
import WebUI
import WebUIDesignSystem

// MARK: - a complete hand-written theme

/// a complete theme exercising every axis: the four token axes plus the palette.
/// omitting any of these would not compile — that is the completeness contract
/// the protocol enforces.
struct AccentTheme: DesignTheme {
	static var palette: ThemePalette {
		ThemePalette(tokens: [.colorPrimary500: "#268BD2", .colorBg: "#ffffff"])
	}
	static var spacing: TokenOverrides { [.space4: "1.25rem"] }
	static var radii: TokenOverrides { [.radiusLg: "1rem"] }
	static var typography: TokenOverrides { [.fontSizeLg: "1.25rem"] }
	static var motion: TokenOverrides { [.transitionBase: "250ms ease"] }
}

// MARK: - DesignTheme

@Suite("DesignTheme protocol")
struct DesignThemeProtocolTests {

	@Test("the default theme renders nothing — byte-identical to the unthemed document")
	func defaultThemeIsByteIdentical() {
		#expect(DefaultDesignTheme.resolvedPalette.isEmpty)
		#expect(WebUITheme(mode: .automatic, theme: DefaultDesignTheme.self) == .standard)
		#expect(DefaultDesignTheme.webUITheme(mode: .automatic).stylesheet() == "")
	}

	@Test("the default theme renders an unthemed document's exact bytes")
	func defaultDocumentIsByteIdentical() {
		let plain = WebUIDocument(title: "t", body: "<p>hi</p>").renderThroughBuffer()
		let themed = WebUIDocument(
			title: "t", body: "<p>hi</p>",
			theme: WebUITheme(mode: .automatic, theme: DefaultDesignTheme.self)
		).renderThroughBuffer()
		// the csp nonce is random per render; scrub both spellings so the
		// comparison isolates the theme's contribution.
		func scrubNonce(_ html: String) -> String {
			html
				.replacingOccurrences(of: "'nonce-[^']*'", with: "'nonce-N'", options: .regularExpression)
				.replacingOccurrences(of: "nonce=\"[^\"]*\"", with: "nonce=\"N\"", options: .regularExpression)
		}
		#expect(scrubNonce(themed) == scrubNonce(plain))
	}

	@Test("resolvedPalette folds all five axes into the one :root token set")
	func resolvedPaletteFoldsEveryAxis() {
		let folded = AccentTheme.resolvedPalette
		#expect(folded.tokens.count == 6)
		for (token, value) in [
			(DesignToken.colorPrimary500, "#268BD2"),
			(DesignToken.colorBg, "#ffffff"),
			(DesignToken.space4, "1.25rem"),
			(DesignToken.radiusLg, "1rem"),
			(DesignToken.fontSizeLg, "1.25rem"),
			(DesignToken.transitionBase, "250ms ease"),
		] {
			#expect(folded.tokens[token] == value)
		}
	}

	@Test("webUITheme renders the whole theme through the webui theme machinery")
	func themeRendersDirectly() {
		let css = AccentTheme.webUITheme(mode: .light).stylesheet()
		#expect(css.contains("color-scheme: light;"))
		#expect(css.contains("--color-primary-500: #268BD2;"))
		#expect(css.contains("--space-4: 1.25rem;"))
	}
}

// MARK: - DerivedTheme

@Suite("DerivedTheme<Base>")
struct DerivedThemeTests {

	@Test("a derived theme renders its override and inherits every other axis")
	func derivedRendersOverrideAndInherits() {
		let derived = DerivedTheme<AccentTheme>(
			mode: .dark,
			overrides: [.colorPrimary500: "#ff6b6b"]
		)
		let css = derived.webUITheme().stylesheet()
		// the palette override wins on its token…
		#expect(css.contains("--color-primary-500: #ff6b6b;"))
		#expect(!css.contains("--color-primary-500: #268BD2;"))
		// …and every other token — the base's palette and the four untouched
		// axes — rides through unchanged.
		#expect(css.contains("--color-bg: #ffffff;"))
		#expect(css.contains("--space-4: 1.25rem;"))
		#expect(css.contains("--radius-lg: 1rem;"))
		#expect(css.contains("--font-size-lg: 1.25rem;"))
		#expect(css.contains("--transition-base: 250ms ease;"))
		#expect(css.contains("color-scheme: dark;"))
	}

	@Test(".overriding moves a single token on the default theme")
	func overridingMovesASingleToken() {
		let css = DefaultDesignTheme.overriding([.colorPrimary500: "#123456"]).webUITheme().stylesheet()
		#expect(css.contains("--color-primary-500: #123456;"))
		// .automatic declares nothing: no color-scheme, no other tokens.
		#expect(!css.contains("color-scheme:"))
	}

	@Test("a derived theme is a DesignTheme type inheriting every axis of the base")
	func derivedTypeInheritsEveryAxis() {
		#expect(DerivedTheme<AccentTheme>.palette == AccentTheme.palette)
		#expect(DerivedTheme<AccentTheme>.spacing == AccentTheme.spacing)
		#expect(DerivedTheme<AccentTheme>.radii == AccentTheme.radii)
		#expect(DerivedTheme<AccentTheme>.typography == AccentTheme.typography)
		#expect(DerivedTheme<AccentTheme>.motion == AccentTheme.motion)
	}

	@Test("a derived theme's override reaches a real document's bytes")
	func derivedThemeReachesDocument() {
		let html = WebUIDocument(
			title: "t", body: "<p>hi</p>",
			theme: AccentTheme.overriding([.colorPrimary500: "#cc5500"]).webUITheme()
		).renderThroughBuffer()
		#expect(html.contains("--color-primary-500: #cc5500;"))
		#expect(html.contains("--space-4: 1.25rem;"))
	}

	@Test("an empty override on automatic renders nothing at all")
	func emptyDerivedRendersNothing() {
		let css = DerivedTheme<DefaultDesignTheme>(mode: .automatic, overrides: TokenOverrides()).webUITheme().stylesheet()
		#expect(css == "")
	}
}

// MARK: - TokenOverrides

@Suite("TokenOverrides")
struct TokenOverridesTests {

	@Test("layers per token, the override winning")
	func overlayingLayersPerToken() {
		let base = TokenOverrides([.space4: "1rem", .space2: "0.5rem"])
		let layered = base.overlaying([.space4: "2rem"])
		#expect(layered.tokens[.space4] == "2rem")
		#expect(layered.tokens[.space2] == "0.5rem")
		#expect(base.overlaying(TokenOverrides()) == base)
	}

	@Test("reports emptiness and equality")
	func emptinessAndEquality() {
		#expect(TokenOverrides().isEmpty)
		#expect(TokenOverrides.empty == TokenOverrides())
		#expect(!TokenOverrides([.space4: "1rem"]).isEmpty)
		#expect(TokenOverrides([.space4: "1rem"]) == TokenOverrides([.space4: "1rem"]))
	}

	@Test("emits through the theme renderer sorted and deduplicated")
	func emittedThroughThemeRenderer() {
		// a token repeated across axes collapses to one declaration
		struct Repeated: DesignTheme {
			static var palette: ThemePalette { ThemePalette(tokens: [.space4: "WRONG"]) }
			static var spacing: TokenOverrides { [.space4: "1.25rem"] }
			static var radii: TokenOverrides { .empty }
			static var typography: TokenOverrides { .empty }
			static var motion: TokenOverrides { .empty }
		}
		let css = Repeated.webUITheme().stylesheet()
		// the later axis (spacing) wins, deterministically.
		#expect(css.contains("--space-4: 1.25rem;"))
		#expect(!css.contains("--space-4: WRONG;"))
	}
}

// MARK: - ThemeSheet(theme:)

@Suite("ThemeSheet(theme:mode:)")
struct ThemeSheetDesignThemeTests {

	@Test("a design theme renders into a content-addressed sheet")
	func designThemeSheet() {
		let sheet = ThemeSheet(theme: AccentTheme.self, mode: .light)
		#expect(sheet.css.contains("--color-primary-500: #268BD2;"))
		#expect(sheet.css.contains("color-scheme: light;"))
		#expect(sheet.url.hasPrefix("/__assets/theme."))
		#expect(!sheet.isEmpty)
	}

	@Test("the default theme yields an empty sheet")
	func defaultThemeSheetIsEmpty() {
		#expect(ThemeSheet(theme: DefaultDesignTheme.self).isEmpty)
	}
}
