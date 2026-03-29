import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionServices")

/// Groups auxiliary session lifecycle services: context injection for restored
/// sessions and handoff generation on process exit.
///
/// Extracted from `TerminalViewModel` to reduce its init parameter count.
@MainActor
final class SessionServices {
    // MARK: - Dependencies

    let contextInjectionService: (any ContextInjectionServiceProtocol)?
    let sessionHandoffService: (any SessionHandoffServiceProtocol)?
    let isRestoredSession: Bool

    // MARK: - Internal state

    private var hasInjectedContext = false
    private var injectionTask: Task<Void, Never>?

    // MARK: - Init

    init(
        contextInjectionService: (any ContextInjectionServiceProtocol)? = nil,
        sessionHandoffService: (any SessionHandoffServiceProtocol)? = nil,
        isRestoredSession: Bool = false
    ) {
        self.contextInjectionService = contextInjectionService
        self.sessionHandoffService = sessionHandoffService
        self.isRestoredSession = isRestoredSession
    }

    deinit {
        injectionTask?.cancel()
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
        guard let service = contextInjectionService else { return }
        injectionTask?.cancel()
        injectionTask = Task { @MainActor [weak self] in
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
            _ = self // prevent premature dealloc
            await engine.send(text)
        }
    }

    // MARK: - Session handoff

    /// Generate a session handoff document on process exit.
    /// Requires an active agent (non-unknown), a session with a working directory,
    /// and a configured handoff service.
    func generateHandoffIfNeeded(
        session: SessionRecord?,
        chunks: [OutputChunk],
        agentState: AgentState?
    ) {
        guard let agentState, agentState.agentType != .unknown else { return }
        guard let session, session.workingDirectory != nil else { return }
        guard let handoffService = sessionHandoffService else { return }

        Task.detached {
            do {
                try await handoffService.generateHandoff(
                    session: session,
                    chunks: chunks,
                    agentState: agentState
                )
            } catch {
                logger.error("Session handoff failed: \(error)")
            }
        }
    }
}
