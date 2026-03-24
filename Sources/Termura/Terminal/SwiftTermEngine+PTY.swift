import AppKit
import Foundation
import OSLog
import SwiftTerm

private let logger = Logger(subsystem: "com.termura.app", category: "SwiftTermEngine.PTY")

// MARK: - PTY Lifecycle

extension SwiftTermEngine {
    func startProcess(shell: String, currentDirectory: String? = nil) {
        let resolvedShell = resolveShell(shell)
        let sid = sessionID
        logger.info("Starting PTY shell=\(resolvedShell) session=\(sid) dir=\(currentDirectory ?? "~")")

        terminalView.startProcess(
            executable: resolvedShell,
            args: [],
            currentDirectory: currentDirectory
        )
        isRunning = true
    }

    private func resolveShell(_ shell: String) -> String {
        guard shell.isEmpty else { return shell }
        if let envShell = ProcessInfo.processInfo.environment["SHELL"], !envShell.isEmpty {
            return envShell
        }
        return "/bin/zsh"
    }
}

// MARK: - LocalProcessTerminalViewDelegate

extension SwiftTermEngine: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Size change is initiated by our own resize() call — no-op here
    }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in
            self?.continuation.yield(.titleChanged(title))
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory else { return }
        Task { @MainActor [weak self] in
            self?.continuation.yield(.workingDirectoryChanged(directory))
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        let code = exitCode ?? -1
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sid = sessionID
            logger.info("PTY terminated session=\(sid) exitCode=\(code)")
            isRunning = false
            continuation.yield(.processExited(code))
            shellContinuation.finish()
            continuation.finish()
        }
    }
}
