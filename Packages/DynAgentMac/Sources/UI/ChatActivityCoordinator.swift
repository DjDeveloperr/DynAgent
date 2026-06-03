import Foundation

final class ChatActivityCoordinator {
    typealias Scheduler = (_ delay: TimeInterval, _ item: DispatchWorkItem) -> Void

    private var throttleState = ChatActivityThrottleState()
    private var pendingToolRefreshByConversationId: [String: DispatchWorkItem] = [:]
    private let now: () -> TimeInterval
    private let scheduler: Scheduler

    init(
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
        scheduler: @escaping Scheduler = { delay, item in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    ) {
        self.now = now
        self.scheduler = scheduler
    }

    func emitActivity(
        for conversation: Conversation,
        force: Bool = false,
        onActivity: ((Conversation) -> Void)?
    ) {
        let result = ChatActivityThrottleModel.planEmit(
            conversationId: conversation.id,
            force: force,
            now: now(),
            state: throttleState
        )
        throttleState = result.state
        guard result.shouldEmit else { return }
        onActivity?(conversation)
    }

    func scheduleToolRefresh(
        for conversation: Conversation,
        trigger: ChatToolRefreshTrigger,
        isVisible: Bool,
        isActive: Bool,
        shouldRefresh: @escaping () -> Bool,
        refresh: @escaping (Conversation) -> Void
    ) {
        guard ChatToolRefreshModel.shouldScheduleRefresh(
            trigger: trigger,
            isVisible: isVisible,
            isActive: isActive
        ) else { return }
        pendingToolRefreshByConversationId[conversation.id]?.cancel()
        let item = DispatchWorkItem { [weak conversation] in
            guard let conversation, shouldRefresh() else { return }
            refresh(conversation)
        }
        pendingToolRefreshByConversationId[conversation.id] = item
        scheduler(ChatToolRefreshModel.delay, item)
    }
}
