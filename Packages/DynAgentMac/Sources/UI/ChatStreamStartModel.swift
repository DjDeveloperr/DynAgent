import Foundation

struct ChatStreamStartResult {
    let userMessage: ChatMessage?
    let startedAt: Double
    let shouldGenerateTitle: Bool
}

enum ChatStreamStartModel {
    static func prepareTurn(
        text: String,
        conversation: Conversation,
        harness: Harness,
        model: String,
        appendUser: Bool,
        now: Double
    ) -> ChatStreamStartResult {
        conversation.harness = harness
        conversation.model = model

        let userMessage: ChatMessage?
        if appendUser {
            userMessage = ChatStreamMutationModel.appendUserPrompt(text, to: conversation, startedAt: now)
        } else {
            userMessage = nil
        }

        let shouldGenerateTitle = conversation.messages.filter { $0.role == .user && $0.isSteer != true }.count == 1
        conversation.status = .thinking
        conversation.updatedAt = now

        return ChatStreamStartResult(
            userMessage: userMessage,
            startedAt: now,
            shouldGenerateTitle: appendUser && shouldGenerateTitle
        )
    }
}
