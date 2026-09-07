import Foundation
import Synchronization

// MARK: - LoginThrottle

/// a fixed-window attempt limiter for authentication endpoints. keys are
/// caller-supplied ("ip:1.2.3.4", "user:alice" — anything stable an attacker
/// cannot cheaply rotate). each `record(_:now:)` bumps the count for the
/// current window and reports whether the attempt is still allowed; windows
/// slide by wall clock, so no timers run. `prune(before:)` bounds memory by
/// dropping rolled-over windows.
public final class LoginThrottle: Sendable {
    private struct State {
        var windows: [String: (start: TimeInterval, count: Int)] = [:]
    }
    private let state = Mutex(State())

    public let windowSeconds: TimeInterval
    public let maxAttempts: Int

    public init(windowSeconds: TimeInterval = 60, maxAttempts: Int = 20) {
        precondition(windowSeconds > 0 && maxAttempts > 0)
        self.windowSeconds = windowSeconds
        self.maxAttempts = maxAttempts
    }

    /// record one attempt under `key`. returns `true` while the key is under
    /// its window budget; once exhausted, further attempts report `false`
    /// until the window rolls over.
    public func record(_ key: String, now: Date = Date()) -> Bool {
        let t = now.timeIntervalSince1970
        return state.withLock { state -> Bool in
            if let entry = state.windows[key], t - entry.start < windowSeconds {
                guard entry.count < maxAttempts else { return false }
                state.windows[key] = (entry.start, entry.count + 1)
                return true
            }
            state.windows[key] = (t, 1)
            return true
        }
    }

    /// clear a key's history (call after a successful authentication).
    public func reset(_ key: String) {
        state.withLock { state in
            _ = state.windows.removeValue(forKey: key)
        }
    }

    /// drop every window that has rolled over.
    public func prune(before now: Date = Date()) {
        let boundary = now.timeIntervalSince1970 - windowSeconds
        state.withLock { state in
            state.windows = state.windows.filter { $0.value.start > boundary }
        }
    }
}
