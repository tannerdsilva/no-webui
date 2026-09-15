import Testing
import WebUI
import WebUIDesignSystem

// MARK: - compiled fixtures
//
// these types are expanded by the REAL compiler through the external macro
// plugin (not the in-process expansion harness), so the generated `DesignToken`
// member references are genuinely type-checked: an unknown token name here is
// a compile error, and the runtime tests below exercise the generated witness.

extension CSSRule {
	static let chatBubble = CSSRule(".chat-bubble", [CSSDeclaration("background", "var(--color-bg-subtle)")])
	static let streamDots = CSSRule(".stream-dots", [CSSDeclaration("animation", "blink 1s step-end infinite")])
}

@Theme
struct NexusDark {
	static let scheme = ColorScheme.dark
	static let rules: [CSSRule] = [.chatBubble, .streamDots]
	static let customTokens = ["--chat-user-bubble": "#2a2a2e"]
	static let colorPrimarySolid = "#6c8cff"
	static let colorBg = "#101014"
}

@Theme
public struct PublicPalette {
	static let colorBg = "#0b0b0f"
	static let colorTextMuted = "#97a3b8"
}

@Theme
struct AccentOnly {
	static let colorPrimarySolid = "#f59e0b"
}

@Suite("@Theme compiled runtime")
struct ThemeCompiledRuntimeTests {

	@Test("generated witness exposes every axis")
	func witnessExposesAxes() {
		let theme = NexusDark.theme
		#expect(theme.tokens[.colorPrimarySolid] == "#6c8cff")
		#expect(theme.tokens[.colorBg] == "#101014")
		#expect(theme.customTokens["--chat-user-bubble"] == "#2a2a2e")
		#expect(theme.scheme == .dark)
		#expect(theme.rules.count == 2)
	}

	@Test("a themed document renders the generated overrides")
	func themedDocumentRenders() {
		let html = WebUIDocument(
			title: "t",
			body: "<p class=\"chat-bubble\">hi</p>",
			theme: NexusDark.theme
		).render()
		#expect(html.contains("color-scheme: dark;"))
		#expect(html.contains("--color-primary-solid: #6c8cff;"))
		#expect(html.contains("--chat-user-bubble: #2a2a2e;"))
		#expect(html.contains(".chat-bubble {"))
	}

	@Test("overlaying composes with a generated theme")
	func overlayingComposes() {
		let combined = NexusDark.theme.overlaying(AccentOnly.theme)
		#expect(combined.tokens[.colorPrimarySolid] == "#f59e0b")
		#expect(combined.tokens[.colorBg] == "#101014")
		#expect(combined.scheme == .dark)
	}

	@Test("a public struct yields a publicly accessible theme")
	func publicThemeAccessible() {
		#expect(PublicPalette.theme.tokens[.colorBg] == "#0b0b0f")
		#expect(PublicPalette.theme.tokens[.colorTextMuted] == "#97a3b8")
	}

	@Test("an empty token bag overrides nothing")
	func emptyBagOverridesNothing() {
		let theme = AccentOnly.theme.overlaying(WebUITheme())
		#expect(theme.tokens[.colorPrimarySolid] == "#f59e0b")
	}
}
