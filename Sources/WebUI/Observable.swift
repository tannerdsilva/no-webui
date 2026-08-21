import Foundation
import Logging

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
public final class ObserverList: @unchecked Sendable {
    public let maxObservers: Int
    private let lock = NSLock()
    private var observers: [any Observable] = []

    public init(maxObservers: Int = 100) {
        self.maxObservers = maxObservers
    }
    public func add(_ observer: any Observable) {
        lock.lock()
        if observers.count >= maxObservers {
            lock.unlock()
            return
        }
        observers.append(observer)
        lock.unlock()
    }
    public func remove(_ observer: any Observable) {
        lock.lock()
        observers.removeAll { $0 === observer }
        lock.unlock()
    }
    public func removeAll() {
        lock.lock()
        observers.removeAll()
        lock.unlock()
    }
    public func emit(_ event: ObservableEvent) {
        lock.lock()
        let current = observers
        lock.unlock()
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
            let ms = Double(durationNs) / 1_000_000
            self.trace("rendered \(viewType) in \(String(format: "%.2f", ms))ms")
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
