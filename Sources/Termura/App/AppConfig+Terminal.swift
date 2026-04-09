import Foundation

extension AppConfig {
    enum Terminal {
        static let maxScrollbackLines = 10000
        static let maxOutputChunksPerSession = 500
        static let ptyColumns: UInt16 = 80
        static let ptyRows: UInt16 = 24
        /// Backpressure cap for PTY output / shell-event AsyncStreams.
        /// Oldest events are dropped once the buffer is full; prevents unbounded memory growth
        /// during high-throughput commands (e.g. `cat` on a large file).
        static let streamBufferCapacity = 512
        /// Debounce window before sending SIGWINCH after a layout change.
        /// Prevents spurious double-resize when SwiftUI rebuilds the terminal view tree
        /// during a session switch (first layout pass fires with a transient wrong size,
        /// second pass fires with the correct size; only the second should send SIGWINCH).
        static let resizeDebounce: Duration = .milliseconds(16)
    }

    enum Runtime {
        /// Search debounce (Combine scheduler requires Double; keep as seconds)
        static let searchDebounceSeconds: Double = 0.3
        /// Notes auto-save debounce
        static let notesAutoSave: Duration = .seconds(1)
        /// Debounce before persisting session metadata changes (rename, working directory).
        /// Intentionally separate from notesAutoSave so each can be tuned independently.
        static let sessionMetadataDebounce: Duration = .seconds(1)
        /// Maximum concurrent background tasks per terminal session.
        /// Bounds CPU/memory usage during high-frequency output (e.g. `cat` large file).
        static let maxConcurrentSessionTasks = 8
        /// Queue depth multiplier for BoundedTaskExecutor.isAtCapacity.
        /// When tracked.count >= maxConcurrent * this value, incoming output batches
        /// are coalesced into a pending buffer instead of spawning a new task,
        /// preventing unbounded task accumulation during PTY floods.
        static let taskQueueDepthMultiplier = 4
        /// Long command notification threshold
        static let longCommandThresholdSeconds: Double = 30.0
        /// Maximum time (seconds) to wait for DB flush + handoff during app termination.
        /// If the deadline is exceeded the app still calls reply(toApplicationShouldTerminate:)
        /// rather than hanging until the OS force-kills the process.
        static let terminationFlushTimeoutSeconds: Double = 2.0
        /// Visor animation duration
        static let visorAnimationSeconds: Double = 0.2
        /// Delay before dismissing onboarding sheet after install.
        static let onboardingDismissDelay: Duration = .seconds(1)
        /// Auto-dismiss duration for transient toast banners (e.g. "Saved to Notes").
        static let toastAutoDismiss: Duration = .seconds(2)
        /// Minimum interval between SessionMetadata UI refreshes during streaming output.
        /// Prevents per-packet SwiftUI redraws during high-throughput terminal output.
        static let metadataRefreshThrottleSeconds: Double = 0.5
        /// Debounce before forking a PTY when activating a session without an existing engine.
        /// Prevents a PTY fork storm when the user rapidly clicks through the session list:
        /// only the session the user actually settles on creates a shell process.
        static let engineCreationDebounce: Duration = .milliseconds(120)
        /// Tick interval for AgentStateStore.now, which drives elapsed-duration display in sidebar
        /// and agent dashboard. 1s granularity matches the coarsest unit MetadataFormatter emits.
        static let agentDurationTickSeconds: Double = 1.0
    }

    enum SLO {
        /// Launch time P95 target: < 2s
        static let launchSeconds: Double = 2.0
        /// Session switch target: < 100ms
        static let sessionSwitchSeconds: Double = 0.1
        /// Full-text search P99 target: < 200ms
        static let searchSeconds: Double = 0.2
        /// Terminal input latency target: < 16ms (1 frame)
        static let inputLatencySeconds: Double = 0.016
    }
}
