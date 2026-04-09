import Foundation
import OSLog

private let persistLogger = Logger(subsystem: "com.termura.app", category: "ProjectViewModel+Persistence")

// MARK: - Expansion Persistence

extension ProjectViewModel {
    var expandedIDsKey: String {
        AppConfig.UserDefaultsKeys.fileTreeExpandedIDs(projectRoot: projectRootPath)
    }

    var hideIgnoredKey: String {
        AppConfig.UserDefaultsKeys.fileTreeHideIgnored(projectRoot: projectRootPath)
    }

    func persistExpandedIDs() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            do {
                try await self?.clock.sleep(for: AppConfig.UI.expansionPersistDebounce)
            } catch is CancellationError {
                // CancellationError is expected — a newer expansion event supersedes this persist.
                return
            } catch {
                persistLogger.debug("Expansion persist debounce interrupted: \(error.localizedDescription)")
                return
            }
            guard let self, !Task.isCancelled else { return }
            userDefaults.set(Array(expandedNodeIDs), forKey: expandedIDsKey)
        }
    }

    func restoreExpandedIDs() {
        if let saved = userDefaults.stringArray(forKey: expandedIDsKey) {
            treeManager.setExpandedNodeIDs(Set(saved))
            hasRestoredExpandState = !saved.isEmpty
        }
        // Restore ignore filter (defaults to true if not set)
        if userDefaults.object(forKey: hideIgnoredKey) != nil {
            treeManager.setHideIgnoredFiles(userDefaults.bool(forKey: hideIgnoredKey))
        }
    }

    func debouncedRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await self?.clock.sleep(for: AppConfig.Git.refreshDebounce)
            } catch is CancellationError {
                // CancellationError is expected — a newer refresh event supersedes this one.
                return
            } catch {
                persistLogger.warning("Git refresh debounce interrupted: \(error.localizedDescription)")
                return
            }
            self?.refresh()
        }
    }
}
