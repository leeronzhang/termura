import Foundation

/// A sendable box that cancels the wrapped task when deallocated.
/// This allows safe teardown of tasks owned by actors while keeping
/// task cleanup encapsulated in a small reference type.
final class AutoCancellableTask: Sendable {
    private let task: Task<Void, Never>

    init(_ task: Task<Void, Never>) {
        self.task = task
    }

    deinit {
        task.cancel()
    }

    func cancel() {
        task.cancel()
    }

    var value: Void {
        get async {
            await task.value
        }
    }

    var result: Result<Void, Never> {
        get async {
            await task.result
        }
    }
}
