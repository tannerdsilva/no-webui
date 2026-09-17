import Testing
import Foundation
import WebUI
import WebUIDesignSystem

// MARK: - View Protocol Tests

@Test("Text renders escaped HTML")
func textRendersEscaped() {
    let view = Text("<script>alert('xss')</script>")
    #expect(view.render() == "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;")
}

@Test("Raw renders unescaped HTML")
func rawRendersUnescaped() {
    let view = Raw("<strong>Bold</strong>")
    #expect(view.render() == "<strong>Bold</strong>")
}

@Test("EmptyView renders nothing")
func emptyViewRendersNothing() {
    let view = EmptyView()
    #expect(view.render() == "")
}

// MARK: - Primitives Tests

@Test("Div renders with class and children")
func divRendersWithClass() {
    let view = Div(class: "container") {
        Text("Hello")
        Text("World")
    }
    let html = view.render()
    #expect(html.contains("<div class=\"container\">"))
    #expect(html.contains("Hello"))
    #expect(html.contains("World"))
    #expect(html.contains("</div>"))
}

@Test("Button renders with type attribute")
func buttonRendersWithType() {
    let view = Button("Click me")
    let html = view.render()
    #expect(html.contains("type=\"submit\""))
    #expect(!html.contains("class="))
}

@Test("Button renders with custom id and class")
func buttonRendersWithCustomAttributes() {
    let view = Button("Send", id: "send-btn", class: "btn-primary")
    let html = view.render()
    #expect(html.contains("id=\"send-btn\""))
    #expect(html.contains("class=\"btn-primary\""))
}

@Test("Button renders disabled state")
func buttonRendersDisabled() {
    let view = Button("Delete", disabled: true)
    let html = view.render()
    #expect(html.contains("disabled"))
}

@Test("Button renders with button type")
func buttonRendersButtonType() {
    let view = Button("Cancel", type: .button)
    let html = view.render()
    #expect(html.contains("type=\"button\""))
}

@Test("Button renders with name attribute")
func buttonRendersWithName() {
    let view = Button("Submit", name: "action")
    let html = view.render()
    #expect(html.contains("name=\"action\""))
}

@Test("Input renders with placeholder and type")
func inputRendersWithAttributes() {
    let view = Input(id: "email", placeholder: "Enter email", type: .email)
    let html = view.render()
    #expect(html.contains("id=\"email\""))
    #expect(html.contains("placeholder=\"Enter email\""))
    #expect(html.contains("type=\"email\""))
}

@Test("Input renders with name attribute")
func inputRendersWithName() {
    let view = Input(name: "username")
    let html = view.render()
    #expect(html.contains("name=\"username\""))
}

@Test("Input renders disabled and required")
func inputRendersDisabledRequired() {
    let view = Input(disabled: true, required: true)
    let html = view.render()
    #expect(html.contains("disabled"))
    #expect(html.contains("required"))
}

@Test("Input escapes attribute keys to prevent XSS")
func inputEscapesAttributeKeys() {
    let view = Input(attributes: [("\" onclick=\"alert(1)", "x")])
    let html = view.render()
    // the key should be escaped, preventing attribute injection
    #expect(html.contains("&quot;"))
    // the key value is escaped, so onclick is inside an attribute value, not a new attribute
    #expect(!html.contains("onclick=\"alert(1)"))
}

@Test("Link renders with href")
func linkRendersWithHref() {
    let view = Link("Home", href: "/")
    let html = view.render()
    #expect(html.contains("href=\"/\""))
    #expect(html.contains("Home"))
}

@Test("Link renders with target and rel")
func linkRendersWithTargetRel() {
    let view = Link("External", href: "https://example.com", target: .blank, rel: [.noopener])
    let html = view.render()
    #expect(html.contains("target=\"_blank\""))
    #expect(html.contains("rel=\"noopener\""))
}

@Test("Heading renders correct level")
func headingRendersCorrectLevel() {
    let h1 = Heading("Title", level: .h1)
    let h3 = Heading("Subtitle", level: .h3)
    #expect(h1.render().hasPrefix("<h1"))
    #expect(h3.render().hasPrefix("<h3"))
}

@Test("Image renders with src and alt")
func imageRendersWithAttributes() {
    let view = Image(src: "/logo.svg", alt: "Logo")
    let html = view.render()
    #expect(html.contains("src=\"/logo.svg\""))
    #expect(html.contains("alt=\"Logo\""))
}

@Test("Image renders with loading and decoding")
func imageRendersWithLoadingDecoding() {
    let view = Image(src: "/photo.jpg", alt: "Photo", loading: .lazy, decoding: .async)
    let html = view.render()
    #expect(html.contains("loading=\"lazy\""))
    #expect(html.contains("decoding=\"async\""))
}

@Test("TextArea renders with value content")
func textAreaRendersWithValue() {
    let view = TextArea(name: "bio", value: "Hello world")
    let html = view.render()
    #expect(html.contains("name=\"bio\""))
    #expect(html.contains(">Hello world</textarea>"))
}

@Test("Select renders with name attribute")
func selectRendersWithName() {
    let view = Select(name: "country", options: [SelectOption(value: "us", label: "USA"), SelectOption(value: "ca", label: "Canada")])
    let html = view.render()
    #expect(html.contains("name=\"country\""))
}

// MARK: - Layout Tests

@Test("VStack renders with flexbox classes")
func vstackRendersWithClasses() {
    let view = VStack(alignment: .center, spacing: 16) {
        Text("A")
        Text("B")
    }
    let html = view.render()
    #expect(html.contains("class=\"vstack spacing-16 align-center\""))
}

@Test("HStack renders with flexbox classes")
func hstackRendersWithClasses() {
    let view = HStack(alignment: .top, spacing: 12) {
        Text("Left")
        Text("Right")
    }
    let html = view.render()
    #expect(html.contains("class=\"hstack spacing-12 align-flex-start\""))
}

