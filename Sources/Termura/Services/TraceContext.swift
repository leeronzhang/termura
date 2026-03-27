import Foundation

/// Lightweight trace context propagated across async boundaries.
/// Provides correlation IDs for cross-component tracing.
struct TraceContext: Sendable {
    let traceID: UUID
    let spanName: String
    let startTime: ContinuousClock.Instant

    init(spanName: String) {
        traceID = UUID()
        self.spanName = spanName
        startTime = ContinuousClock.now
    }

    /// Elapsed time since this span started.
    var elapsed: Duration {
        ContinuousClock.now - startTime
    }

    /// Elapsed time in seconds (convenience for metrics recording).
    var elapsedSeconds: Double {
        Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
}

/// TaskLocal storage for implicit trace propagation through structured concurrency.
enum TraceLocal {
    @TaskLocal static var current: TraceContext?
}

/// Execute an operation within a traced scope.
/// The trace context is automatically available via `TraceLocal.current`
/// in nested async calls (including `async let` and `TaskGroup`).
///
/// Note: `Task.detached` and unstructured `Task { }` do NOT inherit TaskLocal values.
/// For those, capture `trace` explicitly from the closure parameter.
func withTrace<T: Sendable>(
    _ spanName: String,
    operation: (TraceContext) async throws -> T
) async rethrows -> T {
    let trace = TraceContext(spanName: spanName)
    return try await TraceLocal.$current.withValue(trace) {
        try await operation(trace)
    }
}
