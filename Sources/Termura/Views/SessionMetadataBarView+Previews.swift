import SwiftUI

#if DEBUG
#Preview("Session Info \u{2014} Active Agent") {
    SessionMetadataBarView(
        metadata: SessionMetadata(
            sessionID: SessionID(),
            estimatedTokenCount: 42_100,
            totalCharacterCount: 168_400,
            inputTokenCount: 28_000,
            outputTokenCount: 12_000,
            cachedTokenCount: 2_100,
            estimatedCostUSD: 0.087,
            sessionDuration: 263,
            commandCount: 14,
            workingDirectory: "~/Documents/Codes/termura",
            activeAgentCount: 1,
            currentAgentType: .claudeCode,
            currentAgentStatus: .toolRunning,
            currentAgentTask: "Writing #Preview macros for all leaf views",
            agentElapsedTime: 183,
            contextWindowLimit: 200_000,
            contextUsageFraction: 0.21,
            agentActiveFilePath: "Sources/Termura/Views/AgentIconView.swift"
        )
    )
    .frame(width: 240, height: 500)
}

#Preview("Session Info \u{2014} Terminal Only") {
    SessionMetadataBarView(
        metadata: SessionMetadata(
            sessionID: SessionID(),
            estimatedTokenCount: 0,
            totalCharacterCount: 0,
            inputTokenCount: 0,
            outputTokenCount: 0,
            cachedTokenCount: 0,
            estimatedCostUSD: 0,
            sessionDuration: 45,
            commandCount: 3,
            workingDirectory: "~/",
            activeAgentCount: 0,
            currentAgentType: nil,
            currentAgentStatus: nil,
            currentAgentTask: nil,
            agentElapsedTime: 0,
            contextWindowLimit: 0,
            contextUsageFraction: 0,
            agentActiveFilePath: nil
        )
    )
    .frame(width: 240, height: 300)
}
#endif
