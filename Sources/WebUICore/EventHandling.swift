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
    /// the most render sessions the router holds before evicting the
    /// least-recently-used. bounds a long-lived server's routing state.
    public let maxSessions: Int
    private let state: State
    public let observers: ObserverList
    public let logger: Logger
    private final class State: Sendable {
        /// one render pass's worth of routing state: the handlers it registered
        /// and the two mint counters it drained.
        struct Session {
            var handlers: [ComponentID: EventHandler] = [:]
            var nextID: Int = 0
            var nextElementID: Int = 0
            /// the clock reading at this session's last use — the LRU key.
            var tick: UInt64 = 0
        }
        private struct Values {
            var sessions: [RenderSessionID: Session] = [:]
            /// `(session, tick)` in append order. an entry whose tick no longer
            /// matches the stored session is stale (superseded by a later use)
            /// and is skipped when the list is walked for eviction.
            var lru: [(id: RenderSessionID, tick: UInt64)] = []
            var clock: UInt64 = 0
        }
        private let values = Mutex(Values())

        // MARK: session lifecycle

        /// start a render pass in `session`. an existing session is RESET, which
        /// is what makes a re-render idempotent: the mint counters restart, so the
        /// same views mint the same ids and every registration is a dictionary
        /// assignment onto a key that already exists.
        func begin(_ session: RenderSessionID) {
            values.withLock { values in
                values.clock += 1
                var fresh = Session()
                fresh.tick = values.clock
                values.sessions[session] = fresh
                values.lru.append((session, values.clock))
                Self.compact(&values)
            }
        }

        /// drop `session`, returning how many handlers went with it.
        @discardableResult
        func end(_ session: RenderSessionID) -> Int {
            values.withLock { values in
                guard let gone = values.sessions.removeValue(forKey: session) else { return 0 }
                return gone.handlers.count
            }
        }

        var sessionCount: Int {
            values.withLock { $0.sessions.count }
        }

        /// whether `session` is live. lets a server distinguish "unknown token"
        /// (reject) from "known page with no controls" (nothing to route).
        func contains(_ session: RenderSessionID) -> Bool {
            values.withLock { $0.sessions[session] != nil }
        }

        /// drop least-recently-used sessions until `maxSessions` holds, returning
        /// the evicted ids. bounded state is the point: a server that renders for
        /// a year must not accumulate a session per request.
        func evict(maxSessions: Int) -> [RenderSessionID] {
            values.withLock { values in
                var evicted: [RenderSessionID] = []
                while values.sessions.count > maxSessions, !values.lru.isEmpty {
                    let head = values.lru.removeFirst()
                    guard let live = values.sessions[head.id], live.tick == head.tick else { continue }
                    values.sessions.removeValue(forKey: head.id)
                    evicted.append(head.id)
                }
                return evicted
            }
        }

        /// collapse superseded LRU entries once the list outgrows the live set.
        /// without this the list itself becomes the leak it exists to prevent:
        /// one entry is appended per registration, so a page with 25 controls
        /// rendered 10k times would hold 250k entries.
        private static func compact(_ values: inout Values) {
            guard values.lru.count > 64, values.lru.count > values.sessions.count * 4 else { return }
            var seen = Set<RenderSessionID>()
            var kept: [(id: RenderSessionID, tick: UInt64)] = []
            for entry in values.lru.reversed() {
                guard let live = values.sessions[entry.id], live.tick == entry.tick else { continue }
                guard seen.insert(entry.id).inserted else { continue }
                kept.append(entry)
            }
            values.lru = kept.reversed()
        }

        // MARK: handlers

        func register(_ handler: @escaping EventHandler, for componentID: ComponentID, in session: RenderSessionID) {
            values.withLock { values in
                if values.sessions[session] == nil {
                    values.clock += 1
                    var fresh = Session()
                    fresh.tick = values.clock
                    values.sessions[session] = fresh
                    values.lru.append((session, values.clock))
                }
                values.sessions[session]?.handlers[componentID] = handler
            }
        }

        func handler(for componentID: ComponentID, in session: RenderSessionID) -> EventHandler? {
            values.withLock { $0.sessions[session]?.handlers[componentID] }
        }

        /// handlers in one session — the number a soak test asserts on.
        func handlerCount(in session: RenderSessionID) -> Int {
            values.withLock { $0.sessions[session]?.handlers.count ?? 0 }
        }

        /// handlers across every session.
        var handlerCount: Int {
            values.withLock { values in
                values.sessions.values.reduce(0) { $0 + $1.handlers.count }
            }
        }

        func nextComponentID(in session: RenderSessionID) -> ComponentID {
            values.withLock { values in
                var current = values.sessions[session] ?? Session()
                let id = ComponentID("c\(current.nextID)")
                current.nextID += 1
                values.sessions[session] = current
                return id
            }
        }

        func nextElementID(in session: RenderSessionID) -> ComponentID {
            values.withLock { values in
                var current = values.sessions[session] ?? Session()
                let id = ComponentID("e\(current.nextElementID)")
                current.nextElementID += 1
                values.sessions[session] = current
                return id
            }
        }

        func reset() {
            values.withLock { values in values = Values() }
        }
    }
    public init(
        logger: Logger = Logger(label: "webui.events"),
        observers: ObserverList? = nil,
        maxHandlers: Int = 10_000,
        maxSessions: Int = 1_024
    ) {
        self.state = State()
        self.logger = logger
        self.observers = observers ?? ObserverList()
        self.maxHandlers = maxHandlers
        self.maxSessions = maxSessions
    }

    // MARK: render sessions

    /// start a render pass in `session`, resetting it if it already exists.
    ///
    /// a server calls this once per page render with a session derived from the
    /// render's own identity (see `WebUIServer`). re-rendering the same page then
    /// mints the same component ids and every registration lands on a key that
    /// already exists — which is why the table stops growing.
    public func begin(_ session: RenderSessionID) {
        state.begin(session)
        let evicted = state.evict(maxSessions: maxSessions)
        if !evicted.isEmpty {
            logger.emit(
                ObservableEvent.debug(message: "EventRouter: evicted \(evicted.count) least-recently-used render session(s)"),
                observers: observers
            )
        }
    }

    /// drop `session`, returning how many handlers went with it. a host calls
    /// this when a page instance can no longer produce events (its socket closed
    /// and no re-render is coming).
    @discardableResult
    public func end(_ session: RenderSessionID) -> Int {
        let removed = state.end(session)
        if removed > 0 {
            logger.emit(
                ObservableEvent.debug(message: "EventRouter: ended render session '\(session.rawValue)' (\(removed) handler(s))"),
                observers: observers
            )
        }
        return removed
    }

    /// how many render sessions the router currently holds.
    public var sessionCount: Int { state.sessionCount }

    /// whether `session` is live.
    public func contains(_ session: RenderSessionID) -> Bool {
        state.contains(session)
    }

    /// how many handlers `session` holds.
    public func handlerCount(in session: RenderSessionID) -> Int {
        state.handlerCount(in: session)
    }

    // MARK: registration

    /// register `handler` for `componentID` in `session`.
    public func register(
        _ handler: @escaping EventHandler,
        for componentID: ComponentID,
        in session: RenderSessionID
    ) {
        if state.handlerCount(in: session) >= maxHandlers {
            logger.warning("EventRouter: handler cap reached (\(maxHandlers)) in session '\(session.rawValue)'. Call begin(_:) before each render, or increase maxHandlers.")
            return
        }
        state.register(handler, for: componentID, in: session)
    }

    /// register into the shared default session — the single-page host's path.
    public func register(_ handler: @escaping EventHandler, for componentID: ComponentID) {
        register(handler, for: componentID, in: .default)
    }

    /// mint the next component id in `session`.
    public func nextComponentID(in session: RenderSessionID) -> ComponentID {
        state.nextComponentID(in: session)
    }

    public func nextComponentID() -> ComponentID {
        state.nextComponentID(in: .default)
    }

    /// mint the next framework element id (`e0`, `e1`, ...) for an
    /// `ElementRef`. separate counter from component ids so a `data-component-id`
    /// never collides with a DOM element id.
    public func nextElementID(in session: RenderSessionID) -> ComponentID {
        state.nextElementID(in: session)
    }

    public func nextElementID() -> ComponentID {
        state.nextElementID(in: .default)
    }

    /// handlers across every session.
    public var handlerCount: Int {
        state.handlerCount
    }

    // MARK: dispatch

    /// route `event` within `session`.
    public func handle(_ event: EventData, in session: RenderSessionID) async -> [FragmentUpdate] {
        logger.emit(ObservableEvent.eventReceived(component: event.component.value, event: event.event), observers: observers)

        guard let handler = state.handler(for: event.component, in: session) else {
            // route through `logger.emit` so the observer fan-out stays on the
            // single funnel every other emission uses (log line + notify).
            logger.emit(ObservableEvent.debug(message: "no handler registered for component '\(event.component.value)'"), observers: observers)
            return []
        }

        let updates = await handler(event)
        logger.emit(ObservableEvent.eventHandled(component: event.component.value, event: event.event, fragmentCount: updates.count), observers: observers)
        return updates
    }

    /// route within the shared default session.
    public func handle(_ event: EventData) async -> [FragmentUpdate] {
        await handle(event, in: .default)
    }

    /// discard every session and every handler.
    public func reset() {
        state.reset()
    }
}

// MARK: - RenderContext
public struct RenderContext: Sendable {
    public var router: EventRouter
    /// the render session this pass mints ids and registers handlers in. a host
    /// that renders one page with one router can leave this at `.default`; a
    /// server that serves many page instances passes one per render.
    public var session: RenderSessionID

    public init(router: EventRouter, session: RenderSessionID = .default) {
        self.router = router
        self.session = session
    }
    public mutating func nextComponentID() -> ComponentID {
        router.nextComponentID(in: session)
    }

    public mutating func nextElementID() -> ComponentID {
        router.nextElementID(in: session)
    }
    public mutating func register(handler: @escaping EventHandler, for componentID: ComponentID) {
        router.register(handler, for: componentID, in: session)
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
