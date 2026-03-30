import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalViewModel")

/// ViewModel bridging the terminal engine with output chunking, token counting,
/// and session metadata for the terminal area view hierarchy.
///
/// Delegates agent detection/state to `AgentCoordinator`, output chunking/tokens
/// to `OutputProcessor`, and context injection/handoff to `SessionServices`.
@Observable
@MainActor
final class TerminalViewModel {
    // MARK: - Observable state

    var currentMetadata: SessionMetadata
    /// True while an interactive tool (Claude Code `>`) is showing its prompt.
    var isInteractivePrompt: Bool = false
    /// Currently pending risk alert (shown as sheet).
    var pendingRiskAlert: RiskAlert?
    /// Context window warning alert (shown as sheet).
    var contextWindowAlert: ContextWindowAlert?

    // MARK: - Dependencies

    let sessionID: SessionID
    let engine: any TerminalEngine
    let sessionStore: any SessionStoreProtocol
    let modeController: InputModeController
    let agentCoordinator: AgentCoordinator
    let outputProcessor: OutputProcessor
    let sessionServices: SessionServices
    let clock: any AppClock
    let sessionStartTime: Date = .init()

    // MARK: - Internal state (not view-driving — excluded from @Observable tracking)

    /// Bounded executor for background tasks.
    private let taskExecutor: BoundedTaskExecutor
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    /// Debounced re-check for prompt detection after PTY output settles.
    @ObservationIgnored private var promptRecheckTask: Task<Void, Never>?
    /// Throttled metadata refresh: independent slot from promptRecheckTask (CLAUDE.md §6 debounce rule).
    @ObservationIgnored private var pendingMetadataRefreshTask: Task<Void, Never>?
    /// Timestamp of the last completed metadata refresh, used for throttle calculation.
    @ObservationIgnored private var lastMetadataRefreshDate: Date = .distantPast
    /// Shell events subscription task — independent slot per CLAUDE.md §6 debounce rule.
    @ObservationIgnored private var shellTask: Task<Void, Never>?
    /// Consumes AgentCoordinator.riskAlerts — independent slot per CLAUDE.md §6 debounce rule.
    @ObservationIgnored private var riskAlertTask: Task<Void, Never>?
    /// Consumes AgentCoordinator.contextWindowAlerts — independent slot.
    @ObservationIgnored private var contextWindowAlertTask: Task<Void, Never>?

    // MARK: - Agent resume

    /// Callback injected by TerminalAreaView: fired at most once when the first shell
    /// prompt is detected in a restored session. Internal (not private) because
    /// TerminalAreaView sets it at view-setup time — not an implementation detail.
    @ObservationIgnored var onShellPromptReadyForResume: (() -> Void)?
    @ObservationIgnored private var hasTriggeredAgentResume = false

    // MARK: - Init

    init(_ components: Components) {
        sessionID = components.sessionID
        engine = components.engine
        sessionStore = components.sessionStore
        modeController = components.modeController
        agentCoordinator = components.agentCoordinator
        outputProcessor = components.outputProcessor
        sessionServices = components.sessionServices
        clock = components.clock
        taskExecutor = BoundedTaskExecutor(maxConcurrent: AppConfig.Runtime.maxConcurrentSessionTasks)

        currentMetadata = SessionMetadata.empty(
            sessionID: components.sessionID,
            workingDirectory: components.initialWorkingDirectory
        )

        subscribeToOutput()
        subscribeToShellEvents()
        subscribeToAlerts()
    }

    deinit {
        streamTask?.cancel()
        shellTask?.cancel()
        promptRecheckTask?.cancel()
        pendingMetadataRefreshTask?.cancel()
        riskAlertTask?.cancel()
        contextWindowAlertTask?.cancel()
    }
}

// MARK: - Task execution

extension TerminalViewModel {

    func spawnTracked(_ operation: @escaping @MainActor () async -> Void) {
        taskExecutor.spawn(operation)
    }

    func spawnDetachedTracked(_ operation: @Sendable @escaping () async -> Void) {
        taskExecutor.spawnDetached(operation)
    }

    /// Fires `onShellPromptReadyForResume` exactly once per session lifecycle.
    /// Called from both OSC 133 (`promptStarted`) and screen-buffer fallback paths.
    func triggerAgentResumeIfNeeded() {
        guard !hasTriggeredAgentResume else { return }
        hasTriggeredAgentResume = true
        onShellPromptReadyForResume?()
        onShellPromptReadyForResume = nil
    }
}

// MARK: - Subscriptions

extension TerminalViewModel {

    /// Subscribe to AgentCoordinator's alert streams. Runs on @MainActor so state
    /// writes (pendingRiskAlert, contextWindowAlert) are safe without extra hops.
    func subscribeToAlerts() {
        let riskStream = agentCoordinator.riskAlerts
        // Task inherits @MainActor from TerminalViewModel's @MainActor context — no explicit annotation needed.
        riskAlertTask = Task { [weak self] in
            for await risk in riskStream {
                guard let self, !Task.isCancelled else { break }
                // Dedup: only surface a new alert when none is already pending,
                // so continuous agent output does not re-open the sheet after dismiss.
                guard pendingRiskAlert == nil else { continue }
                pendingRiskAlert = risk
            }
        }
        let ctxStream = agentCoordinator.contextWindowAlerts
        contextWindowAlertTask = Task { [weak self] in
            for await alert in ctxStream {
                guard let self, !Task.isCancelled else { break }
                contextWindowAlert = alert
            }
        }
    }

