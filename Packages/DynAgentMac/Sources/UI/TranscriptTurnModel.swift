import Foundation

struct TranscriptRenderTurn {
    let messages: [ChatMessage]
    let allowCollapse: Bool
    let forceActive: Bool
}

struct TranscriptTurnPlan {
    let hiddenCount: Int
    let visibleMessages: [ChatMessage]
    let turns: [TranscriptRenderTurn]
}

enum TranscriptTurnModel {
    static let defaultRecentActiveWindow: Double = 20 * 60

    static func plan(messages allMessages: [ChatMessage],
                     maxRenderedMessages: Int,
                     isActive: Bool,
                     updatedAt: Double,
                     now: Double = Date().timeIntervalSince1970) -> TranscriptTurnPlan {
        let trimmedCount = max(0, allMessages.count - maxRenderedMessages)
        let visibleMessages = trimmedCount > 0 ? Array(allMessages.suffix(maxRenderedMessages)) : allMessages
        var turns: [TranscriptRenderTurn] = []
        var i = 0

        while i < visibleMessages.count {
            var j = i + 1
            while j < visibleMessages.count && !startsPromptTurn(visibleMessages[j]) { j += 1 }
            let turn = Array(visibleMessages[i..<j])
            let isLastTurn = j >= visibleMessages.count
            let streamingLastTurn = isLastTurn && isActive
            if let final = turn.last(where: { $0.isFinal == true }), final.timestamp == nil {
                final.timestamp = updatedAt > 0 ? updatedAt : now
            }
            turns.append(TranscriptRenderTurn(
                messages: turn,
                allowCollapse: isComplete(turn, isLastTurn: isLastTurn) && !streamingLastTurn,
                forceActive: streamingLastTurn
            ))
            i = j
        }

        return TranscriptTurnPlan(hiddenCount: trimmedCount, visibleMessages: visibleMessages, turns: turns)
    }

    static func latestTurnLooksActive(conversation: Conversation,
                                      now: Double = Date().timeIntervalSince1970,
                                      recentWindow: Double = defaultRecentActiveWindow) -> Bool {
        guard conversation.updatedAt >= now - recentWindow else { return false }
        guard let promptIndex = conversation.messages.lastIndex(where: startsPromptTurn) else { return false }
        let latestTurn = conversation.messages[promptIndex...]
        if latestTurn.contains(where: { ($0.isFinal ?? false) || $0.turnStatus == "completed" }) { return false }
        return latestTurnHasRunningStatus(latestTurn)
    }

    static func latestTurnHasRunningStatus<S: Sequence>(_ messages: S) -> Bool where S.Element == ChatMessage {
        messages.contains { $0.turnStatus != nil && $0.turnStatus != "completed" }
    }

    static func activeStartedAt(messages: [ChatMessage], fallbackUpdatedAt: Double? = nil) -> Double? {
        if let started = messages.reversed().compactMap(\.turnStartedAt).first {
            return started
        }
        if let fallbackUpdatedAt, fallbackUpdatedAt > 0 {
            return fallbackUpdatedAt
        }
        return nil
    }

    private static func startsPromptTurn(_ message: ChatMessage) -> Bool {
        message.role == .user && message.isSteer != true
    }

    private static func isComplete(_ turn: [ChatMessage], isLastTurn: Bool) -> Bool {
        turn.contains { $0.isFinal == true }
            || turn.contains { $0.role == .assistant && $0.turnStatus == nil && ($0.timestamp != nil || $0.turnDuration != nil) }
            || (!isLastTurn && turn.allSatisfy { $0.turnStatus == nil })
    }
}
