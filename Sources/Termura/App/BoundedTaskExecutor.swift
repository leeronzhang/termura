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
    private var _tracked: [UUID: AutoCancellableTask] = [:]
    /// O(1) active-task count maintained incrementally alongside `_tracked`.
    /// Avoids calling `_tracked.count` (O(n) dictionary probe) in `activeCount`
    /// and `isAtCapacity`, which are queried on every high-frequency spawn check.
    private var _trackedCount = 0

    /// - Parameter maxConcurrent: Maximum tasks executing simultaneously.
    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
        semaphore = AsyncSemaphore(value: maxConcurrent)
    }

    /// Number of tasks currently tracked (pending + executing).
    var activeCount: Int { _trackedCount }

    /// True when the queue depth has reached the hard cap.
    /// Callers MUST NOT drop data when this returns true. Instead, coalesce
    /// the new payload into a pending buffer so the next spawned task can
    /// drain it — see `TerminalSessionController.handlePreprocessedData`.
    var isAtCapacity: Bool {
        _trackedCount >= maxConcurrent * AppConfig.Runtime.taskQueueDepthMultiplier
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
            defer { self?.removeTracked(id) }
            if !Task.isCancelled {
                await operation()
            }
            await sem.signal()
        }
        _tracked[id] = AutoCancellableTask(task)
        _trackedCount += 1
    }

    /// Spawns a detached task off MainActor with bounded concurrency.
    /// The task waits for a semaphore permit before executing the operation.
    func spawnDetached(_ operation: @Sendable @escaping () async -> Void) {
        let id = UUID()
        let sem = semaphore
        let cleanup = { @MainActor @Sendable [weak self] in
            self?.removeTracked(id)
        }
        // WHY: Executor-owned background work must leave MainActor while still respecting the semaphore bound.
        // OWNER: BoundedTaskExecutor tracks this task in _tracked[id] until cleanup runs.
        // TEARDOWN: cleanup removes the tracked handle after operation completion or cancellation.
        // TEST: Cover waitForIdle, cancellation, and bounded parallelism behavior.
        let task = Task.detached {
            await sem.wait()
            if !Task.isCancelled {
                await operation()
            }
            await sem.signal()
            await cleanup()
        }
        _tracked[id] = AutoCancellableTask(task)
        _trackedCount += 1
    }

    /// Awaits all currently tracked tasks and any follow-on tasks they schedule until the
    /// executor becomes idle. Useful for deterministic teardown and tests of tracked work.
    func waitForIdle() async {
        while !_tracked.isEmpty {
            let snapshot = Array(_tracked.values)
            for task in snapshot {
                await task.value
            }
        }
    }

    private func removeTracked(_ id: UUID) {
        if _tracked.removeValue(forKey: id) != nil {
            _trackedCount -= 1
        }
    }
}
