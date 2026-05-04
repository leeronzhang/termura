import Foundation

extension ClaudeCodeTranscriptParser.ParseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "Transcript line is not valid JSON."
        case let .missingField(name):
            "Transcript line is missing required field \"\(name)\"."
        }
    }
}
