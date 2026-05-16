import SwiftUI

/// Submenu view-builders for AppCommands. Extracted so AppCommands.swift
/// stays inside the soft file-size budget (CLAUDE.md §6.1).
extension AppCommands {
    @ViewBuilder
    var newBranchMenu: some View {
        Menu("New Branch") {
            ForEach(BranchType.allCases.filter { $0 != .main }, id: \.self) { type in
                Button(type.rawValue.capitalized) {
                    dispatcher.createBranch(type: type)
                }
            }
        }
    }

    /// File ▸ Open Recent submenu. Lists existence-filtered recents from
    /// `RecentProjectsService`; clicking a row routes through
    /// `ProjectCoordinator.openProject(at:)`, which restores the existing
    /// window when the project is already open. Disabled when empty.
    @ViewBuilder
    var openRecentMenu: some View {
        let recents = dispatcher.recentProjects()
        Menu("Open Recent") {
            ForEach(recents, id: \.path) { project in
                Button(project.displayName) {
                    dispatcher.openProject(at: URL(fileURLWithPath: project.path))
                }
            }
            if !recents.isEmpty {
                Divider()
                Button("Clear Menu") {
                    dispatcher.clearRecentProjects()
                }
            }
        }
        .disabled(recents.isEmpty)
    }
}
