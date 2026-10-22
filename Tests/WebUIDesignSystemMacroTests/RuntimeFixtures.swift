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
	static let defaultMode = ThemeMode.dark
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

@Theme
struct FullAxisTheme {
	static let colorPrimarySolid = "#6c8cff"
	static let space4 = "1.5rem"
	static let radiusLg = "0.75rem"
	static let fontSizeLg = "1.125rem"
	static let transitionFast = "150ms ease"
}

@Suite("@Theme compiled runtime")
struct ThemeCompiledRuntimeTests {

	@Test("generated witness exposes every axis")
	func witnessExposesAxes() {
		let theme = NexusDark.theme
		#expect(theme.palette.tokens[.colorPrimarySolid] == "#6c8cff")
		#expect(theme.palette.tokens[.colorBg] == "#101014")
		#expect(theme.palette.customTokens["--chat-user-bubble"] == "#2a2a2e")
		#expect(theme.defaultMode == .dark)
		#expect(theme.rules.count == 2)
	}

	@Test("a themed document renders the generated overrides")
	func themedDocumentRenders() {
		let html = WebUIDocument(
			title: "t",
			body: .trusted("<p class=\"chat-bubble\">hi</p>"),
			theme: NexusDark.theme
		).markup.html
		#expect(html.contains("color-scheme: dark;"))
		#expect(html.contains("--color-primary-solid: #6c8cff;"))
		#expect(html.contains("--chat-user-bubble: #2a2a2e;"))
		#expect(html.contains(".chat-bubble {"))
	}

	@Test("overlaying composes with a generated theme")
	func overlayingComposes() {
		let combined = NexusDark.theme.overlaying(AccentOnly.theme)
		#expect(combined.palette.tokens[.colorPrimarySolid] == "#f59e0b")
		#expect(combined.palette.tokens[.colorBg] == "#101014")
		#expect(combined.defaultMode == .dark)
	}

	@Test("a public struct yields a publicly accessible theme")
	func publicThemeAccessible() {
		#expect(PublicPalette.theme.palette.tokens[.colorBg] == "#0b0b0f")
		#expect(PublicPalette.theme.palette.tokens[.colorTextMuted] == "#97a3b8")
	}

	@Test("an empty token bag overrides nothing")
	func emptyBagOverridesNothing() {
		let theme = AccentOnly.theme.overlaying(WebUITheme())
		#expect(theme.palette.tokens[.colorPrimarySolid] == "#f59e0b")
	}

	@Test("the synthesized DesignTheme conformance partitions flat members into the five axes")
	func designThemeSynthesisPartitions() {
		#expect(FullAxisTheme.palette.tokens[.colorPrimarySolid] == "#6c8cff")
		#expect(FullAxisTheme.spacing.tokens[.space4] == "1.5rem")
		#expect(FullAxisTheme.radii.tokens[.radiusLg] == "0.75rem")
		#expect(FullAxisTheme.typography.tokens[.fontSizeLg] == "1.125rem")
		#expect(FullAxisTheme.motion.tokens[.transitionFast] == "150ms ease")
		// the empty axes exist and are empty: completeness without noise.
		#expect(DefaultDesignTheme.spacing.isEmpty)
	}

	@Test("a @Theme struct is a DesignTheme: derivation renders real bytes")
	func macroDesignThemeDerivesAndRenders() {
		let css = FullAxisTheme.overriding([.colorPrimarySolid: "#123456"]).webUITheme().stylesheet()
		#expect(css.contains("--color-primary-solid: #123456;"))
		#expect(css.contains("--space-4: 1.5rem;"))
		#expect(css.contains("--radius-lg: 0.75rem;"))
		#expect(css.contains("--font-size-lg: 1.125rem;"))
		#expect(css.contains("--transition-fast: 150ms ease;"))
	}
}

// MARK: - @Wired / @WireGroup compiled runtime

/// a compiled runtime fixture proving the macro-generated registrar type-checks
/// and routes events correctly against a real `EventRouter`.
@Suite("@Wired / @WireGroup compiled runtime")
struct WiredCompiledRuntimeTests {

	@Test("generated registrar routes listed events and filters non-listed")
	func registrarRoutesAndFilters() async throws {
		let router = EventRouter()
		let session = RenderSessionID.default

		let wiring = ProbeWiring()
		wiring.wireGroup_chat(router)

		// a listed event reaches the handler
		let listed = await router.handle(
			EventData(component: ComponentID("cb-file"), event: "click")
		)
		#expect(!listed.isEmpty, "listed event should produce fragments")

		// a non-listed event returns empty (the filter is the contract)
		let nonListed = await router.handle(
			EventData(component: ComponentID("cb-file"), event: "mouseover")
		)
		#expect(nonListed.isEmpty, "non-listed event should produce no fragments")

		// handlerCount matches the handler count
		#expect(router.handlerCount(in: session) == 2)
	}
}

@WireGroup("chat")
struct ProbeWiring {
	@Wired("cb-file", events: [.click])
	func cbFile(_ event: EventData) async -> [FragmentUpdate] {
		[FragmentUpdate(id: "cb-file", html: "<p>file attached</p>")]
	}

	@Wired("cb-send", events: [.click, .submit])
	func cbSend(_ event: EventData) async -> [FragmentUpdate] {
		[FragmentUpdate(id: "cb-send", html: "<p>sent</p>")]
	}
}
