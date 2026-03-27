import SwiftUI

// MARK: - Helpers

extension SessionMetadataBarView {
    func turnLabel(_ turn: TimelineTurn) -> String {
        if !turn.command.isEmpty { return turn.command }
        guard let tl = timeline else { return "Turn" }
        let idx = tl.turns.firstIndex(where: { $0.id == turn.id }).map { $0 + 1 } ?? 0
        return "Turn \(idx)"
    }

    func agentStatusColor(_ status: AgentStatus) -> Color {
        switch status {
        case .idle: .secondary
        case .thinking: .blue
        case .toolRunning: .orange
        case .waitingInput: .yellow
        case .error: .red
        case .completed: .green
        }
    }

    func exitCodeColor(_ code: Int?) -> Color {
        guard let code else { return .secondary }
        return code == 0 ? .green : .red
    }

    func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
