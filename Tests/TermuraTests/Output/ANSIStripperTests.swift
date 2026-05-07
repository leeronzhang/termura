@testable import Termura
import Testing

@Suite("ANSIStripper")
struct ANSIStripperTests {
    // MARK: - Fast path

    @Test("Plain text without escape sequences passes through unchanged")
    func plainTextUnchanged() {
        let input = "Hello, world! This is plain text."
        #expect(ANSIStripper.strip(input) == input)
    }

    @Test("Empty string returns empty")
    func emptyString() {
        #expect(ANSIStripper.strip("") == "")
    }

    // MARK: - CSI sequences

    @Test("Strips single SGR color sequence")
    func stripsSingleSGR() {
        let input = "\u{1B}[32mgreen\u{1B}[0m"
        #expect(ANSIStripper.strip(input) == "green")
    }

    @Test("Strips multiple CSI sequences: bold + color + reset")
    func stripsMultipleCSI() {
        let input = "\u{1B}[1m\u{1B}[31mbold red\u{1B}[0m normal"
        #expect(ANSIStripper.strip(input) == "bold red normal")
    }

    @Test("Strips cursor movement sequences")
    func stripsCursorMovement() {
        let input = "\u{1B}[2J\u{1B}[Hcontent after clear"
        #expect(ANSIStripper.strip(input) == "content after clear")
    }

    @Test("Strips CSI with multiple parameters")
    func stripsCSIMultipleParams() {
        let input = "\u{1B}[1;31;40mtext\u{1B}[0m"
        #expect(ANSIStripper.strip(input) == "text")
    }

    // MARK: - OSC sequences

    @Test("Strips OSC terminated by BEL")
    func stripsOSCWithBEL() {
        let input = "\u{1B}]0;My Window Title\u{07}content"
        #expect(ANSIStripper.strip(input) == "content")
    }

    @Test("Strips OSC terminated by ST (ESC backslash)")
    func stripsOSCWithST() {
        let input = "\u{1B}]0;My Window Title\u{1B}\\content"
        #expect(ANSIStripper.strip(input) == "content")
    }

    // MARK: - Other escapes

    @Test("Strips character set designation sequences")
    func stripsCharsetDesignation() {
        let input = "\u{1B}(Btext after charset"
        #expect(ANSIStripper.strip(input) == "text after charset")
    }

    @Test("Strips two-byte escape sequence")
    func stripsTwoByteEscape() {
        let input = "\u{1B}Mreverse index text"
        #expect(ANSIStripper.strip(input) == "reverse index text")
    }

    // MARK: - Edge cases

    @Test("Strips interleaved ANSI and text correctly")
    func mixedANSIAndText() {
        let input = "start\u{1B}[1m bold \u{1B}[0mmiddle\u{1B}[32m green \u{1B}[0mend"
        #expect(ANSIStripper.strip(input) == "start bold middle green end")
    }

    @Test("Handles incomplete ESC at end of string")
    func incompleteESCAtEnd() {
        let input = "text\u{1B}"
        let result = ANSIStripper.strip(input)
        #expect(result == "text")
    }

    @Test("Strips adjacent sequences with no text between")
    func adjacentSequences() {
        let input = "\u{1B}[1m\u{1B}[31m\u{1B}[0m"
        #expect(ANSIStripper.strip(input) == "")
    }

    @Test("Preserves unicode, tabs, newlines, and CJK characters")
    func preservesUnicodeAndSpecial() {
        let input = "\u{1B}[32m\t\n\u{4F60}\u{597D}\u{1B}[0m"
        #expect(ANSIStripper.strip(input) == "\t\n\u{4F60}\u{597D}")
    }

    @Test("Real-world output with mixed color codes and content")
    func realWorldOutput() {
        let input = "\u{1B}[1m\u{1B}[36m>\u{1B}[0m Building project...\n\u{1B}[32mSuccess\u{1B}[0m"
        #expect(ANSIStripper.strip(input) == "> Building project...\nSuccess")
    }

    // MARK: - Property tests

    @Test("Idempotency: strip(strip(x)) == strip(x) for a realistic output corpus")
    func idempotencyCorpus() {
        let corpus: [String] = [
            // Plain text — no sequences
            "Hello, world!",
            // Single SGR
            "\u{1B}[32mgreen\u{1B}[0m",
            // Cursor movement + text
            "\u{1B}[2J\u{1B}[Hcontent after clear",
            // OSC window title (BEL)
            "\u{1B}]0;My Window\u{07}after title",
            // OSC hyperlink (ST)
            "\u{1B}]8;;https://example.com\u{1B}\\link text\u{1B}]8;;\u{1B}\\",
            // Charset designation
            "\u{1B}(Btext after charset",
            // Two-byte escape
            "\u{1B}Mreverse index",
            // CJK with color codes
            "\u{1B}[32m\u{4F60}\u{597D}\u{1B}[0m",
            // Adjacent sequences with no text between
            "\u{1B}[1m\u{1B}[31m\u{1B}[0m",
            // Mixed multi-line output
            "\u{1B}[1m\u{1B}[36m>\u{1B}[0m Building...\n\u{1B}[32mSuccess\u{1B}[0m"
        ]

        for input in corpus {
            let once = ANSIStripper.strip(input)
            let twice = ANSIStripper.strip(once)
            #expect(twice == once, "strip must be idempotent for input: \(input.prefix(40))")
        }
    }

    @Test("No ESC byte in any stripped output from realistic corpus")
    func noESCByteInStrippedOutput() {
        let corpus: [String] = [
            "\u{1B}[32mgreen\u{1B}[0m",
            "\u{1B}]0;Title\u{07}after",
            "\u{1B}(Bcharset text",
            "\u{1B}Mreverse",
            // ESC at end of string
            "text\u{1B}",
            // Multiple adjacent sequences
            "\u{1B}[1m\u{1B}[31m\u{1B}[0m",
            // OSC terminated by ST
            "\u{1B}]0;Title\u{1B}\\content"
        ]

        for input in corpus {
            let stripped = ANSIStripper.strip(input)
            let hasESC = stripped.unicodeScalars.contains { $0.value == 0x1B }
            #expect(!hasESC, "Stripped output must contain no ESC bytes for input: \(input.prefix(40))")
        }
    }

    @Test("Unclosed OSC (no BEL or ST) does not crash and strips the partial sequence")
    func malformedUnclosedOSCDoesNotCrash() {
        // OSC begins but the string ends without BEL (\u{07}) or ST (ESC \)
        let input = "\u{1B}]0;Unterminated window title"
        let result = ANSIStripper.strip(input)
        // The OSC scanner reaches endIndex and returns it; the entire string is consumed.
        #expect(result == "")
        let hasESC = result.unicodeScalars.contains { $0.value == 0x1B }
        #expect(!hasESC)
    }

    @Test("CSI with no final byte (hits end of string) does not crash")
    func malformedCSINoFinalByteDoesNotCrash() {
        // Parameter bytes 0x30-0x3F, no final byte in 0x40-0x7E
        let input = "\u{1B}[1;31"
        let result = ANSIStripper.strip(input)
        // The CSI scanner advances to endIndex; whole string is consumed.
        #expect(result == "")
        let hasESC = result.unicodeScalars.contains { $0.value == 0x1B }
        #expect(!hasESC)
    }
}
