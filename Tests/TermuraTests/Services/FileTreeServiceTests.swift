import Testing
@testable import Termura

@Suite("FileTreeService annotation")
struct FileTreeServiceTests {

    private func makeNode(
        name: String,
        path: String,
        isDir: Bool = false,
        children: [FileTreeNode]? = nil
    ) -> FileTreeNode {
        FileTreeNode(
            name: name,
            relativePath: path,
            isDirectory: isDir,
            children: children
        )
    }

    private func makeGitResult(files: [GitFileStatus]) -> GitStatusResult {
        GitStatusResult(branch: "main", files: files, isGitRepo: true, ahead: 0, behind: 0)
    }

    // MARK: - Annotate tests

    @Test("Annotates modified file with git status")
    func annotateModifiedFile() async {
        let service = FileTreeService()
        let tree = [makeNode(name: "App.swift", path: "Sources/App.swift")]
        let git = makeGitResult(files: [
            GitFileStatus(path: "Sources/App.swift", kind: .modified, isStaged: false)
        ])

        let result = await service.annotate(tree: tree, with: git)

        #expect(result.count == 1)
        #expect(result[0].gitStatus == .modified)
        #expect(result[0].isGitStaged == false)
    }

    @Test("Annotates staged added file")
    func annotateStagedFile() async {
        let service = FileTreeService()
        let tree = [makeNode(name: "New.swift", path: "New.swift")]
        let git = makeGitResult(files: [
            GitFileStatus(path: "New.swift", kind: .added, isStaged: true)
        ])

        let result = await service.annotate(tree: tree, with: git)

        #expect(result[0].gitStatus == .added)
        #expect(result[0].isGitStaged == true)
    }

    @Test("File without git changes has nil status")
    func cleanFileHasNilStatus() async {
        let service = FileTreeService()
        let tree = [makeNode(name: "Clean.swift", path: "Clean.swift")]
        let git = makeGitResult(files: [
            GitFileStatus(path: "Other.swift", kind: .modified, isStaged: false)
        ])

        let result = await service.annotate(tree: tree, with: git)

        #expect(result[0].gitStatus == nil)
        #expect(result[0].isGitStaged == false)
    }

    @Test("Directory inherits status when child has changes")
    func directoryPropagation() async {
        let service = FileTreeService()
        let tree = [
            makeNode(
                name: "Sources",
                path: "Sources",
                isDir: true,
                children: [
                    makeNode(name: "App.swift", path: "Sources/App.swift"),
                    makeNode(name: "Clean.swift", path: "Sources/Clean.swift")
                ]
            )
        ]
        let git = makeGitResult(files: [
            GitFileStatus(path: "Sources/App.swift", kind: .modified, isStaged: false)
        ])

        let result = await service.annotate(tree: tree, with: git)

        // Directory should get a status because it contains a changed file
        #expect(result[0].gitStatus == .modified)
        // Child file should have the actual status
        #expect(result[0].children?[0].gitStatus == .modified)
        // Clean file should be nil
        #expect(result[0].children?[1].gitStatus == nil)
    }

    @Test("Directory with no changed children has nil status")
    func cleanDirectory() async {
        let service = FileTreeService()
        let tree = [
            makeNode(
                name: "Tests",
                path: "Tests",
                isDir: true,
                children: [
                    makeNode(name: "Test.swift", path: "Tests/Test.swift")
                ]
            )
        ]
        let git = makeGitResult(files: [
            GitFileStatus(path: "Sources/Other.swift", kind: .modified, isStaged: false)
        ])

        let result = await service.annotate(tree: tree, with: git)

        #expect(result[0].gitStatus == nil)
    }

    @Test("Non-git repo returns tree unchanged")
    func nonGitRepo() async {
        let service = FileTreeService()
        let tree = [makeNode(name: "file.txt", path: "file.txt")]
        let git = GitStatusResult.notARepo

        let result = await service.annotate(tree: tree, with: git)

        #expect(result[0].gitStatus == nil)
    }

    @Test("Multiple file statuses annotated correctly")
    func multipleFiles() async {
        let service = FileTreeService()
        let tree = [
            makeNode(name: "a.swift", path: "a.swift"),
            makeNode(name: "b.swift", path: "b.swift"),
            makeNode(name: "c.swift", path: "c.swift")
        ]
        let git = makeGitResult(files: [
            GitFileStatus(path: "a.swift", kind: .modified, isStaged: true),
            GitFileStatus(path: "b.swift", kind: .deleted, isStaged: false),
            GitFileStatus(path: "c.swift", kind: .untracked, isStaged: false)
        ])

        let result = await service.annotate(tree: tree, with: git)

        #expect(result[0].gitStatus == .modified)
        #expect(result[0].isGitStaged == true)
        #expect(result[1].gitStatus == .deleted)
        #expect(result[2].gitStatus == .untracked)
    }
}
