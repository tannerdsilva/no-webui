import Testing
import Foundation
import WebUI
import WebUIDesignSystem

// hardening tests for the consistency sweep: url-sanitization bypass payloads,
// attribute escaping on every emission site, the real markdown subset, css
// minification, runtime configuration, grid semantics, typed typography
// modifiers, and the dismiss/focus event surface.

@Suite("URL Sanitization Hardening")
struct URLSanitizationHardeningTests {

	@Test("sanitizeURL blocks whitespace-padded schemes")
	func blocksWhitespacePadded() {
		#expect(sanitizeURL(" javascript:alert(1)") == nil)
		#expect(sanitizeURL("\tjavascript:alert(1)") == nil)
		#expect(sanitizeURL("\njavascript:alert(1)") == nil)
	}

	@Test("sanitizeURL blocks control characters embedded in the scheme")
	func blocksEmbeddedControlChars() {
		#expect(sanitizeURL("java\tscript:alert(1)") == nil)
		#expect(sanitizeURL("java\nscript:alert(1)") == nil)
		#expect(sanitizeURL("java\rscript:alert(1)") == nil)
	}

	@Test("sanitizeURL still blocks plain and case-mixed unsafe schemes")
	func blocksPlainUnsafeSchemes() {
		#expect(sanitizeURL("javascript:alert(1)") == nil)
		#expect(sanitizeURL("JaVaScRiPt:alert(1)") == nil)
		#expect(sanitizeURL("data:text/html;base64,PHNjcmlwdD4=") == nil)
		#expect(sanitizeURL("vbscript:msgbox(1)") == nil)
	}

	@Test("sanitizeURL keeps safe schemes and normalizes stray whitespace")
	func keepsSafeSchemes() {
		#expect(sanitizeURL("https://example.com") == "https://example.com")
		#expect(sanitizeURL("/relative/path") == "/relative/path")
		#expect(sanitizeURL("mailto:a@example.com") == "mailto:a@example.com")
		#expect(sanitizeURL("  https://example.com  ") == "https://example.com")
	}

	@Test("Link with a padded javascript: href renders text-only")
	func linkDropsUnsafeHref() {
		let html = Link("click", href: " \tjava\nscript:alert(1)").render()
		#expect(html == "click")
		#expect(!html.contains("href="))
	}

	@Test("Image with a padded javascript: src omits the src attribute")
	func imageDropsUnsafeSrc() {
		let html = Image(src: " java\tscript:alert(1)", alt: "img").render()
		#expect(html == "<img alt=\"img\">")
		#expect(!html.contains("src="))
	}

	@Test("Form action still sanitizes and retains safe actions")
	func formActionSanitizes() {
		let safe = Form(action: "https://ok.example/submit") { Text("") }.render()
		#expect(safe.contains("action=\"https://ok.example/submit\""))
		let unsafe = Form(action: " javascript:alert(1)") { Text("") }.render()
		#expect(unsafe.contains("action=\"\""))
	}
}

@Suite("Attribute Escaping Hardening")
struct AttributeEscapingHardeningTests {

	@Test("Div class payload cannot break the attribute boundary")
	func divClassPayload() {
		let html = Div(class: "x\" autofocus onfocus=alert(1)") { Text("") }.render()
		#expect(html.contains("&quot;"))
		#expect(!html.contains("\" autofocus"))
	}

	@Test("Button name payload cannot inject an attribute")
	func buttonNamePayload() {
		let html = Button("go", name: "\" onmouseover=\"alert(1)").render()
		#expect(html.contains("&quot;"))
		#expect(!html.contains("\" onmouseover=\""))
	}

	@Test("Input id payload cannot inject an attribute")
	func inputIDPayload() {
		let html = Input(id: "x\" onfocus=\"alert(1)").render()
		#expect(html.contains("&quot;"))
		#expect(!html.contains("\" onfocus="))
	}

	@Test("Avatar data-status payload cannot inject an attribute")
	func avatarStatusPayload() {
		let html = WebUIAvatar(initials: "A", status: "\" onload=\"alert(1)").render()
		#expect(html.contains("&quot;"))
		#expect(!html.contains("\" onload="))
	}

	@Test("Form method payload cannot inject an attribute")
	func formMethodPayload() {
		let html = Form(method: "post\" onsubmit=\"alert(1)") { Text("") }.render()
		#expect(html.contains("&quot;"))
		#expect(!html.contains("\" onsubmit="))
	}

