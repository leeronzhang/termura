@testable import Termura
import Testing

@Suite("OSCExtendedParser")
struct OSCExtendedParserTests {
    private let attribution = " — via Termura Terminal"

    // MARK: - OSC 9

    @Test func osc9ValidMessage() {
        let payload = Array("Hello World".utf8)[...]
        let result = OSCExtendedParser.parseOSC9(payload)
        guard case let .notify(message) = result else {
            Issue.record("Expected .notify")
            return
        }
        #expect(message == "Hello World" + attribution)
    }

    @Test func osc9EmptyPayload() {
        let result = OSCExtendedParser.parseOSC9([][...])
        #expect(result == nil)
    }

    // MARK: - OSC 99

    @Test func osc99StateAndValue() {
        let payload = Array("1;50".utf8)[...]
        let result = OSCExtendedParser.parseOSC99(payload)
        guard case let .progress(state, value) = result else {
            Issue.record("Expected .progress")
            return
        }
        #expect(state == 1)
        #expect(value == 50)
    }

    @Test func osc99StateOnly() {
        let payload = Array("0".utf8)[...]
        let result = OSCExtendedParser.parseOSC99(payload)
        guard case let .progress(state, value) = result else {
            Issue.record("Expected .progress")
            return
        }
        #expect(state == 0)
        #expect(value == nil)
    }

    @Test func osc99EmptyPayload() {
        let result = OSCExtendedParser.parseOSC99([][...])
        #expect(result == nil)
    }

    // MARK: - OSC 777

    @Test func osc777ValidNotification() {
        let payload = Array("notify;Title;Body text".utf8)[...]
        let result = OSCExtendedParser.parseOSC777(payload)
        guard case let .notification(title, body) = result else {
            Issue.record("Expected .notification")
            return
        }
        #expect(title == "Title")
        #expect(body == "Body text" + attribution)
    }

    @Test func osc777MissingBody() {
        let payload = Array("notify;Title".utf8)[...]
        let result = OSCExtendedParser.parseOSC777(payload)
        #expect(result == nil)
    }

    @Test func osc777EmptyPayload() {
        let result = OSCExtendedParser.parseOSC777([][...])
        #expect(result == nil)
    }
}
