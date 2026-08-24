import Foundation
import Logging

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
    public let data: [String: String]
    public init(component: ComponentID, event: String, data: [String: String]) {
        self.component = component
        self.event = event
        self.data = data
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
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var _handlers: [ComponentID: EventHandler] = [:]
        private var _nextID: Int = 0

        func register(_ handler: @escaping EventHandler, for componentID: ComponentID) {
            lock.lock()
            _handlers[componentID] = handler
            lock.unlock()
        }

        var handlerCount: Int {
            lock.lock()
            let c = _handlers.count
            lock.unlock()
            return c
        }

        func handler(for componentID: ComponentID) -> EventHandler? {
            lock.lock()
            let h = _handlers[componentID]
            lock.unlock()
            return h
        }

        func nextComponentID() -> ComponentID {
            lock.lock()
            let id = ComponentID("c\(_nextID)")
            _nextID += 1
            lock.unlock()
            return id
        }

        func reset() {
            lock.lock()
            _handlers.removeAll()
            _nextID = 0
            lock.unlock()
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
    public var handlerCount: Int {
        state.handlerCount
    }
    public func handle(_ event: EventData) async -> [FragmentUpdate] {
        logger.emit(ObservableEvent.eventReceived(component: event.component.value, event: event.event), observers: observers)

        guard let handler = state.handler(for: event.component) else {
            logger.warning("no handler registered for component '\(event.component.value)'")
            observers.emit(ObservableEvent.debug(message: "no handler registered for component '\(event.component.value)'"))
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
    public mutating func register(handler: @escaping EventHandler, for componentID: ComponentID) {
        router.register(handler, for: componentID)
    }
    @TaskLocal public static var current: RenderContext?
}
