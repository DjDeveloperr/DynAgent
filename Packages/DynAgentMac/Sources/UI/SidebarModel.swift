import Foundation

struct SidebarContent {
    var workspaceRefs: [WorkspaceRef]
    var pinnedConversations: [Conversation]
    var projectlessConversations: [Conversation]
    var workspaces: [Workspace]
}

enum SidebarModel {
    static func build(
        conversations: [Conversation],
        codexStubs: [String: [Conversation]],
        workspaceRefs initialWorkspaceRefs: [WorkspaceRef],
        primaryPath: String,
        projectlessKey: String,
        archivedCodexIds: Set<String>
    ) -> SidebarContent {
        var workspaceRefs = initialWorkspaceRefs
        for conversation in conversations {
            let path = conversation.workspace
            guard !path.isEmpty, !path.contains("/worktrees/") else { continue }
            guard !workspaceRefs.contains(where: { $0.path == path }) else { continue }
            workspaceRefs.append(WorkspaceRef(name: (path as NSString).lastPathComponent, path: path))
        }

        let projectless = (codexStubs[projectlessKey] ?? [])
            .filter { !archivedCodexIds.contains($0.codexThreadId ?? "") }

        let workspaces = workspaceRefs.map { ref in
            let local = conversations.filter { ($0.workspace.isEmpty ? primaryPath : $0.workspace) == ref.path }
            let localThreadIds = Set(local.compactMap(\.codexThreadId))
            let stubs = (codexStubs[ref.path] ?? [])
                .filter { !archivedCodexIds.contains($0.codexThreadId ?? "") }
                .filter { !localThreadIds.contains($0.codexThreadId ?? "") }
            let combined = (local + stubs)
                .filter { !$0.pinned }
                .sorted { $0.updatedAt > $1.updatedAt }
            return Workspace(name: ref.name, path: ref.path, conversations: combined)
        }

        var seenPinned = Set<String>()
        let allPinnedSources = conversations + projectless + pinnedWorkspaceStubs(
            codexStubs: codexStubs,
            workspaceRefs: workspaceRefs,
            archivedCodexIds: archivedCodexIds
        )
        let pinned = allPinnedSources
            .filter(\.pinned)
            .filter { seenPinned.insert(identity(for: $0)).inserted }
            .sorted { $0.updatedAt > $1.updatedAt }

        let chats = projectless
            .filter { !$0.pinned }
            .sorted { $0.updatedAt > $1.updatedAt }

        return SidebarContent(
            workspaceRefs: workspaceRefs,
            pinnedConversations: pinned,
            projectlessConversations: chats,
            workspaces: workspaces
        )
    }

    private static func pinnedWorkspaceStubs(codexStubs: [String: [Conversation]], workspaceRefs: [WorkspaceRef], archivedCodexIds: Set<String>) -> [Conversation] {
        let workspacePaths = Set(workspaceRefs.map(\.path))
        return codexStubs
            .filter { key, _ in workspacePaths.contains(key) }
            .flatMap(\.value)
            .filter { !archivedCodexIds.contains($0.codexThreadId ?? "") }
            .filter(\.pinned)
    }

    private static func identity(for conversation: Conversation) -> String {
        conversation.codexThreadId ?? conversation.id
    }
}
