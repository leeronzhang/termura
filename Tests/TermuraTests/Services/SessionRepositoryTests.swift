@testable import Termura
import XCTest

final class SessionRepositoryTests: XCTestCase {
    private var dbService: MockDatabaseService!
    private var repository: SessionRepository!

    override func setUp() async throws {
        dbService = try MockDatabaseService()
        repository = SessionRepository(db: dbService)
    }

    func testSaveAndFetchAll() async throws {
        let record = SessionRecord(title: "Test Session")
        try await repository.save(record)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Test Session")
    }

    func testDeleteRemovesRecord() async throws {
        let record = SessionRecord(title: "To Delete")
        try await repository.save(record)
        try await repository.delete(id: record.id)

        let all = try await repository.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    func testArchiveHidesFromFetchAll() async throws {
        let record = SessionRecord(title: "Archive Me")
        try await repository.save(record)
        try await repository.archive(id: record.id)

        let all = try await repository.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    func testSearchFindsMatchingTitle() async throws {
        let record = SessionRecord(title: "UniqueSearchTitle")
        try await repository.save(record)

        let results = try await repository.search(query: "UniqueSearch")
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.title, "UniqueSearchTitle")
    }

    func testSearchReturnsEmptyForShortQuery() async throws {
        let record = SessionRecord(title: "Something")
        try await repository.save(record)

        let results = try await repository.search(query: "S")
        XCTAssertTrue(results.isEmpty)
    }

    func testReorderUpdatesOrderIndex() async throws {
        let first = SessionRecord(title: "First", orderIndex: 0)
        let second = SessionRecord(title: "Second", orderIndex: 1)
        try await repository.save(first)
        try await repository.save(second)

        try await repository.reorder(ids: [second.id, first.id])

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.first?.title, "Second")
    }

