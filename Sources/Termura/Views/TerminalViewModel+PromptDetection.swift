import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "PromptDetection")

// MARK: - Prompt detection via screen buffer

extension TerminalViewModel {
    /// Reads the rendered cursor row from SwiftTerm's screen buffer to determine
    /// which kind of prompt (if any) is currently displayed.
    ///
    /// Why screen buffer instead of raw bytes:
    ///   TUI apps like Claude Code use ANSI cursor-movement sequences to position
    ///   text.  The raw PTY stream cannot be reliably split on newlines to find the
    ///   `>` prompt — it appears embedded in a dense block of escape codes.
    ///   After `super.dataReceived(slice:)` runs, SwiftTerm's buffer holds the
    ///   *rendered* state; `getLine(row: cursorRow)` returns exactly what is shown.

    /// Characters used as AI tool prompts (Claude Code, Aider, etc.).
    /// `>` (U+003E), U+276F, and U+203A are all common.
    static let aiPromptCharacters: Set<Character> = [">", "\u{276F}", "\u{203A}"]

    /// Shell prompt suffixes used in `isShellPromptLine`.
    /// Format: trailing space + shell sigil, or bare sigil on an otherwise empty line.
    private static let shellPromptSuffixes: [String] = [" $", " %", " #"]
    private static let bareShellPrompts: Set<String> = ["$", "%", "#"]

    func detectPromptFromScreenBuffer() {
        // Scan cursor line + up to 5 lines above. TUI apps (Claude Code) often
        // position the cursor on hint/status lines below the actual prompt.
        let lines = engine.linesNearCursor(above: 5)

        #if DEBUG
        if modeController.mode == .passthrough {
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let codepoints = trimmed.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
                logger.debug("promptDetect[\(i)]: '\(trimmed)' codepoints=[\(codepoints)]")
            }
        }
        #endif

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isAIPromptLine(trimmed) {
                isInteractivePrompt = true
                let services = sessionServices
                let dir = currentMetadata.workingDirectory
                let eng = engine
                let clk = clock
                Task { await services.injectContextIfNeeded(workingDirectory: dir, engine: eng, clock: clk) }
                return
            }
        }

        // Fall back: check cursor line for shell prompt.
        let cursorLine = lines.last?.trimmingCharacters(in: .whitespaces) ?? ""
        if isShellPromptLine(cursorLine) {
            isInteractivePrompt = false
            triggerAgentResumeIfNeeded()
        }
    }

    func isShellPromptLine(_ line: String) -> Bool {
        Self.shellPromptSuffixes.contains(where: line.hasSuffix)
            || Self.bareShellPrompts.contains(line)
    }

    /// Returns true if the line is an AI tool prompt: a single prompt character
    /// optionally followed by whitespace. Handles `>`, U+276F, U+203A and variations.
    func isAIPromptLine(_ line: String) -> Bool {
        guard let first = line.first, Self.aiPromptCharacters.contains(first) else {
            return false
        }
        // The rest (after the prompt character) must be empty or whitespace-only.
        let rest = line.dropFirst()
        return rest.allSatisfy(\.isWhitespace)
    }

    /// Schedules a debounced re-check of the screen buffer after PTY output settles.
    /// Solves the race where prompt characters arrive across multiple data chunks —
    /// the immediate `detectPromptFromScreenBuffer()` may fire before SwiftTerm has
    /// rendered the full prompt line, and no further data event triggers a re-check.
    func schedulePromptRecheck() {
        promptRecheckTask?.cancel()
        promptRecheckTask = Task { @MainActor [weak self] in
            do {
                try await self?.clock.sleep(for: AppConfig.UI.promptRecheckDelay)
            } catch is CancellationError {
                // CancellationError is expected — a newer output event supersedes this check.
                return
            } catch {
                // Non-critical: prompt recheck is a debounced UI hint; missing it is imperceptible.
                logger.warning("Prompt recheck delay failed: \(error.localizedDescription)")
                return
            }
            self?.detectPromptFromScreenBuffer()
        }
    }
}
