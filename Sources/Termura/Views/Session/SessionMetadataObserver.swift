import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionMetadataObserver")

@MainActor
final class SessionMetadataObserver {
    let sessionStore: any SessionStoreProtocol
    let outputProcessor: OutputProcessor
    let agentCoordinator: AgentCoordinator
    let sessionID: SessionID
    let clock: any AppClock
    weak var viewModel: TerminalViewModel?

    private(set) var pendingMetadataRefreshTask: AutoCancellableTask?
    var pendingMetadataRefreshWorkingDirectory: String?
    var lastMetadataRefreshDate: Date = .distantPast

    init(
        sessionID: SessionID,
        sessionStore: any SessionStoreProtocol,
        outputProcessor: OutputProcessor,
        agentCoordinator: AgentCoordinator,
        clock: any AppClock
    ) {
        self.sessionID = sessionID
        self.sessionStore = sessionStore
        self.outputProcessor = outputProcessor
        self.agentCoordinator = agentCoordinator
        self.clock = clock
    }

    func inject(viewModel: TerminalViewModel) {
        self.viewModel = viewModel
    }

    func tearDown() {
        pendingMetadataRefreshTask?.cancel()
    }

    func scheduleMetadataRefresh(workingDirectory: String? = nil) {
        if let workingDirectory {
            pendingMetadataRefreshWorkingDirectory = workingDirectory
        }
        guard pendingMetadataRefreshTask == nil else { return }
        pendingMetadataRefreshTask = AutoCancellableTask(Task { [weak self] in
            defer {
                self?.pendingMetadataRefreshTask = nil
                self?.pendingMetadataRefreshWorkingDirectory = nil
            }
            while let self, !Task.isCancelled {
                let elapsed = clock.now().timeIntervalSince(lastMetadataRefreshDate)
                let throttle = AppConfig.Runtime.metadataRefreshThrottleSeconds
                let delay = max(0.0, throttle - elapsed)
                if delay > 0 {
                    do {
                        try await clock.sleep(for: .seconds(delay))
                    } catch is CancellationError {
                        // CancellationError is expected — session closed during throttle
                        return
                    } catch {
                        logger.warning("Metadata refresh throttle interrupted: \(error.localizedDescription)")
                        return
                    }
                    guard !Task.isCancelled else { return }
                }
                let dir = pendingMetadataRefreshWorkingDirectory
                pendingMetadataRefreshWorkingDirectory = nil
                await refreshMetadata(workingDirectory: dir)
                lastMetadataRefreshDate = clock.now()
                guard pendingMetadataRefreshWorkingDirectory != nil else { break }
            }
        })
    }

    func refreshMetadata(workingDirectory: String? = nil) async {
        guard let viewModel else { return }
        let service = outputProcessor.tokenCountingService
        let sid = sessionID
        let breakdown = await service.tokenBreakdown(for: sid)
        let tokens = breakdown.inputTokens + breakdown.cachedTokens
        let elapsed = clock.now().timeIntervalSince(viewModel.sessionStartTime)
        let cmdCount = outputProcessor.outputStore.chunks.count
        let dir = workingDirectory ?? viewModel.currentMetadata.workingDirectory
        let agentDet = agentCoordinator.agentDetector
        let agentState = await agentDet.buildState(tokenCount: tokens)

        let ctxLimit = agentState?.contextWindowLimit ?? 0
        let ctxFraction = agentState?.contextUsageFraction ?? 0
        let agentElapsed = agentState.map { clock.now().timeIntervalSince($0.startedAt) } ?? 0
        let cost = agentState?.estimatedCostUSD ?? 0

        let metadata = SessionMetadata(
            sessionID: sessionID,
            estimatedTokenCount: tokens,
            totalCharacterCount: tokens * AppConfig.AI.asciiCharsPerToken,
            inputTokenCount: breakdown.inputTokens,
            outputTokenCount: breakdown.outputTokens,
            cachedTokenCount: breakdown.cachedTokens,
            estimatedCostUSD: cost,
            sessionDuration: elapsed,
            commandCount: cmdCount,
            workingDirectory: dir,
            activeAgentCount: agentCoordinator.agentStateStore.activeAgentCount,
            currentAgentType: agentState?.agentType,
            currentAgentStatus: agentState?.status,
            currentAgentTask: agentState?.currentTask,
            agentElapsedTime: agentElapsed,
            contextWindowLimit: ctxLimit,
            contextUsageFraction: ctxFraction,
            agentActiveFilePath: agentState?.activeFilePath
        )

        guard metadata.estimatedTokenCount != viewModel.currentMetadata.estimatedTokenCount ||
            metadata.sessionDuration != viewModel.currentMetadata.sessionDuration ||
            metadata.workingDirectory != viewModel.currentMetadata.workingDirectory else { return }

        let sidValue = sessionID.rawValue
        logger.debug("Updating ViewModel metadata for session \(sidValue)")
        viewModel.currentMetadata = metadata
    }
}
