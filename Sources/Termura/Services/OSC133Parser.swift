import Foundation

/// Stateless parser for OSC 133 shell integration sequences.
/// Input: the payload bytes after "133;" in the OSC escape.
/// Returns nil for unknown or malformed payloads.
enum OSC133Parser {
    // MARK: - Public API

    static func parse(_ payload: ArraySlice<UInt8>) -> ShellIntegrationEvent? {
        guard let first = payload.first else { return nil }
        switch first {
        case UInt8(ascii: "A"):
            return .promptStarted
        case UInt8(ascii: "B"):
            return .commandStarted
        case UInt8(ascii: "C"):
            return .executionStarted
        case UInt8(ascii: "D"):
            return parseFinished(payload)
        case UInt8(ascii: "X"):
            return parseMetadata(payload)
        default:
            return nil
        }
    }

    /// Parses `X[;key=value[;key=value]...]` payloads. Termura private extension —
    /// shells without OSC 133 X support simply produce no event. Empty payload
    /// (just "X") yields an empty-metadata event so callers can still detect the
    /// boundary marker if they need it.
    private static func parseMetadata(_ payload: ArraySlice<UInt8>) -> ShellIntegrationEvent? {
        let afterX = payload.dropFirst()
        guard let body = String(bytes: afterX, encoding: .utf8) else { return nil }
        var trimmed = body
        if trimmed.hasPrefix(";") {
            trimmed = String(trimmed.dropFirst())
        }
        if trimmed.isEmpty {
            return .commandMetadata([:])
        }
        var pairs: [String: String] = [:]
        for segment in trimmed.split(separator: ";") {
            guard let separatorIndex = segment.firstIndex(of: "=") else { continue }
            let key = String(segment[..<separatorIndex])
            let value = String(segment[segment.index(after: separatorIndex)...])
            guard !key.isEmpty else { continue }
            pairs[key] = value
        }
        return .commandMetadata(pairs)
    }

    // MARK: - Private helpers

    private static func parseFinished(_ payload: ArraySlice<UInt8>) -> ShellIntegrationEvent {
        // Payload is "D" or "D;<exitCode>"
        let afterD = payload.dropFirst()
        guard afterD.first == UInt8(ascii: ";") else {
            return .executionFinished(exitCode: nil)
        }
        let codeSlice = afterD.dropFirst()
        let exitCode = parseIntFromBytes(codeSlice)
        return .executionFinished(exitCode: exitCode)
    }

    private static func parseIntFromBytes(_ slice: ArraySlice<UInt8>) -> Int? {
        guard !slice.isEmpty else { return nil }
        var result = 0
        var foundDigit = false
        for byte in slice {
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { break }
            result = result * 10 + Int(byte - UInt8(ascii: "0"))
            foundDigit = true
        }
        return foundDigit ? result : nil
    }
}
