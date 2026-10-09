import Testing
import WebUI
import WebUISharedCore

// the S3 contract (`.hermes/plans/2026-09-28_123131-render-buffer-v2.md` §3 S3):
// every primitive and layout writes its own element into the buffer, and the
// two element-less leaves (`Text`, `Raw`) write straight bytes. the pins are
// exact strings — this stage's gate is byte-identity, per file.
//
// the last two suites pin the MECHANISM rather than the bytes: a contribution
// must drain into a primitive's own element (a naive append would leak it to
// the next element), and a void element must leave no frame behind.

@Suite("primitive render")
struct PrimitiveRenderTests {

	// MARK: text and raw — no element to frame

	@Test("text escapes on both paths")
	func textEscapes() {
		#expect(Text("<b>&</b>'").renderThroughBuffer() == "&lt;b&gt;&amp;&lt;/b&gt;&#39;")
		var buffer = HTMLBuffer()
		Text("<b>&</b>'").render(into: &buffer)
		#expect(buffer.finish() == "&lt;b&gt;&amp;&lt;/b&gt;&#39;")
	}

	@Test("raw stays verbatim on both paths")
	func rawVerbatim() {
		#expect(Raw("<i>x</i>").renderThroughBuffer() == "<i>x</i>")
		var buffer = HTMLBuffer()
		Raw("<i>x</i>").render(into: &buffer)
		#expect(buffer.finish() == "<i>x</i>")
	}

	// MARK: void elements

