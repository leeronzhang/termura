import Foundation
import OSLog
import os

private let logger = Logger(subsystem: "com.termura.app", category: "BoundedTaskExecutor")

/// Manages bounded concurrent task execution with automatic cleanup.
///
/// Replaces raw `[Task]` arrays that grow without bound. Each spawned task
/// acquires a semaphore permit before executing and releases it on completion,
/// providing natural backpressure when the concurrency limit is reached.
/// Completed tasks are automatically removed from tracking.
@MainActor
final class BoundedTaskExecutor {
    private let semaphore: AsyncSemaphore
    private let maxConcurrent: Int
    // OSAllocatedUnfairLock is Sendable, so it can be accessed from nonisolated
    // deinit without unsafe annotations. All mutations happen on MainActor (no actual
    // contention); the lock satisfies Swift 6 Sendability for deinit-access.
    private let _tracked: OSAllocatedUnfairLock<[UUID: Task<Void, Never>]> =
        OSAllocatedUnfairLock(initialState: [:])

    /// - Parameter maxConcurrent: Maximum tasks executing simultaneously.
    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
        semaphore = AsyncSemaphore(value: maxConcurrent)
    }

    deinit {
        _tracked.withLock { $0.values.forEach { $0.cancel() } }
    }

    /// Number of tasks currently tracked (pending + executing).
    var activeCount: Int { _tracked.withLock { $0.count } }

    /// True when the queue depth has reached the hard cap.
    /// Callers can check this before spawning non-critical work to shed load
    /// during high-throughput output bursts (e.g. large PTY floods).
    var isAtCapacity: Bool {
        _tracked.withLock { $0.count } >= maxConcurrent * AppConfig.Runtime.taskQueueDepthMultiplier
    }

    /// Spawns a task on the MainActor context with bounded concurrency.
    /// The task waits for a semaphore permit before executing the operation.
    func spawn(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        let sem = semaphore
        // Task inherits @MainActor from BoundedTaskExecutor's @MainActor context — no explicit annotation needed.
        let task = Task { [weak self] in
            await sem.wait()
            // Defer handles synchronous tracking cleanup.
            // sem.signal() is called inline below — Swift defer cannot contain `await`,
            // so an inner Task would be needed otherwise, but that Task would escape
            // tracking and could signal the semaphore after deinit (CLAUDE.md §3).
            defer { self?.removeTracked(id) }
            if !Task.isCancelled {
                await operation()
            }
            await sem.signal()
        }
        _tracked.withLock { $0[id] = task }
    }

    /// Spawns a detached task off MainActor with bounded concurrency.
    /// The task waits for a semaphore permit before executing the operation.
    func spawnDetached(_ operation: @Sendable @escaping () async -> Void) {
        let id = UUID()
        let sem = semaphore
        let cleanup = { @MainActor @Sendable [weak self] in
            self?.removeTracked(id)
        }
        let task = Task.detached {
            await sem.wait()
            // Signal and hop to MainActor for cleanup are called inline — Swift defer
            // cannot contain `await`, so a nested Task would be required otherwise.
            // A nested Task escapes the tracked dictionary, preventing deinit from
            // cancelling it and allowing sem.signal() to fire after executor teardown.
            if !Task.isCancelled {
                await operation()
            }
            await sem.signal()
            await cleanup()
        }
        _tracked.withLock { $0[id] = task }
    }

    private func removeTracked(_ id: UUID) {
        _tracked.withLock { _ = $0.removeValue(forKey: id) }
    }
}