@Test("ZStack renders with grid overlay")
func zstackRendersWithGrid() {
    let view = ZStack {
        Text("Back")
        Text("Front")
    }
    let html = view.render()
    #expect(html.contains("style=\"display:grid;"))
}

@Test("Spacer renders with flex:1")
func spacerRendersWithFlex() {
    let view = Spacer(minSize: 8)
    let html = view.render()
    #expect(html.contains("flex:1"))
    #expect(html.contains("min-width:8px"))
}

@Test("ScrollView renders with scrollview class")
func scrollViewRendersWithClass() {
    let view = ScrollView {
        Text("Content")
    }
    let html = view.render()
    #expect(html.contains("class=\"scrollview\""))
}

@Test("Grid renders with CSS grid")
func gridRendersWithCSSGrid() {
    let view = Grid(columns: .fraction(3), spacing: 20) {
        Text("A")
        Text("B")
        Text("C")
    }
    let html = view.render()
    #expect(html.contains("grid-template-columns:repeat(3, 1fr)"))
    #expect(html.contains("gap:20px"))
}

// MARK: - Modifier Tests

@Test("backgroundColor modifier injects inline style into root element")
func backgroundColorModifier() {
    let view = Div { Text("Hello") }.backgroundColor("#ff0")
    let html = view.render()
    // style should be injected into the <div>, not wrapped in a <span>
    #expect(html.contains("<div style=\"background-color: #ff0;\">"))
    #expect(!html.hasPrefix("<span"))
}

@Test("foregroundColor modifier on Text wraps in span (no root tag)")
func foregroundColorModifierOnText() {
    let view = Text("Hello").foregroundColor("red")
    let html = view.render()
    // Text has no HTML tag, so it wraps in span
    #expect(html.contains("<span style=\"color: red;\">"))
    #expect(html.contains("Hello"))
}

@Test("font modifier composes size and weight")
func fontModifierComposes() {
    let view = Text("Hello").font(size: 18, weight: "bold")
    let html = view.render()
    #expect(html.contains("font-size: 18px"))
    #expect(html.contains("font-weight: bold"))
}

@Test("padding modifier")
func paddingModifier() {
    let view = Text("Hello").padding(12)
    let html = view.render()
    #expect(html.contains("padding: 12px"))
}

@Test("padding with axis")
func paddingAxisModifier() {
    let view = Text("Hello").padding(horizontal: 16, vertical: 8)
    let html = view.render()
    #expect(html.contains("padding: 8px 16px"))
}

@Test("showIf hides when false")
func showIfHides() {
    let view = Text("Secret").showIf(false)
    let html = view.render()
    #expect(html.contains("display: none"))
}

@Test("showIf shows when true")
func showIfShows() {
    let view = Text("Visible").showIf(true)
    let html = view.render()
    #expect(html == "Visible")
}

@Test("id modifier injects into root element")
func idModifier() {
    let view = Div { Text("Hello") }.id("greeting")
    let html = view.render()
    // id should be on the div, not a wrapping span
    #expect(html.contains("<div id=\"greeting\""))
}

@Test("class modifier injects into root element")
func classModifier() {
    let view = Div { Text("Hello") }.class("highlight")
    let html = view.render()
    #expect(html.contains("<div class=\"highlight\""))
}

@Test("multiple modifiers chain correctly on block element")
func multipleModifiersChainOnDiv() {
    let view = Div { Text("Styled") }
        .font(size: 16, weight: "600")
        .foregroundColor("var(--color-text)")
        .padding(8)
    let html = view.render()
    // all styles should be on the div
    #expect(html.contains("<div style=\""))
    #expect(html.contains("font-size: 16px"))
    #expect(html.contains("font-weight: 600"))
    #expect(html.contains("color: var(--color-text)"))
    #expect(html.contains("padding: 8px"))
}

// MARK: - ViewBuilder Tests

@Test("ViewBuilder builds multiple views")
func viewBuilderBuildsMultipleViews() {
    let views = ViewBuilder.buildBlock(
        [Text("A")],
        [Text("B")],
        [Text("C")]
    )
    #expect(views.count == 3)
}

@Test("ViewBuilder buildOptional returns empty array for nil")
func viewBuilderOptionalNil() {
    let views = ViewBuilder.buildOptional(nil)
    #expect(views.isEmpty)
}

@Test("ViewBuilder buildOptional returns component for non-nil")
func viewBuilderOptionalSome() {
    let views = ViewBuilder.buildOptional([Text("Hello")])
    #expect(views.count == 1)
}

// MARK: - CSS System Tests

@Test("CSSRule renders correctly")
func cssRuleRenders() {
    let rule = CSSRule(".button", [CSSDeclaration("color", "red"), CSSDeclaration("font-size", "14px")])
    let rendered = CSSStylesheet([rule]).render()
    #expect(rendered.contains(".button {"))
    #expect(rendered.contains("color: red;"))
    #expect(rendered.contains("font-size: 14px;"))
}

@Test("CSSStylesheet renders multiple rules")
func cssStylesheetRendersMultiple() {
    let sheet = CSSStylesheet([
        CSSRule("body", [CSSDeclaration("margin", "0")]),
        CSSRule("p", [CSSDeclaration("color", "#333")]),
    ])
    let rendered = sheet.render()
    #expect(rendered.contains("body {"))
    #expect(rendered.contains("p {"))
}

@Test("CSSMediaQuery renders correctly")
func cssMediaQueryRenders() {
    let mq = CSSMediaQuery("prefers-color-scheme: dark", rules: [
        CSSRule(":root", [CSSDeclaration("--color-bg", "#000")])
    ])
    let rendered = mq.render()
    #expect(rendered.contains("@media (prefers-color-scheme: dark)"))
    #expect(rendered.contains("--color-bg: #000;"))
}

