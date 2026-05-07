@testable import Termura
import Testing

@Suite("OSC133Parser")
struct OSC133ParserTests {
    // MARK: - Valid sequences

    @Test("Parses A → promptStarted")
    func parsePromptStarted() {
        let payload: [UInt8] = [UInt8(ascii: "A")]
        let event = OSC133Parser.parse(payload[...])
        guard case .promptStarted = event else {
            Issue.record("Expected .promptStarted, got \(String(describing: event))")
            return
        }
    }

    @Test("Parses B → commandStarted")
    func parseCommandStarted() {
        let payload: [UInt8] = [UInt8(ascii: "B")]
        let event = OSC133Parser.parse(payload[...])
        guard case .commandStarted = event else {
            Issue.record("Expected .commandStarted, got \(String(describing: event))")
            return
        }
    }

    @Test("Parses C → executionStarted")
    func parseExecutionStarted() {
        let payload: [UInt8] = [UInt8(ascii: "C")]
        let event = OSC133Parser.parse(payload[...])
        guard case .executionStarted = event else {
            Issue.record("Expected .executionStarted, got \(String(describing: event))")
            return
        }
    }

    @Test("Parses D (no code) → executionFinished with nil exit code")
    func parseDNoCode() {
        let payload: [UInt8] = [UInt8(ascii: "D")]
        let event = OSC133Parser.parse(payload[...])
        guard case let .executionFinished(code) = event else {
            Issue.record("Expected .executionFinished, got \(String(describing: event))")
            return
        }
        #expect(code == nil)
    }

    @Test("Parses D;0 → executionFinished exit code 0")
    func parseDWithZero() {
        let payload: [UInt8] = Array("D;0".utf8)
        let event = OSC133Parser.parse(payload[...])
        guard case let .executionFinished(code) = event else {
            Issue.record("Expected .executionFinished, got \(String(describing: event))")
            return
        }
        #expect(code == 0)
    }

    @Test("Parses D;127 → executionFinished exit code 127")
    func parseDWith127() {
        let payload: [UInt8] = Array("D;127".utf8)
        let event = OSC133Parser.parse(payload[...])
        guard case let .executionFinished(code) = event else {
            Issue.record("Expected .executionFinished, got \(String(describing: event))")
            return
        }
        #expect(code == 127)
    }

    // MARK: - Edge cases

    @Test("Unknown letter returns nil")
    func parseUnknown() {
        let payload: [UInt8] = [UInt8(ascii: "Z")]
        let event = OSC133Parser.parse(payload[...])
        #expect(event == nil)
    }

    @Test("Empty slice returns nil")
    func parseEmpty() {
        let payload: [UInt8] = []
        let event = OSC133Parser.parse(payload[...])
        #expect(event == nil)
    }

    @Test("D with semicolon but no digits returns nil exit code")
    func parseDSemicolonNoDigits() {
        let payload: [UInt8] = Array("D;".utf8)
        let event = OSC133Parser.parse(payload[...])
        guard case let .executionFinished(code) = event else {
            Issue.record("Expected .executionFinished, got \(String(describing: event))")
            return
        }
        #expect(code == nil)
    }

    // MARK: - X (Termura private metadata extension)

    @Test("X with single key=value pair → commandMetadata")
    func parseXSinglePair() {
        let payload: [UInt8] = Array("X;remoteCmdId=abc-123".utf8)
        let event = OSC133Parser.parse(payload[...])
        guard case let .commandMetadata(pairs) = event else {
            Issue.record("Expected .commandMetadata, got \(String(describing: event))")
            return
        }
        #expect(pairs == ["remoteCmdId": "abc-123"])
    }

    @Test("X with multiple key=value pairs preserves all keys")
    func parseXMultiplePairs() {
        let payload: [UInt8] = Array("X;remoteCmdId=abc;origin=ios".utf8)
        let event = OSC133Parser.parse(payload[...])
        guard case let .commandMetadata(pairs) = event else {
            Issue.record("Expected .commandMetadata, got \(String(describing: event))")
            return
        }
        #expect(pairs.count == 2)
        #expect(pairs["remoteCmdId"] == "abc")
        #expect(pairs["origin"] == "ios")
    }

    @Test("X with bare empty body → commandMetadata empty dict")
    func parseXEmpty() {
        let payload: [UInt8] = Array("X".utf8)
        let event = OSC133Parser.parse(payload[...])
        guard case let .commandMetadata(pairs) = event else {
            Issue.record("Expected .commandMetadata, got \(String(describing: event))")
            return
        }
        #expect(pairs.isEmpty)
    }

    @Test("X segments without `=` are skipped")
    func parseXSkipsMalformed() {
        let payload: [UInt8] = Array("X;novalue;remoteCmdId=ok".utf8)
        let event = OSC133Parser.parse(payload[...])
        guard case let .commandMetadata(pairs) = event else {
            Issue.record("Expected .commandMetadata, got \(String(describing: event))")
            return
        }
        #expect(pairs == ["remoteCmdId": "ok"])
    }
}
