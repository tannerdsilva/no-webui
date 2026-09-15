import Foundation
import Testing
import WebUI
import WebUIDesignSystem

// MARK: - WebUITheme core

@Suite("WebUITheme")
struct WebUIThemeTests {

	@Test("standard is empty and contributes no css")
	func standardIsEmpty() {
		#expect(WebUITheme.standard.isEmpty)
		#expect(WebUITheme.standard.stylesheet() == "")
		#expect(WebUITheme().isEmpty)
	}

	@Test("token overrides render a :root block, sorted by css name")
	func tokenOverridesRenderRootBlock() {
		let theme = WebUITheme(
			tokens: [
				.colorBg: "#0b0b0f",
				.colorPrimarySolid: "#6c8cff",
			]
		)
		let css = theme.stylesheet()
		#expect(css.contains(":root {"))
		#expect(css.hasPrefix(":root {"))
		// sorted deterministically by rawValue: color-bg before color-primary-solid
		let bgRange = css.range(of: "--color-bg: #0b0b0f;")!
		let primaryRange = css.range(of: "--color-primary-solid: #6c8cff;")!
		#expect(bgRange.lowerBound < primaryRange.lowerBound)
		#expect(css.hasSuffix("}"))
	}

	@Test("customTokens render after token overrides with keys verbatim")
	func customTokensRenderVerbatim() {
		let theme = WebUITheme(
			customTokens: [
				"--chat-user-bubble": "#2a2a2e",
				"--chat-ai-bubble": "var(--color-neutral-900)",
			]
		)
		let css = theme.stylesheet()
		#expect(css.contains("--chat-ai-bubble: var(--color-neutral-900);"))
		#expect(css.contains("--chat-user-bubble: #2a2a2e;"))
		// sorted
		let ai = css.range(of: "--chat-ai-bubble:")!
		let user = css.range(of: "--chat-user-bubble:")!
		#expect(ai.lowerBound < user.lowerBound)
	}

	@Test("scheme emits color-scheme in the :root block")
	func schemeEmitsColorScheme() {
		let dark = WebUITheme(scheme: .dark)
		#expect(dark.stylesheet().contains("color-scheme: dark;"))
		let light = WebUITheme(scheme: .light)
		#expect(light.stylesheet().contains("color-scheme: light;"))
		#expect(WebUITheme(scheme: .automatic).stylesheet() == "")
	}

	@Test("rules are appended after the :root block")
	func rulesAppendAfterRoot() {
		let theme = WebUITheme(
			tokens: [.colorPrimarySolid: "#6c8cff"],
			rules: [
				CSSRule(".user-bubble", [CSSDeclaration("background", "var(--chat-user-bubble)")]),
				CSSRule(".ai-bubble", [CSSDeclaration("border-radius", "var(--radius-lg)")]),
			]
		)
		let css = theme.stylesheet()
		#expect(css.contains(":root {"))
		let rootRange = css.range(of: ":root {")!
		let userRange = css.range(of: ".user-bubble {")!
		let aiRange = css.range(of: ".ai-bubble {")!
		#expect(rootRange.lowerBound < userRange.lowerBound)
		#expect(userRange.lowerBound < aiRange.lowerBound)
	}

	@Test("overlaying merges tokens, replaces scheme, appends rules")
	func overlayingMerges() {
		let base = WebUITheme(
			tokens: [.colorPrimarySolid: "#6366f1", .colorBg: "#ffffff"],
			scheme: .light,
			rules: [CSSRule(".a", [CSSDeclaration("color", "red")])]
		)
		let overlay = WebUITheme(
			tokens: [.colorPrimarySolid: "#6c8cff"],
			customTokens: ["--accent": "#123456"],
			rules: [CSSRule(".b", [CSSDeclaration("color", "blue")])]
		)
		let merged = base.overlaying(overlay)
		#expect(merged.tokens[.colorPrimarySolid] == "#6c8cff")
		#expect(merged.tokens[.colorBg] == "#ffffff")
		#expect(merged.customTokens["--accent"] == "#123456")
		#expect(merged.scheme == .light)
		#expect(merged.rules.count == 2)
	}

