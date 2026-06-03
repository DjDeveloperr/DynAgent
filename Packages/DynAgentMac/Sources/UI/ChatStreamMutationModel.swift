import Foundation

struct ChatStreamAssistantResult {
    let message: ChatMessage
    let created: Bool
}

enum ChatStreamMutationModel {
    static func appendUserPrompt(_ text: String, to conversation: Conversation, startedAt: Double) -> ChatMessage {
        let user = ChatMessage(role: .user, text: text)
        user.turnStartedAt = startedAt
        user.turnStatus = "running"
        conversation.messages.append(user)
        return user
    }

    static func appendAssistantText(
        _ text: String,
        to conversation: Conversation,
        existing: ChatMessage?
    ) -> ChatStreamAssistantResult {
        let assistant: ChatMessage
        let created: Bool
        if let existing {
            assistant = existing
            created = false
        } else {
            assistant = ChatMessage(role: .assistant, text: "")
            conversation.messages.append(assistant)
            created = true
        }
        assistant.text += text
        return ChatStreamAssistantResult(message: assistant, created: created)
    }

    static func appendErrorText(
        _ error: String,
        to conversation: Conversation,
        existing: ChatMessage?,
        startedAt: Double?
    ) -> ChatStreamAssistantResult {
        let prefix = "\u{26A0}\u{FE0E} "
        let result = appendAssistantText(
            existing?.text.isEmpty == false ? "\n\(prefix)\(error)" : "\(prefix)\(error)",
            to: conversation,
            existing: existing
        )
        if result.created {
            result.message.turnStartedAt = startedAt
            result.message.turnStatus = "running"
        }
        return result
    }

    static func appendTool(
        name: String,
        detail: String?,
        to conversation: Conversation,
        startedAt: Double?
    ) -> ChatMessage {
        let tool = ChatMessage(role: .tool, text: "", toolName: name, toolDetail: detail)
        tool.turnStartedAt = startedAt
        tool.turnStatus = "running"
        conversation.messages.append(tool)
        return tool
    }

    static func completeToolResult(name: String, detail: String?, in conversation: Conversation) -> ChatMessage? {
        guard let tool = conversation.messages.last(where: { $0.role == .tool && $0.toolName == name && !$0.toolDone }) else {
            return nil
        }
        tool.toolDone = true
        tool.turnStatus = "completed"
        if let detail, !detail.isEmpty {
            tool.toolDetail = (tool.toolDetail.map { $0 + "\n\n" } ?? "") + detail
        }
        return tool
    }

    static func finishAssistantTurn(
        in conversation: Conversation,
        assistant: ChatMessage?,
        startedAt: Double?,
        now: Double = Date().timeIntervalSince1970
    ) -> ChatMessage? {
        guard let assistant else { return nil }
        assistant.timestamp = now
        assistant.turnDuration = now - (startedAt ?? now)
        assistant.turnStatus = "completed"
        assistant.isFinal = true
        ConversationTurnMutationModel.finishLatestPromptTurn(in: conversation.messages)
        return assistant
    }
}
