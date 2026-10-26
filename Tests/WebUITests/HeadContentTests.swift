import Testing
import WebUI

// W2.3: the typed escape hatches. `Raw`, `head:`, `dir:` and the script surface
// used to be plain strings, which meant the framework could not tell a host's
// careful markup from a host's injection. each now either has a typed path that
// does the escaping, or requires an explicit `UnsafeMarkup` that names the call
// site in a grep.

@Suite("the typed escape hatches")
struct HeadContentTests {

    // MARK: - UnsafeMarkup and Raw

    @Test("Raw's typed initializer emits verbatim")
    func rawTyped() {
        #expect(Raw(UnsafeMarkup.trusted("<b>x</b>")).markup.html == "<b>x</b>")
    }

    @Test("the payload is readable, so a host can audit what it trusted")
    func markupIsReadable() {
        #expect(UnsafeMarkup.trusted("<i>y</i>").html == "<i>y</i>")
    }

    // MARK: - escaping

    @Test("meta escapes both halves of the pair")
    func metaEscapes() {
        let out = HeadContent.meta(name: "\"><script>alert(1)</script>", content: "a\"b").render(nonce: nil)
        #expect(!out.contains("<script>"))
        #expect(out.contains("&quot;"))
        #expect(out.contains("&lt;script&gt;"))
    }

    @Test("og escapes its text and drops an unusable image rather than emitting it")
    func ogEscapes() {
        let escaping = HeadContent.og(title: "a\"b", description: "<i>c</i>").render(nonce: nil)
        #expect(escaping.contains("&quot;"))
        #expect(!escaping.contains("<i>"))
        // no image asked for -> no og:image tag at all (an empty one is a fact a
        // crawler reads).
        #expect(!escaping.contains("og:image"))
        // a javascript: image is dropped entirely.
        let hostile = HeadContent.og(title: "t", description: "d", image: "javascript:alert(1)").render(nonce: nil)
        #expect(!hostile.contains("og:image"))
        #expect(!hostile.lowercased().contains("javascript:"))
        // a real url survives, escaped.
        let good = HeadContent.og(title: "t", description: "d", image: "/img/a.png?x=1&y=2").render(nonce: nil)
        #expect(good.contains("img/a.png?x=1&amp;y=2"))
    }

    @Test("link sanitizes its href and escapes the relation")
    func linkSanitizes() {
        #expect(!HeadContent.link(rel: .stylesheet, href: "javascript:alert(1)").render(nonce: nil).contains("javascript:"))
        let out = HeadContent.link(rel: .preload, href: "/a.css", type: "text/css").render(nonce: nil)
        #expect(out.contains("rel=\"preload\""))
        #expect(out.contains("href=\"/a.css\""))
        #expect(out.contains("type=\"text/css\""))
        // the url never gains an unescaped ampersand.
        #expect(!HeadContent.link(rel: .icon, href: "/a.ico?x=1&y=2").render(nonce: nil).contains("&y=2"))
    }

    // MARK: - the render nonce

    @Test("a script emitted through the builder carries the render nonce")
    func scriptCarriesNonce() {
        let out = HeadContent.script(src: "/a.js", module: true).render(nonce: "N0NCE")
        #expect(out.contains("nonce=\"N0NCE\""))
        #expect(out.contains("type=\"module\""))
        #expect(out.contains("src=\"/a.js\""))
        // with no nonce the attribute is simply absent, which is the honest
        // rendering for a policy that names no nonce source.
        #expect(HeadContent.script(src: "/a.js").render(nonce: nil) == "<script src=\"/a.js\"></script>")
    }

    @Test("the document injects its own nonce into head scripts")
    func documentInjectsNonce() throws {
        let doc = HTMLDocument(body: .trusted("<p>x</p>"), headContent: .script(src: "/a.js"))
        let nonce = try #require(doc.nonce)
        let html = doc.markup.html
        #expect(html.contains("nonce=\"\(nonce)\""))
        #expect(html.contains("src=\"/a.js\""))
    }

    // MARK: - JSON-LD

    @Test("jsonLD cannot close the script element it lives in")
    func jsonLDScriptBreakout() {
        let evil = JSONValue.string("</script><script>alert(1)</script>")
        let out = HeadContent.jsonLD(evil).render(nonce: "N")
        #expect(!out.contains("</script><script>"))
        #expect(out.contains("<\\/script>"))
        #expect(out.contains("type=\"application/ld+json\""))
        #expect(out.contains("nonce=\"N\""))
        // exactly one real closing tag survives: the element's own.
        #expect(out.components(separatedBy: "</script>").count == 2)
    }

    @Test("jsonLD emits the payload it was given")
    func jsonLDShape() {
        let value = JSONValue.object(["@type": .string("Article"), "n": .number(3)])
        let out = HeadContent.jsonLD(value).render(nonce: nil)
        #expect(out.contains("@type"))
        #expect(out.contains("Article"))
    }

    // MARK: - the builder and the typed direction

    @Test("the builder composes a head from typed pieces")
    func builderComposes() {
        let head = HeadContent {
            HeadContent.charset()
            HeadContent.meta(name: "viewport", content: "width=device-width")
            HeadContent.og(title: "T", description: "D")
            if true { HeadContent.link(rel: .icon, href: "/favicon.ico") }
            HeadContent.script(src: "/app.js")
        }
        let out = head.render(nonce: "N")
        #expect(out.contains("charset=\"utf-8\""))
        #expect(out.contains("name=\"viewport\""))
        #expect(out.contains("og:title"))
        #expect(out.contains("favicon.ico"))
        #expect(out.contains("nonce=\"N\""))
    }

    @Test("direction is typed now, and still validated")
    func typedDirection() {
        #expect(HTMLDocument(body: .trusted("x"), direction: .rtl).markup.html.contains(" dir=\"rtl\""))
        #expect(HTMLDocument(body: .trusted("x"), direction: .ltr).markup.html.contains(" dir=\"ltr\""))
        // the raw string path keeps working, and still drops an unusable value.
        #expect(HTMLDocument(body: .trusted("x"), dir: "rtl").markup.html.contains(" dir=\"rtl\""))
        #expect(!HTMLDocument(body: .trusted("x"), dir: "sideways").markup.html.contains(" dir="))
        // the typed slot wins over the raw one.
        #expect(HTMLDocument(body: .trusted("x"), dir: "ltr", direction: .rtl).markup.html.contains(" dir=\"rtl\""))
    }
}