    func subscribeToShellEvents() {
        // Task.detached: keeps stream iteration off @MainActor; direct await hops to
        // MainActor without allocating an intermediate Task on every event.
        let stream = engine.shellEventsStream
        shellTask = Task.detached { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { break }
                await self.handleShellEvent(event)
            }
        }
    }

    // MARK: - Debounced helpers

    /// Schedules a debounced re-check of the screen buffer after PTY output settles.
    /// Solves the race where prompt characters arrive across multiple data chunks.
    func schedulePromptRecheck() {
        promptRecheckTask?.cancel()
        promptRecheckTask = Task { [weak self] in
            do {
                try await self?.clock.sleep(for: AppConfig.UI.promptRecheckDelay)
            } catch is CancellationError {
                // CancellationError is expected — a newer output event supersedes this check.
                return
            } catch {
                logger.warning("Prompt recheck delay failed: \(error.localizedDescription)")
                return
            }
            await self?.detectPromptFromScreenBuffer()
        }
    }

    /// Throttled wrapper for `refreshMetadata()`. Fires immediately if the throttle
    /// interval has elapsed; otherwise schedules one deferred refresh to cover the
    /// window. Additional calls while a deferred refresh is pending are no-ops.
    func scheduleMetadataRefresh(workingDirectory: String? = nil) {
        guard pendingMetadataRefreshTask == nil else { return }
        let elapsed = Date().timeIntervalSince(lastMetadataRefreshDate)
        let throttle = AppConfig.Runtime.metadataRefreshThrottleSeconds
        let delay = max(0.0, throttle - elapsed)
        let dir = workingDirectory
        pendingMetadataRefreshTask = Task { [weak self] in
            defer { self?.pendingMetadataRefreshTask = nil }
            if delay > 0 {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch is CancellationError {
                    // CancellationError is expected — session was closed before the throttle fired.
                    return
                } catch {
                    logger.warning("Metadata refresh throttle interrupted: \(error.localizedDescription)")
                    return
                }
                guard !Task.isCancelled else { return }
            }
            self?.lastMetadataRefreshDate = Date()
            await self?.refreshMetadata(workingDirectory: dir)
        }
    }

    // MARK: - Output subscription

    func subscribeToOutput() {
        // Task.detached: stream loop runs off @MainActor so UTF-8 decode + ANSI strip
        // do not block the main thread. Direct `await self?.method()` hops to MainActor
        // without allocating an intermediate Task on every event (CLAUDE.md Principle 3).
        let stream = engine.outputStream
        streamTask = Task.detached { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { break }
                switch event {
                case let .data(data):
                    // Pre-process off MainActor before hopping back.
                    // Latin-1 fallback preserves content when PTY emits non-UTF-8 bytes
                    // (binary data, legacy-encoded filenames, etc.) instead of silently
                    // dropping the chunk. Latin-1 succeeds for every byte value.
                    let text = String(data: data, encoding: .utf8)
                        ?? String(data: data, encoding: .isoLatin1)
                        ?? ""
                    guard !text.isEmpty else { continue }
                    let stripped = ANSIStripper.strip(text)
                    await self.handlePreprocessedData(text: text, stripped: stripped)
                default:
                    await self.handleOutputEvent(event)
                }
            }
        }
    }

    func handlePreprocessedData(text: String, stripped: String) async {
        let sid = sessionID
        let processor = outputProcessor
        let coordinator = agentCoordinator
        let tokenService = outputProcessor.tokenCountingService

        // Debounced prompt check: schedulePromptRecheck already cancels-and-replaces,
        // so the immediate detectPromptFromScreenBuffer() call on every packet was redundant.
        schedulePromptRecheck()

        // Once the agent type is confirmed from output, skip further per-packet scanning.
        // bufferAndDetect is O(bufferLen) due to lowercased(); skipping saves that work entirely.
        // Single actor hop: check and detect are atomic inside AgentCoordinator (no TOCTOU).
        await coordinator.detectAgentFromOutputIfNeeded(stripped)

        // Backpressure: during PTY floods (e.g. thousands of permission-error lines),
        // the task queue can accumulate faster than tasks complete. When at capacity,
        // drop this packet's background analysis — the token count and chunk detection
        // will be approximate, but the terminal rendering is unaffected and the UI stays responsive.
        guard !taskExecutor.isAtCapacity else { return }

        spawnDetachedTracked {
            await processor.processDataOutput(text, stripped: stripped, sessionID: sid)
            await coordinator.analyzeOutput(stripped, tokenCountingService: tokenService)
            let update = await coordinator.computeAgentStateUpdate(
                tokenCountingService: processor.tokenCountingService
            )
            if let (state, alert) = update {
                await coordinator.applyAgentStateUpdate(state: state, alert: alert)
            }
            // Single hop back to main for UI refresh (CLAUDE.md §6.1 Principle 3).
            Task { @MainActor [weak self] in self?.scheduleMetadataRefresh() }
        }
    }
}
