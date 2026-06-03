import Foundation

enum AppCodexHistoryModel {
    static func refreshThreadId(
        for conversation: Conversation,
        force: Bool,
        inFlight: Set<String>
    ) -> String? {
        guard conversation.harness == .codex, let threadId = conversation.codexThreadId else { return nil }
        guard force || conversation.needsLoad else { return nil }
        guard force || (conversation.status != .thinking && conversation.status != .running) else { return nil }
        guard !inFlight.contains(threadId) else { return nil }
        return threadId
    }

    static func messages(from history: [AgentClient.HistMsg]) -> [ChatMessage] {
        history.map { item in
            let role = Role(rawValue: item.role) ?? .assistant
            let message = ChatMessage(
                role: role,
                text: item.content,
                toolName: item.toolName,
                toolDetail: item.toolDetail
            )
            message.toolDone = item.toolDone ?? false
            message.timestamp = item.timestamp
            message.turnDuration = item.turnDuration
            message.turnStartedAt = item.turnStartedAt
            message.turnStatus = item.turnStatus
            message.isFinal = item.isFinal
            message.isSteer = item.isSteer
            return message
        }
    }

    static func status(
        afterLoading messages: [ChatMessage],
        now: Double = Date().timeIntervalSince1970
    ) -> Conversation.Status {
        let conversation = Conversation(model: "gpt-5.5", harness: .codex)
        conversation.messages = messages
        conversation.updatedAt = latestActivityTimestamp(in: messages) ?? now
        return TranscriptTurnModel.latestTurnLooksActive(conversation: conversation, now: now) ? .running : .idle
    }

    private static func latestActivityTimestamp(in messages: [ChatMessage]) -> Double? {
        messages.reduce(nil) { latest, message in
            var candidates = [Double]()
            if let timestamp = message.timestamp { candidates.append(timestamp) }
            if let started = message.turnStartedAt { candidates.append(started) }
            if let started = message.turnStartedAt, let duration = message.turnDuration {
                candidates.append(started + duration)
            }
            guard let messageLatest = candidates.max() else { return latest }
            return max(latest ?? messageLatest, messageLatest)
        }
    }
}
