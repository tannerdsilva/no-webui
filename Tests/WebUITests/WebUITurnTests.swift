import Testing
import Foundation
import WebUI
import WebUIDesignSystem

// MARK: - Turn transparency component tests
//
// the `.turn-*` classes are design-system vocabulary (design-system.css);
// these components are the Swift surface that emits them. every string is
// escaped so agent-produced content can never inject markup.

@Test("WebUIReasoningBlock renders a collapsible details block")
func reasoningBlockRendersDisclosure() {
    let view = WebUIReasoningBlock("step 1 → step 2")
    let html = view.render()
    #expect(html.contains("<details class=\"turn-reasoning\">"))
    #expect(html.contains("<summary>Reasoning</summary>"))
    #expect(html.contains("<pre>step 1 → step 2</pre>"))
    #expect(html.contains("</details>"))
}

@Test("WebUIReasoningBlock escapes reasoning content")
func reasoningBlockEscapesContent() {
    let view = WebUIReasoningBlock("<script>alert('xss')</script>")
    let html = view.render()
    #expect(!html.contains("<script>"))
    #expect(html.contains("&lt;script&gt;"))
}

@Test("WebUIToolStep renders name, args, result, and duration meta")
func toolStepRendersFullBlock() {
    let view = WebUIToolStep(
        name: "read_file",
        arguments: "path: README.md",
        result: "content…",
        meta: " · 120ms"
    )
    let html = view.render()
    #expect(html.contains("<div class=\"turn-tool\">"))
    #expect(html.contains("<span class=\"turn-tool__name\">read_file · 120ms</span>"))
    #expect(html.contains("<pre class=\"turn-tool__args\">path: README.md</pre>"))
    #expect(html.contains("<pre class=\"turn-tool__result\">content…</pre>"))
    #expect(!html.contains("turn-tool--error"))
}

@Test("WebUIToolStep renders the error variant")
func toolStepRendersErrorVariant() {
    let view = WebUIToolStep(name: "web_search", result: "failed", isError: true)
    let html = view.render()
    #expect(html.contains("turn-tool turn-tool--error"))
}

@Test("WebUIToolStep escapes every field")
func toolStepEscapesFields() {
    let view = WebUIToolStep(
        name: "<img onerror=alert(1)>",
        arguments: "<script>",
        result: "<div>",
        meta: " <b>"
    )
    let html = view.render()
    #expect(!html.contains("<script>"))
    #expect(!html.contains("<img"))
    #expect(!html.contains("<b>"))
    #expect(html.contains("&lt;script&gt;"))
}

@Test("WebUITurnSummary renders a muted summary line")
func turnSummaryRenders() {
    let view = WebUITurnSummary("3 tools · 1.2k tokens · 4 iterations")
    let html = view.render()
    #expect(html.contains("<div class=\"turn-summary\">"))
    #expect(html.contains("3 tools · 1.2k tokens · 4 iterations"))
    #expect(html.contains("</div>"))
}

@Test("WebUITurnSummary escapes summary text")
func turnSummaryEscapes() {
    let view = WebUITurnSummary("<script>alert(1)</script>")
    let html = view.render()
    #expect(!html.contains("<script>"))
    #expect(html.contains("&lt;script&gt;"))
}
