import Foundation

struct AppActivityRefreshPlan: Equatable {
    var refreshSidebar: Bool
    var updateDockOnly: Bool
    var refreshQuota: Bool
    var reloadGit: Bool
    var persist: Bool
    var nextSidebarRefresh: Double?
    var nextHistoryRefresh: Double?
    var nextGitReload: Double?
}

enum AppActivityRefreshModel {
    static let sidebarActiveInterval: TimeInterval = 1.0
    static let activeHistoryInterval: TimeInterval = 8.0
    static let selectedActiveHistoryInterval: TimeInterval = 2.0

    static func activityPlan(
        isActive: Bool,
        now: Double,
        lastSidebarRefresh: Double?,
        lastHistoryRefresh: Double,
        sidebarInterval: TimeInterval = sidebarActiveInterval,
        historyInterval: TimeInterval = activeHistoryInterval
    ) -> AppActivityRefreshPlan {
        let shouldRefreshSidebar = !isActive || now - (lastSidebarRefresh ?? 0) > sidebarInterval
        let shouldRefreshHistory = !isActive || now - lastHistoryRefresh > historyInterval

        return AppActivityRefreshPlan(
            refreshSidebar: shouldRefreshSidebar,
            updateDockOnly: !shouldRefreshSidebar,
            refreshQuota: shouldRefreshHistory,
            reloadGit: !isActive,
            persist: !isActive,
            nextSidebarRefresh: shouldRefreshSidebar ? now : nil,
            nextHistoryRefresh: shouldRefreshHistory ? now : nil,
            nextGitReload: !isActive ? now : nil
        )
    }

    static func shouldRefreshSelectedActiveCodexThread(
        harness: Harness,
        status: Conversation.Status,
        hasLocalStream: Bool,
        now: Double,
        lastRefresh: Double,
        interval: TimeInterval = selectedActiveHistoryInterval
    ) -> Bool {
        guard harness == .codex else { return false }
        guard status == .thinking || status == .running else { return false }
        guard !hasLocalStream else { return false }
        return now - lastRefresh > interval
    }
}
