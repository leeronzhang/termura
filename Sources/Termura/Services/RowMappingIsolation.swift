import Foundation
import OSLog

// Per-row isolation helper for GRDB row → domain-model mapping. A
// single corrupt local-DB row used to make `try rows.map { try $0.toX() }`
// throw for the whole batch — every sibling row was hidden behind
// one bad apple. This helper logs the malformed row (so it surfaces
// in `log stream`) and skips it, letting healthy rows through.
//
// Use at every `rows.map { try $0.toX() }` callsite; never `try rows.map`.

extension Sequence {
    /// Maps each element with `transform`, isolating per-element
    /// failures. Failed rows are logged via `logger.error` with
    /// `recordKind` for grep-ability and skipped from the result.
    /// Use `rowID` to surface the malformed row's primary key in the
    /// log so operators can locate it in the database.
    func compactIsolatedMap<T>(
        logger: Logger,
        recordKind: String,
        rowID: (Element) -> String? = { _ in nil },
        transform: (Element) throws -> T
    ) -> [T] {
        var result: [T] = []
        for element in self {
            do {
                let mapped = try transform(element)
                result.append(mapped)
            } catch {
                let id = rowID(element) ?? "<unknown>"
                let reason = error.localizedDescription
                logger.error(
                    "Skipping malformed \(recordKind, privacy: .public) row id=\(id, privacy: .public): \(reason, privacy: .public)"
                )
            }
        }
        return result
    }
}
