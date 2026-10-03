import Testing
import WebUI
import WebUISharedCore

// the S0 contract for `HTMLBuffer` (`.hermes/plans/2026-09-28_123131-render-buffer-v2.md`).
//
// every expectation here is derived from what the *string* path already does —
// `htmlEscape` for escaping, and `injectAttributes` (+ its AttributeMergeTests
// spec) for attribute placement and merging — because the buffer only earns its
// keep if it reproduces those bytes exactly.

@Suite("html buffer")
struct HTMLBufferTests {

	// MARK: writing

	@Test("an empty buffer renders nothing")
	func empty() {
		let b = HTMLBuffer()
		#expect(b.finish() == "")
		#expect(b.bytes.isEmpty)
		#expect(b.byteCount == 0)
	}

	@Test("appends are byte-identical to concatenation")
	func appendIsConcatenation() {
		var b = HTMLBuffer()
		b.append("<p class=\"x\">")
		b.append("hi")
		b.append("</p>")
		#expect(b.finish() == "<p class=\"x\">hi</p>")
		#expect(b.bytes == Array("<p class=\"x\">hi</p>".utf8))
		#expect(b.byteCount == b.bytes.count)
		#expect(b.byteCount == 19)
	}

	@Test("appendEscaped matches htmlEscape for every escapable and for clean input")
	func escapedParity() {
		let inputs = [
			"", "clean text", "a & b", "<tag>", "double \"quoted\"", "it's",
			"&<>\"'", "&amp; already escaped", "unicode ✓ fine",
		]
		for input in inputs {
			var b = HTMLBuffer()
			b.appendEscaped(input)
			#expect(b.finish() == htmlEscape(input))
		}
	}

	@Test("appendBytes takes raw utf-8 without escaping")
	func appendBytesIsRaw() {
		var b = HTMLBuffer()
		b.appendBytes(Array("<b>".utf8))
		#expect(b.finish() == "<b>")
	}

	@Test("the buffer grows past its initial capacity")
	func growth() {
		var b = HTMLBuffer(capacity: 8)
		for i in 0..<500 { b.append("chunk\(i);") }
		let expected = (0..<500).map { "chunk\($0);" }.joined()
		#expect(b.finish() == expected)
		#expect(b.byteCount == expected.utf8.count)
	}

	// MARK: element framing

	@Test("an element with no attributes")
	func bareElement() {
		var b = HTMLBuffer()
		b.beginElement("div")
		b.endOpenTag()
		b.append("x")
		b.endElement()
		#expect(b.finish() == "<div>x</div>")
	}

	@Test("an element keeps its own attributes")
	func ownAttributes() {
		var b = HTMLBuffer()
		b.beginElement("div", "class=\"card\"")
		b.endOpenTag()
		b.endElement()
		#expect(b.finish() == "<div class=\"card\"></div>")
	}

	@Test("nested elements close in order")
	func nested() {
		var b = HTMLBuffer()
		b.beginElement("div", "class=\"card\"")
		b.endOpenTag()
		b.beginElement("span")
		b.endOpenTag()
		b.append("x")
		b.endElement()
		b.endElement()
		#expect(b.finish() == "<div class=\"card\"><span>x</span></div>")
	}

	@Test("an element can add its own attribute before the tag is written")
	func selfAttribute() {
		var b = HTMLBuffer()
		b.beginElement("input")
		b.addAttribute("disabled")
		b.endOpenTag()
		b.endElement()
		#expect(b.finish() == "<input disabled></input>")
	}

	// MARK: the pending slot

	@Test("a contribution lands on the element that opens next")
	func contributionDrains() {
		var b = HTMLBuffer()
		b.addAttribute("id=\"i\"")
		#expect(b.hasPendingAttributes)
		b.beginElement("div", "class=\"card\"")
		b.endOpenTag()
		#expect(!b.hasPendingAttributes)
		b.endElement()
		// unknown keys append after the element's own, exactly as
		// `injectAttributes` merges them
		#expect(b.finish() == "<div class=\"card\" id=\"i\"></div>")
	}

