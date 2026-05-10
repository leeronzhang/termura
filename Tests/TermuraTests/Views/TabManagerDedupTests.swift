import Foundation
@testable import Termura
import Testing

/// Cross-case dedup for file/preview tabs. Same physical file opened via different
/// entry points (file tree as text vs. binary, harness sidebar, problems list)
/// must produce a single tab.
@MainActor
@Suite("TabManager: file/preview dedup")
struct TabManagerDedupTests {
    @Test("Opening the same path as .file then .preview keeps a single tab (preview wins)")
    func filePreviewSamePathCollapses() {
        let manager = TabManager()
        manager.openFileTab(path: "foo.txt", name: "foo.txt")
        manager.openPreviewTab(path: "foo.txt", name: "foo.txt")

        #expect(manager.openTabs.count == 1)
        if case .preview = manager.openTabs[0] {
            // ok
        } else {
            Issue.record("expected last opened case .preview to win, got \(manager.openTabs[0])")
        }
        #expect(manager.selectedContentTab == manager.openTabs[0])
    }

    @Test("Opening the same path as .preview then .file keeps a single tab (file wins)")
    func previewFileSamePathCollapses() {
        let manager = TabManager()
        manager.openPreviewTab(path: "foo.bin", name: "foo.bin")
        manager.openFileTab(path: "foo.bin", name: "foo.bin")

        #expect(manager.openTabs.count == 1)
        if case .file = manager.openTabs[0] {
            // ok
        } else {
            Issue.record("expected last opened case .file to win, got \(manager.openTabs[0])")
        }
    }

    @Test("Different paths stay as separate tabs")
    func differentPathsRemainSeparate() {
        let manager = TabManager()
        manager.openFileTab(path: "a.txt", name: "a.txt")
        manager.openFileTab(path: "b.txt", name: "b.txt")

        #expect(manager.openTabs.count == 2)
    }

    @Test("Diff tab and file tab on the same path coexist (diff is intentionally excluded from dedup)")
    func diffAndFileSamePathCoexist() {
        let manager = TabManager()
        manager.openFileTab(path: "foo.swift", name: "foo.swift")
        manager.openDiffTab(path: "foo.swift", staged: false)

        #expect(manager.openTabs.count == 2)
    }

    @Test("Re-opening the same .file tab updates name in place without duplicating")
    func reopeningFileTabUpdatesInPlace() {
        let manager = TabManager()
        manager.openFileTab(path: "foo.txt", name: "old-name.txt")
        manager.openFileTab(path: "foo.txt", name: "new-name.txt")

        #expect(manager.openTabs.count == 1)
        #expect(manager.openTabs[0].title == "new-name.txt")
    }
}
