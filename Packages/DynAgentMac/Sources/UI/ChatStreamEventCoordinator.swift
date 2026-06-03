import Foundation

struct ChatStreamEventOutcome {
    var shouldHideThinking = false
    var shouldFinalizeAssistant = false
    var createdAssistant: ChatMessage?
    var assistantToRender: ChatMessage?
    var appendedTool: ChatMessage?
    var completedTool: ChatMessage?
    var completedToolRefresh: ChatToolRefreshTrigger?
    var receivedSteer = false
    var suppressedStoppingError = false
    var finalAssistant: ChatMessage?
    var shouldFinishConversation = false
    var shouldScheduleStreamDoneRefresh = false
    var shouldEmitActivity = false
    var forceActivity = false
    var shouldScroll = true
}

final class ChatStreamEventCoordinator {
    private let assistantCache: ChatAssistantStreamCache
    private let nowProvider: () -> Double

    init(
        assistantCache: ChatAssistantStreamCache = ChatAssistantStreamCache(),
        nowProvider: @escaping () -> Double = { Date().timeIntervalSince1970 }
    ) {
        self.assistantCache = assistantCache
        self.nowProvider = nowProvider
    }

    @discardableResult
    func adoptVisibleAssistant(for conversation: Conversation) -> ChatMessage? {
        assistantCache.adoptVisibleAssistant(for: conversation)
    }

    func clearAssistant(for conversation: Conversation, visible: Bool) {
        assistantCache.clearAssistant(for: conversation, visible: visible)
    }

    func finalizableAssistant(for conversation: Conversation, visible: Bool) -> ChatMessage? {
        assistantCache.finalizableAssistant(for: conversation, visible: visible)
    }

    func cachedAssistant(for conversation: Conversation) -> ChatMessage? {
        assistantCache.cachedAssistant(for: conversation)
    }

    func handle(
        _ event: AgentClient.Event,
        conversation c: Conversation,
        isVisible: Bool,
        activeStartedAt: Double?,
        consumeStoppingError: () -> Bool
    ) -> ChatStreamEventOutcome {
        var outcome = ChatStreamEventOutcome()

        switch event {
        case .thread(let id):
            c.codexThreadId = id

        case .text(let text):
            ConversationTurnMutationModel.markOpenToolsCompleted(in: c.messages)
            let result = ChatStreamMutationModel.appendAssistantText(
                text,
                to: c,
                existing: assistantCache.cachedAssistant(for: c)
            )
            if result.created {
                assistantCache.setAssistant(result.message, for: c, visible: isVisible)
                outcome.createdAssistant = result.message
            }
            outcome.assistantToRender = result.message
            outcome.shouldEmitActivity = true

        case .steer:
            outcome.receivedSteer = true

        case .tool(let name, let detail):
            ConversationTurnMutationModel.markOpenToolsCompleted(in: c.messages)
            c.status = .running
            c.updatedAt = nowProvider()
            outcome.shouldEmitActivity = true
            outcome.shouldFinalizeAssistant = true
            assistantCache.clearAssistant(for: c, visible: isVisible)
            outcome.appendedTool = ChatStreamMutationModel.appendTool(
                name: name,
                detail: detail,
                to: c,
                startedAt: activeStartedAt
            )

        case .toolResult(let name, let detail):
            guard let tool = ChatStreamMutationModel.completeToolResult(name: name, detail: detail, in: c) else {
                outcome.shouldScroll = false
                return outcome
            }
            outcome.completedTool = tool
            outcome.completedToolRefresh = .completedTool(name: tool.toolName)
            outcome.shouldEmitActivity = true
            outcome.forceActivity = true

        case .error(let error):
            outcome.shouldHideThinking = true
            guard !consumeStoppingError() else {
                outcome.suppressedStoppingError = true
                outcome.shouldScroll = false
                return outcome
            }
            let result = ChatStreamMutationModel.appendErrorText(
                error,
                to: c,
                existing: assistantCache.cachedAssistant(for: c),
                startedAt: activeStartedAt
            )
            if result.created {
                assistantCache.setAssistant(result.message, for: c, visible: isVisible)
                outcome.createdAssistant = result.message
            }
            outcome.assistantToRender = result.message
            c.status = .error
            outcome.shouldFinishConversation = true

        case .done:
            outcome.shouldHideThinking = true
            outcome.shouldFinalizeAssistant = true
            if let final = ChatStreamMutationModel.finishAssistantTurn(
                in: c,
                assistant: c.messages.last(where: { $0.role == .assistant }),
                startedAt: activeStartedAt,
                now: nowProvider()
            ) {
                outcome.finalAssistant = final
            }
            c.status = .idle
            outcome.shouldFinishConversation = true
            outcome.shouldScheduleStreamDoneRefresh = true
        }

        c.updatedAt = nowProvider()
        return outcome
    }
}