	@Test("Modal title id payload cannot inject an attribute")
	func modalTitlePayload() {
		let html = WebUIModal(title: "T", id: "m\" onfocus=\"alert(1)") { Text("") }.render()
		#expect(html.contains("&quot;"))
		#expect(!html.contains("\" onfocus="))
	}

	@Test("clean attribute values still render exactly as before")
	func cleanValuesUnaffected() {
		let div = Div(class: "app container") { Text("") }.render()
		#expect(div.hasPrefix("<div class=\"app container\">"))
		let input = Input(id: "email", name: "email", placeholder: "Enter email").render()
		#expect(input.contains("id=\"email\""))
		#expect(input.contains("name=\"email\""))
		let label = Label("Name", for: "name-input").render()
		#expect(label == "<label for=\"name-input\">Name</label>")
	}
}

@Suite("Markdown Rendering")
struct MarkdownRenderingTests {

	@Test("headings render atx levels and clamp above h6")
	func headings() {
		#expect(markdownToHTML("# Title") == "<h1>Title</h1>")
		#expect(markdownToHTML("###### Deep") == "<h6>Deep</h6>")
		#expect(markdownToHTML("####### Clamped") == "<h6>Clamped</h6>")
	}

	@Test("lists render from markup and numbered markers")
	func lists() {
		#expect(markdownToHTML("- a\n- b") == "<ul><li>a</li><li>b</li></ul>")
		#expect(markdownToHTML("* a\n* b") == "<ul><li>a</li><li>b</li></ul>")
		#expect(markdownToHTML("1. a\n2. b") == "<ol><li>a</li><li>b</li></ol>")
	}

	@Test("bold and emphasis wrap balanced delimiters")
	func inlineEmphasis() {
		#expect(markdownToHTML("hi **bold**") == "<p>hi <strong>bold</strong></p>")
		#expect(markdownToHTML("hi *em*") == "<p>hi <em>em</em></p>")
	}

	@Test("unpaired delimiters render literally")
	func unpairedDelimiters() {
		#expect(markdownToHTML("a ** b") == "<p>a ** b</p>")
		#expect(markdownToHTML("a *** b") == "<p>a *** b</p>")
	}

	@Test("code spans are never parsed for emphasis")
	func codeSpansProtectContent() {
		#expect(markdownToHTML("`**not bold**`") == "<p><code>**not bold**</code></p>")
	}

	@Test("fenced code blocks render pre/code with escaped content and language")
	func fencedCode() {
		let out = markdownToHTML("```swift\nprint(\"hi\")\n```")
		#expect(out.contains("<pre><code class=\"language-swift\">"))
		#expect(out.contains("print(&quot;hi&quot;)"))
		#expect(out.contains("</code></pre>"))
	}

	@Test("pipe tables render thead/tbody and skip the separator row")
	func tables() {
		let out = markdownToHTML("| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |")
		#expect(out.contains("<table>"))
		#expect(out.contains("<th>A</th>"))
		#expect(out.contains("<th>B</th>"))
		#expect(out.contains("<td>1</td>"))
		#expect(out.contains("<td>4</td>"))
		#expect(!out.contains("---"))
	}

	@Test("markdownBody wraps the fragment in the md scope")
	func bodyScope() {
		let out = markdownBody("# Hi")
		#expect(out.hasPrefix("<div class=\"md\">"))
		#expect(out.contains("<h1>Hi</h1>"))
		#expect(out.hasSuffix("\n</div>"))
	}

	@Test("links render safe targets and keep unsafe ones literal")
	func links() {
		#expect(markdownToHTML("[x](https://example.com)") == "<p><a href=\"https://example.com\">x</a></p>")
		#expect(markdownToHTML("[x](javascript:alert(1))") == "<p>[x](javascript:alert(1))</p>")
		#expect(markdownToHTML("[x]( java\tscript:alert(1))") == "<p>[x]( java\tscript:alert(1))</p>")
	}

	@Test("raw html in markdown is escaped, never emitted")
	func rawHTMLEscaped() {
		let html = markdownToHTML("<script>alert(1)</script>")
		#expect(html == "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>")
		#expect(!html.contains("<script>"))
	}

	@Test("paragraphs join non-empty lines")
	func paragraphs() {
		#expect(markdownToHTML("one\n\ntwo") == "<p>one</p>\n<p>two</p>")
	}
}

@Suite("CSS Minification")
struct CSSMinificationTests {

	@Test("minifyCSS strips comments, trims lines, drops blank lines")
	func minify() {
		let input = """
		/* todo: explain */
		.a {
		  color: red;
		}


		.b { background: blue; }
		"""
		let out = minifyCSS(input)
		#expect(!out.contains("/* todo"))
		#expect(out == ".a {\ncolor: red;\n}\n.b { background: blue; }")
	}