@Test("CSSKeyframes renders correctly")
func cssKeyframesRenders() {
    let kf = CSSKeyframes("fadeIn", [
        ("from", [CSSDeclaration("opacity", "0")]),
        ("to", [CSSDeclaration("opacity", "1")]),
    ])
    let rendered = kf.render()
    #expect(rendered.contains("@keyframes fadeIn"))
    #expect(rendered.contains("from {"))
    #expect(rendered.contains("to {"))
}

@Test("LayoutStyles provides vstack and hstack CSS")
func layoutStylesProvidesLayoutCSS() {
    let styles = LayoutStyles.all
    let rendered = CSSStylesheet(styles).render()
    #expect(rendered.contains(".vstack {"))
    #expect(rendered.contains(".hstack {"))
    #expect(rendered.contains(".zstack {"))
    #expect(rendered.contains(".spacer {"))
    #expect(rendered.contains(".scrollview {"))
    #expect(rendered.contains(".grid {"))
}

@Test("LayoutStyles.complete includes spacing and alignment classes")
func layoutStylesComplete() {
    let rendered = CSSStylesheet(LayoutStyles.complete).render()
    #expect(rendered.contains(".spacing-8 {"))
    #expect(rendered.contains(".spacing-16 {"))
    #expect(rendered.contains(".align-flex-start {"))
    #expect(rendered.contains(".align-center {"))
    #expect(rendered.contains(".align-flex-end {"))
}

@Test("generateSpacingClasses creates correct rules")
func generateSpacingClassesTest() {
    let rules = generateSpacingClasses([4, 8, 16])
    #expect(rules.count == 3)
    let rendered = CSSStylesheet(rules).render()
    #expect(rendered.contains(".spacing-4 {") && rendered.contains("gap: 4px;"))
    #expect(rendered.contains(".spacing-8 {") && rendered.contains("gap: 8px;"))
    #expect(rendered.contains(".spacing-16 {") && rendered.contains("gap: 16px;"))
}

@Test("generateAlignmentClasses creates correct rules")
func generateAlignmentClassesTest() {
    let rules = generateAlignmentClasses(["flex-start", "center"])
    #expect(rules.count == 2)
    let rendered = CSSStylesheet(rules).render()
    #expect(rendered.contains(".align-flex-start {") && rendered.contains("align-items: flex-start;"))
    #expect(rendered.contains(".align-center {") && rendered.contains("align-items: center;"))
}

// MARK: - HTMLDocument Tests

@Test("HTMLDocument renders complete page")
func htmlDocumentRenders() {
    let doc = HTMLDocument(
        title: "Test Page",
        body: "<p>Hello</p>",
        styles: CSSStylesheet([CSSRule("p", [CSSDeclaration("color", "red")])]),
        scripts: "console.log('hello');"
    )
    let html = doc.render()
    #expect(html.hasPrefix("<!DOCTYPE html>"))
    #expect(html.contains("<title>Test Page</title>"))
    #expect(html.contains("<p>Hello</p>"))
    #expect(html.contains("<style>"))
    #expect(html.contains("color: red;"))
    #expect(html.contains("<script nonce"))
    #expect(html.contains("console.log('hello');"))
}

@Test("HTMLDocument dev mode links external assets")
func htmlDocumentDevMode() {
    let doc = HTMLDocument(
        title: "Dev",
        body: "<p>Dev mode</p>",
        styles: CSSStylesheet([CSSRule("p", [CSSDeclaration("color", "red")])]),
        scripts: "console.log('dev');",
        devMode: true
    )
    let html = doc.render()
    #expect(html.contains("<link rel=\"stylesheet\" href=\"/ui/styles.css\">"))
    #expect(html.contains("<script src=\"/ui/scripts.js\">"))
    #expect(!html.contains("<style>"))
}

// MARK: - Utility Tests

@Test("htmlEscape escapes special characters")
func htmlEscapeEscapes() {
    #expect(htmlEscape("&") == "&amp;")
    #expect(htmlEscape("<") == "&lt;")
    #expect(htmlEscape(">") == "&gt;")
    #expect(htmlEscape("\"") == "&quot;")
    #expect(htmlEscape("'") == "&#39;")
    #expect(htmlEscape("safe text") == "safe text")
}

@Test("attrIf conditionally includes attribute")
func attrIfConditional() {
    #expect(attrIf("disabled", "true", true) == " disabled=\"true\"")
    #expect(attrIf("disabled", "true", false) == "")
}

@Test("classIf conditionally includes class")
func classIfConditional() {
    #expect(classIf("active", true) == " active")
    #expect(classIf("active", false) == "")
}

@Test("injectAttributes injects into first HTML tag")
func injectAttributesIntoTag() {
    let result = injectAttributes(into: "<div>content</div>", "class=\"foo\"")
    #expect(result == "<div class=\"foo\">content</div>")
}

@Test("injectAttributes wraps text in span when no tag exists")
func injectAttributesWrapsText() {
    let result = injectAttributes(into: "plain text", "class=\"foo\"")
    #expect(result == "<span class=\"foo\">plain text</span>")
}

@Test("injectAttributes handles self-closing tags")
func injectAttributesSelfClosing() {
    let result = injectAttributes(into: "<br>", "class=\"foo\"")
    #expect(result == "<br class=\"foo\">")
}

@Test("injectAttributes passes closing tags through unchanged")
func injectAttributesSkipsClosingTag() {
    let result = injectAttributes(into: "</div>", "class=\"foo\"")
    // closing tags have no opening tag to inject into — pass through unchanged
    #expect(result == "</div>")
}

