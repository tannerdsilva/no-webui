import Synchronization

// MARK: - AsyncSemaphore

/// an async counting semaphore — the auth-side gate for expensive
/// verifications (`argon2`). `wait()` suspends the calling task until a
/// permit is available; `signal()` releases one. backed by a `Mutex`
/// (Swift `Synchronization`) and task suspensions, so no thread is ever
/// blocked (unlike a dispatch semaphore). the queue is fifo: `signal()`
/// resumes the longest-parked waiter first; resumption itself is scheduled
/// cooperatively by the executor.
///
/// waiters are resumed *outside* the mutex so the resumed task never runs
/// while the lock is held.
public final class AsyncSemaphore: Sendable {
    private struct State {
        var permits: Int
        var waiters: [CheckedContinuation<Void, Never>] = []
    }
    private let state: Mutex<State>

    /// - Parameter permits: the number of concurrent holders.
    public init(permits: Int) {
        precondition(permits > 0, "AsyncSemaphore requires at least one permit")
        self.state = Mutex(State(permits: permits))
    }

    /// the number of waiters currently parked (allows tests to stage parks
    /// deterministically and serves as an admission-pressure gauge).
    public var waiterCount: Int {
        state.withLock { $0.waiters.count }
    }

    /// acquire a permit, suspending until one is released.
    public func wait() async {
        if takePermitIfAvailable() { return }
        await withCheckedContinuation { continuation in
            if takePermitIfAvailable() {
                continuation.resume()
            } else {
                enqueueWaiter(continuation)
            }
        }
    }

    /// release a permit, resuming the next waiter if one is queued.
    public func signal() {
        let waiter = state.withLock { s -> CheckedContinuation<Void, Never>? in
            if let w = s.waiters.first {
                s.waiters.removeFirst()
                return w
            }
            s.permits += 1
            return nil
        }
        waiter?.resume()
    }

    // MARK: sync critical sections

    private func takePermitIfAvailable() -> Bool {
        state.withLock { s in
            guard s.permits > 0 else { return false }
            s.permits -= 1
            return true
        }
    }

    private func enqueueWaiter(_ continuation: CheckedContinuation<Void, Never>) {
        state.withLock { $0.waiters.append(continuation) }
    }
}
