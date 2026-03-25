import Foundation
import Testing
@testable import Termura

/// Tests for the type-safe CommandRouter that replaced NotificationCenter communication.
@Suite("CommandRouter")
@MainActor
struct CommandRouterTests {
    // MARK: - Sheet toggles

    @Test("requestSearch sets showSearch to true")
    func requestSearch() {
        let router = CommandRouter()
        #expect(!router.showSearch)
        router.requestSearch()
        #expect(router.showSearch)
    }

    @Test("requestNotes sets showNotes to true")
    func requestNotes() {
        let router = CommandRouter()
        router.requestNotes()
        #expect(router.showNotes)
    }

    @Test("requestHarness sets showHarness to true")
    func requestHarness() {
        let router = CommandRouter()
        router.requestHarness()
        #expect(router.showHarness)
    }

    @Test("requestBranchMerge sets showBranchMerge to true")
    func requestBranchMerge() {
        let router = CommandRouter()
        router.requestBranchMerge()
        #expect(router.showBranchMerge)
    }

    // MARK: - Export with payload

    @Test("requestExport sets exportSessionID")
    func requestExport() {
        let router = CommandRouter()
        let id = SessionID()
        router.requestExport(sessionID: id)
        #expect(router.exportSessionID == id)
    }

    // MARK: - Split actions

    @Test("requestSplitVertical sets pendingSplitAction")
    func splitVertical() {
        let router = CommandRouter()
        router.requestSplitVertical()
        #expect(router.pendingSplitAction == .vertical)
    }

    @Test("requestSplitHorizontal sets pendingSplitAction")
    func splitHorizontal() {
        let router = CommandRouter()
        router.requestSplitHorizontal()
        #expect(router.pendingSplitAction == .horizontal)
    }

    @Test("requestCloseSplitPane sets pendingSplitAction")
    func closeSplitPane() {
        let router = CommandRouter()
        router.requestCloseSplitPane()
        #expect(router.pendingSplitAction == .closePane)
    }

    // MARK: - Toggle sidebar

    @Test("toggleSidebar flips showSidebar")
    func toggleSidebar() {
        let router = CommandRouter()
        #expect(router.showSidebar)
        router.toggleSidebar()
        #expect(!router.showSidebar)
        router.toggleSidebar()
        #expect(router.showSidebar)
    }

    // MARK: - Timeline / Agent Dashboard ticks

    @Test("toggleTimeline increments tick")
    func toggleTimeline() {
        let router = CommandRouter()
        let initial = router.toggleTimelineTick
        router.toggleTimeline()
        #expect(router.toggleTimelineTick == initial &+ 1)
    }

    @Test("toggleAgentDashboard increments tick")
    func toggleAgentDashboard() {
        let router = CommandRouter()
        let initial = router.toggleAgentDashboardTick
        router.toggleAgentDashboard()
        #expect(router.toggleAgentDashboardTick == initial &+ 1)
    }

    // MARK: - Chunk completed handler

    @Test("onChunkCompleted fires registered handlers")
    func chunkCompleted() {
        let router = CommandRouter()
        var receivedCommand: String?
        router.onChunkCompleted { chunk in
            receivedCommand = chunk.commandText
        }

        let chunk = OutputChunk(
            sessionID: SessionID(),
            commandText: "ls",
            outputLines: [],
            rawANSI: "",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date(),
            contentType: .text,
            uiContent: nil
        )
        router.notifyChunkCompleted(chunk)

        #expect(receivedCommand == "ls")
    }

    @Test("Multiple chunk handlers all receive events")
    func multipleChunkHandlers() {
        let router = CommandRouter()
        var count1 = 0
        var count2 = 0
        router.onChunkCompleted { _ in count1 += 1 }
        router.onChunkCompleted { _ in count2 += 1 }

        let chunk = OutputChunk(
            sessionID: SessionID(),
            commandText: "test",
            outputLines: [],
            rawANSI: "",
            exitCode: nil,
            startedAt: Date(),
            finishedAt: Date(),
            contentType: .text,
            uiContent: nil
        )
        router.notifyChunkCompleted(chunk)

        #expect(count1 == 1)
        #expect(count2 == 1)
    }

    // MARK: - Data signals

    @Test("hasUncommittedChanges defaults to false")
    func uncommittedChangesDefault() {
        let router = CommandRouter()
        #expect(!router.hasUncommittedChanges)
    }
}
