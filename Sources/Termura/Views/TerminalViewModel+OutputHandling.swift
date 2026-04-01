import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalViewModel")

// MARK: - Output event handling

extension TerminalViewModel {

    func handleOutputEvent(_ event: TerminalOutputEvent) async {
        switch event {
        case .data:
            // Pre-processed in subscribeToOutput before the @MainActor hop.
            break

        case let .processExited(code):
            let sid = sessionID
            logger.info("Session \(sid) process exited code=\(code)")
            let detector = agentCoordinator.agentDetector
            let agentState = await detector.buildState()
            let session = sessionStore.session(id: sessionID)
            let chunks = Array(outputProcessor.outputStore.chunks)
            await sessionServices.generateHandoffIfNeeded(
                session: session,
                chunks: chunks,
                agentState: agentState,
                projectRoot: sessionStore.projectRoot
            )

        case let .titleChanged(title):
            sessionStore.renameSession(id: sessionID, title: title)

        case let .workingDirectoryChanged(path):
            sessionStore.updateWorkingDirectory(id: sessionID, path: path)
            await refreshMetadata(workingDirectory: path)
        }
    }

}
