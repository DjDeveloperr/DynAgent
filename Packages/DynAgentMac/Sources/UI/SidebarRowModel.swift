import Foundation

struct SidebarTooltipModel: Equatable {
    var title: String
    var detail: String
}

struct SidebarWorkspaceRowModel: Equatable {
    var name: String
    var path: String
    var tooltip: SidebarTooltipModel
    var hasChats: Bool
}

struct SidebarConversationRowModel: Equatable {
    var id: String
    var title: String
    var workspaceDetail: String
    var timeLabel: String
    var isWorking: Bool
    var isThinking: Bool
    var isPinned: Bool
    var isUnread: Bool
    var isWorktree: Bool
    var tooltip: SidebarTooltipModel
}

enum SidebarRowModel {
    static func workspace(_ workspace: Workspace) -> SidebarWorkspaceRowModel {
        SidebarWorkspaceRowModel(
            name: workspace.name,
            path: workspace.path,
            tooltip: SidebarTooltipModel(title: workspace.name, detail: workspace.path),
            hasChats: !workspace.conversations.isEmpty
        )
    }

    static func conversation(_ conversation: Conversation, now: Double = Date().timeIntervalSince1970) -> SidebarConversationRowModel {
        let working = isWorking(conversation.status)
        let workspaceDetail = conversation.workspace.nilIfEmpty ?? "No workspace"
        return SidebarConversationRowModel(
            id: conversation.id,
            title: conversation.title,
            workspaceDetail: workspaceDetail,
            timeLabel: working ? workingLabel(conversation.status) : relativeTime(conversation.updatedAt, now: now),
            isWorking: working,
            isThinking: conversation.status == .thinking,
            isPinned: conversation.pinned,
            isUnread: conversation.unread,
            isWorktree: isWorktreePath(conversation.workspace),
            tooltip: SidebarTooltipModel(title: conversation.title, detail: workspaceDetail)
        )
    }

    static func isWorking(_ status: Conversation.Status) -> Bool {
        status == .thinking || status == .running
    }

    static func workingLabel(_ status: Conversation.Status) -> String {
        switch status {
        case .thinking: return "thinking"
        case .running: return "running"
        case .idle, .error: return ""
        }
    }

    static func isWorktreePath(_ path: String) -> Bool {
        path.contains("/worktrees/")
            || path.contains("/.worktrees/")
            || path.contains("/.codex/worktrees/")
    }

    static func relativeTime(_ epoch: Double, now: Double = Date().timeIntervalSince1970) -> String {
        guard epoch > 0 else { return "" }
        let delta = max(0, now - epoch)
        if delta < 45 { return "now" }
        if delta < 90 { return "1m" }
        if delta < 3600 { return "\(Int(delta / 60))m" }
        if delta < 5400 { return "1h" }
        if delta < 86_400 { return "\(Int(delta / 3600))h" }
        if delta < 172_800 { return "1d" }
        if delta < 604_800 { return "\(Int(delta / 86_400))d" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: Date(timeIntervalSince1970: epoch))
    }
}
