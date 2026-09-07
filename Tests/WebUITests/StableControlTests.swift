import Foundation
import Testing
@testable import WebUI
@testable import WebUIDesignSystem
@testable import WebUIChart

// MARK: - controlAttributes

@Suite("controlAttributes stable-id control wiring")
struct StableControlAttributesTests {

    @Test("registers the handler and emits routing attributes when a context is present")
    func registersWithContext() async {
        let router = EventRouter()
        let context = RenderContext(router: router)
        let attrs = controlAttributes(id: "ctrl-1", handler: { _ in [] })
        #expect(attrs.contains("data-component-id=\"ctrl-1\""))
        #expect(attrs.contains("data-event=\"click\""))

        let updates = await router.handle(EventData(component: "ctrl-1", event: "click", data: [:]))
        #expect(updates.isEmpty)
        _ = context
    }

    @Test("emits the stable id WITHOUT registering when no context is present (fragment re-render path)")
    func emitsWithoutContext() async {
        // page build: render INSIDE a RenderContext so the handler registers
        // under the stable id, and the control HTML carries routing attributes.
        let router = EventRouter()
        let context = RenderContext(router: router)
        let attrs = RenderContext.$current.withValue(context) {
            controlAttributes(id: "ctrl-1", handler: { _ in [] })
        }
        #expect(attrs.contains("data-component-id=\"ctrl-1\""))

        // fragment re-render: a handler re-rendering a fragment calls the
        // helper OUTSIDE any context. the stable id is re-emitted so routing
        // continues, but nothing is re-registered (page build did that).
        let again = controlAttributes(id: "ctrl-1", handler: { _ in [FragmentUpdate(id: "x", html: "x")] })
        #expect(again.contains("data-component-id=\"ctrl-1\""))

        // dispatching the stable id still routes to the page-build handler.
        let updates = await router.handle(EventData(component: "ctrl-1", event: "click", data: [:]))
        #expect(updates.isEmpty)
        _ = context
    }

    @Test("emits nothing for a non-interactive control")
    func nilHandlerEmitsNothing() {
        let attrs = controlAttributes(id: "static", handler: nil)
        #expect(attrs.isEmpty)
    }
}

// MARK: - WebUITable typed handlers

@Suite("WebUITable typed handlers (onSort/onSelectAll/onSelect/onToggleExpand)")
struct TableTypedHandlerTests {

    private final class Box: @unchecked Sendable {
        var sortCalls: [(column: Int, ref: ElementRef)] = []
        var selectAllCalls: Int = 0
        var selectCalls: [String] = []
        var expandCalls: [String] = []
    }

    private func renderWiredTable(box: Box) -> (html: String, router: EventRouter) {
        let router = EventRouter()
        let context = RenderContext(router: router)
        let html = RenderContext.$current.withValue(context) {
            WebUITable(
                headers: ["Name", "Age"],
                rows: [[Text("Alice"), Text("30")], [Text("Bob"), Text("25")]],
                id: "tbl",
                sortableColumns: [0, 1],
                selectable: true,
                rowIds: ["a", "b"],
                rowDetails: ["a": Text("detail"), "b": Text("detail2")]
            )
            .onSort { ref, column in box.sortCalls.append((column, ref)); return [] }
            .onSelectAll { _ in box.selectAllCalls += 1; return [] }
            .onSelect { _, rowID in box.selectCalls.append(rowID); return [] }
            .onToggleExpand { _, rowID in box.expandCalls.append(rowID); return [] }
            .render()
        }
        return (html, router)
    }

    @Test("each control routes to exactly its typed handler")
    func typedHandlerRouting() async {
        let box = Box()
        let (html, router) = renderWiredTable(box: box)

        // controls carry routing attributes
        #expect(html.contains("data-component-id=\"tbl-sort-0\""), "emitted: \(html)")
        #expect(html.contains("data-component-id=\"tbl-sort-1\""), "emitted: \(html)")
        #expect(html.contains("data-component-id=\"tbl-select-all\""), "emitted: \(html)")
        #expect(html.contains("data-component-id=\"tbl-select-a\""), "emitted: \(html)")
        #expect(html.contains("data-component-id=\"tbl-expand-b\""), "emitted: \(html)")

        // dispatch to each control id → only that typed handler fires
        _ = await router.handle(EventData(component: "tbl-sort-1", event: "click", data: [:]))
        _ = await router.handle(EventData(component: "tbl-select-all", event: "click", data: [:]))
        _ = await router.handle(EventData(component: "tbl-select-a", event: "click", data: [:]))
        _ = await router.handle(EventData(component: "tbl-expand-b", event: "click", data: [:]))

        #expect(box.sortCalls.count == 1)
        #expect(box.sortCalls[0].column == 1)
        #expect(box.selectAllCalls == 1)
        #expect(box.selectCalls == ["a"])
        #expect(box.expandCalls == ["b"])
    }

