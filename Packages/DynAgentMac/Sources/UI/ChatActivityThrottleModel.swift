import Foundation

struct ChatActivityThrottleState: Equatable {
    var lastEmitByConversationId: [String: TimeInterval] = [:]
}

struct ChatActivityThrottleResult: Equatable {
    var state: ChatActivityThrottleState
    var shouldEmit: Bool
}

enum ChatActivityThrottleModel {
    static let defaultInterval: TimeInterval = 2.0

    static func planEmit(
        conversationId: String,
        force: Bool,
        now: TimeInterval,
        state: ChatActivityThrottleState,
        interval: TimeInterval = defaultInterval
    ) -> ChatActivityThrottleResult {
        if !force, let last = state.lastEmitByConversationId[conversationId], now - last < interval {
            return ChatActivityThrottleResult(state: state, shouldEmit: false)
        }

        var next = state
        next.lastEmitByConversationId[conversationId] = now
        return ChatActivityThrottleResult(state: next, shouldEmit: true)
    }
}
