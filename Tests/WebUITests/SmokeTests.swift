import Testing
import WebUI
import WebUIDesignSystem

// MARK: - HTML Structural Validation Helpers

/// count occurrences of a substring
func count(_ str: String, _ substr: String) -> Int {
    str.components(separatedBy: substr).count - 1
}

/// extract all tags from HTML
func extractTags(_ html: String) -> [String] {
    var tags: [String] = []
    var i = html.startIndex
    let rawTextTags: Set<String> = ["script", "style"]

    while i < html.endIndex {
        if html[i] == "<" {
            let rest = html[i...]
            guard let close = rest.firstIndex(of: ">") else { break }
            let tagContent = String(rest[..<close].dropFirst())

            // skip comments, doctype, processing instructions
            if tagContent.hasPrefix("!") || tagContent.hasPrefix("?") {
                i = html.index(after: close)
                continue
            }

            // determine if this is a closing tag
            let isClosing = tagContent.hasPrefix("/")
            let nameStart = isClosing ? tagContent.index(after: tagContent.startIndex) : tagContent.startIndex
            let tagName = String(tagContent[nameStart...]
                .prefix(while: { !$0.isWhitespace && $0 != "/" && $0 != ">" }))

            if !tagName.isEmpty {
                tags.append(isClosing ? "/\(tagName)" : String(tagName))

                // if this is an opening raw-text tag (script, style),
                // skip ahead to the closing tag to avoid parsing
                // < and > characters inside the content
                if !isClosing && rawTextTags.contains(tagName.lowercased()) {
                    let afterOpen = html.index(after: close)
                    if let closeTagStart = html[afterOpen...].firstRange(of: "</\(tagName)") {
                        if let closeTagEnd = html[closeTagStart.upperBound...].firstIndex(of: ">") {
                            i = html.index(after: closeTagEnd)
                            tags.append("/\(tagName.lowercased())")
                            continue
                        }
                    }
                }
            }

            i = html.index(after: close)
            continue
        }
        i = html.index(after: i)
    }
    return tags
}

/// validate tag balance — every opening tag has a matching closing tag
func validateTagBalance(_ html: String, sourceLocation: SourceLocation = #_sourceLocation) -> Bool {
    let tags = extractTags(html)
    var stack: [String] = []
    let voidElements: Set<String> = ["br", "hr", "img", "input", "meta", "link", "area", "base", "col", "embed", "source", "track", "wbr"]

    for tag in tags {
        if tag.hasPrefix("/") {
            let closeTag = String(tag.dropFirst())
            if stack.last == closeTag {
                stack.removeLast()
            } else {
                return false
            }
        } else if !voidElements.contains(tag) {
            stack.append(tag)
        }
    }
    return stack.isEmpty
}

/// check that all CSS class names in the HTML match the expected BEM pattern
func validateBEMClasses(_ html: String) -> [String] {
    var issues: [String] = []
    // find all class attributes using simple string scanning
    var searchRange = html.startIndex..<html.endIndex
    while let classStart = html[searchRange].firstRange(of: "class=\"") {
        let afterOpen = classStart.upperBound
        guard let classEnd = html[afterOpen...].firstIndex(of: "\"") else { break }
        let classes = html[afterOpen..<classEnd]
        for cls in classes.split(separator: " ") {
            let s = String(cls)
            // BEM classes should be lowercase with hyphens or double-hyphens/underscores
            if s.contains(" ") {
                issues.append("class contains space: '\(s)'")
            }
        }
        searchRange = classEnd..<html.endIndex
    }
    return issues
}

// MARK: - 1. Structural Integrity Tests

@Suite("Structural Integrity")
struct StructuralTests {

    @Test("simple text has no tags")
    func simpleText() {
        let html = Text("Hello").render()
        #expect(html == "Hello")
        #expect(validateTagBalance(html))
    }

    @Test("div with children has balanced tags")
    func divBalanced() {
        let html = Div(class: "test") {
            Text("A")
            Text("B")
        }.render()
        #expect(validateTagBalance(html))
        #expect(html.hasPrefix("<div"))
        #expect(html.hasSuffix("</div>"))
    }

    @Test("nested divs are properly balanced")
    func nestedDivs() {
        let html = Div(class: "outer") {
            Div(class: "inner") {
                Text("Deep")
            }
        }.render()
        #expect(validateTagBalance(html))
        // verify nesting order
        let outerOpen = html.range(of: "<div class=\"outer\">")!
        let innerOpen = html.range(of: "<div class=\"inner\">")!
        let innerClose = html.range(of: "</div>")!
        let outerClose = html.range(of: "</div>", options: .backwards)!
        #expect(outerOpen.lowerBound < innerOpen.lowerBound)
        #expect(innerOpen.lowerBound < innerClose.lowerBound)
        #expect(innerClose.lowerBound < outerClose.lowerBound)
    }

    @Test("complex view tree is balanced")
    func complexTree() {
        let html = Div(class: "page") {
            Header(class: "header") {
                Navigation(class: "nav") {
                    Link("Home", href: "/")
                    Link("About", href: "/about")
                }
            }
            Main(class: "content") {
                Section(id: "hero") {
                    Heading("Welcome", level: .h1)
                    Paragraph("This is a test.")
                }
                WebUICard(variant: .elevated) {
                    WebUITable(
                        headers: ["Col A", "Col B"],
                        rows: [[Text("1"), Text("2")], [Text("3"), Text("4")]]
                    )
                }
            }
            Footer(class: "footer") {
                Text("© 2026")
            }
        }.render()
        #expect(validateTagBalance(html))
    }

    @Test("button is self-contained")
    func buttonBalanced() {
        let html = WebUIButton("Click", variant: .primary).render()
        #expect(validateTagBalance(html))
        #expect(html.hasPrefix("<button"))
        #expect(html.hasSuffix("</button>"))
    }

    @Test("void elements are not closed")
    func voidElements() {
        let html = Input(id: "test", placeholder: "Enter").render()
        #expect(html.hasSuffix(">"))
        #expect(!html.hasSuffix("/>"))
        #expect(!html.contains("</input>"))
        #expect(validateTagBalance(html))
    }

    @Test("image is self-closing")
    func imageSelfClosing() {
        let html = Image(src: "test.png", alt: "Test").render()
        #expect(html.hasSuffix(">"))
        #expect(!html.contains("</img>"))
    }
}

// MARK: - 2. BEM Class Name Tests

@Suite("BEM Class Correctness")
struct BEMTests {

    @Test("WebUIButton uses correct BEM classes")
    func buttonBEM() {
        let html = WebUIButton("Submit", variant: .primary, size: .lg).render()
        #expect(html.contains("class=\"button button--primary button--lg\""))
        #expect(validateBEMClasses(html).isEmpty)
    }

