import Foundation

struct SearchOverlayRowModel: Equatable {
    var title: String
    var detail: String
}

enum SearchOverlayModel {
    static let defaultLimit = 14
    static let defaultMessageSearchLimit = 80

    static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func matches(
        conversations: [Conversation],
        query: String,
        limit: Int = defaultLimit,
        messageSearchLimit: Int = defaultMessageSearchLimit
    ) -> [Conversation] {
        let normalized = normalizedQuery(query)
        let filtered = conversations.filter { conversation in
            guard !normalized.isEmpty else { return true }
            if conversation.title.lowercased().contains(normalized) { return true }
            if conversation.workspace.lowercased().contains(normalized) { return true }
            return conversation.messages.suffix(max(0, messageSearchLimit)).contains {
                $0.text.lowercased().contains(normalized)
            }
        }
        return Array(filtered.sorted { $0.updatedAt > $1.updatedAt }.prefix(max(0, limit)))
    }

    static func rowModel(for conversation: Conversation) -> SearchOverlayRowModel {
        SearchOverlayRowModel(
            title: conversation.title,
            detail: ((conversation.workspace.nilIfEmpty ?? "Projectless") as NSString).lastPathComponent
        )
    }
}
