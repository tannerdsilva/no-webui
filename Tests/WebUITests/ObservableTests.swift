import Testing
import Foundation
import Logging
import WebUI
import WebUIDesignSystem

// MARK: - Observable Tests

@Test("ObserverList emits events to registered observers")
func observerListEmitsEvents() {
    let list = ObserverList()
    let collector = EventCollector()
    let observer = TestObserver { event in
        collector.add(event)
    }
    list.add(observer)
    list.emit(.debug(message: "test"))
    #expect(collector.count == 1)
    if case .debug(let msg) = collector.events[0] {
        #expect(msg == "test")
    } else {
        Issue.record("expected .debug event")
    }
}

@Test("ObserverList remove stops receiving events")
func observerListRemove() {
    let list = ObserverList()
    let collector = EventCollector()
    let observer = TestObserver { event in
        collector.add(event)
    }
    list.add(observer)
    list.remove(observer)
    list.emit(.debug(message: "should not arrive"))
    #expect(collector.count == 0)
}

@Test("ObserverList removeAll clears all observers")
func observerListRemoveAll() {
    let list = ObserverList()
    let collector = EventCollector()
    let observer = TestObserver { _ in collector.increment() }
    list.add(observer)
    list.add(observer)
    list.removeAll()
    list.emit(.debug(message: "test"))
    #expect(collector.count == 0)
}

@Test("EventRouter emits observable events on handle")
func eventRouterEmitsEvents() async {
    let logger = Logger(label: "test")
    let observers = ObserverList()
    let collector = EventCollector()
    let observer = TestObserver { event in
        collector.add(event)
    }
    observers.add(observer)

    let router = EventRouter(logger: logger, observers: observers)
    router.register({ _ in [] }, for: "test-btn")

    let updates = await router.handle(EventData(
        component: "test-btn",
        event: "click",
        data: [:]
    ))

    #expect(updates.isEmpty)
    #expect(collector.count >= 1)
    let hasEventReceived = collector.events.contains { event in
        if case .eventReceived = event { return true }
        return false
    }
    #expect(hasEventReceived)
}

@Test("EventRouter emits eventHandled after handler runs")
func eventRouterEmitsHandled() async {
    let logger = Logger(label: "test")
    let observers = ObserverList()
    let collector = EventCollector()
    let observer = TestObserver { event in
        collector.add(event)
    }
    observers.add(observer)

    let router = EventRouter(logger: logger, observers: observers)
    router.register({ _ in [FragmentUpdate(id: "result", html: "<span>Done</span>")] }, for: "test-btn")

    _ = await router.handle(EventData(
        component: "test-btn",
        event: "click",
        data: [:]
    ))

    let hasHandled = collector.events.contains { event in
        if case .eventHandled(_, _, let count) = event, count == 1 { return true }
        return false
    }
    #expect(hasHandled)
}

// MARK: - Asset Embedding Tests

@Test("WebUIAssets.css contains design tokens")
func webuiAssetsContainsTokens() {
    #expect(WebUIAssets.css.contains("--color-primary-500"))
    #expect(WebUIAssets.css.contains("--font-sans"))
    #expect(WebUIAssets.css.contains("--space-4"))
    #expect(WebUIAssets.css.contains("--radius-lg"))
    #expect(WebUIAssets.css.contains("--shadow-md"))
}

@Test("WebUIAssets.css contains component styles")
func webuiAssetsContainsComponents() {
    #expect(WebUIAssets.css.contains(".button {"))
    #expect(WebUIAssets.css.contains(".card {"))
    #expect(WebUIAssets.css.contains(".modal {"))
    #expect(WebUIAssets.css.contains(".alert {"))
    #expect(WebUIAssets.css.contains(".badge {"))
    #expect(WebUIAssets.css.contains(".tabs {"))
}

@Test("WebUIAssets.js contains runtime functions")
func webuiAssetsContainsRuntime() {
    #expect(WebUIAssets.js.contains("WebUIRuntime"))
    #expect(WebUIAssets.js.contains("createWSClient"))
    #expect(WebUIAssets.js.contains("createEventDelegator"))
    #expect(WebUIAssets.js.contains("createFragmentPatcher"))
    #expect(WebUIAssets.js.contains("createStateStore"))
}

@Test("WebUIRuntime.source loads from embedded assets")
func webuiRuntimeSource() {
    let source = WebUIRuntime.source
    #expect(source.contains("WebUIRuntime"))
    #expect(source.contains("createWSClient"))
    // should not contain the fallback warning message
    #expect(!source.contains("Runtime source not found"))
}

// MARK: - HTMLDocument with Raw Styles Tests

@Test("HTMLDocument includes rawStyles in production mode")
func htmlDocumentWithRawStyles() {
    let doc = HTMLDocument(
        title: "Test",
        body: "<p>Hello</p>",
        rawStyles: [".custom { color: red; }"]
    )
    let html = doc.render()
    #expect(html.contains(".custom { color: red; }"))
    #expect(validateTagBalance(html))
}