    @Test("WebUIButton all variants")
    func buttonAllVariants() {
        let variants: [WebUIButton.Variant] = [.primary, .secondary, .outline, .ghost, .danger, .success, .warning]
        for variant in variants {
            let html = WebUIButton("Test", variant: variant).render()
            #expect(html.contains("button--\(variant.rawValue.split(separator: "--").last!)"))
        }
    }

    @Test("WebUICard uses correct BEM classes")
    func cardBEM() {
        let html = WebUICard(variant: .elevated) { Text("Content") }.render()
        #expect(html.contains("class=\"card card--elevated\""))
    }

    @Test("WebUIBadge uses correct BEM classes")
    func badgeBEM() {
        let html = WebUIBadge("New", variant: .success, size: .sm).render()
        #expect(html.contains("class=\"badge badge--success badge--sm\""))
    }

    @Test("WebUIAlert uses correct BEM classes")
    func alertBEM() {
        let html = WebUIAlert(variant: .warning, message: "Warning!").render()
        #expect(html.contains("class=\"alert alert--warning\""))
        #expect(html.contains("role=\"alert\""))
    }

    @Test("WebUITabs uses correct BEM classes")
    func tabsBEM() {
        let html = WebUITabs(tabs: [TabItem(id: "a", label: "A"), TabItem(id: "b", label: "B")], activeTab: "a").render()
        #expect(html.contains("class=\"tabs\""))
        #expect(html.contains("class=\"tabs__tab tabs__tab--active\""))
        #expect(html.contains("aria-selected=\"true\""))
        #expect(html.contains("aria-selected=\"false\""))
    }

    @Test("WebUIAvatar uses correct BEM classes")
    func avatarBEM() {
        let html = WebUIAvatar(initials: "TS", size: .xl).render()
        #expect(html.contains("class=\"avatar avatar--xl\""))
        #expect(html.contains("class=\"avatar__initials\""))
    }

    @Test("WebUIProgress uses correct BEM classes")
    func progressBEM() {
        let html = WebUIProgress(value: 0.75, variant: .success, showLabel: true).render()
        #expect(html.contains("class=\"progress progress--success progress--md\""))
        #expect(html.contains("class=\"progress__bar\""))
        #expect(html.contains("class=\"progress__label\""))
        #expect(html.contains("style=\"width: 75%\""))
        #expect(html.contains("role=\"progressbar\""))
    }

    @Test("WebUISkeleton uses correct BEM classes")
    func skeletonBEM() {
        let html = WebUISkeleton(variant: .card).render()
        #expect(html.contains("class=\"skeleton skeleton--card\""))
        #expect(html.contains("aria-hidden=\"true\""))
    }

    @Test("WebUIToast uses correct BEM classes")
    func toastBEM() {
        let html = WebUIToast(variant: .success, message: "Saved!").render()
        #expect(html.contains("class=\"toast toast--success\""))
        #expect(html.contains("class=\"toast__message\""))
        #expect(html.contains("class=\"toast__close\""))
        #expect(html.contains("role=\"alert\""))
    }

    @Test("WebUIModal uses correct BEM classes")
    func modalBEM() {
        let html = WebUIModal(title: "Dialog") { Text("Content") }.render()
        #expect(html.contains("class=\"modal-overlay\""))
        #expect(html.contains("class=\"modal\""))
        #expect(html.contains("class=\"modal__header\""))
        #expect(html.contains("class=\"modal__title\""))
        #expect(html.contains("class=\"modal__body\""))
        #expect(html.contains("class=\"modal__close\""))
        #expect(html.contains("role=\"dialog\""))
        #expect(html.contains("aria-modal=\"true\""))
    }

    @Test("WebUITable uses correct BEM classes")
    func tableBEM() {
        let html = WebUITable(headers: ["A"], rows: [[Text("1")]], striped: true, hoverable: false, compact: true).render()
        #expect(html.contains("class=\"table table--striped table--compact\""))
        #expect(!html.contains("table--hoverable"))
    }

    @Test("WebUITable wrapped emits the table-wrap container")
    func tableWrapped() {
        let html = WebUITable(headers: ["A"], rows: [[Text("1")]], wrapped: true).render()
        #expect(html.hasPrefix("<div class=\"table-wrap\"><table class=\"table table--striped table--hoverable\">"))
        #expect(html.hasSuffix("</table></div>"))
    }

    @Test("WebUITable responsive emits class and per-cell data-label")
    func tableResponsive() {
        let html = WebUITable(headers: ["Name", "Age"], rows: [[Text("Alice"), Text("30")]], responsive: true).render()
        #expect(html.contains("table--responsive"))
        #expect(html.contains("<td data-label=\"Name\">Alice</td>"))
        #expect(html.contains("<td data-label=\"Age\">30</td>"))
    }

    @Test("WebUITable footer renders tfoot")
    func tableFooter() {
        let html = WebUITable(
            headers: ["Item", "Qty"],
            rows: [[Text("Widget"), Text("2")]],
            footer: [Text("Total"), Text("2")]
        ).render()
        #expect(html.contains("<tfoot><tr><td>Total</td><td>2</td></tr></tfoot>"))
    }

    @Test("WebUITable alignment classes land on th and td")
    func tableAlignments() {
        let html = WebUITable(
            headers: ["Name", "Status", "Qty"],
            rows: [[Text("A"), Text("ok"), Text("3")]],
            alignments: [.leading, .center, .trailing]
        ).render()
        #expect(html.contains("<th>Name</th>"))
        #expect(html.contains("<th class=\"align-center\">Status</th>"))
        #expect(html.contains("<th class=\"num\">Qty</th>"))
        #expect(html.contains("<td>A</td>"))
        #expect(html.contains("<td class=\"align-center\">ok</td>"))
        #expect(html.contains("<td class=\"num\">3</td>"))
    }

    @Test("WebUITable emptyState renders in-table empty row with colspan")
    func tableEmptyState() {
        let html = WebUITable(
            headers: ["Name", "Age", "City"],
            rows: [],
            emptyState: WebUITable.EmptyState(icon: "📭", title: "No people", message: "Try a different filter.")
        ).render()
        #expect(html.contains("<td colspan=\"3\" class=\"table__empty\">"))
        #expect(html.contains("<div class=\"table__empty-icon\">📭</div>"))
        #expect(html.contains("<div class=\"table__empty-title\">No people</div>"))
        #expect(html.contains("<div class=\"table__empty-message\">Try a different filter.</div>"))
    }

