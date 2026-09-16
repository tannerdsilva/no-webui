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

// MARK: - Stable-ID Control Wiring

/// Wire a caller-stable interactive control: register `handler` under the
/// stable component `id` when a `RenderContext` is present, and return the
/// `data-component-id`/`data-event` attributes to emit on the control.
///
/// When no `RenderContext` is present (a fragment re-render produced from
/// inside a handler) the same stable attributes are emitted WITHOUT
/// re-registering — the page-build registration persists in the router, so
/// routing to the already-registered handler continues. This is what makes
/// typed component handlers (`WebUITable.onSort`, chart mark selection, ...)
/// survive fragment re-renders: the ids are a pure function of component
/// state, so re-rendered HTML carries identical routing attributes.
///
/// Pass `nil` as `handler` to render the control statically (no routing
/// attributes emitted), e.g. when the component has no interactive audience.
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
