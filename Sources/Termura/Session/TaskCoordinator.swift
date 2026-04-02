import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TaskCoordinator")

/// Manages asynchronous tasks with support for debouncing, single-flighting, and awaiting completion.
/// Designed for @MainActor usage within ViewModels or Stores.
@MainActor
final class TaskCoordinator {
    private var tasks: [String: AutoCancellableTask] = [:]
    private var taskIDs: [String: UUID] = [:]
    private var trackedTasks: [UUID: AutoCancellableTask] = [:]

    // MARK: - Debounce

    /// Cancels previous task for the key and starts a new one after a delay.
    func debounce(
        key: String,
        delay: Duration,
        clock: any AppClock,
        operation: @MainActor @Sendable @escaping () async throws -> Void,
        onFailure: (@MainActor @Sendable (Error) -> Void)? = nil
    ) {
        tasks[key]?.cancel()
        let id = UUID()
        taskIDs[key] = id

        let task = Task {
            defer {
                if taskIDs[key] == id {
                    tasks.removeValue(forKey: key)
                    taskIDs.removeValue(forKey: key)
                }
            }
            do {
                try await clock.sleep(for: delay)
                try await operation()
            } catch is CancellationError {
                // Expected when a newer task supersedes this one or during teardown.
                return
            } catch {
                onFailure?(error)
            }
        }
        tasks[key] = AutoCancellableTask(task)
    }

    // MARK: - Single flight

    /// Cancels previous task for the key and starts a new one immediately.
    func singleFlight(
        key: String,
        operation: @MainActor @Sendable @escaping () async throws -> Void,
        onFailure: (@MainActor @Sendable (Error) -> Void)? = nil
    ) {
        tasks[key]?.cancel()
        let id = UUID()
        taskIDs[key] = id

        let task = Task {
            defer {
                if taskIDs[key] == id {
                    tasks.removeValue(forKey: key)
                    taskIDs.removeValue(forKey: key)
                }
            }
            do {
                try await operation()
            } catch is CancellationError {
                // CancellationError is expected — newer task supersedes or owner deinit.
                return
            } catch {
                onFailure?(error)
            }
        }
        tasks[key] = AutoCancellableTask(task)
    }

    // MARK: - Tracked execution

    /// Runs a task and tracks it so it can be awaited during flush.
    func track(
        operation: @MainActor @Sendable @escaping () async throws -> Void,
        onFailure: (@MainActor @Sendable (Error) -> Void)? = nil
    ) {
        let id = UUID()
        let task = Task {
            defer { trackedTasks.removeValue(forKey: id) }
            do {
                try await operation()
            } catch is CancellationError {
                // CancellationError is expected — flush cancelled or task completed.
                return
            } catch {
                onFailure?(error)
            }
        }
        trackedTasks[id] = AutoCancellableTask(task)
    }

    // MARK: - Teardown

    /// Cancels all debounced and single-flight tasks.
    func cancelAllPending() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        taskIDs.removeAll()
    }

    /// Awaits all tracked tasks until they finish (or are cancelled externally).
    func flushTracked() async {
        let snapshot = Array(trackedTasks.values)
        // We don't remove them here; the defer in each task handles removal.
        for task in snapshot {
            _ = await task.result
        }
    }

    /// Checks if there are any active tasks.
    var isIdle: Bool {
        tasks.isEmpty && trackedTasks.isEmpty
    }

    /// Awaits all pending and tracked tasks until idle.
    func waitForIdle() async {
        while !isIdle {
            let pending = Array(tasks.values)
            let tracked = Array(trackedTasks.values)
            for task in pending {
                _ = await task.result
            }
            for task in tracked {
                _ = await task.result
            }
        }
    }
}
