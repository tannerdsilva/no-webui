import Testing
import WebUI
import WebUIDesignSystem

// W1.6: the six stringly-typed slots. each took a free string that the render
// either interpolated into a class fragment or wrote into an attribute token.
// each is a typed enum now, and each keeps the bytes it shipped — with one
// deliberate exception, the donut's colour, which took raw css and now names the
// sheet's own palette.

private func render(_ view: some View) -> String {
    RenderContext.$current.withValue(RenderContext(router: EventRouter())) { view.render() }
}

@Suite("the stringly slots are typed")
struct TypedSlotTests {

    @Test("Avatar's status is the data-status token, typed")
    func avatarStatus() {
        #expect(render(WebUIAvatar(initials: "A", status: .online)).contains("data-status=\"online\""))
        #expect(render(WebUIAvatar(initials: "A", status: .away)).contains("data-status=\"away\""))
        #expect(render(WebUIAvatar(initials: "A", status: .busy)).contains("data-status=\"busy\""))
        #expect(render(WebUIAvatar(initials: "A", status: .offline)).contains("data-status=\"offline\""))
        // absent status is the 1.x default: no badge, no attribute.
        let bare = render(WebUIAvatar(initials: "A"))
        #expect(!bare.contains("data-status"))
        #expect(!bare.contains("avatar__status"))
    }

    @Test("Gantt bar state: three sheet classes, nil is the unstyled bar")
    func ganttState() {
        func bar(_ state: GanttBarState?) -> String {
            render(WebUIGantt(rows: [.init("b", bars: [.init("t", start: 0, span: 5, state: state)])]))
        }
        #expect(bar(.active).contains("class=\"gantt__bar gantt__bar--active\""))
        #expect(bar(.done).contains("class=\"gantt__bar gantt__bar--done\""))
        #expect(bar(.warn).contains("class=\"gantt__bar gantt__bar--warn\""))
        // the 1.x default was "" and rendered a trailing-space class — still does.
        #expect(bar(nil).contains("class=\"gantt__bar \""))
    }

    @Test("JsonTree node type: four leaf classes, string is the default")
    func jsonTreeType() {
        func leaf(_ type: JsonNodeType) -> String {
            render(WebUIJsonTree(nodes: [.init("k", value: "v", type: type)]))
        }
        #expect(leaf(.string).contains("class=\"json-tree__str\""))
        #expect(leaf(.number).contains("class=\"json-tree__num\""))
        #expect(leaf(.boolean).contains("class=\"json-tree__bool\""))
        #expect(leaf(.null).contains("class=\"json-tree__null\""))
        #expect(render(WebUIJsonTree(nodes: [.init("k", value: "v")])).contains("class=\"json-tree__str\""))
    }

    @Test("Diff line kind: one case per shipped class, header maps to --hunk")
    func diffKind() {
        func line(_ kind: DiffLineKind) -> String {
            render(WebUIDiff(file: "f", lines: [.init(kind, num: 1, text: "t")]))
        }
        #expect(line(.added).contains("class=\"diff__line diff__line--add\""))
        #expect(line(.removed).contains("class=\"diff__line diff__line--del\""))
        #expect(line(.header).contains("class=\"diff__line diff__line--hunk\""))
        #expect(line(.context).contains("class=\"diff__line diff__line--ctx\""))
    }

    @Test("Terminal line kind: plain carries no fragment")
    func terminalKind() {
        func line(_ kind: TerminalLineKind) -> String {
            render(WebUITerminal(lines: [.init(kind, text: "t")]))
        }
        #expect(line(.ok).contains("class=\"terminal__line terminal__line--ok\""))
        #expect(line(.warn).contains("class=\"terminal__line terminal__line--warn\""))
        #expect(line(.error).contains("class=\"terminal__line terminal__line--err\""))
        #expect(line(.plain).contains("class=\"terminal__line\""))
        #expect(!line(.plain).contains("terminal__line--"))
    }

    @Test("Donut colour names the sheet's palette instead of raw css")
    func donutColor() {
        let hexed = render(WebUIDonut(slices: [.init("iOS", value: 44, color: .c1)], centerValue: "10"))
        #expect(hexed.contains("var(--color-chart-1)"))
        // the point of the slot: no raw css rides the call site any more.
        #expect(!hexed.contains("#"))
        for slot in ChartColorSlot.allCases {
            let out = render(WebUIDonut(slices: [.init("s", value: 1, color: slot)], centerValue: "0"))
            #expect(out.contains("var(--color-chart-"), "slot \(slot.rawValue) names no token")
        }
    }
}