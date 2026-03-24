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
        default:
            return nil
        }
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