    func testSetColorLabel() async throws {
        let record = SessionRecord(title: "ColorTest", colorLabel: .none)
        try await repository.save(record)

        try await repository.setColorLabel(id: record.id, label: .blue)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.first?.colorLabel, .blue)
    }

    func testSetPinned() async throws {
        let record = SessionRecord(title: "PinTest", isPinned: false)
        try await repository.save(record)

        try await repository.setPinned(id: record.id, pinned: true)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.first?.isPinned, true)
    }

    // MARK: - FTS Edge Cases

    func testSearchWithQuotesInQuery() async throws {
        let record = SessionRecord(title: "Quote \"test\" session")
        try await repository.save(record)
        let results = try await repository.search(query: "\"test\"")
        // Should not crash; may or may not find the result depending on FTS escaping
        XCTAssertNotNil(results)
    }

    func testSearchWithSpecialFTSCharacters() async throws {
        let record = SessionRecord(title: "Special chars session")
        try await repository.save(record)
        // FTS operators should be safely escaped, not crash
        let results = try await repository.search(query: "chars*()")
        XCTAssertNotNil(results)
    }

    func testSearchEmptyResults() async throws {
        let record = SessionRecord(title: "Something")
        try await repository.save(record)
        let results = try await repository.search(query: "nonexistent")
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchLongQuery() async throws {
        let record = SessionRecord(title: "LongQueryTarget")
        try await repository.save(record)
        let longQuery = String(repeating: "a", count: 500)
        let results = try await repository.search(query: longQuery)
        // Should not crash, returns empty since nothing matches
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchDoesNotReturnArchivedSessions() async throws {
        let record = SessionRecord(title: "ArchivedSearchTarget")
        try await repository.save(record)
        try await repository.archive(id: record.id)
        let results = try await repository.search(query: "ArchivedSearch")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Session lifecycle (markEnded / markReopened / updateSummary)

    func testMarkEndedSetsEndedAt() async throws {
        let record = SessionRecord(title: "MarkEnded")
        try await repository.save(record)

        let stamp = Date()
        try await repository.markEnded(id: record.id, at: stamp)

        let all = try await repository.fetchAll()
        XCTAssertNotNil(all.first?.endedAt)
        if let endedAt = all.first?.endedAt {
            XCTAssertLessThanOrEqual(
                abs(endedAt.timeIntervalSince(stamp)), 1.0,
                "endedAt must be within 1s of the provided stamp"
            )
        }
    }

    func testMarkReopenedClearsEndedAt() async throws {
        let record = SessionRecord(title: "MarkReopened")
        try await repository.save(record)

        try await repository.markEnded(id: record.id, at: Date())
        try await repository.markReopened(id: record.id)

        let all = try await repository.fetchAll()
        XCTAssertNil(all.first?.endedAt)
    }

    func testMarkEndedReopenedIsIdempotent() async throws {
        let record = SessionRecord(title: "LifecycleIdempotent")
        try await repository.save(record)

        try await repository.markEnded(id: record.id, at: Date())
        try await repository.markEnded(id: record.id, at: Date())
        try await repository.markReopened(id: record.id)

        let all = try await repository.fetchAll()
        XCTAssertNil(all.first?.endedAt)
    }

    func testUpdateSummaryTruncatesAtMaxLength() async throws {
        let record = SessionRecord(title: "SummaryTruncate")
        try await repository.save(record)

        let oversized = String(repeating: "s", count: AppConfig.SessionTree.summaryMaxLength + 50)
        try await repository.updateSummary(record.id, summary: oversized)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.first?.summary?.count, AppConfig.SessionTree.summaryMaxLength)
    }

    func testUpdateSummaryBelowLimitPassesThrough() async throws {
        let record = SessionRecord(title: "SummaryShort")
        try await repository.save(record)

        try await repository.updateSummary(record.id, summary: "short")

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.first?.summary, "short")
    }

    // MARK: - Session tree (fetchChildren, fetchAncestors, createBranch depth)

    func testFetchChildrenReturnsOnlyDirectChildren() async throws {
        let parent = SessionRecord(title: "Parent")
        let child = SessionRecord(title: "Child", parentID: parent.id, branchType: .experiment)
        let grandchild = SessionRecord(title: "Grandchild", parentID: child.id, branchType: .experiment)
        try await repository.save(parent)
        try await repository.save(child)
        try await repository.save(grandchild)

        let children = try await repository.fetchChildren(of: parent.id)
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children.first?.id, child.id)
    }

    func testFetchChildrenEmptyForLeaf() async throws {
        let leaf = SessionRecord(title: "Leaf")
        try await repository.save(leaf)

        let children = try await repository.fetchChildren(of: leaf.id)
        XCTAssertTrue(children.isEmpty)
    }

    func testFetchAncestorsReturnsChainInOrder() async throws {
        let grandparent = SessionRecord(title: "Grandparent")
        let parent = SessionRecord(title: "Parent", parentID: grandparent.id, branchType: .main)
        let child = SessionRecord(title: "Child", parentID: parent.id, branchType: .experiment)
        try await repository.save(grandparent)
        try await repository.save(parent)
        try await repository.save(child)

        let ancestors = try await repository.fetchAncestors(of: child.id)
        XCTAssertEqual(ancestors.count, 2)
        // ORDER BY created_at ASC: grandparent first, then parent.
        XCTAssertEqual(ancestors.first?.id, grandparent.id)
        XCTAssertEqual(ancestors.last?.id, parent.id)
    }

    func testFetchAncestorsEmptyForRoot() async throws {
        let root = SessionRecord(title: "Root")
        try await repository.save(root)

        let ancestors = try await repository.fetchAncestors(of: root.id)
        XCTAssertTrue(ancestors.isEmpty)
    }

    func testCreateBranchThrowsAtMaxDepth() async throws {
        // Build a chain where the last node has exactly maxDepth ancestors.
        // root → depth1 → ... → depth(maxDepth) has maxDepth ancestors of depth(maxDepth).
        // Calling createBranch from depth(maxDepth) checks fetchAncestors count >= maxDepth.
        var currentID = SessionID()
        let root = SessionRecord(id: currentID, title: "Root")
        try await repository.save(root)

        for depth in 1 ... AppConfig.SessionTree.maxDepth {
            let branch = SessionRecord(
                title: "Depth \(depth)",
                parentID: currentID,
                branchType: .experiment
            )
            try await repository.save(branch)
            currentID = branch.id
        }

        // At this point currentID has exactly maxDepth - 1 ancestors (depth 0..maxDepth-1).
        // Creating one more branch from currentID would require ancestors.count >= maxDepth.
        var caughtError: Error?
        do {
            _ = try await repository.createBranch(
                from: currentID, type: .experiment, title: "Too Deep"
            )
            XCTFail("Expected branchDepthExceeded error")
        } catch {
            caughtError = error
        }

        guard let repoError = caughtError as? RepositoryError else {
            XCTFail("Expected RepositoryError, got: \(String(describing: caughtError))")
            return
        }
        if case let .branchDepthExceeded(depth) = repoError {
            XCTAssertGreaterThanOrEqual(depth, AppConfig.SessionTree.maxDepth)
        } else {
            XCTFail("Expected branchDepthExceeded, got: \(repoError)")
        }
    }

    // MARK: - reorder batch boundary

    func testReorderEmptyListIsNoOp() async throws {
        let r1 = SessionRecord(title: "NoOp1", orderIndex: 0)
        let r2 = SessionRecord(title: "NoOp2", orderIndex: 1)
        try await repository.save(r1)
        try await repository.save(r2)

        try await repository.reorder(ids: [])

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 2, "Empty reorder must not remove any records")
    }

    func testReorderSingleItem() async throws {
        let record = SessionRecord(title: "Alone", orderIndex: 0)
        try await repository.save(record)

        try await repository.reorder(ids: [record.id])

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, record.id)
    }

    func testReorderExactlyOneBatch() async throws {
        let batchSize = AppConfig.Persistence.reorderBatchSize
        var sessions: [SessionRecord] = []
        for i in 0 ..< batchSize {
            let s = SessionRecord(title: "Batch\(i)", orderIndex: i)
            sessions.append(s)
            try await repository.save(s)
        }

        let reversedIDs = sessions.reversed().map(\.id)
        try await repository.reorder(ids: reversedIDs)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, batchSize)
        XCTAssertEqual(all.first?.id, sessions.last?.id,
                       "After reversal, original last item must be first")
        XCTAssertEqual(all.last?.id, sessions.first?.id,
                       "After reversal, original first item must be last")
    }

    func testReorderOneBatchPlusOne() async throws {
        let count = AppConfig.Persistence.reorderBatchSize + 1
        var sessions: [SessionRecord] = []
        for i in 0 ..< count {
            let s = SessionRecord(title: "TwoBatch\(i)", orderIndex: i)
            sessions.append(s)
            try await repository.save(s)
        }

        let reversedIDs = sessions.reversed().map(\.id)
        try await repository.reorder(ids: reversedIDs)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, count)
        XCTAssertEqual(all.first?.id, sessions.last?.id,
                       "Two-batch reorder: original last item must be first")
        XCTAssertEqual(all.last?.id, sessions.first?.id,
                       "Two-batch reorder: original first item must be last")
    }
}