@Test("injectAttributes merges a duplicate style attribute instead of emitting a dead one")
func injectAttributesMergesDuplicateStyle() {
    // browsers honor only the FIRST of duplicated attributes — a naive append
    // of a second `style` ships dead bytes and silently drops the modifier.
    // the merge appends declarations, so both halves survive in one attribute.
    let result = injectAttributes(
        into: "<div style=\"display: block;\">x</div>",
        "style=\"padding: 12px;\""
    )
    #expect(result == "<div style=\"display: block; padding: 12px;\">x</div>")
}

@Test("injectAttributes merges style into a pre-existing inline style")
func injectAttributesMergesExistingStyle() {
    let result = injectAttributes(
        into: "<span style=\"font-size: 16px;\">x</span>",
        "style=\"color: red;\""
    )
    // the original declaration keeps its trailing `;` — no stray separator
    #expect(result == "<span style=\"font-size: 16px; color: red;\">x</span>")
}

@Test("injectAttributes replaces a duplicate non-style attribute with the later value")
func injectAttributesReplacesDuplicateAttribute() {
    let result = injectAttributes(
        into: "<a href=\"/old\">x</a>",
        "href=\"/new\""
    )
    #expect(result == "<a href=\"/new\">x</a>")
}

@Test("injectAttributes appends an attribute that does not already exist")
func injectAttributesAppendsNewAttribute() {
    let result = injectAttributes(into: "<div class=\"a\">x</div>", "id=\"b\"")
    #expect(result == "<div class=\"a\" id=\"b\">x</div>")
}

// MARK: - Design System Tests

@Test("shipped css defines the nexus token set")
func webuiShippedCssDefinesTokens() {
    let css = WebUIAssets.css
    #expect(css.contains("--color-neutral-50"))
    #expect(css.contains("--color-primary-500"))
    #expect(css.contains("--color-success"))
    #expect(css.contains("--color-bg"))
    #expect(css.contains("--font-sans"))
    #expect(css.contains("--space-4"))
    #expect(css.contains("--radius-lg"))
    #expect(css.contains("--shadow-md"))
    #expect(css.contains("--transition-fast"))
    #expect(css.contains("--z-modal"))
}

@Test("shipped css includes the dark-mode remap")
func webuiShippedCssIncludesDarkMode() {
    let css = WebUIAssets.css
    #expect(css.contains("@media (prefers-color-scheme: dark)"))
}

@Test("WebUIButton renders with BEM classes")
func webuiButtonRenders() {
    let view = WebUIButton("Submit", variant: .primary, size: .lg)
    let html = view.render()
    #expect(html.contains("class=\"button button--primary button--lg\""))
    #expect(html.contains("Submit"))
}

@Test("WebUIButton disabled adds attribute")
func webuiButtonDisabled() {
    let view = WebUIButton("Disabled", disabled: true)
    let html = view.render()
    #expect(html.contains("disabled"))
}

@Test("WebUICard renders with variant")
func webuiCardRenders() {
    let view = WebUICard(variant: .elevated) {
        Text("Card content")
    }
    let html = view.render()
    #expect(html.contains("class=\"card card--elevated\""))
    #expect(html.contains("Card content"))
}

@Test("WebUIBadge renders with variant and size")
func webuiBadgeRenders() {
    let view = WebUIBadge("New", variant: .primary, size: .sm)
    let html = view.render()
    #expect(html.contains("class=\"badge badge--primary badge--sm\""))
    #expect(html.contains("New"))
}

@Test("WebUIAlert renders with role and variant")
func webuiAlertRenders() {
    let view = WebUIAlert(variant: .danger, title: "Error", message: "Something went wrong")
    let html = view.render()
    #expect(html.contains("class=\"alert alert--danger\""))
    #expect(html.contains("role=\"alert\""))
    #expect(html.contains("Error"))
    #expect(html.contains("Something went wrong"))
}

@Test("WebUIAlert renders a semantic icon by default")
func webuiAlertOmitsIcon() {
    let view = WebUIAlert(message: "Info")
    let html = view.render()
    // an info alert now carries its default `.info` glyph as inline SVG
    #expect(html.contains("alert__icon"))
    #expect(html.contains("<svg"))
    #expect(!html.contains("📭") && !html.contains("ℹ️"))
}

@Test("WebUIAlert renders icon when provided")
func webuiAlertRendersIcon() {
    let view = WebUIAlert(message: "Info", icon: .info)
    let html = view.render()
    #expect(html.contains("alert__icon"))
    #expect(html.contains("<svg"))
    #expect(!html.contains("ℹ️"))
}

@Test("WebUITabs renders with active tab")
func webuiTabsRenders() {
    let view = WebUITabs(tabs: [TabItem(id: "tab1", label: "Tab 1"), TabItem(id: "tab2", label: "Tab 2")], activeTab: "tab1")
    let html = view.render()
    #expect(html.contains("class=\"tabs__tab tabs__tab--active\""))
    #expect(html.contains("aria-selected=\"true\""))
}

@Test("WebUIAvatar renders with initials")
func webuiAvatarRenders() {
    let view = WebUIAvatar(initials: "JD", size: .lg)
    let html = view.render()
    #expect(html.contains("class=\"avatar avatar--lg\""))
    #expect(html.contains("JD"))
}

@Test("WebUIProgress renders with correct width")
func webuiProgressRenders() {
    let view = WebUIProgress(value: 0.45, showLabel: true)
    let html = view.render()
    #expect(html.contains("style=\"width: 45%\""))
    #expect(html.contains("45%"))
    #expect(html.contains("role=\"progressbar\""))
}

@Test("WebUIProgress uses typed enums for variant and size")
func webuiProgressTypedEnums() {
    let view = WebUIProgress(value: 0.5, variant: .success, size: .lg)
    let html = view.render()
    #expect(html.contains("progress--success"))
    #expect(html.contains("progress--lg"))
}