    @Test("interactive table without a caller id renders static (warning path)")
    func noIDRendersStatic() {
        let router = EventRouter()
        let context = RenderContext(router: router)
        let html = RenderContext.$current.withValue(context) {
            WebUITable(
                headers: ["Name"],
                rows: [[Text("Alice")]],
                sortableColumns: [0]
            )
            .onSort { _, _ in [] }
            .render()
        }
        // no stable id → no routing attributes (the warning path);
        // the sort span still renders (static) with the fallback base id.
        #expect(!html.contains("data-component-id"), "emitted: \(html)")
        #expect(html.contains("id=\"webui-table-sort-0\""), "emitted: \(html)")
    }

    @Test("typed handlers are not required: plain table renders as before")
    func plainTableNoRoutingAttrs() {
        let html = WebUITable(headers: ["Name"], rows: [[Text("Alice")]]).render()
        #expect(!html.contains("data-component-id"))
        #expect(html.contains("<th>Name</th>"))
    }
}

// MARK: - WebUIPagination typed handlers

@Suite("WebUIPagination typed handlers (onPageChange/onRowsPerPageChange)")
struct PaginationTypedHandlerTests {

    private final class Box: @unchecked Sendable {
        var pages: [Int] = []
        var rows: [Int] = []
    }

    @Test("prev/next/number route to onPageChange with the computed page")
    func pageChangeRouting() async {
        let box = Box()
        let router = EventRouter()
        let context = RenderContext(router: router)
        let html = RenderContext.$current.withValue(context) {
            WebUIPagination(page: 5, pages: 12, id: "pg")
                .onPageChange { _, page in box.pages.append(page); return [] }
                .render()
        }

        #expect(html.contains("data-component-id=\"pg-prev\""), "emitted: \(html)")
        #expect(html.contains("data-component-id=\"pg-next\""), "emitted: \(html)")
        #expect(html.contains("data-component-id=\"pg-page-5\""), "emitted: \(html)")

        _ = await router.handle(EventData(component: "pg-prev", event: "click", data: [:]))
        _ = await router.handle(EventData(component: "pg-next", event: "click", data: [:]))
        // page window at 5/12: 1 2 4 5 6 11 12 → click page 6
        _ = await router.handle(EventData(component: "pg-page-6", event: "click", data: [:]))

        #expect(box.pages == [4, 6, 6])
    }

    @Test("rows-per-page select change routes the parsed size")
    func rowsPerPageRouting() async {
        let box = Box()
        let router = EventRouter()
        let context = RenderContext(router: router)
        let html = RenderContext.$current.withValue(context) {
            WebUIPagination(page: 1, pages: 4, id: "pg", rowsPerPage: 25, rowsPerPageOptions: [10, 25, 50])
                .onRowsPerPageChange { _, size in box.rows.append(size); return [] }
                .render()
        }

        #expect(html.contains("data-component-id=\"pg-rows\""), "emitted: \(html)")
        #expect(html.contains("data-event=\"change\""), "emitted: \(html)")

        _ = await router.handle(EventData(component: "pg-rows", event: "change", data: ["value": "50"]))
        #expect(box.rows == [50])
    }

    @Test("typed handlers on pagination require an id: static fallback otherwise")
    func noIDStatic() {
        let router = EventRouter()
        let context = RenderContext(router: router)
        let html = RenderContext.$current.withValue(context) {
            WebUIPagination(page: 1, pages: 4)
                .onPageChange { _, _ in [] }
                .render()
        }
        #expect(!html.contains("data-component-id"), "emitted: \(html)")
    }
}

// MARK: - WebUIChart onSelectMark

@Suite("WebUIChart onSelectMark")
struct ChartTypedHandlerTests {

    private final class Box: @unchecked Sendable {
        var categories: [String] = []
    }

    private func makeBars() -> [ChartMark] {
        [
            BarMark(x: .value("Month", "Jan"), y: .value("Sales", 12)).foregroundStyle(by: "A").makeMark(),
            BarMark(x: .value("Month", "Feb"), y: .value("Sales", 20)).foregroundStyle(by: "A").makeMark(),
        ]
    }

    @Test("each bar routes to onSelectMark with its category")
    func barRouting() async {
        let box = Box()
        let router = EventRouter()
        let context = RenderContext(router: router)
        let html = RenderContext.$current.withValue(context) {
            Chart(makeBars())
                .chartID("chart-1")
                .onSelectMark { _, category in box.categories.append(category); return [] }
                .render()
        }

        #expect(html.contains("data-component-id=\"chart-1-mark-Jan-A\""), "emitted: \(html)")
        #expect(html.contains("data-component-id=\"chart-1-mark-Feb-A\""), "emitted: \(html)")

        _ = await router.handle(EventData(component: "chart-1-mark-Feb-A", event: "click", data: [:]))
        #expect(box.categories == ["Feb"])
    }

    @Test("chart without onSelectMark renders marks statically")
    func noHandlerStatic() {
        let html = Chart(makeBars()).chartID("chart-1").render()
        #expect(!html.contains("data-component-id"), "emitted: \(html)")
    }
}
