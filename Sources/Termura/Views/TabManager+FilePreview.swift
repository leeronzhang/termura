import Foundation

// Path-based dedup across `.file` and `.preview` cases. Same physical file
// opened through different entry points (file tree text vs. binary fallback,
// harness sidebar, problems list) collapses to a single tab — without this,
// `ContentTab.id`'s case prefix would let `.file(foo.txt)` and `.preview(foo.txt)`
// coexist as two tabs for what the user perceives as one document.
// `.diff` is intentionally excluded — its visual diverges enough to warrant
// a separate tab even for the same path.

// MARK: - File / Preview tab management

extension TabManager {
    func openFileTab(path: String, name: String) {
        upsertFileOrPreviewTab(.file(path: path, name: name), forPath: path)
    }

    func openPreviewTab(path: String, name: String) {
        upsertFileOrPreviewTab(.preview(path: path, name: name), forPath: path)
    }

    private func upsertFileOrPreviewTab(_ tab: ContentTab, forPath path: String) {
        let existingIdx = openTabs.firstIndex { existing in
            switch existing {
            case let .file(existingPath, _), let .preview(existingPath, _): existingPath == path
            default: false
            }
        }
        if let existingIdx {
            openTabs[existingIdx] = tab
        } else {
            openTabs.append(tab)
        }
        selectedContentTab = tab
    }
}
