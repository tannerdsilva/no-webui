import Logging
import Synchronization

// MARK: - ObservableEvent
public enum ObservableEvent: Sendable, Codable {
    case viewRendered(viewType: String, durationNanoseconds: UInt64)
    case eventReceived(component: String, event: String)
    case eventHandled(component: String, event: String, fragmentCount: Int)
    case fragmentSent(fragmentCount: Int, seq: Int?)
    case websocketConnected
    case websocketDisconnected
    case websocketError(error: String)
    case error(message: String)
    case debug(message: String)
}

// MARK: - Observable
public protocol Observable: AnyObject, Sendable {
    func observe(_ event: ObservableEvent)
}

// MARK: - ObserverList

/// a thread-safe collection of `Observable` conformers. observers are retained
/// strongly until removed — call `remove(_:)` when an observer's lifetime ends.
/// registration is identity-deduped (adding the same instance twice is a no-op),
/// and a rejection at the `maxObservers` cap is logged as a warning instead of
/// failing silently, so a monitoring stack can never lose a sink without a trace.
/// delivers to a snapshot taken under the lock: observers added or removed
/// mid-emission take effect on the next `emit`. observers must not synchronously
/// re-emit — reentrant dispatch is permitted but unguarded.
public final class ObserverList: Sendable {
    public let maxObservers: Int
    public let logger: Logger
    private struct State {
        var observers: [any Observable] = []
    }
    private let state = Mutex(State())

    public init(
        maxObservers: Int = 100,
        logger: Logger = Logger(label: "webui.observers")
    ) {
        self.maxObservers = maxObservers
        self.logger = logger
    }

    /// register an observer. duplicate registrations are ignored; once the
    /// `maxObservers` cap is reached new observers are rejected with a warning.
    public func add(_ observer: any Observable) {
        state.withLock { state in
            guard !state.observers.contains(where: { $0 === observer }) else { return }
            guard state.observers.count < maxObservers else {
                logger.warning("ObserverList: observer cap reached (\(maxObservers)); remove(_:) unused observers or raise maxObservers.")
                return
            }
            state.observers.append(observer)
        }
    }

    public func remove(_ observer: any Observable) {
        state.withLock { $0.observers.removeAll { $0 === observer } }
    }

    public func removeAll() {
        state.withLock { $0.observers.removeAll() }
    }

    /// deliver an event to a snapshot of the current observers.
    public func emit(_ event: ObservableEvent) {
        let current = state.withLock { $0.observers }
        for observer in current {
            observer.observe(event)
        }
    }
}

// MARK: - Logger + ObservableEvent

extension Logger {
    public func emit(_ event: ObservableEvent, observers: ObserverList? = nil) {
        switch event {
        case .viewRendered(let viewType, let durationNs):
            // integer microseconds: stdlib-only arithmetic, no locale dependence
            let us = durationNs / 1_000
            self.trace("rendered \(viewType) in \(us)µs")
        case .eventReceived(let component, let event):
            self.debug("event received: \(event) on \(component)")
        case .eventHandled(let component, let event, let count):
            self.debug("event handled: \(event) on \(component) → \(count) fragment(s)")
        case .fragmentSent(let count, let seq):
            let seqStr = seq.map { " seq=\($0)" } ?? ""
            self.trace("sent \(count) fragment(s)\(seqStr)")
        case .websocketConnected:
            self.info("WebSocket connected")
        case .websocketDisconnected:
            self.warning("WebSocket disconnected")
        case .websocketError(let error):
            self.error("WebSocket error: \(error)")
        case .error(let message):
            self.error("\(message)")
        case .debug(let message):
            self.debug("\(message)")
        }
        observers?.emit(event)
    }
}
