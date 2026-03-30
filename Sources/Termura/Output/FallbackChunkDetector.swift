import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "FallbackChunkDetector")

/// Heuristic chunk detector for terminals without OSC 133 shell integration.
/// Detects chunk boundaries by matching shell prompt patterns ($, %, #, >) in ANSI-stripped output.
/// Used as a fallback when `hasReceivedShellEvents` is false.
actor FallbackChunkDetector {
    // MARK: - State

    private var pendingLines: [String] = []
    private var pendingLineCharCount: Int = 0
    private var pendingRawANSI: String = ""
    private var currentCommand: String = ""
    private var chunkStart: Date = .init()
    private let sessionID: SessionID
    private let clock: any AppClock

    // MARK: - Instance regex

    private let promptRegex: NSRegularExpression

    // MARK: - Pre-validated default regex

    /// The default prompt regex, validated once at process launch.
    /// Uses the AI tool prompt pattern from AppConfig (`^[>U+276F U+203A]\s*$`).
    /// Falls back to matching nothing if the pattern is somehow invalid.
    private static let defaultPromptRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: AppConfig.Output.aiToolPromptPattern)
        } catch {
            preconditionFailure(
                "Default AI prompt pattern is invalid — fix AppConfig.Output.aiToolPromptPattern: \(error)"
            )
        }
    }()

    // MARK: - Init

    /// Creates a detector using the default AI tool prompt pattern.
    /// - Parameters:
    ///   - sessionID: The owning session.
    ///   - clock: Clock for deterministic timestamps. Defaults to `LiveClock`.
    init(sessionID: SessionID, clock: any AppClock = LiveClock()) {
        self.sessionID = sessionID
        self.clock = clock
        promptRegex = Self.defaultPromptRegex
    }

    /// Creates a detector with a custom prompt pattern.
    /// - Parameters:
    ///   - sessionID: The owning session.
    ///   - pattern: Regex pattern used to detect prompt boundaries.
    ///   - clock: Clock for deterministic timestamps. Defaults to `LiveClock`.
    /// - Throws: If the pattern is not a valid regular expression.
    init(sessionID: SessionID, pattern: String, clock: any AppClock = LiveClock()) throws {
        self.sessionID = sessionID
        self.clock = clock
        promptRegex = try NSRegularExpression(pattern: pattern)
    }

    // MARK: - Public API

    /// Process a batch of ANSI-stripped terminal output.
    /// Returns completed chunks when prompt boundaries are detected.
    /// - Parameters:
    ///   - stripped: ANSI-stripped text for the batch
    ///   - raw: Original raw ANSI bytes for the same batch
    func processOutput(_ stripped: String, raw: String) -> [OutputChunk] {
        var emitted: [OutputChunk] = []

        // Accumulate raw for the current pending chunk, respecting cap
        let rawRemaining = AppConfig.Output.maxChunkOutputChars - pendingRawANSI.count
        if rawRemaining > 0 {
            pendingRawANSI += String(raw.prefix(rawRemaining))
        }

        let lines = stripped.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
            if promptRegex.firstMatch(in: trimmed, range: nsRange) != nil {
                // Prompt boundary detected — emit buffered output as a chunk
                if !pendingLines.isEmpty {
                    emitted.append(buildChunk())
                }
                currentCommand = extractCommand(from: trimmed)
                chunkStart = clock.now()
            } else {
                appendLine(line)
            }
        }

        return emitted
    }

    // MARK: - Private

    private func appendLine(_ line: String) {
        guard pendingLineCharCount < AppConfig.Output.maxChunkOutputChars else { return }
        pendingLines.append(line)
        pendingLineCharCount += line.count
    }

    private func buildChunk() -> OutputChunk {
        let lines = pendingLines
        let raw = pendingRawANSI
        let command = currentCommand
        let start = chunkStart

        pendingLines = []
        pendingLineCharCount = 0
        pendingRawANSI = ""

        let joined = lines.joined(separator: "\n")
        let classification = SemanticParser.classify(joined, command: command)
        let uiBlock = SemanticParser.buildUIContent(
            from: classification,
            displayLines: lines,
            exitCode: nil
        )

        return OutputChunk(
            sessionID: sessionID,
            commandText: command,
            outputLines: lines,
            rawANSI: raw,
            exitCode: nil,
            startedAt: start,
            finishedAt: clock.now(),
            contentType: classification.type,
            uiContent: uiBlock
        )
    }

    /// Extract the command portion from a prompt line, e.g. "~/path % ls -la" → "ls -la".
    private func extractCommand(from promptLine: String) -> String {
        let promptChars: [Character] = ["$", "%", "#", ">"]
        var lastIdx: String.Index?
        for char in promptChars {
            if let idx = promptLine.lastIndex(of: char) {
                if let current = lastIdx {
                    if idx > current { lastIdx = idx }
                } else {
                    lastIdx = idx
                }
            }
        }
        guard let idx = lastIdx else { return "" }
        let afterPrompt = promptLine[promptLine.index(after: idx)...]
        return afterPrompt.trimmingCharacters(in: .whitespaces)
    }
}
