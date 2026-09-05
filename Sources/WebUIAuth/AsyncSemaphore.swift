import Foundation

// MARK: - AsyncSemaphore

/// an async counting semaphore — the auth-side gate for expensive
/// verifications (`argon2`). `wait()` suspends the calling task until a
/// permit is available; `signal()` releases one. backed by an `NSLock` and
/// task suspensions, so no thread is ever blocked (unlike a dispatch
/// semaphore). not a fair queue by design — any ready waiter may be resumed.
///
/// the lock is only ever touched from synchronous helper functions: foundation
/// marks `NSLock` unavailable in async contexts, so the async methods funnel
/// every critical section through a sync `private` call.
public final class AsyncSemaphore: @unchecked Sendable {
	private let lock = NSLock()
	private var permits: Int
	private var waiters: [CheckedContinuation<Void, Never>] = []

	/// - Parameter permits: the number of concurrent holders.
	public init(permits: Int) {
		precondition(permits > 0, "AsyncSemaphore requires at least one permit")
		self.permits = permits
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
		lock.lock()
		if let waiter = waiters.first {
			waiters.removeFirst()
			lock.unlock()
			waiter.resume()
		} else {
			permits += 1
			lock.unlock()
		}
	}

	// MARK: sync-only critical sections (NSLock is async-unavailable)

	private func takePermitIfAvailable() -> Bool {
		lock.lock()
		defer { lock.unlock() }
		guard permits > 0 else { return false }
		permits -= 1
		return true
	}

	private func enqueueWaiter(_ continuation: CheckedContinuation<Void, Never>) {
		lock.lock()
		defer { lock.unlock() }
		waiters.append(continuation)
	}
}
