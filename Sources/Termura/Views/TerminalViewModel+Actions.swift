import Foundation

// MARK: - Terminal actions

extension TerminalViewModel {
    func send(_ text: String) {
        let eng = engine
        let processor = outputProcessor
        let sid = sessionID
        spawnTracked {
            await eng.send(text)
            await processor.accumulateInput(text, sessionID: sid)
        }
    }

    /// Detect agent type from a submitted command.
    func detectAgentFromCommand(_ command: String) {
        let coordinator = agentCoordinator
        spawnTracked {
            await coordinator.detectAgentFromCommand(command)
        }
    }

    func resize(columns: UInt16, rows: UInt16) {
        let eng = engine
        spawnTracked { await eng.resize(columns: columns, rows: rows) }
    }

    /// Silent working directory switch: cd + clear so the user never sees the command.
    /// The command is intentionally not accumulated as user input.
    func changeDirectory(to url: URL) {
        let eng = engine
        let cdCommand = "cd \(url.path.shellEscaped) && clear\r"
        spawnTracked { await eng.send(cdCommand) }
    }

    /// Dismiss the pending risk alert. ViewModel is the single source of truth for alert state.
    func dismissRiskAlert() {
        pendingRiskAlert = nil
    }
}
