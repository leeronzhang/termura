@testable import Termura
import Testing

@Suite("InterventionService")
struct InterventionServiceTests {
    @Test("Detects rm -rf as critical risk")
    func detectRmRf() {
        let result = InterventionService.detectRisk(in: "Running: rm -rf /tmp/project", agentStatus: .toolRunning)
        #expect(result != nil)
        #expect(result?.severity == .critical)
    }

    @Test("Detects git push --force as critical")
    func detectForcePush() {
        let result = InterventionService.detectRisk(in: "git push --force origin main", agentStatus: .toolRunning)
        #expect(result != nil)
        #expect(result?.severity == .critical)
    }

    @Test("Detects git reset --hard as high risk")
    func detectHardReset() {
        let result = InterventionService.detectRisk(in: "git reset --hard HEAD~3", agentStatus: .toolRunning)
        #expect(result != nil)
        #expect(result?.severity == .high)
    }

    @Test("Safe commands return nil")
    func safeCommand() {
        let result = InterventionService.detectRisk(in: "git status\nls -la\ncat file.txt", agentStatus: .toolRunning)
        #expect(result == nil)
    }

    @Test("DROP TABLE detected as critical")
    func detectDropTable() {
        let result = InterventionService.detectRisk(in: "DROP TABLE users;", agentStatus: .toolRunning)
        #expect(result != nil)
        #expect(result?.severity == .critical)
    }
}

// MARK: - XCTest-based additional risk pattern tests

import XCTest

@MainActor
final class InterventionServiceXCTests: XCTestCase {
    override func setUp() async throws {}

    func testNoRiskForNormalOutput() {
        let result = InterventionService.detectRisk(in: "echo hello\nls -la\ngit status", agentStatus: .toolRunning)
        XCTAssertNil(result)
    }

    func testDetectsRiskInDestructiveCommand() throws {
        let result = InterventionService.detectRisk(in: "Running: rm -rf /home/user/project", agentStatus: .toolRunning)
        let alert = try XCTUnwrap(result)
        XCTAssertEqual(alert.severity, .critical)
    }

    func testDetectsRiskInSudoCommandWithDestructivePayload() throws {
        // The service detects the payload pattern, not "sudo" itself.
        // Verify that "sudo rm -rf" still triggers the rm -rf pattern.
        let result = InterventionService.detectRisk(in: "sudo rm -rf /var/data", agentStatus: .toolRunning)
        let alert = try XCTUnwrap(result)
        XCTAssertEqual(alert.severity, .critical)
    }
}
