import Foundation
import XCTest
@testable import Termura

// MARK: - Inline mock for RuleFileRepository

private actor MockRuleFileRepo: RuleFileRepositoryProtocol {
    var savedRecords: [RuleFileRecord] = []

    func save(_ record: RuleFileRecord) async throws {
        savedRecords.append(record)
    }

    func fetchHistory(for filePath: String) async throws -> [RuleFileRecord] {
        savedRecords.filter { $0.filePath == filePath }
            .sorted { $0.version > $1.version }
    }

    func fetchLatest(for filePath: String) async throws -> RuleFileRecord? {
        savedRecords.filter { $0.filePath == filePath }
            .max(by: { $0.version < $1.version })
    }

    func fetchAll() async throws -> [RuleFileRecord] {
        var latest: [String: RuleFileRecord] = [:]
        for record in savedRecords {
            if latest[record.filePath] == nil || record.version > (latest[record.filePath]?.version ?? 0) {
                latest[record.filePath] = record
            }
        }
        return Array(latest.values)
    }
}

@MainActor
final class HarnessViewModelTests: XCTestCase {
    private var repo: MockRuleFileRepo!
    private var tempDir: String!

    override func setUp() async throws {
        repo = MockRuleFileRepo()
        tempDir = NSTemporaryDirectory() + "harness-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    // MARK: - Helpers

    private func makeViewModel() -> HarnessViewModel {
        HarnessViewModel(repository: repo, projectRoot: tempDir)
    }

    private func createRuleFile(name: String, content: String) throws {
        let path = (tempDir as NSString).appendingPathComponent(name)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Load

    func testLoadRuleFilesFindsFiles() async throws {
        try createRuleFile(name: "CLAUDE.md", content: "# Rules\n\nSome content.")
        let vm = makeViewModel()
        await vm.loadRuleFiles()
        XCTAssertFalse(vm.ruleFiles.isEmpty)
    }

    func testLoadRuleFilesEmptyDirProducesNoFiles() async {
        let vm = makeViewModel()
        await vm.loadRuleFiles()
        XCTAssertTrue(vm.ruleFiles.isEmpty)
    }

    // MARK: - Select

    func testSelectFilePopulatesSections() async throws {
        let content = "# Title\n\n## Section 1\n\nBody 1\n\n## Section 2\n\nBody 2"
        try createRuleFile(name: "CLAUDE.md", content: content)
        let path = (tempDir as NSString).appendingPathComponent("CLAUDE.md")

        let vm = makeViewModel()
        await vm.selectFile(path)
        XCTAssertEqual(vm.selectedFilePath, path)
        XCTAssertFalse(vm.selectedSections.isEmpty)
    }

    // MARK: - Corruption scan

    func testRunCorruptionScanSetsIsScanning() async throws {
        let content = "# Rules\n\n## Section\n\nClean content."
        try createRuleFile(name: "CLAUDE.md", content: content)
        let path = (tempDir as NSString).appendingPathComponent("CLAUDE.md")

        let vm = makeViewModel()
        vm.selectedFilePath = path
        await vm.runCorruptionScan()
        // After scan completes, isScanning should be false (defer resets it).
        XCTAssertFalse(vm.isScanning)
    }

    func testRunCorruptionScanWithoutSelectedFileIsNoop() async {
        let vm = makeViewModel()
        await vm.runCorruptionScan()
        XCTAssertTrue(vm.corruptionResults.isEmpty)
    }

    // MARK: - Snapshot versioning

    func testLoadSnapshotsNewFile() async throws {
        try createRuleFile(name: "CLAUDE.md", content: "# Rules\n\nContent v1.")
        let vm = makeViewModel()
        await vm.loadRuleFiles()

        // The first load should save a version 1 snapshot.
        let saved = await repo.savedRecords
        XCTAssertFalse(saved.isEmpty)
        XCTAssertEqual(saved.first?.version, 1)
    }

    func testLoadSnapshotsSameContentSkipsVersion() async throws {
        try createRuleFile(name: "CLAUDE.md", content: "# Rules\n\nSame content.")
        let vm = makeViewModel()
        await vm.loadRuleFiles()
        let countAfterFirst = await repo.savedRecords.count

        // Load again with same content — should NOT create a new version.
        await vm.loadRuleFiles()
        let countAfterSecond = await repo.savedRecords.count
        XCTAssertEqual(countAfterFirst, countAfterSecond)
    }
}