	@Test("overlaying with an automatic scheme keeps the base scheme")
	func overlayingKeepsBaseSchemeWhenAutomatic() {
		let base = WebUITheme(scheme: .dark)
		let merged = base.overlaying(WebUITheme())
		#expect(merged.scheme == .dark)
	}

	@Test("overlaying with an explicit scheme replaces the base scheme")
	func overlayingReplacesScheme() {
		let base = WebUITheme(scheme: .dark)
		let merged = base.overlaying(WebUITheme(scheme: .light))
		#expect(merged.scheme == .light)
	}
}

// MARK: - WebUIDocument(theme:)

@Suite("WebUIDocument(theme:)")
struct WebUIDocumentThemeTests {

	@Test("standard theme renders byte-identical to no theme")
	func standardIsByteIdentical() {
		let plain = WebUIDocument(title: "t", body: "<p>hi</p>").render()
		let themed = WebUIDocument(title: "t", body: "<p>hi</p>", theme: .standard).render()
		// the csp nonce is random per render; scrub both spellings (the
		// `'nonce-…'` inside the csp meta and `nonce="…"` on the script tag)
		// so the comparison isolates the theme's contribution.
		func scrubNonce(_ html: String) -> String {
			html
				.replacingOccurrences(of: "'nonce-[^']*'", with: "'nonce-N'", options: .regularExpression)
				.replacingOccurrences(of: "nonce=\"[^\"]*\"", with: "nonce=\"N\"", options: .regularExpression)
		}
		#expect(scrubNonce(themed) == scrubNonce(plain))

		// and the style element specifically contributes zero bytes.
		func styleBlock(_ html: String) -> String {
			guard let open = html.range(of: "<style>"), let close = html.range(of: "</style>") else { return "" }
			return String(html[open.lowerBound..<close.lowerBound])
		}
		#expect(styleBlock(themed) == styleBlock(plain))
	}

	@Test("a non-standard theme appends its css after the design sheet")
	func themedDocumentEmbedsOverrides() {
		let theme = WebUITheme(
			tokens: [.colorPrimarySolid: "#6c8cff"],
			customTokens: ["--chat-user-bubble": "#2a2a2e"],
			scheme: .dark,
			rules: [CSSRule(".user-bubble", [CSSDeclaration("border-radius", "var(--radius-lg)")])]
		)
		let html = WebUIDocument(title: "t", body: "<p>hi</p>", theme: theme).render()
		#expect(html.contains("color-scheme: dark;"))
		#expect(html.contains("--color-primary-solid: #6c8cff;"))
		#expect(html.contains("--chat-user-bubble: #2a2a2e;"))
		#expect(html.contains(".user-bubble {"))
		#expect(html.contains("border-radius: var(--radius-lg);"))
		// the theme block sits after the design sheet inside the same <style>
		let styleOpen = html.range(of: "<style>")!
		let sheetMarker = html.range(of: "--color-neutral-50:")!
		let themeMarker = html.range(of: "--color-primary-solid: #6c8cff;")!
		#expect(styleOpen.lowerBound < sheetMarker.lowerBound)
		#expect(sheetMarker.lowerBound < themeMarker.lowerBound)
		// a theme override token also exists in the base sheet; the override
		// must appear later in the css so the cascade resolves to it.
	}

	@Test("themed document keeps the design sheet and runtime intact")
	func themedDocumentKeepsSheet() {
		let html = WebUIDocument(body: "<p>x</p>", theme: WebUITheme(scheme: .dark)).render()
		#expect(html.contains("WebUIRuntime"))
		#expect(html.contains("--color-neutral-50:"))
	}
}

// MARK: - WebUIThemeProvider

@Suite("WebUIThemeProvider")
struct WebUIThemeProviderTests {

	struct Unthemed: WebUIThemeProvider {}

	struct HandWritten: WebUIThemeProvider {
		static var theme: WebUITheme {
			WebUITheme(tokens: [.colorPrimarySolid: "#123456"])
		}
	}

	@Test("conforming without a theme yields standard")
	func defaultIsStandard() {
		#expect(Unthemed.theme.isEmpty)
		#expect(Unthemed.theme == .standard)
	}

	@Test("hand-written providers keep their theme")
	func handWrittenThemeWins() {
		#expect(HandWritten.theme.tokens[.colorPrimarySolid] == "#123456")
	}
}
