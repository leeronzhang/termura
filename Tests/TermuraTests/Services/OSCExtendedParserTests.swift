import Testing
@testable import Termura

@Suite("OSCExtendedParser")
struct OSCExtendedParserTests {

    // MARK: - OSC 9

    @Test func osc9ValidMessage() {
        let payload = Array("Hello World".utf8)[...]
        let result = OSCExtendedParser.parseOSC9(payload)
        guard case .notify(let message) = result else {
            Issue.record("Expected .notify")
            return
        }
        #expect(message == "Hello World")
    }

    @Test func osc9EmptyPayload() {
        let result = OSCExtendedParser.parseOSC9([][...])
        #expect(result == nil)
    }

    // MARK: - OSC 99

    @Test func osc99StateAndValue() {
        let payload = Array("1;50".utf8)[...]
        let result = OSCExtendedParser.parseOSC99(payload)
        guard case .progress(let state, let value) = result else {
            Issue.record("Expected .progress")
            return
        }
        #expect(state == 1)
        #expect(value == 50)
    }

    @Test func osc99StateOnly() {
        let payload = Array("0".utf8)[...]
        let result = OSCExtendedParser.parseOSC99(payload)
        guard case .progress(let state, let value) = result else {
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
        guard case .notification(let title, let body) = result else {
            Issue.record("Expected .notification")
            return
        }
        #expect(title == "Title")
        #expect(body == "Body text")
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
