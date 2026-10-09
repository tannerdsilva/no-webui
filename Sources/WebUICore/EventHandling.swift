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

    /// an integral field (`Double` on the wire, `Int` in a handler).
    public func int(_ key: String) -> Int? {
        number(key).map(Int.init)
    }

    /// a boolean field.
    public func bool(_ key: String) -> Bool? {
        guard case .bool(let value)? = data[key] else { return nil }
        return value
    }

    // MARK: the named payload fields

    // every framework-shipped handler reads these instead of the stringly
    // accessors above, so the pattern a reader copies out of the source is the
    // typed one, and a typo is a compile error in framework code immediately and
    // in consumer code on migration. `string(_:)` stays — it is frozen surface —
    // for a field the framework does not name.

    /// the id of the nearest id-bearing element *inside* the component boundary.
    ///
    /// a click usually lands on a label or an icon child rather than the item
    /// itself, which is why this exists: it is how a container handler learns
    /// which row was clicked. clicking the component's own root reports `nil`.
    public var targetID: String? { string("targetId") }

    /// the class of the nearest class-bearing element inside the boundary.
    public var targetClass: String? { string("targetClass") }

    /// a control's current value.
    public var value: String? { string("value") }

    /// the key from a keyboard event.
    public var key: String? { string("key") }

    /// a checkbox's checked state.
    public var checked: Bool? { bool("checked") }
}

// MARK: - the wave-4 event deck payloads (W4.1)
//
// the events `HTMLEvent` added in wave 4 carry typed payloads, so a handler
// reads `event.pointer()?.x` instead of `event.number("x")` — the magic
// strings retired for these events in the deck's Swift surface. each struct
// decodes from the wire keys the engine emits (see `extractEventData` in
// `designer/assets/webui-engine.js`) and is `Sendable` + `Equatable` like the
// rest of the event surface, so a handler can snapshot and compare payloads.

/// one pointer position on the wire — `clientX`/`clientY` plus the button
/// state the browser reports (`event.button`, `event.buttons`).
public struct PointerPayload: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let button: Int
    public let buttons: Int
    public init(x: Double, y: Double, button: Int, buttons: Int) {
        self.x = x
        self.y = y
        self.button = button
        self.buttons = buttons
    }
}

/// the first changed touch point plus how many touches are on the surface.
public struct TouchPayload: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let identifier: Int
    public let touches: Int
    public init(x: Double, y: Double, identifier: Int, touches: Int) {
        self.x = x
        self.y = y
        self.identifier = identifier
        self.touches = touches
    }
}

/// one file carried by a drag: what the engine can read synchronously off the
/// `DataTransfer`'s `File` object (`name`, `size`, `type`).
public struct DroppedFile: Sendable, Equatable {
    public let name: String
    public let size: Int
    public let type: String
    public init(name: String, size: Int, type: String) {
        self.name = name
        self.size = size
        self.type = type
    }
}

/// what a drag/drop carried: the `DataTransfer`'s data map (mime type →
/// string) and its file list.
public struct DragPayload: Sendable, Equatable {
    public let data: [String: String]
    public let files: [DroppedFile]
    public init(data: [String: String], files: [DroppedFile]) {
        self.data = data
        self.files = files
    }
}

/// what a clipboard event carried: the plain-text and html halves of the
/// clipboard, either of which may be absent.
public struct PastePayload: Sendable, Equatable {
    public let text: String?
    public let html: String?
    public init(text: String?, html: String?) {
        self.text = text
        self.html = html
    }
}