@Test("WebUISkeleton renders with variant")
func webuiSkeletonRenders() {
    let view = WebUISkeleton(variant: .title)
    let html = view.render()
    #expect(html.contains("class=\"skeleton skeleton--title\""))
    #expect(html.contains("aria-hidden=\"true\""))
}

@Test("WebUISkeleton renders multiple items")
func webuiSkeletonMultiple() {
    let view = WebUISkeleton(variant: .text, count: 3)
    let html = view.render()
    let count = html.components(separatedBy: "skeleton--text").count - 1
    #expect(count == 3)
}

@Test("WebUITable renders with view-based rows")
func webuiTableRenders() {
    let view = WebUITable(
        headers: ["Name", "Age"],
        rows: [[Text("Alice"), Text("30")], [Text("Bob"), Text("25")]]
    )
    let html = view.render()
    #expect(html.contains("<table class=\"table table--striped table--hoverable\">"))
    #expect(html.contains("<th>Name</th>"))
    #expect(html.contains("<td>Alice</td>"))
}

@Test("WebUIChip renders with removable button")
func webuiChipRemovable() {
    let view = WebUIChip("Tag", variant: .info, removable: true)
    let html = view.render()
    #expect(html.contains("class=\"chip chip--info\""))
    #expect(html.contains("class=\"chip__remove\""))
}

@Test("WebUIEmptyState renders with action button")
func webuiEmptyStateWithAction() {
    let view = WebUIEmptyState(
        icon: .package,
        title: "No items",
        message: "Get started by adding an item.",
        action: ("Add Item", "add-btn")
    )
    let html = view.render()
    #expect(html.contains("No items"))
    #expect(html.contains("Add Item"))
    #expect(html.contains("id=\"add-btn\""))
    #expect(html.contains("<svg"))
    #expect(!html.contains("📦"))
}

@Test("WebUISpinner renders with size")
func webuiSpinnerRenders() {
    let view = WebUISpinner(size: .lg, label: "Loading...")
    let html = view.render()
    #expect(html.contains("class=\"spinner spinner--lg\""))
    #expect(html.contains("Loading..."))
    #expect(html.contains("role=\"status\""))
}

@Test("WebUITooltip renders with position")
func webuiTooltipRenders() {
    let view = WebUITooltip("Helpful info", position: .bottom) {
        Text("Hover me")
    }
    let html = view.render()
    #expect(html.contains("class=\"tooltip tooltip--bottom\""))
    #expect(html.contains("Hover me"))
    #expect(html.contains("Helpful info"))
}

@Test("WebUIModal renders with title and content")
func webuiModalRenders() {
    let view = WebUIModal(title: "Confirm") {
        Text("Are you sure?")
    }
    let html = view.render()
    #expect(html.contains("class=\"modal\""))
    #expect(html.contains("role=\"dialog\""))
    #expect(html.contains("Confirm"))
    #expect(html.contains("Are you sure?"))
}

@Test("WebUIModal omits footer when not provided")
func webuiModalOmitsFooter() {
    let view = WebUIModal(title: "Confirm") {
        Text("Are you sure?")
    }
    let html = view.render()
    #expect(!html.contains("modal__footer"))
}

@Test("WebUIModal renders footer when provided")
func webuiModalRendersFooter() {
    let view = WebUIModal(title: "Confirm") {
        Text("Content")
    } footer: {
        WebUIButton("OK")
    }
    let html = view.render()
    #expect(html.contains("modal__footer"))
    #expect(html.contains("OK"))
}

@Test("WebUIToast renders with dismissible close button")
func webuiToastRenders() {
    let view = WebUIToast(message: "Saved")
    let html = view.render()
    #expect(html.contains("toast__close"))
}

@Test("WebUIToast hides close button when not dismissible")
func webuiToastNotDismissible() {
    let view = WebUIToast(message: "Saved", dismissible: false)
    let html = view.render()
    #expect(!html.contains("toast__close"))
}

// MARK: - Integration Tests

@Test("composing a page with multiple components")
func composePage() {
    let page = Div(class: "page") {
        Header(class: "page-header") {
            WebUIButton("Menu", variant: .ghost, size: .sm)
            Heading("My App", level: .h1)
        }
        Main(class: "page-content") {
            WebUICard(variant: .outlined) {
                WebUIAlert(variant: .info, message: "Welcome back!")
                WebUITable(
                    headers: ["Item", "Status"],
                    rows: [[Text("Task 1"), Text("Done")], [Text("Task 2"), Text("Pending")]]
                )
            }
        }
        Footer(class: "page-footer") {
            Text("© 2026")
        }
    }

    let html = page.render()
    #expect(html.contains("class=\"page\""))
    #expect(html.contains("class=\"page-header\""))
    #expect(html.contains("class=\"page-content\""))
    #expect(html.contains("class=\"page-footer\""))
    #expect(html.contains("My App"))
    #expect(html.contains("Welcome back!"))
    #expect(html.contains("Task 1"))
    #expect(html.contains("© 2026"))
}

@Test("HTMLDocument with full WebUI theme")
func htmlDocumentWithTheme() {
    let body = Div(class: "app") {
        WebUIButton("Get Started", variant: .primary)
    }.render()

    let doc = HTMLDocument(
        title: "WebUI App",
        body: body,
        styles: CSSStylesheet([CSSRule(":root", [CSSDeclaration("--color-primary-500", "#6366f1")])]),
        head: "<meta name=\"theme-color\" content=\"#6366f1\">"
    )

    let html = doc.render()
    #expect(html.contains("<title>WebUI App</title>"))
    #expect(html.contains("--color-primary-500"))
    #expect(html.contains("Get Started"))
    #expect(html.contains("<meta name=\"theme-color\""))
}

// MARK: - New API Tests

@Test("Input renders with value attribute")
func inputWithValue() {
    let view = Input(id: "name", value: "John")
    let html = view.render()
    #expect(html.contains("value=\"John\""))
}

