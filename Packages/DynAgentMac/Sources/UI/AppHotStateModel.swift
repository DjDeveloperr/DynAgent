import Foundation

struct AppHotState: Codable {
    var conversations: [Conversation]
    var draft: Conversation?
    var codexStubs: [String: [Conversation]]
    var workspaceRefs: [WorkspaceRef]
    var worktreesByPath: [String: [String]]
    var modelCache: [String: [String]]
    var primaryPath: String
    var active: WorkspaceRef
    var archivedCodexIds: [String]
    var selectedConversationId: String?
    var savedAt: Double
}

enum AppHotStateModel {
    static let stateKey = "DynAgentUIHotState"

    struct Restored {
        var conversations: [Conversation]
        var draft: Conversation?
        var codexStubs: [String: [Conversation]]
        var workspaceRefs: [WorkspaceRef]
        var worktreesByPath: [String: [String]]
        var modelCache: [Harness: [String]]
        var primaryPath: String
        var active: WorkspaceRef
        var archivedCodexIds: Set<String>
        var selectedConversationId: String?
    }

    static func snapshot(
        conversations: [Conversation],
        draft: Conversation?,
        codexStubs: [String: [Conversation]],
        workspaceRefs: [WorkspaceRef],
        worktreesByPath: [String: [String]],
        modelCache: [Harness: [String]],
        primaryPath: String,
        active: WorkspaceRef,
        archivedCodexIds: Set<String>,
        selectedConversationId: String?,
        savedAt: Double = Date().timeIntervalSince1970
    ) -> AppHotState {
        AppHotState(
            conversations: conversations,
            draft: draft,
            codexStubs: codexStubs,
            workspaceRefs: workspaceRefs,
            worktreesByPath: worktreesByPath,
            modelCache: Dictionary(uniqueKeysWithValues: modelCache.map { ($0.key.rawValue, $0.value) }),
            primaryPath: primaryPath,
            active: active,
            archivedCodexIds: Array(archivedCodexIds),
            selectedConversationId: selectedConversationId,
            savedAt: savedAt
        )
    }

    static func restored(from state: AppHotState) -> Restored {
        for conversation in state.conversations + state.codexStubs.values.flatMap({ $0 }) where conversation.harness == .codex {
            reconcileActiveCodexStatus(conversation)
        }

        return Restored(
            conversations: state.conversations,
            draft: state.draft,
            codexStubs: state.codexStubs,
            workspaceRefs: state.workspaceRefs.filter { !$0.path.contains("/worktrees/") },
            worktreesByPath: state.worktreesByPath,
            modelCache: Dictionary(uniqueKeysWithValues: state.modelCache.compactMap { key, value in
                guard let harness = Harness(rawValue: key) else { return nil }
                return (harness, value)
            }),
            primaryPath: state.primaryPath,
            active: state.active,
            archivedCodexIds: Set(state.archivedCodexIds),
            selectedConversationId: state.selectedConversationId
        )
    }

    static func decode(_ data: Data) -> AppHotState? {
        try? JSONDecoder().decode(AppHotState.self, from: data)
    }

    static func encode(_ state: AppHotState) -> Data? {
        try? JSONEncoder().encode(state)
    }

    private static func reconcileActiveCodexStatus(_ conversation: Conversation) {
        if TranscriptTurnModel.latestTurnLooksActive(conversation: conversation) {
            conversation.status = .running
            conversation.needsLoad = true
        } else if conversation.status == .thinking || conversation.status == .running {
            conversation.status = .idle
            conversation.needsLoad = false
        }
    }
}