/// the wheel delta the browser reported.
public struct WheelPayload: Sendable, Equatable {
    public let deltaX: Double
    public let deltaY: Double
    public init(deltaX: Double, deltaY: Double) {
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

/// the scroll position of the scrolled element.
public struct ScrollPayload: Sendable, Equatable {
    public let scrollTop: Double
    public let scrollLeft: Double
    public init(scrollTop: Double, scrollLeft: Double) {
        self.scrollTop = scrollTop
        self.scrollLeft = scrollLeft
    }
}

/// the animation that ended.
public struct AnimationPayload: Sendable, Equatable {
    public let animationName: String
    public init(animationName: String) {
        self.animationName = animationName
    }
}

/// the css property a transition ended on, and how long it took.
public struct TransitionPayload: Sendable, Equatable {
    public let propertyName: String
    public let elapsedTime: Double
    public init(propertyName: String, elapsedTime: Double) {
        self.propertyName = propertyName
        self.elapsedTime = elapsedTime
    }
}

/// a media element's playback state. empty/null fields read as zero/nil, so a
/// `timeupdate` before metadata exists and an `error` with no media error both
/// decode into a usable value.
public struct MediaPayload: Sendable, Equatable {
    public let currentTime: Double
    public let duration: Double
    public let readyState: Int
    public let code: Int?
    public init(currentTime: Double, duration: Double, readyState: Int, code: Int?) {
        self.currentTime = currentTime
        self.duration = duration
        self.readyState = readyState
        self.code = code
    }
}

extension EventData {
    // every deck family decodes through one accessor, never a magic string —
    // the wave-4 analogue of the typed `targetID`/`value` readers above.

    /// the pointer family's payload (`pointer`, `dblclick`, `contextmenu` all
    /// report a pointer position).
    public func pointer() -> PointerPayload? {
        guard let x = number("x"), let y = number("y") else { return nil }
        return PointerPayload(x: x, y: y, button: int("button") ?? 0, buttons: int("buttons") ?? 0)
    }

    /// the touch family's payload — the first changed touch and the touch count.
    public func touch() -> TouchPayload? {
        guard let x = number("x"), let y = number("y") else { return nil }
        return TouchPayload(x: x, y: y, identifier: int("identifier") ?? 0, touches: int("touches") ?? 0)
    }

    /// the drag & drop payload — the `dataTransfer` map and file list. always
    /// decodes; a drop that carried neither data nor files is still a drop.
    public func drag() -> DragPayload {
        var dataMap: [String: String] = [:]
        if case .object(let strData)? = self.data["data"] {
            for (key, value) in strData {
                if case .string(let text) = value { dataMap[key] = text }
            }
        }
        var files: [DroppedFile] = []
        if case .array(let list)? = self.data["files"] {
            for item in list {
                guard case .object(let file) = item else { continue }
                let name = (file["name"].flatMap { if case .string(let s) = $0 { return s }; return nil }) ?? ""
                let size = (file["size"].flatMap { if case .number(let n) = $0 { return Int(n) }; return nil }) ?? 0
                let type = (file["type"].flatMap { if case .string(let s) = $0 { return s }; return nil }) ?? ""
                files.append(DroppedFile(name: name, size: size, type: type))
            }
        }
        return DragPayload(data: dataMap, files: files)
    }

    /// the clipboard payload — the plain-text/html halves, either nullable.
    public func paste() -> PastePayload {
        PastePayload(text: string("text"), html: string("html"))
    }

    /// the wheel payload.
    public func wheel() -> WheelPayload {
        WheelPayload(deltaX: number("deltaX") ?? 0, deltaY: number("deltaY") ?? 0)
    }

    /// the scroll payload.
    public func scroll() -> ScrollPayload {
        ScrollPayload(scrollTop: number("scrollTop") ?? 0, scrollLeft: number("scrollLeft") ?? 0)
    }

    /// the animation payload.
    public func animation() -> AnimationPayload {
        AnimationPayload(animationName: string("animationName") ?? "")
    }

    /// the transition payload.
    public func transition() -> TransitionPayload {
        TransitionPayload(propertyName: string("propertyName") ?? "", elapsedTime: number("elapsedTime") ?? 0)
    }

    /// the media payload. `code` is the media element's `error.code` for an
    /// `error` event and nil otherwise.
    public func media() -> MediaPayload {
        MediaPayload(
            currentTime: number("currentTime") ?? 0,
            duration: number("duration") ?? 0,
            readyState: int("readyState") ?? 0,
            code: int("code")
        )
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
            var handlers: [ComponentID: OutcomeHandler] = [:]
            /// per-component fragments to render when that component's handler
            /// fails, so a broken interaction degrades instead of vanishing.
            var fallbacks: [ComponentID: EventHandler] = [:]
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

        func register(_ handler: @escaping OutcomeHandler, for componentID: ComponentID, in session: RenderSessionID) {
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

        func handler(for componentID: ComponentID, in session: RenderSessionID) -> OutcomeHandler? {
            values.withLock { $0.sessions[session]?.handlers[componentID] }
        }

        func registerFallback(_ handler: @escaping EventHandler, for componentID: ComponentID, in session: RenderSessionID) {
            values.withLock { values in
                if values.sessions[session] == nil {
                    values.clock += 1
                    values.sessions[session] = Session(tick: values.clock)
                }
                values.sessions[session]?.fallbacks[componentID] = handler
            }
        }

        func fallback(for componentID: ComponentID, in session: RenderSessionID) -> EventHandler? {
            values.withLock { $0.sessions[session]?.fallbacks[componentID] }
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

    /// register a fragment-returning `handler` for `componentID` in `session`.
    ///
    /// the 1.x handler shape, adapted to ``HandlerOutcome``: a handler that only
    /// ever returns fragments keeps saying exactly that.
    public func register(
        _ handler: @escaping EventHandler,
        for componentID: ComponentID,
        in session: RenderSessionID
    ) {
        register(outcome: { event in .fragments(await handler(event)) }, for: componentID, in: session)
    }

    /// register a handler that can answer with a redirect, a client-state write,
    /// a reload or a failure — not only fragments.
    public func register(
        outcome handler: @escaping OutcomeHandler,
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

    /// register an outcome handler into the shared default session.
    public func register(outcome handler: @escaping OutcomeHandler, for componentID: ComponentID) {
        register(outcome: handler, for: componentID, in: .default)
    }

    /// register fragments to render when `componentID`'s handler fails.
    ///
    /// a fallback is what turns a dead control into a degraded one: the page is
    /// told the interaction failed and, in the same message, given something to
    /// show in the control's place.
    public func register(
        fallback handler: @escaping EventHandler,
        for componentID: ComponentID,
        in session: RenderSessionID
    ) {
        state.registerFallback(handler, for: componentID, in: session)
    }

    /// register a fallback into the shared default session.
    public func register(fallback handler: @escaping EventHandler, for componentID: ComponentID) {
        register(fallback: handler, for: componentID, in: .default)
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

    /// route `event` within `session`, returning the full outcome.
    public func dispatch(_ event: EventData, in session: RenderSessionID) async -> HandlerOutcome {
        logger.emit(ObservableEvent.eventReceived(component: event.component.value, event: event.event), observers: observers)

        guard let handler = state.handler(for: event.component, in: session) else {
            // route through `logger.emit` so the observer fan-out stays on the
            // single funnel every other emission uses (log line + notify).
            logger.emit(ObservableEvent.debug(message: "no handler registered for component '\(event.component.value)'"), observers: observers)
            return .fragments([])
        }

        let outcome: HandlerOutcome
        do {
            outcome = try await handler(event)
        } catch {
            // a handler used to be unable to fail at all — the type said so — and
            // the server's own comment admitted the gap. now a throw is an
            // answer: it reaches observers, and the page when the host's policy
            // says so.
            let message = String(describing: error)
            logger.emit(ObservableEvent.error(message: "handler for '\(event.component.value)' threw: \(message)"), observers: observers)
            let fragments: [FragmentUpdate]
            if let fallback = state.fallback(for: event.component, in: session) {
                fragments = await fallback(event)
            } else {
                fragments = []
            }
            return .fail(code: "handler", message: message, fallback: fragments)
        }

        logger.emit(ObservableEvent.eventHandled(component: event.component.value, event: event.event, fragmentCount: outcome.fragments.count), observers: observers)
        return outcome
    }

    /// route within the shared default session.
    public func dispatch(_ event: EventData) async -> HandlerOutcome {
        await dispatch(event, in: .default)
    }

    /// route `event` within `session`, returning its fragments.
    ///
    /// the fragment-only view of ``dispatch(_:in:)``, kept because every 1.x
    /// call site reads fragments. an outcome that carries none — a redirect, a
    /// state write, a reload — reports `[]`.
    public func handle(_ event: EventData, in session: RenderSessionID) async -> [FragmentUpdate] {
        await dispatch(event, in: session).fragments
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
    /// the innermost error boundary this render pass sits inside, or nil
    /// outside one (W4.2). a boundary installs a context value carrying its
    /// record while its content renders, so every id the subtree registers
    /// lands in that record and the boundary can answer those ids' failures.
    var boundary: ErrorBoundaryRecord?

    /// the localized environment this pass renders under (w4.5). a host that
    /// renders one locale can leave this at the default (english/en/ltr);
    /// a server serving many locales sets it per render. components read the
    /// catalog's strings from here, so a page sets the locale once.
    public var localized: LocalizedEnvironment = WebUILocalization()

    public init(router: EventRouter, session: RenderSessionID = .default) {
        self.router = router
        self.session = session
    }

    /// a render context under a specific localized environment.
    public init(
        router: EventRouter,
        session: RenderSessionID = .default,
        localized: LocalizedEnvironment
    ) {
        self.router = router
        self.session = session
        self.localized = localized
    }
    public mutating func nextComponentID() -> ComponentID {
        let id = router.nextComponentID(in: session)
        boundary?.record(id)
        return id
    }

    public mutating func nextElementID() -> ComponentID {
        router.nextElementID(in: session)
    }
    public mutating func register(handler: @escaping EventHandler, for componentID: ComponentID) {
        boundary?.record(componentID)
        router.register(handler, for: componentID, in: session)
    }

    /// register a handler that can answer with more than fragments.
    public mutating func register(
        outcome handler: @escaping OutcomeHandler,
        for componentID: ComponentID
    ) {
        boundary?.record(componentID)
        router.register(outcome: handler, for: componentID, in: session)
    }

    /// register fragments to render when `componentID`'s handler fails.
    public mutating func register(
        fallback handler: @escaping EventHandler,
        for componentID: ComponentID
    ) {
        router.register(fallback: handler, for: componentID, in: session)
    }
    @TaskLocal public static var current: RenderContext?
}

// MARK: - Localized accessors (w4.5)

extension RenderContext: LocalizedEnvironment {
    public var strings: WebUIStrings { localized.strings }
    public var locale: String { localized.locale }
    public var direction: Directionality { localized.direction }

    /// the catalog in force for this render pass, or english outside one.
    /// components call this instead of touching the literal, so a reworded
    /// english default lands in exactly one file (Localization.swift).
    public static var currentStrings: WebUIStrings {
        current?.strings ?? .english
    }
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

/// Wire a caller-stable interactive control whose handler can answer with more
/// than fragments — a redirect, a client-state write, a reload.
///
/// the same contract as ``controlAttributes(id:event:handler:)``: registration
/// happens only when a `RenderContext` is present, so a fragment re-render
/// re-emits identical routing attributes without re-registering.
public func controlAttributes(
    id: String,
    event: HTMLEvent = .click,
    outcome handler: OutcomeHandler?
) -> String {
    guard let handler else { return "" }
    if var context = RenderContext.current {
        context.register(outcome: handler, for: ComponentID(id))
    }
    return " data-component-id=\"\(htmlEscape(id))\" data-event=\"\(htmlEscape(event.rawValue))\""
}
