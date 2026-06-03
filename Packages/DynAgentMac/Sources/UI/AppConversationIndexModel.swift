import Foundation

struct DockRecentConversation: Equatable {
    var id: String
    var title: String
    var workspace: String
    var updatedAt: Double

    var dictionary: [String: Any] {
        [
            "id": id,
            "title": title,
            "workspace": workspace,
            "updatedAt": updatedAt,
        ]
    }
}

enum AppConversationIndexModel {
    static let defaultDockRecentLimit = 12

    static func visibleConversations(
        local: [Conversation],
        codexStubs: [String: [Conversation]]
    ) -> [Conversation] {
        var seen = Set<String>()
        var out: [Conversation] = []
        for conversation in local + codexStubs.values.flatMap({ $0 }) {
            let key = identity(for: conversation)
            guard seen.insert(key).inserted else { continue }
            out.append(conversation)
        }
        return out
    }

    static func restoredConversation(
        selectedId: String?,
        conversations: [Conversation],
        codexStubs: [String: [Conversation]],
        draft: Conversation?
    ) -> Conversation? {
        let candidates = conversations + codexStubs.values.flatMap { $0 } + (draft.map { [$0] } ?? [])
        if let selectedId,
           let selected = candidates.first(where: { $0.id == selectedId || $0.codexThreadId == selectedId }) {
            return selected
        }
        return candidates.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    static func dockRecent(
        conversations: [Conversation],
        limit: Int = defaultDockRecentLimit
    ) -> [DockRecentConversation] {
        conversations
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(max(0, limit))
            .map { conversation in
                DockRecentConversation(
                    id: conversation.id,
                    title: ChatTitleModel.displayTitle(for: conversation),
                    workspace: conversation.workspace,
                    updatedAt: conversation.updatedAt
                )
            }
    }

    static func unreadFinishedCount(_ conversations: [Conversation]) -> Int {
        conversations.filter {
            $0.unread && $0.status != .thinking && $0.status != .running
        }.count
    }

    private static func identity(for conversation: Conversation) -> String {
        conversation.codexThreadId ?? conversation.id
    }
}