@Test("Input omits value when empty")
func inputOmitsEmptyValue() {
    let view = Input(placeholder: "Enter name")
    let html = view.render()
    #expect(!html.contains("value="))
}

@Test("Input omits placeholder when empty")
func inputOmitsEmptyPlaceholder() {
    let view = Input(value: "John")
    let html = view.render()
    #expect(!html.contains("placeholder="))
}

@Test("ForEach renders collection elements")
func forEachRendersCollection() {
    let view = ForEach(["A", "B", "C"]) { item in
        Text(item)
    }
    #expect(view.render() == "ABC")
}

@Test("ForEach renders integer range")
func forEachRendersRange() {
    let view = ForEach(0..<3) { i in
        Text("\(i)")
    }
    #expect(view.render() == "012")
}

@Test("ForEach with complex content")
func forEachComplex() {
    let view = ForEach(["X", "Y"]) { item in
        Span {
            Text(item)
        }
    }
    let html = view.render()
    #expect(html == "<span>X</span><span>Y</span>")
}

@Test("ForEach works with non-Hashable elements")
func forEachNonHashable() {
    struct Item: Sendable {
        let name: String
    }
    let items = [Item(name: "A"), Item(name: "B")]
    let view = ForEach(items) { item in
        Text(item.name)
    }
    #expect(view.render() == "AB")
}

@Test("Group renders children without wrapper")
func groupRendersWithoutWrapper() {
    let view = Group {
        Text("A")
        Text("B")
    }
    #expect(view.render() == "AB")
}

@Test("Form renders with action and method")
func formRendersWithAction() {
    let view = Form(action: "/submit", method: "post") {
        Input(id: "name", placeholder: "Name")
        Button("Submit")
    }
    let html = view.render()
    #expect(html.hasPrefix("<form"))
    #expect(html.contains("action=\"/submit\""))
    #expect(html.contains("method=\"post\""))
    #expect(html.contains("</form>"))
}

@Test("Form renders without action when empty")
func formEmptyAction() {
    let view = Form {
        Text("No action")
    }
    let html = view.render()
    #expect(html.contains("action=\"\""))
}

@Test("WebUIDocument renders complete page with theme")
func webuiDocumentRenders() {
    let doc = WebUIDocument(
        title: "Test",
        body: WebUIButton("Go").render()
    )
    let html = doc.render()
    #expect(html.hasPrefix("<!DOCTYPE html>"))
    #expect(html.contains("<title>Test</title>"))
    #expect(html.contains("--color-primary-500"))
    #expect(html.contains("class=\"button button--primary button--md\""))
}

@Test("WebUIDocument dev mode links external assets")
func webuiDocumentDevMode() {
    let doc = WebUIDocument(
        title: "Dev",
        body: "<p>Dev</p>",
        devMode: true
    )
    let html = doc.render()
    #expect(html.contains("<link rel=\"stylesheet\" href=\"/ui/styles.css\">"))
    #expect(!html.contains("<style>"))
}

@Test("htmlEscape fast path returns original for safe strings")
func htmlEscapeFastPath() {
    let safe = "hello world"
    let result = htmlEscape(safe)
    #expect(result == safe)
}

@Test("htmlEscape single-pass produces correct output")
func htmlEscapeSinglePass() {
    #expect(htmlEscape("") == "")
    #expect(htmlEscape("safe") == "safe")
    #expect(htmlEscape("a&b<c>d\"e'f") == "a&amp;b&lt;c&gt;d&quot;e&#39;f")
    #expect(htmlEscape("&&&") == "&amp;&amp;&amp;")
    #expect(htmlEscape("<<<") == "&lt;&lt;&lt;")
}

// MARK: - WebSocket Protocol Tests

@Test("WSOutgoing.update encodes with optional seq")
func wsOutgoingUpdateWithSeq() throws {
    let msg = WSOutgoing.update(fragments: [
        FragmentUpdate(id: "test", html: "<p>Hello</p>")
    ], seq: 42)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let data = try encoder.encode(msg)
    let json = String(data: data, encoding: .utf8)!
    #expect(json.contains("\"type\":\"update\""))
    #expect(json.contains("\"seq\":42"))
    #expect(json.contains("\"id\":\"test\""))
}

@Test("WSOutgoing.update encodes without seq")
func wsOutgoingUpdateWithoutSeq() throws {
    let msg = WSOutgoing.update(fragments: [
        FragmentUpdate(id: "a", html: "<span>A</span>")
    ])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let data = try encoder.encode(msg)
    let json = String(data: data, encoding: .utf8)!
    #expect(json.contains("\"type\":\"update\""))
    #expect(!json.contains("\"seq\""))
}

