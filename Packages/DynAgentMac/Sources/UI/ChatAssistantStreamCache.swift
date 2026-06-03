import Foundation

final class ChatAssistantStreamCache {
    private var assistantByConversationId: [String: ChatMessage] = [:]
    private weak var visibleAssistant: ChatMessage?

    func cachedAssistant(for conversation: Conversation) -> ChatMessage? {
        assistantByConversationId[conversation.id]
    }

    @discardableResult
    func adoptVisibleAssistant(for conversation: Conversation) -> ChatMessage? {
        visibleAssistant = assistantByConversationId[conversation.id]
        return visibleAssistant
    }

    func setAssistant(_ message: ChatMessage, for conversation: Conversation, visible: Bool) {
        assistantByConversationId[conversation.id] = message
        if visible {
            visibleAssistant = message
        }
    }

    func clearAssistant(for conversation: Conversation, visible: Bool) {
        assistantByConversationId[conversation.id] = nil
        if visible {
            visibleAssistant = nil
        }
    }

    func finalizableAssistant(for conversation: Conversation, visible: Bool) -> ChatMessage? {
        assistantByConversationId[conversation.id] ?? (visible ? visibleAssistant : nil)
    }
}