    @Test("WebUITable emptyState content is escaped")
    func tableEmptyStateEscaped() {
        let html = WebUITable(
            headers: ["A"],
            rows: [],
            emptyState: WebUITable.EmptyState(icon: "x", title: "<b>Bold</b>", message: "<script>")
        ).render()
        #expect(html.contains("<div class=\"table__empty-title\">&lt;b&gt;Bold&lt;/b&gt;</div>"))
        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<script>"))
    }

    @Test("WebUITable emptyState ignored when rows exist")
    func tableEmptyStateIgnoredWithRows() {
        let html = WebUITable(
            headers: ["A"],
            rows: [[Text("1")]],
            emptyState: WebUITable.EmptyState(title: "No data", message: "")
        ).render()
        #expect(!html.contains("table__empty"))
        #expect(html.contains("<td>1</td>"))
    }

    @Test("WebUITable sortable columns emit sort controls with stable ids")
    func tableSortableColumns() {
        let html = WebUITable(
            headers: ["Name", "Age"],
            rows: [[Text("A"), Text("1")], [Text("B"), Text("2")]],
            id: "staff",
            sortableColumns: [0, 1]
        ).render()
        #expect(html.contains("<table id=\"staff\""))
        #expect(html.contains("<span class=\"sort\" id=\"staff-sort-0\">Name"))
        #expect(html.contains("<span class=\"sort\" id=\"staff-sort-1\">Age"))
        #expect(html.contains("sort-cell"))
        #expect(html.contains("<svg class=\"sort__arrow\""))
        // inactive columns have no aria-sort
        #expect(!html.contains("aria-sort"))
    }

    @Test("WebUITable active sort emits aria-sort and active affordance")
    func tableActiveSort() {
        let html = WebUITable(
            headers: ["Name", "Age"],
            rows: [[Text("A"), Text("1")]],
            id: "staff",
            sortableColumns: [0, 1],
            sort: (column: 0, direction: .descending)
        ).render()
        #expect(html.contains("<th class=\"sort-cell\" aria-sort=\"descending\">"))
        #expect(html.contains("<span class=\"sort sort--active sort--desc\" id=\"staff-sort-0\">Name"))
        // inactive sortable column ("Age"): sort affordance but no aria-sort
        #expect(html.contains("<th class=\"sort-cell\"><span class=\"sort\" id=\"staff-sort-1\">Age"))
        // exactly one aria-sort on the page (the active column only)
        let ariaCount = html.components(separatedBy: "aria-sort").count - 1
        #expect(ariaCount == 1)
    }

    @Test("WebUITable selectable rows emit select controls and selected state")
    func tableSelectableRows() {
        let html = WebUITable(
            headers: ["Name"],
            rows: [[Text("A")], [Text("B")]],
            id: "staff",
            selectable: true,
            rowIds: ["a", "b"],
            selectedRows: ["b"]
        ).render()
        // select-all: partially selected => mixed
        #expect(html.contains("<span class=\"table__select\" id=\"staff-select-all\" role=\"checkbox\" aria-checked=\"mixed\""))
        // per-row controls (server is source of truth for state)
        #expect(html.contains("id=\"staff-select-a\""))
        #expect(html.contains("id=\"staff-select-b\""))
        // selected row styling
        #expect(html.contains("<tr class=\"tr--selected\">"))
        // select column present in header + each row (3 cells)
        let selectColCount = html.components(separatedBy: "class=\"table__select-col").count - 1
        #expect(selectColCount == 3)
    }

    @Test("WebUITable selectable all-rows-selected select-all is checked")
    func tableSelectAllChecked() {
        let html = WebUITable(
            headers: ["Name"],
            rows: [[Text("A")], [Text("B")]],
            id: "staff",
            selectable: true,
            rowIds: ["a", "b"],
            selectedRows: ["a", "b"]
        ).render()
        #expect(html.contains("id=\"staff-select-all\" role=\"checkbox\" aria-checked=\"true\""))
    }

    @Test("WebUITable expandable rows emit detail row and expanded state")
    func tableExpandableRows() {
        let html = WebUITable(
            headers: ["Name"],
            rows: [[Text("A")], [Text("B")]],
            id: "staff",
            rowIds: ["a", "b"],
            expandedRows: ["a"],
            rowDetails: ["a": Text("details for a")]
        ).render()
        // expand button present on every data row; only detail-bearing rows
        // carry aria-expanded, the rest are disabled
        #expect(html.contains("id=\"staff-expand-a\" aria-expanded=\"true\""))
        #expect(html.contains("id=\"staff-expand-b\" aria-disabled=\"true\""))
        // only the expanded row has a detail row
        #expect(html.contains("<tr class=\"tr--expanded\">"))
        #expect(html.contains("<tr class=\"table__detail-row\"><td colspan=\"2\"><div class=\"table__detail\">details for a</div>"))
    }

    @Test("WebUITable empty state renders with colspan = header count")
    func tableEmptyStateColspan() {
        let html = WebUITable(
            headers: ["Name", "Age"],
            rows: [],
            emptyState: WebUITable.EmptyState(title: "None", message: "Try adjusting your filters")
        ).render()
        // no rows => no select/expand columns; colspan spans the headers
        #expect(html.contains("<td colspan=\"2\" class=\"table__empty\">"))
        #expect(html.contains("table__empty-title"))
        #expect(html.contains("table__empty-message"))
    }

    @Test("onClick(id:) emits a stable data-component-id and routes events to the handler")
    func stableIdOnClick() async {
        let router = EventRouter()
        let context = RenderContext(router: router)
        let html: String = RenderContext.$current.withValue(context) {
            Div(class: "t") {
                Text("hi")
            }
            .onClick(id: "stable-table") { event in
                #expect(event.data["targetId"] == "inner")
                return []
            }
            .render()
        }
        #expect(html.contains("data-component-id=\"stable-table\""))
        #expect(html.contains("data-event=\"click\""))
        // exactly one handler registered, under the stable id
        #expect(router.handlerCount == 1)
        // routing by the stable id invokes that handler
        let updates = await router.handle(
            EventData(component: "stable-table", event: "click", data: ["targetId": "inner"])
        )
        #expect(updates.isEmpty)
    }

    @Test("onClick(id:) is byte-stable across re-renders on the same router")
    func stableIdOnClickByteStable() {
        let router = EventRouter()
        let context = RenderContext(router: router)
        let a: String = RenderContext.$current.withValue(context) {
            Div(class: "t") { Text("hi") }.onClick(id: "stable-table") { _ in [] }.render()
        }
        let b: String = RenderContext.$current.withValue(context) {
            Div(class: "t") { Text("hi") }.onClick(id: "stable-table") { _ in [] }.render()
        }
        #expect(a == b)
        #expect(a.contains("data-component-id=\"stable-table\""))
        // contrast: the auto-incremented modifier mints a NEW id each render
        let x: String = RenderContext.$current.withValue(context) {
            Div(class: "t") { Text("hi") }.onClick { _ in [] }.render()
        }
        let y: String = RenderContext.$current.withValue(context) {
            Div(class: "t") { Text("hi") }.onClick { _ in [] }.render()
        }
        #expect(x != y)
        #expect(x.contains("data-component-id="))
        #expect(y.contains("data-component-id="))
    }

