import Testing
import WebUI
import WebUIDesignSystem

// the declared child tree, rendered: `@Part` properties are emitted in
// declaration order, after the host's open tag and before `content`, and a part
// whose value is nil or empty is omitted **entirely**.
//
// the probe (`swift run WebUIProbeStyled`) proves the DetailCard shape
// byte-identical against a hand-written renderer. these tests are the
// executable half: the omission rule and the element-free path fail the suite
// on regression, not a reader's eye.

// `Testing` vends its own `Tag` (the `.tags(...)` trait), so `@StyledElement`
// qualifies the type it emits (`WebUICore.Tag?`) rather than relying on the
// host's file scope; no alias is needed here.

// a part is a `String` with a default; `sub` is a `String?` — both omission
// spellings (empty and nil) are declared here on purpose.
@StyledElement(.div, class: "detail-card")
struct PartTestCard<Content: View> {
    @Part(.h1, class: "detail-title") var title: String = ""
    @Part(.div, class: "detail-sub") var sub: String? = nil
}

// element-free: no wrapper element at all, parts then content.
@StyledElement(nil)
struct PartTestStack<Content: View> {
    @Part(.span, class: "dot") var marker: String? = nil
    @Part(.div, class: "msg") var note: String = ""
}

// a part with no `class:` argument carries no class attribute at all.
@StyledElement(.div, class: "note")
struct PartTestBare<Content: View> {
    @Part(.h2) var heading: String = ""
}

@Suite("StyledElement parts")
struct StyledElementPartRenderTests {

    @Test("parts render in declaration order, after the open tag and before content")
    func partsRenderInDeclarationOrder() {
        let card = PartTestCard(title: "Storage", sub: "where sessions live") { Text("body") }
        #expect(
            card.markup.html
                == "<div class=\"detail-card\"><h1 class=\"detail-title\">Storage</h1><div class=\"detail-sub\">where sessions live</div>body</div>"
        )
    }

    @Test("a part whose value is an empty string is omitted entirely")
    func emptyStringPartIsOmitted() {
        let card = PartTestCard(title: "", sub: "") { Text("body") }
        #expect(card.markup.html == "<div class=\"detail-card\">body</div>")
    }

    @Test("a part whose value is nil is omitted entirely")
    func nilPartIsOmitted() {
        let card = PartTestCard(title: "Storage") { Text("body") }
        #expect(
            card.markup.html
                == "<div class=\"detail-card\"><h1 class=\"detail-title\">Storage</h1>body</div>"
        )
    }

    @Test("one part present and the other absent keeps declaration order")
    func onePartPresent() {
        let card = PartTestCard(sub: "where sessions live") { Text("body") }
        #expect(
            card.markup.html
                == "<div class=\"detail-card\"><div class=\"detail-sub\">where sessions live</div>body</div>"
        )
    }

    @Test("a part's value is escaped, never injected")
    func partValueIsEscaped() {
        let card = PartTestCard(title: "<script>\"&\"") { Text("body") }
        #expect(
            card.markup.html
                == "<div class=\"detail-card\"><h1 class=\"detail-title\">&lt;script&gt;&quot;&amp;&quot;</h1>body</div>"
        )
    }

    @Test("the host's extra class merges after the base class")
    func extraClassMergesAfterBase() {
        let card = PartTestCard(title: "Storage", class: "card-lead") { Text("body") }
        #expect(
            card.markup.html
                == "<div class=\"detail-card card-lead\"><h1 class=\"detail-title\">Storage</h1>body</div>"
        )
    }

    @Test("a part with no class argument carries no class attribute")
    func partWithoutAClassCarriesNone() {
        let note = PartTestBare(heading: "Title") { Text("body") }
        #expect(note.markup.html == "<div class=\"note\"><h2>Title</h2>body</div>")
    }

    @Test("an element-free component emits its parts then its content, with no wrapper")
    func elementFreeEmitsPartsThenContent() {
        let stack = PartTestStack(marker: "m", note: "n") { Text("content") }
        #expect(
            stack.markup.html
                == "<span class=\"dot\">m</span><div class=\"msg\">n</div>content"
        )
    }

    @Test("an element-free component with every part empty emits only its content")
    func elementFreeWithNoPartsEmitsContentAlone() {
        let stack = PartTestStack { Text("content") }
        #expect(stack.markup.html == "content")
    }

    @Test("an element-free component carries no class, id or attribute: there is no element for them")
    func elementFreeCarriesNoAttributes() {
        let stack = PartTestStack(id: "x", class: "extra") { Text("content") }
        #expect(stack.markup.html == "content")
    }
}
