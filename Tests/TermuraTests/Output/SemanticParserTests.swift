import Testing
@testable import Termura

@Suite("SemanticParser")
struct SemanticParserTests {

    @Test("Classifies diff output")
    func classifyDiff() {
        let text = """
            diff --git a/file.swift b/file.swift
            --- a/file.swift
            +++ b/file.swift
            @@ -1,3 +1,4 @@
            +import Foundation
            """
        let result = SemanticParser.classify(text)
        #expect(result.type == .diff)
        #expect(result.filePath == "file.swift")
    }

    @Test("Classifies error output")
    func classifyError() {
        let text = "error: cannot find type 'Foo' in scope"
        let result = SemanticParser.classify(text)
        #expect(result.type == .error)
    }

    @Test("Classifies code blocks")
    func classifyCode() {
        let text = "```swift\nlet x = 42\n```"
        let result = SemanticParser.classify(text)
        #expect(result.type == .code)
        #expect(result.language == "swift")
    }

    @Test("Classifies tool calls")
    func classifyToolCall() {
        let text = "⏺ Writing to Sources/App/Config.swift"
        let result = SemanticParser.classify(text)
        #expect(result.type == .toolCall)
    }

    @Test("Defaults to commandOutput")
    func classifyDefault() {
        let text = "total 42\ndrwxr-xr-x  5 user  staff  160 Mar 21 10:00 ."
        let result = SemanticParser.classify(text)
        #expect(result.type == .commandOutput)
    }

    @Test("Builds UIContentBlock from classification")
    func buildUIContent() {
        let classification = SemanticParser.Classification(type: .error, language: nil, filePath: nil)
        let block = SemanticParser.buildUIContent(
            from: classification,
            displayLines: ["error: test failed"],
            exitCode: 1
        )
        #expect(block.type == .error)
        #expect(block.exitCode == 1)
        #expect(block.displayLines.count == 1)
    }

    // MARK: - Classification priority

    @Test("Diff takes priority over error indicators")
    func diffPriorityOverError() {
        let text = """
            error: something wrong
            diff --git a/file.swift b/file.swift
            --- a/file.swift
            +++ b/file.swift
            """
        let result = SemanticParser.classify(text)
        #expect(result.type == .diff)
    }

    @Test("Error takes priority over code blocks")
    func errorPriorityOverCode() {
        let text = "error: compilation failed\n```swift\nlet x = 1\n```"
        let result = SemanticParser.classify(text)
        #expect(result.type == .error)
    }

    // MARK: - Edge cases

    @Test("Code block with no language defaults to text")
    func codeBlockNoLanguage() {
        let text = "```\nsome code\n```"
        let result = SemanticParser.classify(text)
        #expect(result.type == .code)
        #expect(result.language == "text")
    }

    @Test("Detects Tool: prefix as tool call")
    func toolCallDetectsToolColon() {
        let text = "Tool: Read /path/to/file"
        let result = SemanticParser.classify(text)
        #expect(result.type == .toolCall)
    }

    @Test("Error indicator past prefix scan length is not detected")
    func largeTextOnlyScansPrefix() {
        let padding = String(repeating: "a", count: AppConfig.Output.errorDetectionPrefixLength + 100)
        let text = padding + "\nerror: this should not be detected"
        let result = SemanticParser.classify(text)
        #expect(result.type == .commandOutput)
    }
}
