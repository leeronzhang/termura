import Foundation
import OSLog

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
    private var tracked: [UUID: Task<Void, Never>] = [:]

    /// - Parameter maxConcurrent: Maximum tasks executing simultaneously.
    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
        semaphore = AsyncSemaphore(value: maxConcurrent)
    }

    deinit {
        for task in tracked.values {
            task.cancel()
        }
    }

    /// Number of tasks currently tracked (pending + executing).
    var activeCount: Int { tracked.count }

    /// Spawns a task on the MainActor context with bounded concurrency.
    /// The task waits for a semaphore permit before executing the operation.
    func spawn(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        let sem = semaphore
        let task = Task { @MainActor [weak self] in
            await sem.wait()
            defer {
                Task { await sem.signal() }
                self?.removeTracked(id)
            }
            guard !Task.isCancelled else { return }
            await operation()
        }
        tracked[id] = task
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
            defer {
                Task { await sem.signal() }
                Task { @MainActor in cleanup() }
            }
            guard !Task.isCancelled else { return }
            await operation()
        }
        tracked[id] = task
    }

    private func removeTracked(_ id: UUID) {
        tracked.removeValue(forKey: id)
    }
}