	@Test("contributions merge innermost-first, so a chained style reads the same as the string path")
	func contributionOrder() {
		var b = HTMLBuffer()
		// a wrapping layer runs before the element renders, so the first
		// contribution is the OUTERMOST — and it must end up last in the tag.
		b.addAttribute("style=\"color:y\"")    // outer
		b.addAttribute("style=\"padding:x\"")  // inner
		b.beginElement("div")
		b.endOpenTag()
		b.endElement()
		#expect(b.finish() == "<div style=\"padding:x; color:y\"></div>")
	}

	@Test("a later contributed value wins for a non-style key")
	func contributionReplaces() {
		var b = HTMLBuffer()
		b.addAttribute("id=\"outer\"")
		b.addAttribute("id=\"inner\"")
		b.beginElement("div")
		b.endOpenTag()
		b.endElement()
		#expect(b.finish() == "<div id=\"outer\"></div>")
	}

	@Test("two valueless contributions stay separate attributes")
	func valuelessContributions() {
		var b = HTMLBuffer()
		b.addAttribute("required")
		b.addAttribute("disabled")
		b.beginElement("input")
		b.endOpenTag()
		b.endElement()
		#expect(b.finish() == "<input disabled required></input>")
	}

	@Test("a contribution merges with the element's own style instead of shipping a dead duplicate")
	func styleMergesWithOwn() {
		var b = HTMLBuffer()
		b.addAttribute("style=\"color:red\"")
		b.beginElement("div", "style=\"padding:4px\"")
		b.endOpenTag()
		b.endElement()
		#expect(b.finish() == "<div style=\"padding:4px; color:red\"></div>")
	}

	@Test("a duplicate in the element's own attributes folds without crashing")
	func duplicateOwnAttributes() {
		var b = HTMLBuffer()
		b.addAttribute("style=\"y:2\"")
		b.beginElement("div", "class=\"a\" class=\"b\" style=\"x:1\"")
		b.endOpenTag()
		b.endElement()
		#expect(b.finish() == "<div class=\"a\" style=\"x:1; y:2\"></div>")
	}

	@Test("addAttributeValue escapes both halves")
	func attributeValueEscapes() {
		var b = HTMLBuffer()
		b.addAttributeValue("title", "a \"quoted\" & <tagged> value")
		b.beginElement("div")
		b.endOpenTag()
		b.endElement()
		#expect(b.finish() == "<div title=\"a &quot;quoted&quot; &amp; &lt;tagged&gt; value\"></div>")
	}

	// MARK: the no-element fallback

	@Test("undrained contributions can be taken, inspected, and wrapped")
	func spanFallback() {
		var b = HTMLBuffer()
		let mark = b.mark
		b.addAttribute("class=\"x\"")
		b.append("just text")
		#expect(b.hasPendingAttributes)
		let taken = b.takePendingAttributes()
		#expect(taken == "class=\"x\"")
		#expect(!b.hasPendingAttributes)
		b.wrapSpan(from: mark, attributes: taken)
		// byte-identical to `injectAttributes(into: "just text", "class=\"x\"")`
		#expect(b.finish() == "<span class=\"x\">just text</span>")
	}

	@Test("wrapSpan wraps only what was written after its mark")
	func wrapSpanFromMiddle() {
		var b = HTMLBuffer()
		b.append("<div>")
		let mark = b.mark
		b.append("inner")
		b.wrapSpan(from: mark, attributes: "class=\"y\"")
		b.append("</div>")
		#expect(b.finish() == "<div><span class=\"y\">inner</span></div>")
	}

	@Test("dropping taken contributions leaves the content untouched")
	func droppedContributions() {
		var b = HTMLBuffer()
		b.addAttribute("class=\"x\"")
		b.append("<!-- c -->")
		_ = b.takePendingAttributes()
		#expect(b.finish() == "<!-- c -->")
	}

	@Test("the mark is the byte count at the time it is read")
	func markTracksBytes() {
		var b = HTMLBuffer()
		b.append("abc")
		#expect(b.mark == 3)
		b.append("de")
		#expect(b.mark == 5)
		#expect(b.mark == b.byteCount)
	}
}