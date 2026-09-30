import Testing
import WebUI
import WebUIDesignSystem

// MARK: - scoped emission

private let basePalette = ThemePalette(tokens: [
	.colorBg: "#FFFFFF",
	.colorText: "#111111",
	.colorPrimarySolid: "#7A4F00",
])
private let darkPalette = ThemePalette(tokens: [
	.colorBg: "#101014",
	.colorText: "#F2F2F2",
])

private enum TwoSchemeCatalog: ThemeCatalog {
	static var all: [any WebUIThemeProvider.Type] { [Alpha.self, Beta.self] }
	static var defaultTheme: any WebUIThemeProvider.Type { Alpha.self }

	struct Alpha: WebUIThemeProvider {
		static let themeID = "alpha"
		static var theme: WebUITheme { WebUITheme(palette: basePalette, dark: darkPalette) }
	}
	struct Beta: WebUIThemeProvider {
		static let themeID = "beta"
		static var theme: WebUITheme { WebUITheme(palette: basePalette) }
	}
}

@Suite("ThemeScope")
struct ThemeScopeTests {

	@Test("the default scope is `.root`, unchanged")
	func rootIsTheDefault() {
		let theme = WebUITheme(palette: basePalette)
		#expect(theme.stylesheet() == theme.stylesheet(scope: .root))
		#expect(theme.stylesheet().hasPrefix(":root {"))
		// `CSSMediaQuery.render()` wraps the condition in parens itself, so a caller that
		// passes them too produces `@media ((…))` — invalid css that nothing else catches.
		let withDark = WebUITheme(palette: basePalette, dark: darkPalette).stylesheet()
		#expect(withDark.contains("@media (prefers-color-scheme: dark)"),
			"the media condition must be parenthesised exactly once")
		#expect(!withDark.contains("@media (("))
	}

	@Test("`.attribute` scopes to data-scheme × data-theme, never `:root` alone")
	func attributeScoping() {
		let css = WebUITheme(palette: basePalette, dark: darkPalette).stylesheet(scope: .attribute(id: "alpha"))
		#expect(css.contains(#":root[data-scheme="alpha"][data-theme="light"]"#))
		#expect(css.contains(#":root[data-scheme="alpha"][data-theme="dark"]"#))
		#expect(css.contains(#":root[data-scheme="alpha"][data-theme="system"]"#))
		// the media pass overrides only the `system` choice
		#expect(css.contains("@media (prefers-color-scheme: dark)"))
		#expect(!css.contains("\n:root {"), "an attribute-scoped sheet must not leak a bare :root block")
	}

	@Test("both dark routes declare color-scheme: dark")
	func darkDeclaresColorScheme() {
		let css = WebUITheme(palette: basePalette, dark: darkPalette).stylesheet(scope: .attribute(id: "a"))
		#expect(css.contains("color-scheme: dark;"))
	}

	@Test("a theme with no dark palette emits no dark rules at all")
	func noDarkNoRules() {
		let css = WebUITheme(palette: basePalette).stylesheet(scope: .attribute(id: "beta"))
		#expect(css.contains(#"[data-theme="light"]"#))
		#expect(!css.contains(#"[data-theme="dark"]"#))
		#expect(!css.contains("@media"))
	}

	@Test("scoped emission is byte-stable across calls")
	func byteStable() {
		let theme = WebUITheme(palette: basePalette, dark: darkPalette)
		#expect(theme.stylesheet(scope: .attribute(id: "x")) == theme.stylesheet(scope: .attribute(id: "x")))
	}

	@Test("a catalog renders every scheme into ONE sheet, and switching needs no re-render")
	func catalogSheet() {
		let css = TwoSchemeCatalog.stylesheet()
		#expect(css.contains(#"[data-scheme="alpha"]"#))
		#expect(css.contains(#"[data-scheme="beta"]"#))
		#expect(css.hasSuffix("}"), "one sheet, not per-scheme documents")
		// both schemes' declarations are present simultaneously — which is the whole point:
		// the client can switch between them with no server involvement.
		#expect(css.components(separatedBy: "--color-bg:").count >= 3)
	}

	@Test("an empty catalog renders nothing rather than a stray block")
	func emptyCatalog() {
		enum Empty: ThemeCatalog {
			static var all: [any WebUIThemeProvider.Type] { [] }
			static var defaultTheme: any WebUIThemeProvider.Type { TwoSchemeCatalog.Alpha.self }
		}
		#expect(Empty.stylesheet() == "")
	}
}
