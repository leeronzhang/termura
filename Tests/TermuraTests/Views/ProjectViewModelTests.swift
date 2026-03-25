import Combine
import XCTest
@testable import Termura

/// Tests for ProjectViewModel: file tree scanning, git status, and debounced refresh.
@MainActor
final class ProjectViewModelTests: XCTestCase {
    private var mockGit = MockGitService()
    private var router = CommandRouter()
    private var viewModel: ProjectViewModel?
    private var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        mockGit = MockGitService()
        router = CommandRouter()
        viewModel = ProjectViewModel(
            gitService: mockGit,
            projectRoot: "/tmp/test-project",
            commandRouter: router
        )
        cancellables.removeAll()
    }

    override func tearDown() async throws {
        viewModel?.tearDown()
        viewModel = nil
    }

    // MARK: - Initial state

    func testInitialStateIsEmpty() {
        guard let vm = viewModel else { return XCTFail("viewModel nil") }
        XCTAssertTrue(vm.tree.isEmpty)
        XCTAssertFalse(vm.gitResult.isGitRepo)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Git status propagation

    func testRefreshUpdatesGitResult() async throws {
        guard let vm = viewModel else { return XCTFail("viewModel nil") }
        let expected = GitStatusResult(
            branch: "main",
            files: [GitFileStatus(path: "file.swift", kind: .modified, isStaged: false)],
            isGitRepo: true,
            ahead: 0, behind: 0
        )
        await mockGit.setStubbed(expected)

        let expectation = XCTestExpectation(description: "git result updated")
        vm.$gitResult
            .dropFirst()
            .first(where: \.isGitRepo)
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        vm.refresh()
        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertTrue(vm.gitResult.isGitRepo)
        XCTAssertEqual(vm.gitResult.branch, "main")
    }

    // MARK: - Uncommitted changes signal

    func testRefreshUpdatesCommandRouterUncommittedChanges() async throws {
        guard let vm = viewModel else { return XCTFail("viewModel nil") }
        let status = GitStatusResult(
            branch: "main",
            files: [GitFileStatus(path: "file.swift", kind: .modified, isStaged: false)],
            isGitRepo: true,
            ahead: 0, behind: 0
        )
        await mockGit.setStubbed(status)

        let expectation = XCTestExpectation(description: "uncommitted changes set")
        router.$hasUncommittedChanges
            .dropFirst()
            .first(where: { $0 })
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        vm.refresh()
        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertTrue(router.hasUncommittedChanges)
    }

    // MARK: - Teardown cancels tasks

    func testTearDownCancelsRefreshTask() {
        guard let vm = viewModel else { return XCTFail("viewModel nil") }
        vm.refresh()
        vm.tearDown()
        // Should not crash or leak — verifies cancellation path.
    }
}
