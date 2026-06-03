import Foundation

enum TranscriptRenderItem {
    case message(ChatMessage)
    case editGroup([EditToolChange])
    case shellGroup([ChatMessage])
}

enum TranscriptRenderModel {
    static let defaultTurnBatchSize = 6

    static func fingerprint(for conversation: Conversation, maxRenderedMessages: Int) -> Int {
        let allMessages = conversation.messages
        let visibleLimit = max(0, maxRenderedMessages)
        let trimmedCount = visibleLimit > 0 ? max(0, allMessages.count - visibleLimit) : allMessages.count
        let visibleMessages = trimmedCount > 0 ? allMessages.suffix(visibleLimit) : allMessages[...]
        var hasher = Hasher()
        hasher.combine(conversation.id)
        hasher.combine(conversation.status.rawValue)
        hasher.combine(conversation.updatedAt)
        hasher.combine(trimmedCount)
        hasher.combine(visibleMessages.count)
        for message in visibleMessages {
            hasher.combine(ObjectIdentifier(message))
            hasher.combine(message.role.rawValue)
            hasher.combine(message.text)
            hasher.combine(message.toolName)
            hasher.combine(message.toolDetail)
            hasher.combine(message.toolDone)
            hasher.combine(message.turnStartedAt)
            hasher.combine(message.turnStatus)
            hasher.combine(message.isFinal)
            hasher.combine(message.isSteer)
            hasher.combine(message.timestamp)
            hasher.combine(message.turnDuration)
        }
        return hasher.finalize()
    }

    static func batchRange(totalCount: Int, startIndex: Int, batchSize: Int = defaultTurnBatchSize) -> Range<Int>? {
        guard totalCount > 0, batchSize > 0, startIndex < totalCount else { return nil }
        return startIndex..<min(startIndex + batchSize, totalCount)
    }

    static func groupedItems(messages: [ChatMessage], collapseCompletedTools: Bool = true) -> [TranscriptRenderItem] {
        var items: [TranscriptRenderItem] = []
        var index = 0
        while index < messages.count {
            let message = messages[index]
            if message.role == .tool, message.toolName == "edit" {
                if !message.toolDone {
                    items.append(.message(message))
                    index += 1
                    continue
                }

                var changes: [EditToolChange] = []
                var cursor = index
                while cursor < messages.count,
                      messages[cursor].role == .tool,
                      messages[cursor].toolName == "edit",
                      messages[cursor].toolDone {
                    changes.append(contentsOf: EditToolModel.summary(
                        from: messages[cursor].toolDetail ?? messages[cursor].text,
                        done: messages[cursor].toolDone
                    ).changes)
                    cursor += 1
                }
                if changes.isEmpty {
                    items.append(.message(message))
                } else {
                    items.append(.editGroup(changes))
                }
                index = cursor
            } else if !collapseCompletedTools {
                items.append(.message(message))
                index += 1
            } else if message.role == .tool, message.toolName == "shell" {
                var shellMessages: [ChatMessage] = []
                var cursor = index
                while cursor < messages.count,
                      messages[cursor].role == .tool,
                      messages[cursor].toolName == "shell" {
                    shellMessages.append(messages[cursor])
                    cursor += 1
                }
                if let running = shellMessages.last(where: { !$0.toolDone }) {
                    items.append(.message(running))
                } else if shellMessages.count > 1 {
                    items.append(.shellGroup(shellMessages))
                } else if let only = shellMessages.first {
                    items.append(.message(only))
                }
                index = cursor
            } else {
                items.append(.message(message))
                index += 1
            }
        }
        return items
    }
}
