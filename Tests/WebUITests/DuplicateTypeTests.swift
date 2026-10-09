import Testing
import WebUI
import WebUIDesignSystem

// W1.5: the types that existed twice. `Brand` was declared twice with different
// raw-value sets, `Side` meant two unrelated things (a bubble's direction and a
// popover's anchor), and `Edge` meant two unrelated things (a drawer's slide
// axis and a panel's divider side). each pair becomes one distinct shared type,
// and every 1.x spelling still resolves and still renders the same bytes.

private func render(_ view: some View) -> String {
    RenderContext.$current.withValue(RenderContext(router: EventRouter())) { view.renderThroughBuffer() }
}

@Suite("the duplicated types are one type each")
struct DuplicateTypeTests {

    // MARK: Brand — one type, two pay surfaces

    @Test("both pay components now take the one Brand")
    func oneBrandType() {
        #expect(WebUIPayCard.Brand.self == Brand.self)
        #expect(WebUICardInput.Brand.self == Brand.self)
    }

    @Test("PayCard's three brands keep their text; discover is now expressible")
    func payCardBrands() {
        #expect(render(WebUIPayCard(number: "4242", holder: "A", brand: .visa)).contains(">VISA</span>"))
        #expect(render(WebUIPayCard(number: "4242", holder: "A", brand: .mc)).contains(">MC</span>"))
        #expect(render(WebUIPayCard(number: "4242", holder: "A", brand: .amex)).contains(">AMEX</span>"))
        // the 1.x type had no `discover`; the shared one does, and PayCard forwards it.
        #expect(render(WebUIPayCard(number: "4242", holder: "A", brand: .discover)).contains(">DISCOVER</span>"))
    }

    @Test("CardInput's three brands keep their exact class fragments")
    func cardInputBrands() {
        #expect(render(WebUICardInput(number: "4242", holder: "A", brand: .visa)).contains("card-input__brand-icon card-input__brand-icon--visa"))
        #expect(render(WebUICardInput(number: "4242", holder: "A", brand: .mc)).contains("card-input__brand-icon card-input__brand-icon--mc"))
        #expect(render(WebUICardInput(number: "4242", holder: "A", brand: .amex)).contains("card-input__brand-icon card-input__brand-icon--amex"))
        #expect(render(WebUICardInput(number: "4242", holder: "A", brand: .discover)).contains("card-input__brand-icon--discover"))
    }

    // MARK: Side — a bubble's direction vs a popover's anchor

    @Test("ChatBubble's side is BubbleSide, same bytes")
    func chatBubbleSide() {
        #expect(render(WebUIChatBubble("t", side: .sent)).contains("class=\"chat__bubble chat__bubble--sent\""))
        #expect(render(WebUIChatBubble("t", side: .received)).contains("class=\"chat__bubble chat__bubble--received\""))
        // the 1.x type name resolves, to the renamed axis.
        let s: WebUIChatBubble.Side = .sent
        #expect(s == WebUIChatBubble.BubbleSide.sent)
        #expect(WebUIChatBubble.Side.self == WebUIChatBubble.BubbleSide.self)
    }

    @Test("Popover's side is Placement, same bytes for the four anchors")
    func popoverSide() {
        #expect(render(WebUIPopover(side: .top)).contains("class=\"popover popover--top\""))
        #expect(render(WebUIPopover(side: .bottom)).contains("class=\"popover popover--bottom\""))
        #expect(render(WebUIPopover(side: .left)).contains("class=\"popover popover--left\""))
        #expect(render(WebUIPopover(side: .right)).contains("class=\"popover popover--right\""))
        // Placement's logical pair forwards the pattern rather than degrading.
        #expect(render(WebUIPopover(side: .leading)).contains("class=\"popover popover--leading\""))
        #expect(render(WebUIPopover(side: .trailing)).contains("class=\"popover popover--trailing\""))
        #expect(WebUIPopover.Side.self == Placement.self)
    }

    // MARK: Edge — a drawer's slide axis vs a panel's divider side

    @Test("Drawer's edge is DrawerEdge, same four bytes")
    func drawerEdge() {
        #expect(render(WebUIDrawer(edge: .left) { Text("x") }).contains("class=\"drawer drawer--left\""))
        #expect(render(WebUIDrawer(edge: .right) { Text("x") }).contains("class=\"drawer drawer--right\""))
        #expect(render(WebUIDrawer(edge: .top) { Text("x") }).contains("class=\"drawer drawer--top\""))
        #expect(render(WebUIDrawer(edge: .bottom) { Text("x") }).contains("class=\"drawer drawer--bottom\""))
        #expect(WebUIDrawer.Edge.self == DrawerEdge.self)
    }

    @Test("Panel's edge is PanelEdge, same three bytes")
    func panelEdge() {
        #expect(render(WebUIPanel(title: "t", edge: .none) { Text("x") }).contains("class=\"\""))
        #expect(render(WebUIPanel(title: "t", edge: .leading) { Text("x") }).contains("class=\"panel panel--leading\""))
        #expect(render(WebUIPanel(title: "t", edge: .trailing) { Text("x") }).contains("class=\"panel panel--trailing\""))
        #expect(WebUIPanel.Edge.self == PanelEdge.self)
    }

    @Test("the two edges are genuinely different axes now")
    func edgesAreDistinct() {
        // they were both spelled `Edge`; they are not the same vocabulary and
        // must not be one type — this is the point of the split.
        #expect(WebUIDrawer.Edge.self != WebUIPanel.Edge.self)
        #expect(WebUIDrawer.Edge.self == DrawerEdge.self)
        #expect(WebUIPanel.Edge.self == PanelEdge.self)
    }
}