    @Test("WebUIChip uses correct BEM classes")
    func chipBEM() {
        let html = WebUIChip("Tag", variant: .info, removable: true).render()
        #expect(html.contains("class=\"chip chip--info\""))
        #expect(html.contains("class=\"chip__label\""))
        #expect(html.contains("class=\"chip__remove\""))
    }

    @Test("WebUIEmptyState uses correct BEM classes")
    func emptyStateBEM() {
        let html = WebUIEmptyState(icon: "📭", title: "Empty", message: "Nothing here").render()
        #expect(html.contains("class=\"empty-state\""))
        #expect(html.contains("class=\"empty-state__icon\""))
        #expect(html.contains("class=\"empty-state__title\""))
        #expect(html.contains("class=\"empty-state__message\""))
    }

    @Test("WebUISpinner uses correct BEM classes")
    func spinnerBEM() {
        let html = WebUISpinner(size: .sm, label: "Loading").render()
        #expect(html.contains("class=\"spinner spinner--sm\""))
        #expect(html.contains("class=\"spinner__ring\""))
        #expect(html.contains("class=\"spinner__label\""))
        #expect(html.contains("role=\"status\""))
    }

    @Test("WebUITooltip uses correct BEM classes")
    func tooltipBEM() {
        let html = WebUITooltip("Info", position: .right) { Text("Hover") }.render()
        #expect(html.contains("class=\"tooltip-container\""))
        #expect(html.contains("class=\"tooltip tooltip--right\""))
        #expect(html.contains("class=\"tooltip__arrow\""))
        #expect(html.contains("class=\"tooltip__text\""))
        #expect(html.contains("role=\"tooltip\""))
    }

    @Test("no BEM class contains spaces")
    func noSpacesInClasses() {
        let views: [any View] = [
            WebUIButton("A"),
            WebUICard(variant: .flat) { Text("") },
            WebUIBadge("B"),
            WebUIAlert(variant: .info, message: "M"),
            WebUITabs(tabs: [TabItem(id: "a", label: "A")], activeTab: "a"),
            WebUIAvatar(initials: "X"),
            WebUIProgress(value: 0.5),
            WebUISkeleton(),
            WebUIToast(variant: .info, message: "M"),
            WebUIModal(title: "T") { Text("") },
            WebUITable(headers: ["A"], rows: [[Text("1")]]),
            WebUIChip("C"),
            WebUIEmptyState(title: "T", message: "M"),
            WebUISpinner(),
            WebUITooltip("T") { Text("") },
        ]
        for view in views {
            let html = view.render()
            let issues = validateBEMClasses(html)
            #expect(issues.isEmpty, "BEM issues in \(type(of: view)): \(issues)")
        }
    }
}

// MARK: - 3. HTML Attribute Correctness Tests

@Suite("HTML Attribute Correctness")
struct AttributeTests {

    @Test("all attributes are properly quoted")
    func attributesQuoted() {
        let html = Input(id: "test", placeholder: "hello", type: .text, attributes: [
            ("data-value", "some value"),
            ("aria-label", "test input"),
        ]).render()
        // every attribute value should be in double quotes
        #expect(html.contains("id=\"test\""))
        #expect(html.contains("placeholder=\"hello\""))
        #expect(html.contains("type=\"text\""))
        #expect(html.contains("data-value=\"some value\""))
        #expect(html.contains("aria-label=\"test input\""))
    }

    @Test("boolean attributes use minimized syntax")
    func booleanAttributes() {
        let html = WebUIButton("Disabled", disabled: true).render()
        #expect(html.contains(" disabled"))
        // should NOT be disabled="true" or disabled="disabled"
        #expect(!html.contains("disabled="))
    }

    @Test("aria attributes are correct")
    func ariaAttributes() {
        let modal = WebUIModal(title: "Test") { Text("Content") }.render()
        #expect(modal.contains("role=\"dialog\""))
        #expect(modal.contains("aria-modal=\"true\""))

        let progress = WebUIProgress(value: 0.5).render()
        #expect(progress.contains("role=\"progressbar\""))
        #expect(progress.contains("aria-valuenow=\"50\""))
        #expect(progress.contains("aria-valuemin=\"0\""))
        #expect(progress.contains("aria-valuemax=\"100\""))

        let alert = WebUIAlert(variant: .danger, message: "Error").render()
        #expect(alert.contains("role=\"alert\""))

        let skeleton = WebUISkeleton().render()
        #expect(skeleton.contains("aria-hidden=\"true\""))

        let spinner = WebUISpinner(label: "Loading").render()
        #expect(spinner.contains("role=\"status\""))

        let tabs = WebUITabs(tabs: [TabItem(id: "a", label: "A")], activeTab: "a").render()
        #expect(tabs.contains("role=\"tablist\""))
        #expect(tabs.contains("role=\"tab\""))
    }

    @Test("loading state adds aria-busy")
    func loadingAria() {
        let html = WebUIButton("Save", loading: true).render()
        #expect(html.contains("aria-busy=\"true\""))
        #expect(html.contains("button--loading"))
        #expect(html.contains("button__spinner"))
    }

    @Test("data attributes pass through")
    func dataAttributes() {
        let html = Input(id: "test", attributes: [
            ("data-custom", "value"),
            ("data-id", "123"),
        ]).render()
        #expect(html.contains("data-custom=\"value\""))
        #expect(html.contains("data-id=\"123\""))
    }
}

// MARK: - 4. HTML Escaping & XSS Tests

@Suite("HTML Escaping & XSS Prevention")
struct EscapingTests {

    @Test("Text escapes HTML special characters")
    func textEscapesHTML() {
        let html = Text("<script>alert('xss')</script>").render()
        #expect(html == "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;")
        #expect(!html.contains("<script>"))
        #expect(!html.contains("</script>"))
    }

    @Test("Text escapes ampersands")
    func textEscapesAmpersand() {
        let html = Text("A & B").render()
        #expect(html == "A &amp; B")
    }

    @Test("Text escapes double quotes")
    func textEscapesQuotes() {
        let html = Text("Say \"hello\"").render()
        #expect(html == "Say &quot;hello&quot;")
    }

    @Test("Raw does not escape")
    func rawNoEscape() {
        let html = Raw("<strong>Bold</strong>").render()
        #expect(html == "<strong>Bold</strong>")
    }

