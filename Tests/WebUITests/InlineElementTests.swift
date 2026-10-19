import Testing
import WebUI
import WebUISharedCore

// the nine inline element primitives added for the arc markup migration:
// Small, InlineCode, Preformatted, Strong, Emphasis, Blockquote, Article,
// LineBreak, Details. each pins its exact open tag, escaped body, and the
// Details `open` attribute spelling.

@Suite("inline element primitives")
struct InlineElementTests {

    // MARK: inline containers

    @Test("small renders its tag and escapes its body")
    func smallRenders() {
        #expect(Small("a&<>\"'").markup.html == "<small>a&amp;&lt;&gt;&quot;&#39;</small>")
        #expect(Small { Text("x"); Text("y") }.markup.html == "<small>xy</small>")
    }

    @Test("code renders its tag and escapes its body")
    func inlineCodeRenders() {
        #expect(InlineCode("a&<>\"'").markup.html == "<code>a&amp;&lt;&gt;&quot;&#39;</code>")
        #expect(InlineCode { Text("x") }.markup.html == "<code>x</code>")
    }

    @Test("pre renders its tag and escapes its body (literal whitespace preserved)")
    func preformattedRenders() {
        #expect(Preformatted("a&b\nc").markup.html == "<pre>a&amp;b\nc</pre>")
        #expect(Preformatted { Text("x") }.markup.html == "<pre>x</pre>")
    }

    @Test("strong renders its tag and escapes its body")
    func strongRenders() {
        #expect(Strong("a&<>\"'").markup.html == "<strong>a&amp;&lt;&gt;&quot;&#39;</strong>")
        #expect(Strong { Text("x") }.markup.html == "<strong>x</strong>")
    }

    @Test("em renders its tag and escapes its body")
    func emphasisRenders() {
        #expect(Emphasis("a&<>\"'").markup.html == "<em>a&amp;&lt;&gt;&quot;&#39;</em>")
        #expect(Emphasis { Text("x") }.markup.html == "<em>x</em>")
    }

    @Test("blockquote renders its tag and escapes its body")
    func blockquoteRenders() {
        #expect(Blockquote("a&<>\"'").markup.html == "<blockquote>a&amp;&lt;&gt;&quot;&#39;</blockquote>")
        #expect(Blockquote { Text("x") }.markup.html == "<blockquote>x</blockquote>")
    }

    @Test("article renders its tag and escapes its body")
    func articleRenders() {
        #expect(Article("a&<>\"'").markup.html == "<article>a&amp;&lt;&gt;&quot;&#39;</article>")
        #expect(Article { Text("x") }.markup.html == "<article>x</article>")
    }

    // MARK: void / details

    @Test("line break renders a bare br")
    func lineBreakRenders() {
        #expect(LineBreak().markup.html == "<br>")
    }

    @Test("details renders with summary + content, and omits open when closed")
    func detailsClosed() {
        #expect(Details(summary: { Text("S") }, content: { Text("C") }).markup.html
            == "<details><summary>S</summary>C</details>")
    }

    @Test("details open emits the open attribute")
    func detailsOpen() {
        #expect(Details(open: true, summary: { Text("S") }, content: { Text("C") }).markup.html
            == "<details open><summary>S</summary>C</details>")
    }

    @Test("details body is escaped")
    func detailsEscapes() {
        #expect(Details(open: true, summary: { Text("a&") }, content: { Text("\"<b>") }).markup.html
            == "<details open><summary>a&amp;</summary>&quot;&lt;b&gt;</details>")
    }
}