	@Test("minifyCSS preserves declarations and selectors")
	func preservesDeclarations() {
		let css = "/* c */\n.x { display: flex; flex-direction: row; }"
		let out = minifyCSS(css)
		#expect(out.contains("display: flex"))
		#expect(out.contains("flex-direction: row"))
	}

	@Test("shipped css carries no comments")
	func shippedPageHasNoCssComments() {
		// the shipped sheet lives on the content-addressed css route; the page links it.
		let sheet = DesignSystemAssets.minifiedCss
		#expect(!sheet.contains("/*"))
		#expect(!sheet.contains("*/"))
		let page = WebUIDocument(title: "t", body: "<p>hi</p>").render()
		#expect(page.contains("href=\"\(DesignSystemAssets.stylesheetURL)\""))
	}

	@Test("layout rules survive minification on a WebUIDocument page")
	func layoutRulesSurvive() {
		let sheet = DesignSystemAssets.minifiedCss
		#expect(sheet.contains(".vstack"))
		#expect(sheet.contains(".zstack"))
		#expect(sheet.contains("grid-area: 1 / 1"))
		let page = WebUIDocument(title: "t", body: "<p>hi</p>").render()
		#expect(page.contains("href=\"\(DesignSystemAssets.stylesheetURL)\""))
	}

	@Test("the hoisted pre-minified sheet matches a fresh manual minify")
	func hoistedStyleBlockMatchesManualMinify() {
		// byte-identity pin: the route-served sheet and the hoisted constant
		// must render exactly as a fresh minify would — a divergence here means
		// the hoist path and the canonical minify path have drifted. the
		// composition is the tool's: the order statement, then the layout
		// primitives wrapped in `webui.utilities`, then the layered sheet.
		let expected = minifyCSS(
			"@layer webui, webui.utilities;\n\n@layer webui.utilities {\n"
				+ CSSStylesheet(LayoutStyles.complete).render()
				+ "\n}\n\n" + WebUIAssets.css
		)
		#expect(DesignSystemAssets.minifiedCss == expected)
		#expect(WebUIDocument.minifiedDesignStyles == expected)
	}

	@Test("embedded asset constant still matches the source bytes")
	func embeddedConstantUnchanged() throws {
		let source = [UInt8]((try String(contentsOf: packageRootURL().appendingPathComponent("designer/assets/design-system.css"), encoding: .utf8)).utf8)
		#expect(Array(WebUIAssets.css.utf8) == source)
	}
}

@Suite("Runtime Configuration")
struct RuntimeConfigTests {

	@Test("default bootstrap is unchanged")
	func defaultBootstrap() {
		let page = HTMLDocument(title: "t", body: "").render()
		#expect(page.contains("<meta name=\"webui-config\""))
		#expect(!page.contains("WebUIRuntime"))
	}

	@Test("runtime config emits a bootstrap object with only set keys")
	func configEmitsInitObject() {
		let config = RuntimeConfig(wsUrl: "wss://example.com/ws", debounceInputMs: 150, logLevel: "debug")
		let page = HTMLDocument(title: "t", body: "", runtimeConfig: config).render()
		#expect(page.contains("webui-config"))
		#expect(page.contains("wss://example.com/ws"))
		#expect(page.contains("debounceInputMs"))
		#expect(!page.contains("WebUIRuntime"))
		#expect(!page.contains("wsReconnect"))
	}

	@Test("empty config falls back to the plain bootstrap")
	func emptyConfigDefaults() {
		let page = HTMLDocument(title: "t", body: "", runtimeConfig: RuntimeConfig()).render()
		#expect(page.contains("<meta name=\"webui-config\""))
		#expect(!page.contains("WebUIRuntime"))
	}

	@Test("runtime config emits the render token for ws replay binding")
	func renderTokenEmitted() {
		let config = RuntimeConfig(renderToken: "tok-123")
		let json = config.encodedJSON()
		#expect(json.contains("\"renderToken\":\"tok-123\""))
		let page = HTMLDocument(title: "t", body: "", runtimeConfig: config).render()
		#expect(page.contains("renderToken"))
		#expect(page.contains("tok-123"))
		// a token-only config is still non-empty (must emit the config meta).
		#expect(!config.isEmpty)
		#expect(!page.contains("WebUIRuntime"))
	}