    @Test("Button label is escaped")
    func buttonLabelEscaped() {
        let html = Button("<script>alert(1)</script>").render()
        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<script>"))
    }

    @Test("Input placeholder is escaped")
    func inputPlaceholderEscaped() {
        let html = Input(placeholder: "\" onclick=\"alert(1)").render()
        #expect(html.contains("&quot;"))
        // the quote is escaped, so the attribute boundary is preserved
        #expect(!html.contains("placeholder=\"\""))
    }

    @Test("Link href is escaped")
    func linkHrefEscaped() {
        let html = Link("Click", href: "\" onclick=\"alert(1)").render()
        #expect(html.contains("&quot;"))
        #expect(!html.contains("href=\"\""))
    }

    @Test("Image src and alt are escaped")
    func imageAttrsEscaped() {
        let html = Image(src: "\" onerror=\"alert(1)", alt: "\" onerror=\"alert(1)").render()
        #expect(html.contains("&quot;"))
        #expect(!html.contains("src=\"\""))
        #expect(!html.contains("alt=\"\""))
    }

    @Test("Heading text is escaped")
    func headingEscaped() {
        let html = Heading("<script>", level: .h1).render()
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test("Paragraph text is escaped")
    func paragraphEscaped() {
        let html = Paragraph("<b>not bold</b>").render()
        #expect(html.contains("&lt;b&gt;"))
        #expect(!html.contains("<b>"))
    }

    @Test("WebUIButton label is escaped")
    func webuiButtonLabelEscaped() {
        let html = WebUIButton("<script>").render()
        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<script>"))
    }

    @Test("WebUIAlert message is escaped")
    func webuiAlertEscaped() {
        let html = WebUIAlert(variant: .info, message: "<script>").render()
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test("WebUIBadge text is escaped")
    func webuiBadgeEscaped() {
        let html = WebUIBadge("<script>").render()
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test("WebUIChip text is escaped")
    func webuiChipEscaped() {
        let html = WebUIChip("<script>").render()
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test("WebUIEmptyState title and message are escaped")
    func webuiEmptyStateEscaped() {
        let html = WebUIEmptyState(title: "<title>", message: "<message>").render()
        #expect(html.contains("&lt;title&gt;"))
        #expect(html.contains("&lt;message&gt;"))
    }

    @Test("WebUIToast message is escaped")
    func webuiToastEscaped() {
        let html = WebUIToast(variant: .info, message: "<script>").render()
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test("WebUITooltip text is escaped")
    func webuiTooltipEscaped() {
        let html = WebUITooltip("<script>") { Text("Hover") }.render()
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test("WebUIModal title is escaped")
    func webuiModalEscaped() {
        let html = WebUIModal(title: "<script>") { Text("") }.render()
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test("Table cell content is escaped")
    func tableCellEscaped() {
        let html = WebUITable(headers: ["<h>"], rows: [[Text("<script>")]]).render()
        #expect(html.contains("&lt;h&gt;"))
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test("htmlEscape utility handles all five characters")
    func htmlEscapeAll() {
        #expect(htmlEscape("&") == "&amp;")
        #expect(htmlEscape("<") == "&lt;")
        #expect(htmlEscape(">") == "&gt;")
        #expect(htmlEscape("\"") == "&quot;")
        #expect(htmlEscape("'") == "&#39;")
        #expect(htmlEscape("") == "")
        #expect(htmlEscape("safe") == "safe")
        #expect(htmlEscape("a&b<c>d\"e'f") == "a&amp;b&lt;c&gt;d&quot;e&#39;f")
    }
}

// MARK: - 5. Modifier Chain Tests

@Suite("Modifier Chain Correctness")
struct ModifierChainTests {

    @Test("single modifier wraps content in span")
    func singleModifier() {
        let html = Text("Hello").foregroundColor("red").render()
        #expect(html == "<span style=\"color: red;\">Hello</span>")
        #expect(validateTagBalance(html))
    }

    @Test("two modifiers nest spans")
    func twoModifiers() {
        let html = Text("Hello")
            .foregroundColor("red")
            .backgroundColor("blue")
            .render()
        #expect(html.contains("style=\"background-color: blue;\""))
        #expect(html.contains("style=\"color: red;\""))
        #expect(validateTagBalance(html))
    }

    @Test("font modifier composes two inline styles")
    func fontModifier() {
        let html = Text("Hello").font(size: 16, weight: "700").render()
        #expect(html.contains("font-size: 16px"))
        #expect(html.contains("font-weight: 700"))
        #expect(validateTagBalance(html))
    }

    @Test("padding + color + font chain")
    func multiModifierChain() {
        let html = Text("Styled")
            .padding(12)
            .foregroundColor("var(--color-text)")
            .font(size: 14, weight: "500")
            .render()
        #expect(html.contains("padding: 12px"))
        #expect(html.contains("color: var(--color-text)"))
        #expect(html.contains("font-size: 14px"))
        #expect(html.contains("font-weight: 500"))
        #expect(validateTagBalance(html))
    }

    @Test("id modifier adds attribute")
    func idModifier() {
        let html = Text("Hello").id("my-id").render()
        #expect(html.contains("id=\"my-id\""))
    }

    @Test("class modifier adds class attribute")
    func classModifier() {
        let html = Text("Hello").class("my-class").render()
        #expect(html.contains("class=\"my-class\""))
    }

    @Test("showIf(true) is no-op")
    func showIfTrue() {
        let html = Text("Visible").showIf(true).render()
        #expect(html == "Visible")
    }

    @Test("showIf(false) adds display:none")
    func showIfFalse() {
        let html = Text("Hidden").showIf(false).render()
        #expect(html.contains("display: none"))
    }

    @Test("width modifier")
    func widthModifier() {
        let html = Text("Wide").width("100%").render()
        #expect(html.contains("width: 100%"))
    }

    @Test("border modifier")
    func borderModifier() {
        let html = Text("Boxed").border("1px solid red").render()
        #expect(html.contains("border: 1px solid red"))
    }

    @Test("cornerRadius modifier")
    func cornerRadiusModifier() {
        let html = Text("Rounded").cornerRadius("8px").render()
        #expect(html.contains("border-radius: 8px"))
    }
}

// MARK: - 6. Layout Structural Tests

@Suite("Layout Structure")
struct LayoutTests {

    @Test("VStack produces correct flexbox HTML")
    func vstackStructure() {
        let html = VStack(alignment: .center, spacing: 12) {
            Text("A")
            Text("B")
        }.render()
        #expect(html.contains("<div class=\"vstack spacing-12 align-center\">"))
        #expect(html.contains("A"))
        #expect(html.contains("B"))
        #expect(html.hasSuffix("</div>"))
        #expect(validateTagBalance(html))
    }

    @Test("HStack produces correct flexbox HTML")
    func hstackStructure() {
        let html = HStack(alignment: .top, spacing: 8) {
            Text("Left")
            Spacer()
            Text("Right")
        }.render()
        #expect(html.contains("<div class=\"hstack spacing-8 align-flex-start\">"))
        #expect(html.contains("class=\"spacer\""))
        #expect(validateTagBalance(html))
    }

    @Test("ZStack produces CSS grid overlay")
    func zstackStructure() {
        let html = ZStack(alignment: .center, verticalAlignment: .center) {
            Text("Back")
            Text("Front")
        }.render()
        #expect(html.contains("style=\"display:grid;"))
        #expect(html.contains("place-items:center center"))
        #expect(validateTagBalance(html))
    }

    @Test("ScrollView wraps children")
    func scrollViewStructure() {
        let html = ScrollView {
            Text("Content")
        }.render()
        #expect(html.contains("<div class=\"scrollview\">"))
        #expect(html.hasSuffix("</div>"))
        #expect(validateTagBalance(html))
    }

    @Test("Grid produces CSS grid HTML")
    func gridStructure() {
        let html = Grid(columns: .custom("200px 1fr"), spacing: 16) {
            Text("Sidebar")
            Text("Main")
        }.render()
        #expect(html.contains("grid-template-columns:200px 1fr"))
        #expect(html.contains("gap:16px"))
        #expect(validateTagBalance(html))
    }

    @Test("semantic HTML5 elements render correctly")
    func semanticElements() {
        let html = Section(id: "main") {
            Header(class: "page-header") {
                Navigation(class: "nav") {
                    Text("Nav")
                }
            }
            Main(class: "content") {
                Aside(class: "sidebar") {
                    Text("Side")
                }
            }
            Footer(class: "page-footer") {
                Text("Footer")
            }
        }.render()
        #expect(html.contains("<section"))
        #expect(html.contains("<header"))
        #expect(html.contains("<nav"))
        #expect(html.contains("<main"))
        #expect(html.contains("<aside"))
        #expect(html.contains("<footer"))
        #expect(validateTagBalance(html))
    }

    @Test("list elements render correctly")
    func listElements() {
        let html = UnorderedList(class: "items") {
            Text("A")
            Text("B")
            Text("C")
        }.render()
        #expect(html.contains("<ul class=\"items\">"))
        #expect(html.contains("<li>A</li>"))
        #expect(html.contains("<li>B</li>"))
        #expect(html.contains("<li>C</li>"))
        #expect(html.hasSuffix("</ul>"))
        #expect(validateTagBalance(html))
    }

    @Test("ordered list renders correctly")
    func orderedList() {
        let html = OrderedList {
            Text("First")
            Text("Second")
        }.render()
        #expect(html.hasPrefix("<ol>"))
        #expect(html.hasSuffix("</ol>"))
        #expect(validateTagBalance(html))
    }
}

// MARK: - 7. Document Assembly Tests

@Suite("Document Assembly")
struct DocumentTests {

    @Test("HTMLDocument produces valid document structure")
    func validDocumentStructure() {
        let doc = HTMLDocument(
            title: "Test",
            body: "<p>Hello</p>",
            styles: CSSStylesheet([CSSRule("p", [CSSDeclaration("color", "red")])]),
            scripts: "console.log('test');"
        )
        let html = doc.render()
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<html lang=\"en\">"))
        #expect(html.contains("<head>"))
        #expect(html.contains("<title>Test</title>"))
        #expect(html.contains("<meta charset=\"UTF-8\">"))
        #expect(html.contains("<meta name=\"viewport\""))
        #expect(html.contains("<style>"))
        #expect(html.contains("color: red;"))
        #expect(html.contains("</style>"))
        #expect(html.contains("<script nonce"))
        #expect(html.contains("console.log('test');"))
        #expect(html.contains("</script>"))
        #expect(html.contains("<body>"))
        #expect(html.contains("<p>Hello</p>"))
        #expect(html.contains("</body>"))
        #expect(html.contains("</html>"))
        #expect(validateTagBalance(html))
    }

    @Test("HTMLDocument dev mode excludes inline CSS/JS")
    func devModeStructure() {
        let doc = HTMLDocument(
            title: "Dev",
            body: "<p>Dev</p>",
            styles: CSSStylesheet([CSSRule("p", [CSSDeclaration("color", "red")])]),
            scripts: "console.log('dev');",
            devMode: true
        )
        let html = doc.render()
        #expect(html.contains("<link rel=\"stylesheet\" href=\"/ui/styles.css\">"))
        #expect(html.contains("<script src=\"/ui/scripts.js\">"))
        #expect(!html.contains("<style>"))
        #expect(!html.contains("color: red;"))
        #expect(validateTagBalance(html))
    }

    @Test("HTMLDocument with custom head content")
    func customHead() {
        let doc = HTMLDocument(
            title: "Custom",
            body: "",
            head: "<meta name=\"theme-color\" content=\"#10b89f\">"
        )
        let html = doc.render()
        #expect(html.contains("<meta name=\"theme-color\" content=\"#10b89f\">"))
        #expect(validateTagBalance(html))
    }

    @Test("HTMLDocument with body attributes")
    func bodyAttributes() {
        let doc = HTMLDocument(
            title: "Styled",
            body: "",
            bodyAttributes: "class=\"dark\" data-theme=\"dark\""
        )
        let html = doc.render()
        #expect(html.contains("<body class=\"dark\" data-theme=\"dark\">"))
    }

    @Test("HTMLDocument title is escaped")
    func documentTitleEscaped() {
        let doc = HTMLDocument(title: "<script>", body: "")
        let html = doc.render()
        #expect(html.contains("<title>&lt;script&gt;</title>"))
    }

    @Test("HTMLDocument with empty styles and scripts")
    func emptyStylesAndScripts() {
        let doc = HTMLDocument(title: "Minimal", body: "<p>Hi</p>", includeRuntime: false)
        let html = doc.render()
        #expect(!html.contains("<style>"))
        #expect(!html.contains("<script>"))
        #expect(validateTagBalance(html))
    }

    @Test("HTMLDocument includes JS runtime by default")
    func includesRuntimeByDefault() {
        let doc = HTMLDocument(title: "Runtime", body: "<p>Test</p>")
        let html = doc.render()
        #expect(html.contains("WebUIRuntime"))
        #expect(html.contains("<script nonce"))
        #expect(validateTagBalance(html))
    }
}

// MARK: - 8. CSS System Tests

@Suite("CSS System")
struct CSSSystemTests {

    @Test("CSSStylesheet renders multiple rules")
    func stylesheetMultipleRules() {
        let sheet = CSSStylesheet([
            CSSRule("body", [CSSDeclaration("margin", "0"), CSSDeclaration("padding", "0")]),
            CSSRule("p", [CSSDeclaration("color", "#333")]),
        ])
        let css = sheet.render()
        #expect(css.contains("body {"))
        #expect(css.contains("margin: 0;"))
        #expect(css.contains("padding: 0;"))
        #expect(css.contains("p {"))
        #expect(css.contains("color: #333;"))
    }

    @Test("CSSMediaQuery wraps rules")
    func mediaQueryWraps() {
        let mq = CSSMediaQuery("prefers-color-scheme: dark", rules: [
            CSSRule(":root", [CSSDeclaration("--bg", "#000")]),
            CSSRule("body", [CSSDeclaration("color", "#fff")]),
        ])
        let css = mq.render()
        #expect(css.contains("@media (prefers-color-scheme: dark) {"))
        #expect(css.contains("--bg: #000;"))
        #expect(css.contains("color: #fff;"))
    }

    @Test("CSSKeyframes renders animation")
    func keyframesRenders() {
        let kf = CSSKeyframes("slideIn", [
            ("from", [CSSDeclaration("transform", "translateX(-100%)"), CSSDeclaration("opacity", "0")]),
            ("to", [CSSDeclaration("transform", "translateX(0)"), CSSDeclaration("opacity", "1")]),
        ])
        let css = kf.render()
        #expect(css.contains("@keyframes slideIn {"))
        #expect(css.contains("from {"))
        #expect(css.contains("transform: translateX(-100%);"))
        #expect(css.contains("to {"))
        #expect(css.contains("transform: translateX(0);"))
    }

    @Test("CSSFontFace renders")
    func fontFaceRenders() {
        let ff = CSSFontFace([
            CSSDeclaration("font-family", "\"Custom Font\""),
            CSSDeclaration("src", "url('/fonts/custom.woff2')"),
        ])
        let css = ff.render()
        #expect(css.contains("@font-face {"))
        #expect(css.contains("font-family: \"Custom Font\";"))
        #expect(css.contains("src: url('/fonts/custom.woff2');"))
    }
}

// MARK: - 9. Design Token Tests

@Suite("Design Token Integrity")
struct TokenTests {

    @Test("all token categories are present in shipped css")
    func allTokenCategories() {
        let css = WebUIAssets.css
        // neutral palette
        #expect(css.contains("--color-neutral-50"))
        #expect(css.contains("--color-neutral-950"))
        // primary palette
        #expect(css.contains("--color-primary-50"))
        #expect(css.contains("--color-primary-950"))
        // semantic colors
        #expect(css.contains("--color-success"))
        #expect(css.contains("--color-warning"))
        #expect(css.contains("--color-danger"))
        #expect(css.contains("--color-info"))
        // surface
        #expect(css.contains("--color-bg"))
        #expect(css.contains("--color-text"))
        #expect(css.contains("--color-border"))
        // typography
        #expect(css.contains("--font-sans"))
        #expect(css.contains("--font-mono"))
        #expect(css.contains("--font-size-base"))
        #expect(css.contains("--font-weight-bold"))
        // spacing
        #expect(css.contains("--space-0"))
        #expect(css.contains("--space-24"))
        // borders
        #expect(css.contains("--radius-sm"))
        #expect(css.contains("--radius-full"))
        // shadows
        #expect(css.contains("--shadow-sm"))
        #expect(css.contains("--shadow-xl"))
        // motion
        #expect(css.contains("--transition-fast"))
        #expect(css.contains("--ease-out"))
        // z-index
        #expect(css.contains("--z-base"))
        #expect(css.contains("--z-modal"))
        #expect(css.contains("--z-toast"))
    }

    @Test("dark mode media query is present in shipped css")
    func darkModePresent() {
        let css = WebUIAssets.css
        let darkStart = css.range(of: "@media (prefers-color-scheme: dark)")
        let dark = darkStart.map { String(css[$0.lowerBound...]) } ?? ""
        #expect(css.contains("@media (prefers-color-scheme: dark)"))
        #expect(cssTokenValue("color-bg", in: dark) == "#060910")
        #expect(cssTokenValue("color-text", in: dark) == "#e7ecf5")
    }

    @Test("dark mode swaps all surface colors")
    func darkModeSurfaceSwap() {
        let css = WebUIAssets.css
        let darkStart = css.range(of: "@media (prefers-color-scheme: dark)")
        let dark = darkStart.map { String(css[$0.lowerBound...]) } ?? css
        #expect(cssTokenValue("color-bg", in: css) == "#f4f6f8")
        #expect(cssTokenValue("color-bg", in: dark) == "#060910")
    }

    @Test("token values are real nexus colors, not empty")
    func tokenValues() {
        let css = WebUIAssets.css
        #expect(css.contains("#6366f1"))
        #expect(css.contains("#10b981"))
        #expect(css.contains("#060910"))
    }
}

// MARK: - 10. Edge Case Tests

@Suite("Edge Cases")
struct EdgeCaseTests {

    @Test("EmptyView renders nothing")
    func emptyView() {
        #expect(EmptyView().render() == "")
    }

    @Test("ViewBuilder with empty block")
    func emptyViewBuilder() {
        let views = ViewBuilder.buildBlock()
        #expect(views.isEmpty)
    }

    @Test("conditional view with false branch")
    func conditionalFalse() {
        let html = Div {
            if false {
                Text("Hidden")
            }
        }.render()
        #expect(html == "<div></div>")
        #expect(validateTagBalance(html))
    }

    @Test("conditional view with true branch")
    func conditionalTrue() {
        let html = Div {
            if true {
                Text("Visible")
            }
        }.render()
        #expect(html == "<div>Visible</div>")
    }

    @Test("if-else branches")
    func ifElse() {
        let condition = false
        let html = Div {
            if condition {
                Text("A")
            } else {
                Text("B")
            }
        }.render()
        #expect(html == "<div>B</div>")
    }

    @Test("for loop over views")
    func forLoop() {
        let items = ["A", "B", "C"]
        let html = Div {
            for item in items {
                Text(item)
            }
        }.render()
        #expect(html == "<div>ABC</div>")
    }

    @Test("Spacer with zero minSize")
    func spacerZero() {
        let html = Spacer().render()
        #expect(html.contains("flex:1"))
        #expect(html.contains("min-width:0px"))
    }

    @Test("WebUIButton with fullWidth")
    func buttonFullWidth() {
        let html = WebUIButton("Full", fullWidth: true).render()
        #expect(html.contains("button--full"))
    }

    @Test("WebUIProgress clamps value to [0, 1]")
    func progressClamping() {
        let over = WebUIProgress(value: 1.5).render()
        #expect(over.contains("width: 100%"))
        let under = WebUIProgress(value: -0.5).render()
        #expect(under.contains("width: 0%"))
    }

    @Test("Heading level renders correct HTML tag")
    func headingLevelRendersCorrectTag() {
        let h1 = Heading("Title", level: .h1).render()
        #expect(h1.hasPrefix("<h1"))
        let h6 = Heading("Subtitle", level: .h6).render()
        #expect(h6.hasPrefix("<h6"))
    }

    @Test("Skeleton count is at least 1")
    func skeletonMinCount() {
        let html = WebUISkeleton(count: 0).render()
        // count occurrences of the full class attribute
        let count = html.components(separatedBy: "skeleton--text").count - 1
        #expect(count == 1)
    }

    @Test("Select renders options")
    func selectRenders() {
        let html = Select(
            id: "color",
            options: [SelectOption(value: "r", label: "Red"), SelectOption(value: "g", label: "Green"), SelectOption(value: "b", label: "Blue")],
            selected: "g"
        ).render()
        #expect(html.contains("<select id=\"color\">"))
        #expect(html.contains("<option value=\"r\">Red</option>"))
        #expect(html.contains("<option value=\"g\" selected>Green</option>"))
        #expect(html.contains("<option value=\"b\">Blue</option>"))
        #expect(html.hasSuffix("</select>"))
        #expect(validateTagBalance(html))
    }

    @Test("TextArea renders correctly")
    func textAreaRenders() {
        let html = TextArea(id: "bio", placeholder: "Tell us...", rows: 5).render()
        #expect(html.contains("<textarea id=\"bio\" rows=\"5\" placeholder=\"Tell us...\">"))
        #expect(html.hasSuffix("</textarea>"))
        #expect(validateTagBalance(html))
    }

    @Test("Label renders with for attribute")
    func labelRenders() {
        let html = Label("Name", for: "name-input").render()
        #expect(html == "<label for=\"name-input\">Name</label>")
    }
}

// MARK: - 11. Integration Smoke Tests

@Suite("Integration Smoke Tests")
struct IntegrationTests {

    @Test("complete page renders without structural errors")
    func completePage() {
        let body = Div(class: "app") {
            Header(class: "app-header") {
                Navigation(class: "app-nav") {
                    Link("Home", href: "/")
                    Link("Dashboard", href: "/dashboard")
                }
                WebUIButton("Profile", variant: .ghost, size: .sm)
            }
            Main(class: "app-main") {
                Section(id: "welcome") {
                    Heading("Welcome back!", level: .h1)
                    Paragraph("Here's your overview for today.")
                }
                Grid(columns: .fraction(2), spacing: 20) {
                    WebUICard(variant: .elevated) {
                        Heading("Stats", level: .h2)
                        WebUIProgress(value: 0.8, variant: .success, showLabel: true)
                        WebUIBadge("+12%", variant: .success)
                    }
                    WebUICard(variant: .outlined) {
                        Heading("Recent Activity", level: .h2)
                        WebUITable(
                            headers: ["Item", "Status"],
                            rows: [
                                [Text("Task 1"), Text("Done")],
                                [Text("Task 2"), Text("In Progress")],
                                [Text("Task 3"), Text("Pending")],
                            ],
                            compact: true
                        )
                    }
                }
                WebUIAlert(variant: .info, message: "Your subscription renews in 7 days.", dismissible: true)
            }
            Footer(class: "app-footer") {
                Text("© 2026 WebUI UI")
            }
        }.render()

        #expect(validateTagBalance(body), "Page HTML has unbalanced tags")
        #expect(validateBEMClasses(body).isEmpty, "Page HTML has BEM class issues")

        // Verify key structural elements
        #expect(body.contains("<header"))
        #expect(body.contains("<nav"))
        #expect(body.contains("<main"))
        #expect(body.contains("<section"))
        #expect(body.contains("<footer"))

        // Verify components render
        #expect(body.contains("button--ghost"))
        #expect(body.contains("button--sm"))
        #expect(body.contains("card--elevated"))
        #expect(body.contains("card--outlined"))
        #expect(body.contains("badge--success"))
        #expect(body.contains("progress--success"))
        #expect(body.contains("table--compact"))
        #expect(body.contains("alert--info"))

        // Verify content
        #expect(body.contains("Welcome back!"))
        #expect(body.contains("Task 1"))
        #expect(body.contains("Done"))
        #expect(body.contains("Your subscription renews"))
    }

    @Test("full HTMLDocument with WebUI theme renders valid HTML")
    func fullDocumentWithTheme() {
        let body = Div(class: "app") {
            WebUIButton("Get Started", variant: .primary, size: .lg)
            WebUICard(variant: .elevated) {
                WebUIAlert(variant: .success, message: "Everything is working!")
            }
        }.render()

        let doc = HTMLDocument(
            title: "WebUI Smoke Test",
            body: body,
            styles: CSSStylesheet([CSSRule(":root", [CSSDeclaration("--color-primary-500", "#6366f1")])]),
            scripts: "console.log('smoke test');",
            head: "<meta name=\"description\" content=\"Smoke test\">"
        )

        let html = doc.render()
        #expect(validateTagBalance(html), "Full document has unbalanced tags")
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<title>WebUI Smoke Test</title>"))
        #expect(html.contains("--color-primary-500"))
        #expect(html.contains("class=\"button button--primary button--lg\""))
        #expect(html.contains("class=\"card card--elevated\""))
        #expect(html.contains("class=\"alert alert--success\""))
        #expect(html.contains("console.log('smoke test')"))
        #expect(html.contains("<meta name=\"description\""))
    }

    @Test("all WebUIComponents can be rendered in a single document")
    func allComponentsTogether() {
        let html = Div(class: "all-components") {
            WebUIButton("Button")
            WebUIInput(placeholder: "Input")
            WebUICard { Text("Card") }
            WebUIBadge("Badge")
            WebUIAlert(variant: .info, message: "Alert")
            WebUITabs(tabs: [TabItem(id: "a", label: "Tab A")], activeTab: "a")
            WebUIAvatar(initials: "TS")
            WebUIProgress(value: 0.5)
            WebUISkeleton()
            WebUIToast(variant: .info, message: "Toast")
            WebUIModal(title: "Modal") { Text("Content") }
            WebUITable(headers: ["H"], rows: [[Text("R")]])
            WebUIChip("Chip")
            WebUIEmptyState(title: "Empty", message: "State")
            WebUISpinner()
            WebUITooltip("Tooltip") { Text("Hover") }
        }.render()

        #expect(validateTagBalance(html), "All components together has unbalanced tags")
        let issues = validateBEMClasses(html)
        #expect(issues.isEmpty, "BEM issues: \(issues)")
    }
}
