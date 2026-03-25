import Foundation
import Testing
@testable import Termura

/// Tests for MetadataFormatter — extracted from SessionMetadataBarView
/// to enable real code coverage of the formatting logic.
@Suite("MetadataFormatter")
struct MetadataFormatterTests {
    // MARK: - Token count formatting

    @Test("Tokens below 1000 shown as integer")
    func tokensBelowThreshold() {
        #expect(MetadataFormatter.formatTokenCount(500) == "500")
        #expect(MetadataFormatter.formatTokenCount(0) == "0")
        #expect(MetadataFormatter.formatTokenCount(999) == "999")
    }

    @Test("Tokens at or above 1000 shown as k-format")
    func tokensAboveThreshold() {
        #expect(MetadataFormatter.formatTokenCount(1000) == "1.0k")
        #expect(MetadataFormatter.formatTokenCount(1234) == "1.2k")
        #expect(MetadataFormatter.formatTokenCount(50000) == "50.0k")
        #expect(MetadataFormatter.formatTokenCount(200000) == "200.0k")
    }

    // MARK: - Duration formatting

    @Test("Seconds only")
    func secondsOnly() {
        #expect(MetadataFormatter.formatDuration(0) == "0s")
        #expect(MetadataFormatter.formatDuration(45) == "45s")
        #expect(MetadataFormatter.formatDuration(59) == "59s")
    }

    @Test("Minutes and seconds")
    func minutesAndSeconds() {
        #expect(MetadataFormatter.formatDuration(60) == "1m 0s")
        #expect(MetadataFormatter.formatDuration(135) == "2m 15s")
        #expect(MetadataFormatter.formatDuration(3599) == "59m 59s")
    }

    @Test("Hours and minutes")
    func hoursAndMinutes() {
        #expect(MetadataFormatter.formatDuration(3600) == "1h 0m")
        #expect(MetadataFormatter.formatDuration(3661) == "1h 1m")
        #expect(MetadataFormatter.formatDuration(7200) == "2h 0m")
    }

    // MARK: - Directory abbreviation

    @Test("Home directory replaced with tilde")
    func homeReplacement() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = MetadataFormatter.abbreviateDirectory(home + "/Documents/project")
        #expect(result == "~/Documents/project")
    }

    @Test("Home directory itself becomes tilde")
    func homeItself() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = MetadataFormatter.abbreviateDirectory(home)
        #expect(result == "~")
    }

    @Test("Non-home path unchanged")
    func nonHomePath() {
        let result = MetadataFormatter.abbreviateDirectory("/usr/local/bin")
        #expect(result == "/usr/local/bin")
    }

    @Test("Empty path unchanged")
    func emptyPath() {
        let result = MetadataFormatter.abbreviateDirectory("")
        #expect(result == "")
    }
}
