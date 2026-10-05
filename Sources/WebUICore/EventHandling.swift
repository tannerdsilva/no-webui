import Logging
import Synchronization

// MARK: - ComponentID
public struct ComponentID: Sendable, Hashable, Codable, ExpressibleByStringLiteral {
    public let value: String
    public init(_ value: String) { self.value = value }
    public init(stringLiteral: String) { self.value = stringLiteral }
}

// MARK: - EventData

public struct EventData: Sendable, Codable {
    public let component: ComponentID
    public let event: String
    /// widened (p3): typed payload values — flat string fields are read with
    /// `string(_:)`; structured values (search terms, row ids, numeric
    /// filters) flow through the hand-rolled `JSONValue` object unchanged.
    public let data: [String: JSONValue]
    public init(component: ComponentID, event: String, data: [String: JSONValue] = [:]) {
        self.component = component
        self.event = event
        self.data = data
    }

    /// a flat string field (most event payloads: `value`, `targetId`, `key`, …).
    public func string(_ key: String) -> String? {
        guard case .string(let value)? = data[key] else { return nil }
        return value
    }

    /// a numeric field.
    public func number(_ key: String) -> Double? {
        guard case .number(let value)? = data[key] else { return nil }
        return value
    }
}

// MARK: - EventHandler
public typealias EventHandler = @Sendable (EventData) async -> [FragmentUpdate]

// MARK: - DX-14 — the event outcome protocol

/// what an event handler yields. the framework adapts each conformance to the one
/// wire substrate (`[FragmentUpdate]`); the handler states intent, the framework
/// states the wire.
public protocol EventOutcome: Sendable {
    func resolve(_ context: OutcomeContext) async -> [FragmentUpdate]
}

/// the dispatch-scoped facts a `resolve` may use.
public struct OutcomeContext: Sendable {
    /// the control that fired — a ROUTING id (`data-component-id`), not necessarily
    /// a DOM id; minted ids (`cN`) are not in the document.
    public let component: ComponentID
    /// the invalidate half: reaches the live registry. established per-dispatch by
    /// the dispatch seam — a no-op provider at i0, the registry's closure once
    /// `regions:` is attached.
    public let invalidate: @Sendable ([String]) -> Void
    /// the dispatch-scoped context the erased adapter reads; `nil` outside a
    /// dispatch.
    @TaskLocal public static var current: OutcomeContext?

    public init(component: ComponentID, invalidate: @escaping @Sendable ([String]) -> Void) {
        self.component = component
        self.invalidate = invalidate
    }
}

/// one update — the pre-DX-14 handler shape, unchanged.
extension FragmentUpdate: EventOutcome {
    public func resolve(_ context: OutcomeContext) async -> [FragmentUpdate] { [self] }
}

/// several updates, verbatim.
extension Array: EventOutcome where Element == FragmentUpdate {
    public func resolve(_ context: OutcomeContext) async -> [FragmentUpdate] { self }
}

/// render `Content` and replace the element carrying `#<context.component.value>`.
/// REQUIRES the control's replaceable root to carry that DOM id; a minted-id
/// context (`cN`, e.g. `Dismissible`) is out of contract — those return fragments.
public struct ViewOutcome<Content: View>: EventOutcome {
    public let content: Content
    public init(_ content: Content) { self.content = content }
    public func resolve(_ context: OutcomeContext) async -> [FragmentUpdate] {
        [FragmentUpdate(id: context.component.value, html: content.render())]
    }
}

/// the handler declares the change; the region registry renders and pushes the
/// diff. resolve itself carries no fragments.
public struct RegionInvalidations: EventOutcome {
    public let ids: [String]
    public init(_ ids: [String]) { self.ids = ids }
    public func resolve(_ context: OutcomeContext) async -> [FragmentUpdate] {
        context.invalidate(ids)
        return []
    }
}

/// nothing to send.
public struct NoOutcome: EventOutcome {
    public init() {}
    public func resolve(_ context: OutcomeContext) async -> [FragmentUpdate] { [] }
}

/// both, in order.
public struct CombinedOutcome<A: EventOutcome, B: EventOutcome>: EventOutcome {
    public let first: A
    public let second: B
    public init(_ first: A, _ second: B) {
        self.first = first
        self.second = second
    }
    public func resolve(_ context: OutcomeContext) async -> [FragmentUpdate] {
        let head = await first.resolve(context)
        let tail = await second.resolve(context)
        return head + tail
    }
}

// MARK: - EventRouter
public final class EventRouter: Sendable {
    public let maxHandlers: Int
    private let state: State
    public let observers: ObserverList
    public let logger: Logger
    private final class State: Sendable {
        private struct Values {
            var handlers: [ComponentID: EventHandler] = [:]
            var nextID: Int = 0
            var nextElementID: Int = 0
        }
        private let values = Mutex(Values())

        func register(_ handler: @escaping EventHandler, for componentID: ComponentID) {
            values.withLock { $0.handlers[componentID] = handler }
        }

        var handlerCount: Int {
            values.withLock { $0.handlers.count }
        }

        func handler(for componentID: ComponentID) -> EventHandler? {
            values.withLock { $0.handlers[componentID] }
        }

        func nextComponentID() -> ComponentID {
            values.withLock { values in
                let id = ComponentID("c\(values.nextID)")
                values.nextID += 1
                return id
            }
        }

        func nextElementID() -> ComponentID {
            values.withLock { values in
                let id = ComponentID("e\(values.nextElementID)")
                values.nextElementID += 1
                return id
            }
        }

