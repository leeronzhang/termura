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
}
