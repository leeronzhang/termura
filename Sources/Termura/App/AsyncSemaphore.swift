import DequeModule
import Foundation

/// Cooperative async semaphore for bounding concurrent task execution.
///
/// Unlike `DispatchSemaphore`, this suspends callers cooperatively without blocking
/// a thread, making it safe for Swift structured concurrency.
actor AsyncSemaphore {
    private var permits: Int
    struct Suspension {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
    }
    
    private var waiters: Deque<Suspension> = []

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
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if Task.isCancelled {
                    continuation.resume()
                } else {
                    waiters.append(Suspension(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume()
        }
    }

    /// Releases a permit, resuming the next waiter if any.
    func signal() {
        if waiters.isEmpty {
            permits += 1
        } else {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume()
        }
    }
}