        func reset() {
            values.withLock { values in
                values.handlers.removeAll()
                values.nextID = 0
                values.nextElementID = 0
            }
        }
    }
    public init(
        logger: Logger = Logger(label: "webui.events"),
        observers: ObserverList? = nil,
        maxHandlers: Int = 10_000
    ) {
        self.state = State()
        self.logger = logger
        self.observers = observers ?? ObserverList()
        self.maxHandlers = maxHandlers
    }
    public func register(_ handler: @escaping EventHandler, for componentID: ComponentID) {
        if state.handlerCount >= maxHandlers {
            logger.warning("EventRouter: handler cap reached (\(maxHandlers)). Call reset() between renders or increase maxHandlers.")
            return
        }
        state.register(handler, for: componentID)
    }
    public func nextComponentID() -> ComponentID {
        state.nextComponentID()
    }

    /// mint the next framework element id (`e0`, `e1`, ...) for an
    /// `ElementRef`. separate counter from component ids so a `data-component-id`
    /// never collides with a DOM element id.
    public func nextElementID() -> ComponentID {
        state.nextElementID()
    }
    public var handlerCount: Int {
        state.handlerCount
    }
    public func handle(_ event: EventData) async -> [FragmentUpdate] {
        logger.emit(ObservableEvent.eventReceived(component: event.component.value, event: event.event), observers: observers)

        guard let handler = state.handler(for: event.component) else {
            // route through `logger.emit` so the observer fan-out stays on the
            // single funnel every other emission uses (log line + notify).
            logger.emit(ObservableEvent.debug(message: "no handler registered for component '\(event.component.value)'"), observers: observers)
            return []
        }

        let updates = await handler(event)
        logger.emit(ObservableEvent.eventHandled(component: event.component.value, event: event.event, fragmentCount: updates.count), observers: observers)
        return updates
    }
    public func reset() {
        state.reset()
    }
}

// MARK: - RenderContext
public struct RenderContext: Sendable {
    public var router: EventRouter
    public init(router: EventRouter) {
        self.router = router
    }
    public mutating func nextComponentID() -> ComponentID {
        router.nextComponentID()
    }

    public mutating func nextElementID() -> ComponentID {
        router.nextElementID()
    }
    public mutating func register(handler: @escaping EventHandler, for componentID: ComponentID) {
        router.register(handler, for: componentID)
    }
    @TaskLocal public static var current: RenderContext?
}

// MARK: - DX-12 — the render-context seam

extension RenderContext {
    /// run `body` with the render context established for this router. the page
    /// render and the dispatch path both enter here, so a control first rendered
    /// *inside* a handler self-registers (overwrite-wins for a given stable id) —
    /// before this seam existed only the page render established the context and
    /// a handler-introduced control was dead.
    public static func withCurrent<T>(router: EventRouter, _ body: () async throws -> T) async rethrows -> T {
        try await RenderContext.$current.withValue(RenderContext(router: router)) {
            try await body()
        }
    }

    /// the synchronous sibling — for render-time wiring inside a non-async body.
    public static func withCurrent<T>(router: EventRouter, _ body: () throws -> T) rethrows -> T {
        try RenderContext.$current.withValue(RenderContext(router: router), operation: body)
    }
}

// MARK: - Stable-ID Control Wiring

/// wire a caller-stable interactive control: register `handler` under the
/// stable component `id` when a `RenderContext` is present, and return the
/// `data-component-id`/`data-event` attributes to emit on the control.
///
/// registration is **overwrite-wins (last-render-wins)** for a given stable id:
/// re-rendering the control re-registers its current handler, so the router
/// always holds the newest closure for that id. with the dispatch seam in place
/// (`RenderContext.withCurrent`, entered by the server's dispatch path) a control
/// first rendered *inside* a handler registers there and then; before the seam
/// only the page render established the context, so a handler-introduced control
/// was dead.
///
/// when no `RenderContext` is present the stable attributes are still emitted —
/// the ids are a pure function of component state, so a context-free fragment
/// re-render carries identical routing attributes and routing continues to the
/// registration that persists in the router. this is what makes typed component
/// handlers (`WebUITable.onSort`, chart mark selection, ...) survive fragment
/// re-renders.
///
/// pass `nil` as `handler` to render the control statically (no routing
/// attributes emitted), e.g. when the component has no interactive audience.
///
/// the DX-14 sibling `control(_:event:handler:)` takes a handler that yields an
/// `EventOutcome` instead of `[FragmentUpdate]`; this function's behavior and
/// emitted bytes are unchanged by that addition.
public func controlAttributes(
    id: String,
    event: HTMLEvent = .click,
    handler: EventHandler?
) -> String {
    guard let handler else { return "" }
    if var context = RenderContext.current {
        context.register(handler: handler, for: ComponentID(id))
    }
    return " data-component-id=\"\(htmlEscape(id))\" data-event=\"\(htmlEscape(event.rawValue))\""
}

/// the generic sibling of `controlAttributes(id:)`: the handler states *what it
/// yields* — a `View`, one update, several, region invalidations, nothing, or a
/// combination — and the framework adapts it to the one wire substrate.
///
/// the closure's return type fixes `O`, so a bare `{ _ in [] }` cannot infer it —
/// annotate the return type at the call site. `controlAttributes` itself stays
/// byte-unchanged: this entry point is purely additive.
public func control<O: EventOutcome>(
    _ id: String,
    event: HTMLEvent = .click,
    handler: @escaping @Sendable (EventData) async -> O
) -> String {
    controlAttributes(id: id, event: event) { eventData in
        // outside a dispatch there is no context to read; the fallback keeps the
        // adapter total for a direct (test) invocation.
        let context = OutcomeContext.current
            ?? OutcomeContext(component: eventData.component, invalidate: { _ in })
        return await handler(eventData).resolve(context)
    }
}
