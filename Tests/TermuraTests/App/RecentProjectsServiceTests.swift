import Foundation
import XCTest
@testable import Termura

final class RecentProjectsServiceTests: XCTestCase {
    private var tempDir: URL!
    private var fileURL: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("recent-projects.json")
    }

    override func tearDown() async throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeService() -> RecentProjectsService {
        RecentProjectsService(fileURL: fileURL)
    }

    // MARK: - Fetch

    func testFetchRecentReturnsEmptyWhenNoFile() {
        let service = makeService()
        let result = service.fetchRecent()
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Add

    func testAddRecentCreatesEntry() {
        let service = makeService()
        let url = URL(fileURLWithPath: "/tmp/project-a")
        service.addRecent(url)
        let list = service.fetchRecent()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.path, "/tmp/project-a")
    }

    func testAddRecentDeduplicatesSamePath() {
        let service = makeService()
        let url = URL(fileURLWithPath: "/tmp/project-a")
        service.addRecent(url)
        service.addRecent(url)
        let list = service.fetchRecent()
        XCTAssertEqual(list.count, 1)
    }

    func testAddRecentCapsAtMaxCount() {
        let service = makeService()
        let max = AppConfig.RecentProjects.maxCount
        for idx in 0 ..< max + 5 {
            service.addRecent(URL(fileURLWithPath: "/tmp/proj-\(idx)"))
        }
        let list = service.fetchRecent()
        XCTAssertEqual(list.count, max)
    }

    // MARK: - Remove

    func testRemoveRecentRemovesEntry() {
        let service = makeService()
        let url = URL(fileURLWithPath: "/tmp/project-b")
        service.addRecent(url)
        XCTAssertEqual(service.fetchRecent().count, 1)
        service.removeRecent(url)
        XCTAssertTrue(service.fetchRecent().isEmpty)
    }

    // MARK: - Last opened

    func testLastOpenedReturnsNilWhenEmpty() {
        let service = makeService()
        XCTAssertNil(service.lastOpened())
    }

    func testLastOpenedReturnsNilWhenDirectoryNotOnDisk() {
        let service = makeService()
        // Add a path that does not exist on disk.
        let fake = URL(fileURLWithPath: "/nonexistent-dir-\(UUID().uuidString)")
        service.addRecent(fake)
        XCTAssertNil(service.lastOpened())
    }

    // MARK: - JSON decode

    func testFetchRecentDecodesValidJSON() {
        let service = makeService()
        // Write a hand-crafted JSON array.
        let json = """
        [{"path":"/tmp/decoded","lastOpenedAt":0,"displayName":"decoded"}]
        """
        guard let data = json.data(using: .utf8) else {
            XCTFail("Failed to create JSON data")
            return
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            XCTFail("Failed to write test JSON: \(error)")
            return
        }
        let list = service.fetchRecent()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.path, "/tmp/decoded")
    }
}