	@Test("img and input emit a bare open tag — no closing tag")
	func voidElementsHaveNoClosingTag() {
		#expect(Image(src: "/p.png", alt: "p").renderThroughBuffer() == "<img src=\"/p.png\" alt=\"p\">")
		#expect(Input(id: "i", name: "n", placeholder: "ph", type: .email, required: true).renderThroughBuffer()
			== "<input id=\"i\" name=\"n\" type=\"email\" placeholder=\"ph\" required>")
	}

	@Test("a contribution drains into a void element")
	func contributionDrainsIntoVoidElement() {
		#expect(Image(src: "/p.png", alt: "p").class("avatar").renderThroughBuffer()
			== "<img src=\"/p.png\" alt=\"p\" class=\"avatar\">")
		#expect(Input(type: .text).attribute("data-x", "1").renderThroughBuffer() == "<input type=\"text\" data-x=\"1\">")
	}

	@Test("voidElement writes a bare tag, drains a contribution, and leaves no frame")
	func voidElementUnit() {
		var buffer = HTMLBuffer()
		buffer.voidElement("hr")
		#expect(buffer.finish() == "<hr>")

		buffer = HTMLBuffer()
		buffer.addAttribute("data-x=\"1\"")
		buffer.voidElement("hr", " class=\"rule\"")
		#expect(buffer.finish() == "<hr class=\"rule\" data-x=\"1\">")
		#expect(!buffer.hasPendingAttributes)

		// no stale frame: a framed element after it still opens and closes
		buffer = HTMLBuffer()
		buffer.voidElement("hr")
		buffer.beginElement("div")
		buffer.endOpenTag()
		buffer.endElement()
		#expect(buffer.finish() == "<hr><div></div>")
	}

	// MARK: form controls

	@Test("button attributes keep their order and escaping")
	func buttonAttributes() {
		#expect(Button("Go & stop", id: "go", class: "btn", type: .button, disabled: true, name: "act").renderThroughBuffer()
			== "<button id=\"go\" class=\"btn\" name=\"act\" type=\"button\" disabled>Go &amp; stop</button>")
	}

	@Test("input's custom attribute list skips an empty key and escapes both halves")
	func inputCustomAttributes() {
		let input = Input(attributes: [("", "dropped"), ("data-q", "a\"b")])
		#expect(input.renderThroughBuffer() == "<input type=\"text\" data-q=\"a&quot;b\">")
	}

	@Test("image degrades to a bare alt when the src is unsafe")
	func imageUnsafeSrc() {
		#expect(Image(src: "javascript:alert(1)", alt: "x").renderThroughBuffer() == "<img alt=\"x\">")
		#expect(Image(src: "/a.png", alt: "x", class: "c", loading: .lazy, decoding: .async).renderThroughBuffer()
			== "<img src=\"/a.png\" alt=\"x\" class=\"c\" loading=\"lazy\" decoding=\"async\">")
	}

	@Test("link degrades to its text when the href is unsafe, and keeps rel order")
	func linkContracts() {
		#expect(Link("go", href: "javascript:x").renderThroughBuffer() == "go")
		#expect(Link("docs", href: "/d", class: "l", target: .blank, rel: [.noopener, .noreferrer]).renderThroughBuffer()
			== "<a href=\"/d\" class=\"l\" target=\"_blank\" rel=\"noopener noreferrer\">docs</a>")
	}

	@Test("heading levels and paragraph classes frame their tags")
	func headingAndParagraph() {
		#expect(Heading("Hi", level: .h3).renderThroughBuffer() == "<h3>Hi</h3>")
		#expect(Heading("Hi", level: .h1, class: "title").renderThroughBuffer() == "<h1 class=\"title\">Hi</h1>")
		#expect(Paragraph("t", class: "lead").renderThroughBuffer() == "<p class=\"lead\">t</p>")
	}

	@Test("label, textarea, and select keep their attribute and option order")
	func formControls() {
		#expect(Label("Name", for: "nm", class: "lbl").renderThroughBuffer() == "<label for=\"nm\" class=\"lbl\">Name</label>")
		#expect(TextArea(id: "t", name: "ta", placeholder: "p", value: "v", rows: 4).renderThroughBuffer()
			== "<textarea id=\"t\" name=\"ta\" rows=\"4\" placeholder=\"p\">v</textarea>")
		#expect(Select(
			id: "s",
			name: "n",
			options: [SelectOption(value: "us", label: "United"), SelectOption(value: "ca", label: "Canada")],
			selected: "ca"
		).renderThroughBuffer()
			== "<select id=\"s\" name=\"n\"><option value=\"us\">United</option><option value=\"ca\" selected>Canada</option></select>")
	}

	// MARK: tables and forms

	@Test("table frames thead and tbody exactly as the string path did")
	func tableFraming() {
		#expect(Table(headers: ["A", "B"], rows: [[Text("1"), Text("2")]], class: "t").renderThroughBuffer()
			== "<table class=\"t\"><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody></table>")
		#expect(Table(headers: [], rows: []).renderThroughBuffer() == "<table><tbody></tbody></table>")
	}

	@Test("form sanitizes the action and carries the csrf field")
	func formContract() {
		#expect(Form(action: "javascript:x", method: "post", id: "f", csrfToken: "tok<") { }.renderThroughBuffer()
			== "<form id=\"f\" action=\"\" method=\"post\"><input type=\"hidden\" name=\"_csrf\" value=\"tok&lt;\"></form>")
		#expect(Form(action: "/go", method: "get", class: "c") { Text("x") }.renderThroughBuffer()
			== "<form class=\"c\" action=\"/go\" method=\"get\">x</form>")
	}

	@Test("group composes its children with no wrapper")
	func groupComposes() {
		#expect(Group { Text("a"); Text("b") }.renderThroughBuffer() == "ab")
	}

	// MARK: layouts

	@Test("a spacer is an empty framed div")
	func spacerContract() {
		#expect(Spacer(minSize: 8).renderThroughBuffer()
			== "<div class=\"spacer\" style=\"flex:1;min-width:8px;min-height:8px\"></div>")
	}

	@Test("scrollview keeps the literal newlines")
	func scrollViewNewlines() {
		#expect(ScrollView { Text("x") }.renderThroughBuffer() == "<div class=\"scrollview\">\nx\n</div>")
	}

	@Test("the semantic layout tags frame their children")
	func semanticTags() {
		#expect(Navigation(class: "n") { Text("x") }.renderThroughBuffer() == "<nav class=\"n\">x</nav>")
		#expect(Header { Text("x") }.renderThroughBuffer() == "<header>x</header>")
		#expect(Footer { Text("x") }.renderThroughBuffer() == "<footer>x</footer>")
		#expect(Main { Text("x") }.renderThroughBuffer() == "<main>x</main>")
		#expect(Aside { Text("x") }.renderThroughBuffer() == "<aside>x</aside>")
	}

	// MARK: the framing is real, not a naive append

	@Test("a contribution drains into a primitive's own element")
	func contributionDrainsIntoPrimitive() {
		var buffer = HTMLBuffer()
		buffer.addAttribute("class=\"c\"")
		Heading("Hi").render(into: &buffer)
		#expect(buffer.finish() == "<h1 class=\"c\">Hi</h1>")
		#expect(!buffer.hasPendingAttributes)
	}

	@Test("a modifier on a primitive lands in its own tag")
	func modifierOnPrimitive() {
		#expect(Heading("Hi", level: .h2).class("c").renderThroughBuffer() == "<h2 class=\"c\">Hi</h2>")
		#expect(Button("Go").padding(4).renderThroughBuffer()
			== "<button type=\"submit\" style=\"padding: 4px;\">Go</button>")
	}
}