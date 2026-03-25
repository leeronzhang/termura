import Foundation

/// Protocol abstracting heuristic token counting per session.
protocol TokenCountingServiceProtocol: Actor {
    func accumulate(for sessionID: SessionID, text: String)
    func estimatedTokens(for sessionID: SessionID) -> Int
    func reset(for sessionID: SessionID)
}