@Test("HTMLDocument includes multiple rawStyles")
func htmlDocumentWithMultipleRawStyles() {
    let doc = HTMLDocument(
        title: "Test",
        body: "<p>Hello</p>",
        rawStyles: [
            ".a { color: red; }",
            ".b { color: blue; }",
        ]
    )
    let html = doc.render()
    #expect(html.contains(".a { color: red; }"))
    #expect(html.contains(".b { color: blue; }"))
    #expect(validateTagBalance(html))
}

@Test("HTMLDocument omits rawStyles in dev mode")
func htmlDocumentRawStylesDevMode() {
    let doc = HTMLDocument(
        title: "Test",
        body: "<p>Hello</p>",
        rawStyles: [".custom { color: red; }"],
        devMode: true
    )
    let html = doc.render()
    #expect(!html.contains(".custom { color: red; }"))
    #expect(html.contains("<link rel=\"stylesheet\""))
}

// MARK: - WebUIDocument with Full CSS Tests

@Test("WebUIDocument includes full design system CSS")
func webuiDocumentIncludesFullCSS() {
    let doc = WebUIDocument(
        title: "Test",
        body: "<p>Hello</p>"
    )
    let html = doc.render()
    // should contain both design tokens and component styles
    #expect(html.contains("--color-primary-500"))
    #expect(html.contains(".button {"))
    #expect(html.contains(".card {"))
    #expect(html.contains(".modal {"))
    #expect(validateTagBalance(html))
}

@Test("WebUIDocument includes JS runtime")
func webuiDocumentIncludesRuntime() {
    let doc = WebUIDocument(
        title: "Test",
        body: "<p>Hello</p>"
    )
    let html = doc.render()
    #expect(html.contains("WebUIRuntime"))
    #expect(html.contains("createWSClient"))
}

// MARK: - Layout Styles Tests

@Test("LayoutStyles.all contains base layout rules")
func layoutStylesAll() {
    let rules = LayoutStyles.all
    let selectors = rules.map { $0.selector }
    #expect(selectors.contains(".vstack"))
    #expect(selectors.contains(".hstack"))
    #expect(selectors.contains(".zstack"))
    #expect(selectors.contains(".spacer"))
    #expect(selectors.contains(".scrollview"))
    #expect(selectors.contains(".grid"))
}

@Test("LayoutStyles.complete generates spacing and alignment rules")
func layoutStylesCompleteGeneratesRules() {
    let rules = LayoutStyles.complete
    let rendered = CSSStylesheet(rules).render()
    #expect(rendered.contains(".spacing-8"))
    #expect(rendered.contains(".spacing-16"))
    #expect(rendered.contains(".align-flex-start"))
    #expect(rendered.contains(".align-center"))
    #expect(rendered.contains(".align-flex-end"))
}

@Test("generateSpacingClasses produces correct rules")
func generateSpacingClasses() {
    let rules = generateSpacingClasses([4, 8, 16])
    #expect(rules.count == 3)
    #expect(rules[0].selector == ".spacing-4")
    #expect(rules[0].declarations[0] == CSSDeclaration("gap", "4px"))
}

@Test("generateAlignmentClasses produces correct rules")
func generateAlignmentClasses() {
    let rules = generateAlignmentClasses(["flex-start", "center"])
    #expect(rules.count == 2)
    #expect(rules[0].selector == ".align-flex-start")
    #expect(rules[0].declarations[0] == CSSDeclaration("align-items", "flex-start"))
}

// MARK: - Full Pipeline Integration Test

@Test("Full pipeline: View → HTMLDocument → render produces valid output")
func fullPipelineRender() {
    let body = Div(class: "app") {
        WebUIButton("Click me", variant: .primary, size: .lg)
            .id("main-btn")
        WebUICard(variant: .elevated) {
            Text("Card content")
        }
    }.render()

    let doc = WebUIDocument(
        title: "Pipeline Test",
        body: body
    )

    let html = doc.render()

    // structural checks
    #expect(html.hasPrefix("<!DOCTYPE html>"))
    #expect(html.contains("<title>Pipeline Test</title>"))
    #expect(validateTagBalance(html))

    // content checks
    #expect(html.contains("class=\"app\""))
    #expect(html.contains("class=\"button button--primary button--lg\""))
    #expect(html.contains("id=\"main-btn\""))
    #expect(html.contains("Click me"))
    #expect(html.contains("class=\"card card--elevated\""))
    #expect(html.contains("Card content"))

    // design system checks
    #expect(html.contains("--color-primary-500"))
    #expect(html.contains(".button {"))
    #expect(html.contains(".card {"))

    // runtime checks
    #expect(html.contains("WebUIRuntime.init()"))
}

// MARK: - Helpers

/// thread-safe event collector for testing.
private final class EventCollector: @unchecked Sendable {
    private var _events: [ObservableEvent] = []
    private var _count: Int = 0
    private let lock = NSLock()

    var events: [ObservableEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func add(_ event: ObservableEvent) {
        lock.lock()
        _events.append(event)
        _count += 1
        lock.unlock()
    }

    func increment() {
        lock.lock()
        _count += 1
        lock.unlock()
    }
}

private final class TestObserver: Observable {
    let handler: @Sendable (ObservableEvent) -> Void
    init(handler: @escaping @Sendable (ObservableEvent) -> Void) {
        self.handler = handler
    }
    func observe(_ event: ObservableEvent) {
        handler(event)
    }
}
