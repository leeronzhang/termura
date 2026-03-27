import DequeModule
import Foundation

/// Cooperative async semaphore for bounding concurrent task execution.
///
/// Unlike `DispatchSemaphore`, this suspends callers cooperatively without blocking
/// a thread, making it safe for Swift structured concurrency.
actor AsyncSemaphore {
    private var permits: Int
    private var waiters: Deque<CheckedContinuation<Void, Never>> = []

    /// Creates a semaphore with the given number of permits.
    /// - Parameter value: Maximum concurrent permits (must be > 0).
    init(value: Int) {
        precondition(value > 0, "AsyncSemaphore value must be positive")
        permits = value
    }

    /// Acquires a permit, suspending if none are available.
    func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    /// Releases a permit, resuming the next waiter if any.
    func signal() {
        if waiters.isEmpty {
            permits += 1
        } else {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}
