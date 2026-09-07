import Testing
import Foundation
import Logging
import Synchronization
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

// MARK: - ObserverList Hardening Tests (P0)

@Test("ObserverList dedupes identity-duplicate registrations")
func observerListDedupes() {
    let list = ObserverList()
    let collector = EventCollector()
    let observer = TestObserver { collector.add($0) }
    list.add(observer)
    list.add(observer) // duplicate — must be a no-op
    list.emit(.debug(message: "x"))
    #expect(collector.count == 1)
}

@Test("ObserverList cap drops the first observer beyond maxObservers")
func observerListCapDrops() {
    let list = ObserverList(maxObservers: 1)
    let a = EventCollector()
    let b = EventCollector()
    list.add(TestObserver { a.add($0) })
    list.add(TestObserver { b.add($0) }) // rejected at cap
    list.emit(.debug(message: "x"))
    #expect(a.count == 1)
    #expect(b.count == 0)
}

@Test("duplicate registrations do not consume cap slots")
func observerListDuplicatesDoNotStarve() {
    let list = ObserverList(maxObservers: 2)
    let a = EventCollector()
    let b = EventCollector()
    let oa = TestObserver { a.add($0) }
    list.add(oa)
    list.add(oa) // duplicate must not eat a second slot
    list.add(TestObserver { b.add($0) })
    list.emit(.debug(message: "x"))
    #expect(a.count == 1)
    #expect(b.count == 1)
}

@Test("observer removed during emit completes its current turn then stops")
func observerRemovedDuringEmit() {
    let list = ObserverList()
    let remover = SelfRemovingObserver(list: list)
    let collector = EventCollector()
    list.add(remover)
    list.add(TestObserver { collector.add($0) })
    list.emit(.debug(message: "turn"))
    list.emit(.debug(message: "turn2"))
    #expect(remover.received == 1)
    #expect(collector.count == 2)
}

@Test("observer added during emit receives the next event, not the current one")
func observerAddedDuringEmit() {
    let list = ObserverList()
    let lateCollector = EventCollector()
    let adder = AddingObserver(list: list, late: TestObserver { lateCollector.add($0) })
    list.add(adder)
    list.emit(.debug(message: "turn"))
    #expect(lateCollector.count == 0)
    list.emit(.debug(message: "turn2"))
    #expect(lateCollector.count == 1)
}

@Test("Logger.emit forwards events to registered observers")
func loggerEmitForwardsToObservers() {
    let observers = ObserverList()
    let collector = EventCollector()
    observers.add(TestObserver { collector.add($0) })
    let logger = Logger(label: "test.emit")
    logger.emit(.eventReceived(component: "c0", event: "click"), observers: observers)
    #expect(collector.count == 1)
    if case .eventReceived = collector.events[0] {} else {
        Issue.record("expected .eventReceived through the logger funnel")
    }
}

@Test("missing handler emits received + debug and never handled")
func eventRouterMissingHandlerFunnel() async {
    let observers = ObserverList()
    let collector = EventCollector()
    observers.add(TestObserver { collector.add($0) })
    let router = EventRouter(observers: observers)
    _ = await router.handle(EventData(component: "ghost", event: "click", data: [:]))
    let kinds = collector.events.map { kindName(of: $0) }
    #expect(kinds == ["received", "debug"])
}

@Test("ObservableEvent Codable round-trips every case")
func observableEventCodableRoundTrip() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let samples: [ObservableEvent] = [
        .viewRendered(viewType: "Card", durationNanoseconds: 123),
        .eventReceived(component: "c0", event: "click"),
        .eventHandled(component: "c0", event: "click", fragmentCount: 2),
        .fragmentSent(fragmentCount: 2, seq: 7),
        .fragmentSent(fragmentCount: 1, seq: nil),
        .websocketConnected,
        .websocketDisconnected,
        .websocketError(error: "boom"),
        .error(message: "oops"),
        .debug(message: "dbg"),
    ]
    for sample in samples {
        let data = try encoder.encode(sample)
        let back = try decoder.decode(ObservableEvent.self, from: data)
        #expect(String(describing: back) == String(describing: sample))
    }
}

@Test("ObserverList survives concurrent emit/add without deadlock")
func observerListConcurrentHammer() {
    let list = ObserverList()
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "hammer", attributes: .concurrent)
    for _ in 0..<8 {
        queue.async(group: group) {
            for _ in 0..<2000 {
                if Int.random(in: 0..<10) == 0 {
                    list.add(TestObserver { _ in })
                } else {
                    list.emit(.debug(message: "hammer"))
                }
            }
        }
    }
    #expect(group.wait(timeout: .now() + 30) == .success)
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
private final class EventCollector: Sendable {
    private struct State {
        var events: [ObservableEvent] = []
        var count = 0
    }
    private let state = Mutex(State())

    var events: [ObservableEvent] {
        state.withLock { $0.events }
    }

    var count: Int {
        state.withLock { $0.count }
    }

    func add(_ event: ObservableEvent) {
        state.withLock { state in
            state.events.append(event)
            state.count += 1
        }
    }

    func increment() {
        state.withLock { $0.count += 1 }
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

/// an observer that removes itself from the list the first time it observes.
private final class SelfRemovingObserver: Observable, Sendable {
    let list: ObserverList
    private struct State {
        var received = 0
    }
    private let state = Mutex(State())
    var received: Int {
        state.withLock { $0.received }
    }
    init(list: ObserverList) {
        self.list = list
    }
    func observe(_ event: ObservableEvent) {
        state.withLock { $0.received += 1 }
        list.remove(self)
    }
}

/// an observer that registers another observer the first time it observes.
private final class AddingObserver: Observable, Sendable {
    let list: ObserverList
    let late: TestObserver
    init(list: ObserverList, late: TestObserver) {
        self.list = list
        self.late = late
    }
    func observe(_ event: ObservableEvent) {
        list.add(late)
    }
}

private func kindName(of event: ObservableEvent) -> String {
    switch event {
    case .eventReceived: return "received"
    case .eventHandled: return "handled"
    case .debug: return "debug"
    case .viewRendered: return "viewRendered"
    case .fragmentSent: return "fragmentSent"
    case .websocketConnected: return "wsConnected"
    case .websocketDisconnected: return "wsDisconnected"
    case .websocketError: return "wsError"
    case .error: return "error"
    }
}
