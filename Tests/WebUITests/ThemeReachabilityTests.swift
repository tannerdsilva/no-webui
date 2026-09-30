import Testing
import WebUI
import WebUIDesignSystem

// MARK: - reachability must be sound before anything is pruned
//
// Every case below is a way a naive "tokens the theme sets" definition would drop a token that
// is still resolved at runtime — a missing colour, in one rule, in one mode.

/// file-scope, not a method: a type declared inside a test cannot close over the suite's `self`.
private func rule(_ css: String) -> CSSRule {
	CSSRule(".x", [CSSDeclaration("color", css)])
}

@Suite("token reachability")
struct ThemeReachabilityTests {

	@Test("tokens set by either palette are reachable")
	func paletteTokens() {
		let theme = WebUITheme(
			palette: ThemePalette(tokens: [.colorBg: "#fff", .colorText: "#111"]),
			dark: ThemePalette(tokens: [.colorBgRaised: "#222"])
		)
		#expect(ThemeReachability.usedTokens(in: theme) == [.colorBg, .colorText, .colorBgRaised])
	}

	@Test("an ESCAPE-HATCH rule makes its tokens reachable — the §8.9 hole, closed")
	func rulesAreRead() {
		// the palette sets nothing; only the rule references a token.
		let theme = WebUITheme(rules: [rule("var(--color-danger)")])
		#expect(ThemeReachability.usedTokens(in: theme).contains(.colorDanger),
			"pruning on palette keys alone would drop a token this rule still resolves")
	}

	@Test("an ALIAS target is reachable even though nothing sets it")
	func aliasTargetsAreRead() {
		// `--bg: var(--color-bg)` resolves at runtime, so pruning `colorBg` dangles the alias.
		let theme = WebUITheme(aliases: [TokenAlias("--bg", .colorBg)])
		#expect(ThemeReachability.usedTokens(in: theme).contains(.colorBg))
	}

	@Test("the caller's own stylesheet contributes")
	func extraCSS() {
		let theme = WebUITheme(palette: ThemePalette(tokens: [.colorBg: "#fff"]))
		let used = ThemeReachability.usedTokens(in: theme, extraCSS: ".a { color: var(--color-text-muted); }")
		#expect(used.contains(.colorTextMuted))
	}

	@Test("the fallback form still counts as a reference")
	func fallbackForm() {
		#expect(ThemeReachability.referencedTokens(in: ".a{color:var(--color-text,#000);}")
			.contains(.colorText))
	}

	@Test("an app-invented property is not a design token")
	func customPropertiesIgnored() {
		// if these leaked into the token set, every pruning decision would depend on the app's
		// own vocabulary — and a name collision would silently keep or drop the wrong token.
		let found = ThemeReachability.referencedTokens(in: ".a{color:var(--chat-bubble);background:var(--color-bg)}")
		#expect(found == [.colorBg])
	}

	@Test("a catalog aggregates every scheme")
	func catalogAggregate() {
		enum Two: ThemeCatalog {
			static var all: [any WebUIThemeProvider.Type] { [A.self, B.self] }
			static var defaultTheme: any WebUIThemeProvider.Type { A.self }
			struct A: WebUIThemeProvider {
				static var theme: WebUITheme { WebUITheme(palette: ThemePalette(tokens: [.colorBg: "#fff"])) }
			}
			struct B: WebUIThemeProvider {
				static var theme: WebUITheme { WebUITheme(rules: [rule("var(--color-success)")]) }
			}
		}
		let used = Two.usedTokens()
		#expect(used.contains(.colorBg))
		#expect(used.contains(.colorSuccess), "a scheme that only references a token still uses it")
	}

	@Test("the reachable set is far smaller than the vocabulary")
	func pruningIsWorthDoing() {
		let theme = WebUITheme(palette: ThemePalette(tokens: [.colorBg: "#fff"]))
		let used = ThemeReachability.usedTokens(in: theme)
		#expect(used.count < DesignToken.allCases.count,
			"if a theme needed every token there would be nothing to prune")
	}
}
