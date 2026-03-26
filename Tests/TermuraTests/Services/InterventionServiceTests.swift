import Testing
@testable import Termura

@Suite("InterventionService")
struct InterventionServiceTests {

    private func makeService() -> InterventionService {
        InterventionService()
    }

    @Test("Detects rm -rf as critical risk")
    func detectRmRf() async {
        let service = makeService()
        let result = await service.detectRisk(in: "Running: rm -rf /tmp/project")
        #expect(result != nil)
        #expect(result?.severity == .critical)
    }

    @Test("Detects git push --force as critical")
    func detectForcePush() async {
        let service = makeService()
        let result = await service.detectRisk(in: "git push --force origin main")
        #expect(result != nil)
        #expect(result?.severity == .critical)
    }

    @Test("Detects git reset --hard as high risk")
    func detectHardReset() async {
        let service = makeService()
        let result = await service.detectRisk(in: "git reset --hard HEAD~3")
        #expect(result != nil)
        #expect(result?.severity == .high)
    }

    @Test("Safe commands return nil")
    func safeCommand() async {
        let service = makeService()
        let result = await service.detectRisk(in: "git status\nls -la\ncat file.txt")
        #expect(result == nil)
    }

    @Test("DROP TABLE detected as critical")
    func detectDropTable() async {
        let service = makeService()
        let result = await service.detectRisk(in: "DROP TABLE users;")
        #expect(result != nil)
        #expect(result?.severity == .critical)
    }
}

// MARK: - XCTest-based additional risk pattern tests

import XCTest

@MainActor
final class InterventionServiceXCTests: XCTestCase {
    override func setUp() async throws {}

    func testNoRiskForNormalOutput() async {
        let service = InterventionService()
        let result = await service.detectRisk(in: "echo hello\nls -la\ngit status")
        XCTAssertNil(result)
    }

    func testDetectsRiskInDestructiveCommand() async throws {
        let service = InterventionService()
        let result = await service.detectRisk(in: "Running: rm -rf /home/user/project")
        let alert = try XCTUnwrap(result)
        XCTAssertEqual(alert.severity, .critical)
    }

    func testDetectsRiskInSudoCommandWithDestructivePayload() async throws {
        // The service detects the payload pattern, not "sudo" itself.
        // Verify that "sudo rm -rf" still triggers the rm -rf pattern.
        let service = InterventionService()
        let result = await service.detectRisk(in: "sudo rm -rf /var/data")
        let alert = try XCTUnwrap(result)
        XCTAssertEqual(alert.severity, .critical)
    }
}
