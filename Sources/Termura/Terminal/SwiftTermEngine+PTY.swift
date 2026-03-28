import AppKit
import Foundation
import OSLog
import SwiftTerm

private let logger = Logger(subsystem: "com.termura.app", category: "SwiftTermEngine.PTY")

// MARK: - PTY Lifecycle

extension SwiftTermEngine {
    func startProcess(shell: String? = nil, currentDirectory: String? = nil) {
        let start = ContinuousClock.now
        let resolvedShell = resolveShell(shell)
        let sid = sessionID
        logger.info("Starting PTY shell=\(resolvedShell) session=\(sid) dir=\(currentDirectory ?? "~")")

        terminalView.startProcess(
            executable: resolvedShell,
            args: [],
            currentDirectory: currentDirectory
        )
        isRunning = true
        let elapsed = ContinuousClock.now - start
        logger.info("PTY started in \(elapsed.totalSeconds, format: .fixed(precision: 4))s session=\(sid)")
    }

    private func resolveShell(_ shell: String?) -> String {
        if let shell, !shell.isEmpty { return shell }
        if let envShell = ProcessInfo.processInfo.environment["SHELL"], !envShell.isEmpty {
            return envShell
        }
        return "/bin/zsh"
    }
}

// MARK: - LocalProcessTerminalViewDelegate

extension SwiftTermEngine: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // SwiftTerm fires this after setFrameSize() recalculates terminal dimensions
        // and sends SIGWINCH. Log for diagnostics; PTY resize is already handled by SwiftTerm.
        let sid = sessionID
        logger.debug("Terminal resized session=\(sid) cols=\(newCols) rows=\(newRows)")
    }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        #if DEBUG
        let codepoints = title.unicodeScalars.prefix(8)
            .map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
        logger.debug("OSC title codepoints: \(codepoints) | raw: \(title)")
        #endif
        // Lifecycle: nonisolated delegate → MainActor bridge; short-lived yield, no cleanup needed.
        Task { @MainActor [weak self] in
            guard let self else { return }
            continuation.yield(.titleChanged(title))
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // OSC 7 delivers a file:// URL (e.g. "file:///Users/foo/bar"); convert to a plain path.
        guard let directory else { return }
        let resolvedPath: String
        if let url = URL(string: directory), url.isFileURL {
            resolvedPath = url.path
        } else {
            resolvedPath = directory
        }
        // Lifecycle: nonisolated delegate → MainActor bridge; short-lived yield, no cleanup needed.
        Task { @MainActor [weak self] in
            guard let self else { return }
            continuation.yield(.workingDirectoryChanged(resolvedPath))
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        let code = exitCode ?? -1
        // Lifecycle: nonisolated delegate → MainActor bridge; terminal lifecycle event.
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
