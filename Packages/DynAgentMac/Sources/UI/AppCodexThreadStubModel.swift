import Foundation

enum AppCodexThreadStubModel {
    static let workspaceLimit = 60
    static let projectlessLimit = 80

    static func workspaceStubs(
        threadBatches: [(cwd: String, threads: [AgentClient.CodexThread])],
        existingStubs: [Conversation],
        localConversations: [Conversation],
        archivedIds: Set<String>,
        defaultModel: String,
        limit: Int = workspaceLimit
    ) -> [Conversation] {
        let existingById = existingThreadMap(stubs: existingStubs, localConversations: localConversations)
        var stubs: [Conversation] = []
        for batch in threadBatches {
            stubs += batch.threads
                .filter { !archivedIds.contains($0.id) && $0.projectless != true }
                .map {
                    stub(
                        for: $0,
                        existingById: existingById,
                        workspace: batch.cwd,
                        defaultModel: defaultModel
                    )
                }
        }
        return Array(stubs.prefix(max(0, limit)))
    }

    static func projectlessStubs(
        threads: [AgentClient.CodexThread],
        existingStubs: [Conversation],
        archivedIds: Set<String>,
        defaultModel: String,
        fallbackWorkspace: String,
        limit: Int = projectlessLimit
    ) -> [Conversation] {
        let existingById = existingThreadMap(stubs: existingStubs, localConversations: [])
        let stubs = threads
            .filter { !archivedIds.contains($0.id) && ($0.projectless == true || $0.pinned == true) }
            .map {
                stub(
                    for: $0,
                    existingById: existingById,
                    workspace: $0.workspace ?? fallbackWorkspace,
                    defaultModel: defaultModel
                )
            }
        return Array(stubs.prefix(max(0, limit)))
    }

    static func existingThreadMap(
        stubs: [Conversation],
        localConversations: [Conversation]
    ) -> [String: Conversation] {
        var existingById: [String: Conversation] = [:]
        for conversation in stubs + localConversations {
            if let id = conversation.codexThreadId {
                existingById[id] = conversation
            }
        }
        return existingById
    }

    private static func stub(
        for thread: AgentClient.CodexThread,
        existingById: [String: Conversation],
        workspace: String,
        defaultModel: String
    ) -> Conversation {
        let conversation = existingById[thread.id] ?? Conversation(model: defaultModel, workspace: workspace, harness: .codex)
        if conversation.codexThreadId == nil {
            conversation.id = "codex:" + thread.id
        }
        let previousUpdatedAt = conversation.updatedAt
        conversation.title = thread.title
        conversation.workspace = workspace
        conversation.harness = .codex
        conversation.codexThreadId = thread.id
        conversation.pinned = thread.pinned == true
        conversation.updatedAt = thread.updatedAt
        if conversation.messages.isEmpty || thread.updatedAt > previousUpdatedAt + 1 {
            conversation.needsLoad = true
        }
        return conversation
    }
}
