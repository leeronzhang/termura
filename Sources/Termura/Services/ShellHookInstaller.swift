import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ShellHookInstaller")

// MARK: - ShellType

enum ShellType: String, CaseIterable, Sendable {
    case zsh
    case bash

    var rcFileName: String {
        switch self {
        case .zsh: ".zshrc"
        case .bash: ".bashrc"
        }
    }
}

// MARK: - ShellHookInstaller

/// Installs OSC 133 shell integration hooks into the user's shell RC file.
/// Runs all file I/O off-MainActor as a Swift actor.
actor ShellHookInstaller {
    // MARK: - Public API

    /// Append the Termura shell hook to the given shell's RC file if not already present.
    func install(into shell: ShellType) async throws {
        let rcPath = rcFilePath(for: shell)
        let script = hookScript(for: shell)

        let alreadyInstalled: Bool = if fileExists(at: rcPath) {
            try isHookPresent(in: rcPath)
        } else {
            false
        }
        guard !alreadyInstalled else {
            logger.info("Shell hook already installed for \(shell.rawValue)")
            return
        }

        let appendText = "\n\(script)\n"
        guard let data = appendText.data(using: .utf8) else {
            throw ShellHookError.encodingFailed
        }

        if fileExists(at: rcPath) {
            let handle = try FileHandle(forWritingAtPath: rcPath)
                .orThrow(ShellHookError.fileOpenFailed(rcPath))
            defer {
                do {
                    try handle.close()
                } catch {
                    logger.error("Failed to close RC file handle: \(error)")
                }
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: URL(fileURLWithPath: rcPath), options: .atomic)
        }
        logger.info("Shell hook installed for \(shell.rawValue) at \(rcPath)")
    }

    /// Returns true if the Termura hook sentinel comment is already in the RC file.
    func isInstalled(for shell: ShellType) async -> Bool {
        let rcPath = rcFilePath(for: shell)
        do {
            return try isHookPresent(in: rcPath)
        } catch {
            logger.debug("Could not check hook in \(rcPath): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private helpers

    private func rcFilePath(for shell: ShellType) -> String {
        let home = AppConfig.Paths.homeDirectory
        return "\(home)/\(shell.rcFileName)"
    }

    private func isHookPresent(in path: String) throws -> Bool {
        let contents: String
        do {
            contents = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            logger.debug("RC file not readable at \(path): \(error.localizedDescription)")
            return false
        }
        return contents.contains(AppConfig.ShellIntegration.hookSentinelComment)
    }

    private func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private func hookScript(for shell: ShellType) -> String {
        switch shell {
        case .zsh:
            zshHookScript
        case .bash:
            bashHookScript
        }
    }
}

// MARK: - Hook scripts

private let zshHookScript = """
\(AppConfig.ShellIntegration.hookSentinelComment)
_termura_exit=0
precmd_termura() {
    printf '\\033]133;D;%s\\007' "${_termura_exit:-0}"
    printf '\\033]133;A\\007'
}
preexec_termura() {
    _termura_exit=$?
    printf '\\033]133;B\\007'
    printf '\\033]133;C\\007'
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd precmd_termura
add-zsh-hook preexec preexec_termura
"""

private let bashHookScript = """
\(AppConfig.ShellIntegration.hookSentinelComment)
_termura_exit=0
_termura_precmd() {
    printf '\\033]133;D;%s\\007' "${_termura_exit:-0}"
    printf '\\033]133;A\\007'
}
_termura_preexec() {
    _termura_exit=$?
    printf '\\033]133;B\\007'
    printf '\\033]133;C\\007'
}
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_termura_precmd"
trap '_termura_preexec' DEBUG
"""

// MARK: - Errors

enum ShellHookError: LocalizedError {
    case encodingFailed
    case fileOpenFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Failed to encode shell hook script as UTF-8."
        case let .fileOpenFailed(path):
            "Failed to open file for writing at: \(path)"
        }
    }
}

// MARK: - Optional helpers

private extension Optional {
    func orThrow(_ error: some Error) throws -> Wrapped {
        guard let value = self else { throw error }
        return value
    }
}