	@Test("WebUIDocument passes runtime config through")
	func webuiDocumentPassesConfig() {
		let page = WebUIDocument(title: "t", body: "", runtimeConfig: RuntimeConfig(optimisticSettleMs: 1234)).render()
		#expect(page.contains("optimisticSettleMs"))
		#expect(page.contains("1234"))
	}

	@Test("runtime config keys use the js DEFAULTS names without suffixes")
	func configKeyNames() {
		let config = RuntimeConfig(wsMaxReconnectDelayMs: 10_000, wsPingIntervalMs: 15_000, wsPongTimeoutMs: 30_000)
		let json = config.encodedJSON()
		#expect(json.contains("\"wsPingInterval\":15000"))
		#expect(json.contains("\"wsPongTimeout\":30000"))
		#expect(json.contains("\"wsMaxReconnectDelay\":10000"))
		#expect(!json.contains("Ms"))
	}
}

@Suite("Grid Columns Semantics")
struct GridColumnsTests {

	private func renderGrid(_ columns: GridColumns) -> String {
		Grid(columns: columns) { Text("") }.render()
	}

	@Test("fixed tracks are grid-safe and distinct from fraction")
	func fixedColumns() {
		let fixed = renderGrid(.fixed(3))
		#expect(fixed.contains("grid-template-columns:repeat(3, minmax(0, 1fr))"))
		let fraction = renderGrid(.fraction(3))
		#expect(fraction.contains("grid-template-columns:repeat(3, 1fr)"))
	}

	@Test("auto-fill and auto-fit use n as the minimum track size")
	func autoFillAndFit() {
		let fill = renderGrid(.autoFill(200))
		#expect(fill.contains("grid-template-columns:repeat(auto-fill, minmax(200px, 1fr))"))
		let fit = renderGrid(.autoFit(160))
		#expect(fit.contains("grid-template-columns:repeat(auto-fit, minmax(160px, 1fr))"))
	}

	@Test("custom columns pass through unchanged")
	func customColumns() {
		let html = renderGrid(.custom("200px 1fr"))
		#expect(html.contains("grid-template-columns:200px 1fr"))
	}
}

@Suite("Typed Typography Modifiers")
struct TypedTypographyTests {

	@Test("FontWeight overload emits the numeric weight")
	func fontWeightOverload() {
		let html = Text("x").font(size: 14, weight: .semibold).render()
		#expect(html.contains("font-weight: 600"))
	}

	@Test("TextAlignment overload emits the css alignment")
	func textAlignmentOverload() {
		let html = Text("x").textAlign(.center).render()
		#expect(html.contains("text-align: center"))
	}

	@Test("custom escape hatches pass through")
	func customEscapeHatches() {
		let html = Text("x").font(size: 12, weight: .custom("425")).render()
		#expect(html.contains("font-weight: 425"))
		let right = Text("x").textAlign(.right).render()
		#expect(right.contains("text-align: right"))
	}
}

@Suite("Dismiss Markers and Attribute Modifier")
struct DismissMarkerTests {

	@Test("dismissible components emit data-dismiss markers")
	func dismissMarkers() {
		#expect(WebUIAlert(variant: .info, message: "m", dismissible: true).render().contains("data-dismiss"))
		#expect(WebUIToast(message: "m", dismissible: true).render().contains("data-dismiss"))
		#expect(WebUIModal(title: "t") { Text("") }.render().contains("data-dismiss"))
	}

	@Test("chip remove emits data-remove")
	func removeMarker() {
		#expect(WebUIChip("t", removable: true).render().contains("data-remove"))
	}

	@Test("attribute modifier exposes arbitrary attributes")
	func attributeModifier() {
		let html = Text("x").attribute("data-prevent-enter", "false").render()
		#expect(html == "<span data-prevent-enter=\"false\">x</span>")
	}
}

@Suite("Focus Event Modifiers")
struct FocusEventModifierTests {

	private func rendered(_ modifier: (Text) -> some View) -> String {
		let router = EventRouter()
		let context = RenderContext(router: router)
		return RenderContext.$current.withValue(context) {
			modifier(Text("x")).render()
		}
	}

	@Test("onFocusIn emits data-event=focusin")
	func focusInModifier() {
		let html = rendered { $0.onFocusIn { _ in [] } }
		#expect(html.contains("data-event=\"focusin\""))
		#expect(html.contains("data-component-id"))
	}

	@Test("onFocusOut emits data-event=focusout")
	func focusOutModifier() {
		let html = rendered { $0.onFocusOut { _ in [] } }
		#expect(html.contains("data-event=\"focusout\""))
	}
}
