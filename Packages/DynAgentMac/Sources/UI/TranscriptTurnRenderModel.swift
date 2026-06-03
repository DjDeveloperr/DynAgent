import Foundation

enum TranscriptTurnRenderPlan {
    case expanded(messages: [ChatMessage])
    case collapsed(userMessages: [ChatMessage], middleMessages: [ChatMessage], finalMessage: ChatMessage)
    case active(startedAt: Double, userMessages: [ChatMessage], middleMessages: [ChatMessage])
}

enum TranscriptTurnRenderModel {
    static func plan(
        turn: [ChatMessage],
        allowCollapse: Bool,
        isConversationActive: Bool,
        forceActive: Bool,
        fallbackActiveStartedAt: Double?,
        now: Double
    ) -> TranscriptTurnRenderPlan {
        let active = forceActive || (
            isConversationActive &&
            !allowCollapse &&
            TranscriptTurnModel.latestTurnHasRunningStatus(turn)
        )
        if active {
            let startedAt = turn.compactMap(\.turnStartedAt).first ?? fallbackActiveStartedAt ?? now
            return .active(
                startedAt: startedAt,
                userMessages: nonSteerUserMessages(in: turn),
                middleMessages: turn.filter { !($0.role == .user && $0.isSteer != true) }
            )
        }

        guard allowCollapse,
              let finalIndex = finalMessageIndex(in: turn) else {
            return .expanded(messages: turn)
        }

        var userMessages: [ChatMessage] = []
        var middleMessages: [ChatMessage] = []
        for (index, message) in turn.enumerated() {
            if message.role == .user && message.isSteer != true {
                userMessages.append(message)
            } else if index == finalIndex {
                continue
            } else {
                middleMessages.append(message)
            }
        }

        return .collapsed(
            userMessages: userMessages,
            middleMessages: middleMessages,
            finalMessage: turn[finalIndex]
        )
    }

    private static func nonSteerUserMessages(in turn: [ChatMessage]) -> [ChatMessage] {
        turn.filter { $0.role == .user && $0.isSteer != true }
    }

    private static func finalMessageIndex(in turn: [ChatMessage]) -> Int? {
        turn.lastIndex {
            ($0.isFinal == true) ||
            ($0.isFinal == nil && $0.role == .assistant && !$0.text.isEmpty)
        }
    }
}
