import Testing
@testable import Termura

@Suite("GitService porcelain parser")
struct GitServiceTests {

    @Test("Parses branch name from porcelain header")
    func parseBranch() {
        let output = "## main...origin/main\n"
        let result = GitService.parse(porcelain: output)
        #expect(result.isGitRepo)
        #expect(result.branch == "main")
        #expect(result.files.isEmpty)
    }

    @Test("Parses branch without tracking info")
    func parseBranchNoTracking() {
        let output = "## feature/git-sidebar\n"
        let result = GitService.parse(porcelain: output)
        #expect(result.branch == "feature/git-sidebar")
    }

    @Test("Parses modified file in work tree")
    func parseModified() {
        let output = """
        ## main
         M Sources/File.swift
        """
        let result = GitService.parse(porcelain: output)
        #expect(result.files.count == 1)
        #expect(result.files[0].kind == .modified)
        #expect(result.files[0].isStaged == false)
        #expect(result.files[0].path == "Sources/File.swift")
    }

    @Test("Parses staged file")
    func parseStaged() {
        let output = """
        ## main
        M  Sources/File.swift
        """
        let result = GitService.parse(porcelain: output)
        #expect(result.files.count == 1)
        #expect(result.files[0].kind == .modified)
        #expect(result.files[0].isStaged == true)
    }

    @Test("Parses file modified in both index and work tree")
    func parseBothModified() {
        let output = """
        ## main
        MM Sources/File.swift
        """
        let result = GitService.parse(porcelain: output)
        #expect(result.files.count == 2)
        #expect(result.files[0].isStaged == true)
        #expect(result.files[1].isStaged == false)
    }

    @Test("Parses untracked files")
    func parseUntracked() {
        let output = """
        ## main
        ?? NewFile.swift
        """
        let result = GitService.parse(porcelain: output)
        #expect(result.files.count == 1)
        #expect(result.files[0].kind == .untracked)
        #expect(result.files[0].isStaged == false)
    }

    @Test("Parses added file")
    func parseAdded() {
        let output = """
        ## main
        A  Sources/New.swift
        """
        let result = GitService.parse(porcelain: output)
        #expect(result.files.count == 1)
        #expect(result.files[0].kind == .added)
        #expect(result.files[0].isStaged == true)
    }

    @Test("Parses deleted file")
    func parseDeleted() {
        let output = """
        ## main
        D  Sources/Old.swift
        """
        let result = GitService.parse(porcelain: output)
        #expect(result.files.count == 1)
        #expect(result.files[0].kind == .deleted)
        #expect(result.files[0].isStaged == true)
    }

    @Test("Empty output returns not-a-repo")
    func parseEmpty() {
        let result = GitService.parse(porcelain: "")
        #expect(!result.isGitRepo)
    }

    @Test("Clean repo — header only, no files")
    func parseClean() {
        let output = "## main...origin/main\n"
        let result = GitService.parse(porcelain: output)
        #expect(result.isGitRepo)
        #expect(result.files.isEmpty)
    }

    @Test("Multiple files of different types")
    func parseMixed() {
        let output = """
        ## develop...origin/develop
        M  Sources/A.swift
         M Sources/B.swift
        A  Sources/C.swift
        D  Sources/D.swift
        ?? Sources/E.swift
        """
        let result = GitService.parse(porcelain: output)
        #expect(result.branch == "develop")
        #expect(result.files.count == 5)
    }
}
