import Foundation

/// A parsed section within a harness rule file.
/// Represents a heading + its body content for granular rule management.
struct RuleSection: Identifiable, Sendable {
    let id: UUID
    /// Section heading text (e.g. "## Error Handling").
    let heading: String
    /// Heading level (1 = #, 2 = ##, etc.).
    let level: Int
    /// Body content below the heading (until the next heading of same or higher level).
    let body: String
    /// Line range in the original file (1-based, inclusive).
    let lineRange: ClosedRange<Int>

    init(
        id: UUID = UUID(),
        heading: String,
        level: Int,
        body: String,
        lineRange: ClosedRange<Int>
    ) {
        self.id = id
        self.heading = heading
        self.level = level
        self.body = body
        self.lineRange = lineRange
    }
}
