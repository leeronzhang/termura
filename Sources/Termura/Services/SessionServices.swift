import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionServices")

/// Groups auxiliary session lifecycle services: context injection for restored
/// sessions and handoff generation on process exit.
///
/// Extracted from `TerminalViewModel` to reduce its init parameter count.
///
/// Actor isolation: no SwiftUI-observed state — uses Swift native actor per CLAUDE.md §6.1 Principle 1.
actor SessionServices {
    // MARK: - Dependencies

    let contextInjectionService: (any ContextInjectionServiceProtocol)?
    let sessionHandoffService: (any SessionHandoffServiceProtocol)?
    let isRestoredSession: Bool

    /// True when PTY-level context injection is available for this restored session.
    /// Checked synchronously by TerminalAreaView to skip redundant Composer pre-fill.
    /// Safe as `nonisolated let` — immutable value set at init.
    nonisolated let hasContextInjection: Bool

    // MARK: - Internal state

    private var hasInjectedContext = false
    // Swift actor deinit runs synchronously under last-reference guarantee and can
    // access actor-isolated state — no unsafe keyword needed for Task? slots in actors.
    private var injectionTask: Task<Void, Never>?
    /// Tracked handoff task — awaited by flushPendingHandoff() on window close
    /// so the write completes before resources are torn down.
    private var handoffTask: Task<Void, Never>?

    // MARK: - Init

    init(
        contextInjectionService: (any ContextInjectionServiceProtocol)? = nil, // Optional: harness feature gate
        sessionHandoffService: (any SessionHandoffServiceProtocol)? = nil,      // Optional: harness feature gate
        isRestoredSession: Bool = false
    ) {
        self.contextInjectionService = contextInjectionService
        self.sessionHandoffService = sessionHandoffService
        self.isRestoredSession = isRestoredSession
        self.hasContextInjection = isRestoredSession && contextInjectionService != nil
    }

    deinit {
        injectionTask?.cancel()
        handoffTask?.cancel()
    }

    // MARK: - Context injection

    /// Inject project context into a restored session (once only).
    /// Guards: must be a restored session, not already injected, non-empty working directory,
    /// and a context injection service must be available.
    func injectContextIfNeeded(
        workingDirectory: String,
        engine: any TerminalEngine,
        clock: any AppClock
    ) {
        guard isRestoredSession, !hasInjectedContext else { return }
        hasInjectedContext = true
        guard !workingDirectory.isEmpty else { return }
        // contextInjectionService is nil in non-Harness builds (harness feature gate — expected early exit).
        guard let service = contextInjectionService else { return }
        injectionTask?.cancel()
        // Task { @MainActor }: engine.send requires @MainActor (TerminalEngine protocol is @MainActor).
        // The task body does not access any actor-isolated properties of self after the guard check above.
        injectionTask = Task { @MainActor in
            guard let text = await service.buildInjectionText(projectRoot: workingDirectory) else { return }
            do {
                try await clock.sleep(for: AppConfig.SessionHandoff.injectionDelay)
            } catch is CancellationError {
                // CancellationError is expected — session closed before the injection delay elapsed.
                return
            } catch {
                logger.warning("Context injection delay failed: \(error.localizedDescription)")
                return
            }
            await engine.send(text)
        }
    }

    // MARK: - Session handoff

    /// Generate a session handoff document on process exit.
    /// Requires an active agent (non-unknown) and a configured handoff service.
    func generateHandoffIfNeeded(
        session: SessionRecord?,
        chunks: [OutputChunk],
        agentState: AgentState?,
        projectRoot: String?
    ) {
        guard let agentState, agentState.agentType != .unknown else { return }
        guard let session else { return }
        guard let projectRoot else { return }
        // sessionHandoffService is nil in non-Harness builds (harness feature gate — expected early exit).
        guard let handoffService = sessionHandoffService else { return }

        handoffTask = Task.detached {
            do {
                try await handoffService.generateHandoff(
                    session: session,
                    chunks: chunks,
                    agentState: agentState,
                    projectRoot: projectRoot
                )
            } catch {
                logger.error("Session handoff failed: \(error)")
            }
        }
    }

    /// Awaits the in-flight handoff task if one exists.
    /// Called from the flush path on window close to prevent data loss.
    func flushPendingHandoff() async {
        await handoffTask?.value
        handoffTask = nil
    }
}
