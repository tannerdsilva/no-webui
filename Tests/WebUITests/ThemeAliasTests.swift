import Foundation
import Testing
import WebUI
import WebUIDesignSystem

// MARK: - typed app-property aliases
//
// The gap this closes: an app with its own property names (`--bg`, `--surface`) had to
// hand-write a property→token table. Untyped on both sides, so a mistyped token survived to
// runtime and rendered as a missing colour. Here the token is a compile-time name.

private let aliases = [TokenAlias("--bg", .colorBg), TokenAlias("--muted", .colorTextMuted)]

@Suite("theme aliases")
struct ThemeAliasTests {

	@Test("an alias emits an INDIRECTION, so it follows the token")
	func emitsIndirection() {
		let css = WebUITheme(aliases: aliases).stylesheet()
		#expect(css.contains("--bg: var(--color-bg);"))
		#expect(css.contains("--muted: var(--color-text-muted);"))
	}

	@Test("an alias exists even when the theme sets no token at all")
	func worksWithoutSettingTheToken() {
		// the var resolves against the base sheet's `:root`, so the alias is valid on its own.
		// emitting the token's literal value instead would have required the token to be set.
		let css = WebUITheme(aliases: aliases).stylesheet()
		#expect(css.contains("--bg: var(--color-bg);"))
		#expect(!css.contains("--color-bg:"), "the theme itself needs to set nothing")
	}

	@Test("aliases reach every mode: root, attribute light/system AND attribute dark")
	func reachesEveryRule() {
		let theme = WebUITheme(
			palette: ThemePalette(tokens: [.colorBg: "#fff"]),
			dark: ThemePalette(tokens: [.colorBg: "#111"]),
			aliases: aliases
		)
		// attribute scope: 3 mode selectors, each must carry the alias or `--bg` disappears in
		// whichever mode was missed — most likely dark, which is the one nobody looks at.
		let scoped = theme.stylesheet(scope: .attribute(id: "x"))
		for mode in ["light", "system", "dark"] {
			let selector = #"[data-scheme="x"][data-theme="\#(mode)"]"#
			guard let at = scoped.range(of: selector) else {
				Issue.record("no rule for \(mode)"); continue
			}
			let rest = scoped[at.lowerBound...]
			let body = rest.prefix(while: { $0 != "}" })
			#expect(body.contains("--bg: var(--color-bg);"), "\(mode) is missing the alias")
		}
		// root scope carries them too
		#expect(theme.stylesheet().contains("--bg: var(--color-bg);"))
	}

	@Test("overlaying merges aliases by property, the override winning")
	func overlayingMergesAliases() {
		let base = WebUITheme(aliases: [TokenAlias("--bg", .colorBg), TokenAlias("--x", .colorText)])
		let overlay = WebUITheme(aliases: [TokenAlias("--bg", .colorBgRaised)])
		let merged = base.overlaying(overlay)
		#expect(merged.aliases.count == 2, "a re-declared property replaces, it does not append")
		#expect(merged.aliases.first(where: { $0.property == "--bg" })?.token == .colorBgRaised)
		#expect(merged.aliases.first(where: { $0.property == "--x" })?.token == .colorText)
	}

	@Test("aliases serialize with the theme, keyed by css token name")
	func codable() throws {
		let theme = WebUITheme(aliases: aliases)
		let data = try JSONEncoder().encode(theme)
		let text = String(decoding: data, as: UTF8.self)
		#expect(text.contains("--bg"))
		#expect(text.contains("color-bg"), "the token travels as its css name: \(text)")
		let back = try JSONDecoder().decode(WebUITheme.self, from: data)
		#expect(back == theme)
		#expect(back.stylesheet() == theme.stylesheet(), "and it still renders identically")
	}
}
