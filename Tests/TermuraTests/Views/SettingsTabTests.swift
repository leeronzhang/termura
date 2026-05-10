import Foundation
@testable import Termura
import XCTest

final class SettingsTabTests: XCTestCase {
    func testEveryCaseHasNonEmptyLabelAndSystemImage() {
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.label.isEmpty,
                           "SettingsTab.\(tab.rawValue).label must not be empty — empty labels render as a blank tab strip cell")
            XCTAssertFalse(tab.systemImage.isEmpty,
                           "SettingsTab.\(tab.rawValue).systemImage must name an SF Symbol — empty strings render as a missing-image placeholder")
        }
    }

    /// `id` is used as `ForEach` identity in the tab strip; collisions would
    /// silently dedup the strip, so guard the invariant explicitly.
    func testIdsAreUnique() {
        let ids = SettingsTab.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "SettingsTab.id values must be unique")
    }
}
