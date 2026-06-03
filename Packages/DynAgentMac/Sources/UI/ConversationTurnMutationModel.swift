import Foundation

enum ConversationTurnMutationModel {
    enum SteerResult: Equatable {
        case none
        case appended
        case completedPending
    }

    static func finishLatestPromptTurn(in messages: [ChatMessage]) {
        guard let promptIndex = latestPromptIndex(in: messages) else { return }
        complete(messages: Array(messages[promptIndex...]), includeTools: true)
    }

    static func markOpenToolsCompleted(in messages: [ChatMessage]) {
        complete(messages: messages.filter { $0.role == .tool && !$0.toolDone }, includeTools: true)
    }

    @discardableResult
    static func applySteerEvent(to conversation: Conversation, text: String? = nil) -> SteerResult {
        if let text {
            return appendPendingSteer(text: text, to: conversation)
        }
        return completePendingSteerOrAppendNotice(to: conversation)
    }

    static func latestPromptIndex(in messages: [ChatMessage]) -> Int? {
        messages.lastIndex { $0.role == .user && !($0.isSteer ?? false) }
    }

    private static func appendPendingSteer(text: String, to conversation: Conversation) -> SteerResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        if conversation.messages.last?.isSteer == true, conversation.messages.last?.text == text {
            return .none
        }

        let steer = ChatMessage(role: .user, text: text)
        steer.isSteer = true
        steer.toolDetail = "pending"
        steer.toolDone = false
        conversation.messages.append(steer)
        return .appended
    }

    private static func completePendingSteerOrAppendNotice(to conversation: Conversation) -> SteerResult {
        if let pending = conversation.messages.last(where: { $0.isSteer == true && $0.toolDetail == "pending" }) {
            pending.toolDetail = nil
            pending.toolDone = true
            return .completedPending
        }
        if conversation.messages.last?.toolName == "steer" || conversation.messages.last?.isSteer == true {
            return .none
        }

        let notice = ChatMessage(role: .tool, text: "", toolName: "steer", toolDetail: "Steered conversation")
        notice.toolDone = true
        conversation.messages.append(notice)
        return .appended
    }

    private static func complete(messages: [ChatMessage], includeTools: Bool) {
        for message in messages {
            if message.turnStatus != nil { message.turnStatus = "completed" }
            if includeTools, message.role == .tool { message.toolDone = true }
        }
    }
}