@Test("WSOutgoing.redirect encodes with replace")
func wsOutgoingRedirect() throws {
    let msg = WSOutgoing.redirect(url: "/login", replace: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let data = try encoder.encode(msg)
    let json = String(data: data, encoding: .utf8)!
    #expect(json.contains("\"type\":\"redirect\""))
    #expect(json.contains("\"url\":\"/login\""))
    #expect(json.contains("\"replace\":true"))
}

@Test("WSOutgoing.state encodes path and value")
func wsOutgoingState() throws {
    let msg = WSOutgoing.state(path: "user.name", value: "Alice")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let data = try encoder.encode(msg)
    let json = String(data: data, encoding: .utf8)!
    #expect(json.contains("\"type\":\"state\""))
    #expect(json.contains("\"path\":\"user.name\""))
    #expect(json.contains("\"value\":\"Alice\""))
}

@Test("WSOutgoing.error encodes code and message")
func wsOutgoingError() throws {
    let msg = WSOutgoing.error(code: "NOT_FOUND", message: "Resource not found")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let data = try encoder.encode(msg)
    let json = String(data: data, encoding: .utf8)!
    #expect(json.contains("\"type\":\"error\""))
    #expect(json.contains("\"code\":\"NOT_FOUND\""))
    #expect(json.contains("\"message\":\"Resource not found\""))
}

@Test("WSOutgoing.reload encodes correctly")
func wsOutgoingReload() throws {
    let msg = WSOutgoing.reload
    let data = try JSONEncoder().encode(msg)
    let json = String(data: data, encoding: .utf8)!
    #expect(json == "{\"type\":\"reload\"}")
}

@Test("WSOutgoing.pong encodes correctly")
func wsOutgoingPong() throws {
    let msg = WSOutgoing.pong
    let data = try JSONEncoder().encode(msg)
    let json = String(data: data, encoding: .utf8)!
    #expect(json == "{\"type\":\"pong\"}")
}

@Test("WSOutgoing does not include script type")
func wsOutgoingNoScriptType() throws {
    let mirror = Mirror(reflecting: WSOutgoing.pong)
    let cases = mirror.children
    let hasScript = cases.contains { String(describing: $0.0) == "script" }
    #expect(!hasScript)
}

@Test("WSIncoming.event decodes correctly")
func wsIncomingEvent() throws {
    let json = "{\"type\":\"event\",\"component\":\"btn-1\",\"event\":\"click\",\"data\":{\"key\":\"val\"}}"
    let data = json.data(using: .utf8)!
    let msg = try JSONDecoder().decode(WSIncoming.self, from: data)
    guard case .event(let component, let event, let data, let token) = msg else {
        Issue.record("Expected .event")
        return
    }
    #expect(component == "btn-1")
    #expect(event == "click")
    #expect(data["key"] == "val")
    #expect(token == nil)
}

@Test("WSIncoming.event decodes an optional render token")
func wsIncomingEventToken() throws {
    let json = "{\"type\":\"event\",\"component\":\"btn-1\",\"event\":\"click\",\"data\":{},\"token\":\"tok-abc\"}"
    let data = json.data(using: .utf8)!
    let msg = try JSONDecoder().decode(WSIncoming.self, from: data)
    guard case .event(_, _, _, let token) = msg else {
        Issue.record("Expected .event")
        return
    }
    #expect(token == "tok-abc")
}

@Test("WSIncoming.ping decodes correctly")
func wsIncomingPing() throws {
    let json = "{\"type\":\"ping\"}"
    let data = json.data(using: .utf8)!
    let msg = try JSONDecoder().decode(WSIncoming.self, from: data)
    guard case .ping(let token) = msg else {
        Issue.record("Expected .ping")
        return
    }
    #expect(token == nil)
}

@Test("WSIncoming.navigate decodes correctly")
func wsIncomingNavigate() throws {
    let json = "{\"type\":\"navigate\",\"url\":\"/dashboard\"}"
    let data = json.data(using: .utf8)!
    let msg = try JSONDecoder().decode(WSIncoming.self, from: data)
    guard case .navigate(let url) = msg else {
        Issue.record("Expected .navigate")
        return
    }
    #expect(url == "/dashboard")
}

// MARK: - Content Security Policy Tests

@Test("HTMLDocument with CSP includes meta tag")
func htmlDocumentWithCSP() {
    let doc = HTMLDocument(
        title: "Secure",
        body: "<p>Content</p>",
        contentSecurityPolicy: "default-src 'self'; script-src 'self'"
    )
    let html = doc.render()
    #expect(html.contains("Content-Security-Policy"))
    #expect(html.contains("default-src 'self'"))
    #expect(html.contains("script-src 'self'"))
}

@Test("HTMLDocument without CSP omits meta tag when disabled")
func htmlDocumentWithoutCSP() {
    let doc = HTMLDocument(title: "Plain", body: "<p>Content</p>", contentSecurityPolicy: "")
    let html = doc.render()
    #expect(!html.contains("Content-Security-Policy"))
}

@Test("WebUIDocument with CSP includes meta tag")
func webuiDocumentWithCSP() {
    let doc = WebUIDocument(
        title: "Secure",
        body: "<p>Content</p>",
        contentSecurityPolicy: "default-src 'self'"
    )
    let html = doc.render()
    #expect(html.contains("Content-Security-Policy"))
    #expect(html.contains("default-src 'self'"))
}

@Test("FragmentUpdate encodes and decodes")
func fragmentUpdateRoundTrip() throws {
    let original = FragmentUpdate(id: "test-id", html: "<div>Content</div>")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(FragmentUpdate.self, from: data)
    #expect(decoded.id == "test-id")
    #expect(decoded.html == "<div>Content</div>")
}

// MARK: - Event Handling Tests

@Test("EventRouter generates unique component IDs")
func eventRouterUniqueIDs() {
    let router = EventRouter()
    let id1 = router.nextComponentID()
    let id2 = router.nextComponentID()
    let id3 = router.nextComponentID()
    #expect(id1 == "c0")
    #expect(id2 == "c1")
    #expect(id3 == "c2")
    #expect(id1 != id2)
    #expect(id2 != id3)
}

@Test("EventRouter registers and dispatches handlers")
func eventRouterDispatch() async {
    let router = EventRouter()
    let componentID = router.nextComponentID()

    router.register({ event in
        #expect(event.component == componentID)
        #expect(event.event == "click")
        #expect(event.data["key"] == "value")
        return [FragmentUpdate(id: "result", html: "<span>Done</span>")]
    }, for: componentID)

    let updates = await router.handle(EventData(
        component: componentID,
        event: "click",
        data: ["key": "value"]
    ))

    #expect(updates.count == 1)
    #expect(updates[0].id == "result")
    #expect(updates[0].html == "<span>Done</span>")
}

@Test("EventRouter returns empty for unregistered component")
func eventRouterUnregistered() async {
    let router = EventRouter()
    let updates = await router.handle(EventData(
        component: "nonexistent",
        event: "click",
        data: [:]
    ))
    #expect(updates.isEmpty)
}

@Test("EventRouter reset clears all handlers")
func eventRouterReset() async {
    let router = EventRouter()
    let id = router.nextComponentID()
    router.register({ _ in [FragmentUpdate(id: "x", html: "x")] }, for: id)
    router.reset()

    let updates = await router.handle(EventData(
        component: id,
        event: "click",
        data: [:]
    ))
    #expect(updates.isEmpty)
}

@Test("EventHandlerModifier emits data-component-id when context is set")
func eventHandlerModifierEmitsComponentID() {
    let router = EventRouter()
    let context = RenderContext(router: router)

    let html = RenderContext.$current.withValue(context) {
        Text("Hello")
            .onClick { _ in [] }
            .render()
    }

    #expect(html.contains("data-component-id"))
    #expect(html.contains("data-event=\"click\""))
    #expect(html.contains("Hello"))
}

@Test("EventHandlerModifier emits the raw component id, not the struct's debug description")
func eventHandlerModifierEmitsRawComponentID() {
    let router = EventRouter()
    let context = RenderContext(router: router)

    let html = RenderContext.$current.withValue(context) {
        Text("Hello")
            .onClick { _ in [] }
            .render()
    }

    // The attribute must carry the bare id (c0), never the Swift struct's
    // debugDescription ("ComponentID(value: \"c0\")"), or the runtime's event
    // delegation can't route the click back to the registered handler.
    #expect(html.contains("data-component-id=\"c0\""), "emitted: \(html)")
    #expect(!html.contains("ComponentID(value:"))
}

@Test("EventHandlerModifier passes through without context")
func eventHandlerModifierWithoutContext() {
    let html = Text("Hello")
        .onClick { _ in [] }
        .render()

    // Without RenderContext, the modifier passes content through unchanged
    #expect(html == "Hello")
}

@Test("EventHandlerModifier injects into root element of block view")
func eventHandlerModifierOnBlockView() {
    let router = EventRouter()
    let context = RenderContext(router: router)

    let html = RenderContext.$current.withValue(context) {
        Div { Text("Click me") }
            .onClick { _ in [FragmentUpdate(id: "result", html: "<span>Clicked</span>")] }
            .render()
    }

    // data-component-id should be on the div, not a wrapping span
    #expect(html.contains("<div data-component-id="))
    #expect(!html.hasPrefix("<span"))
}

@Test("every rendered data-component-id has a registered handler")
func handlerRegistrationMatchesRenderedComponents() async {
    let counter = ClickCounter()
    let router = EventRouter()
    let html: String = RenderContext.$current.withValue(RenderContext(router: router)) {
        Div(class: "demo") {
            Button("+")
                .onClick { _ in counter.clicks += 1; return [] }
            Button("-")
                .onClick { _ in counter.clicks -= 1; return [] }
            Input(id: "echo-field", name: "echo")
                .onInput { _ in [] }
        }.render()
    }
    let renderedHandlers = html.components(separatedBy: "data-component-id=").count - 1
    #expect(renderedHandlers == 3, "render should emit one data-component-id per handler")
    #expect(router.handlerCount == 3, "router should register one handler per modifier")
    _ = await router.handle(EventData(component: "c0", event: "click", data: [:]))
    #expect(counter.clicks == 1, "registered c0 handler should have run")
}

@Test("onOptimisticClick emits a data-optimistic prediction and registers the perform handler")
func optimisticClickModifierWiring() async {
    let counter = ClickCounter()
    let router = EventRouter()
    let html: String = RenderContext.$current.withValue(RenderContext(router: router)) {
        Button("Reset")
            .onOptimisticClick(
                predict: { [FragmentUpdate(id: "counter-value", html: "<div>0</div>")] },
                perform: { _ in counter.resets += 1; return [] }
            )
            .render()
    }
    #expect(html.contains("data-optimistic="), "prediction attribute missing: \(html)")
    #expect(html.contains("&quot;counter-value&quot;"), "prediction json not attribute-escaped: \(html)")
    #expect(router.handlerCount == 1, "optimistic click should register the perform handler")
    _ = await router.handle(EventData(component: "c0", event: "click", data: [:]))
    #expect(counter.resets == 1, "perform handler should have run")
}

final class ClickCounter: @unchecked Sendable {
    var clicks = 0
    var resets = 0
}

@Test("token-backed modifiers emit var() references")
func tokenModifiersEmitVarReferences() {
    let html = Text("Hi")
        .padding(.four)
        .foregroundColor(.primary)
        .render()
    #expect(html.contains("padding: var(--space-4);"), "got: \(html)")
    #expect(html.contains("color: var(--color-primary-500);"), "got: \(html)")
    let raw = Text("Hi").padding(16).render()
    #expect(raw.contains("padding: 16px;"), "raw Int overload must still exist: \(raw)")
}

@Test("expanded fluent event modifiers emit data-event attributes the runtime delegates")
func expandedEventModifiersEmitDataEvent() {
    let router = EventRouter()
    let html: String = RenderContext.$current.withValue(RenderContext(router: router)) {
        Div {
            Button("k").onKeyDown { _ in [] }
            Button("u").onKeyUp { _ in [] }
            Button("p").onKeyPress { _ in [] }
            Button("md").onMouseDown { _ in [] }
            Button("mo").onMouseOver { _ in [] }
            Button("mu").onMouseUp { _ in [] }
            Button("mout").onMouseOut { _ in [] }
        }.render()
    }
    for event in ["keydown", "keyup", "keypress", "mousedown", "mouseup", "mouseover", "mouseout"] {
        #expect(html.contains("data-event=\"\(event)\""), "missing \(event) in: \(html)")
    }
    #expect(router.handlerCount == 7, "one handler per event modifier")
}
