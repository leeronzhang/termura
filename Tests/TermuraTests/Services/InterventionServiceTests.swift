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
