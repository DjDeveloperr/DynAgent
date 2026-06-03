import Foundation

struct TranscriptRenderSessionState: Equatable {
    var generation: Int = 0
    var renderedConversationId: String?
    var renderedFingerprint: Int?
    var bulkLoading: Bool = false
}

struct TranscriptRenderSessionStart: Equatable {
    var state: TranscriptRenderSessionState
    var generation: Int
    var fingerprint: Int
    var shouldReuse: Bool
}

enum TranscriptRenderSessionModel {
    static func beginShow(
        state: TranscriptRenderSessionState,
        conversation: Conversation,
        wasShowingSameConversation: Bool,
        isActive: Bool,
        maxRenderedMessages: Int
    ) -> TranscriptRenderSessionStart {
        var next = state
        next.generation += 1
        let generation = next.generation
        let fingerprint = TranscriptRenderModel.fingerprint(
            for: conversation,
            maxRenderedMessages: maxRenderedMessages
        )
        let shouldReuse = ChatPresentationModel.shouldReuseRenderedTranscript(
            wasShowingSameConversation: wasShowingSameConversation,
            isActive: isActive,
            renderedConversationId: state.renderedConversationId,
            renderedFingerprint: state.renderedFingerprint,
            conversationId: conversation.id,
            fingerprint: fingerprint
        )

        if shouldReuse {
            return TranscriptRenderSessionStart(
                state: next,
                generation: generation,
                fingerprint: fingerprint,
                shouldReuse: true
            )
        }

        next.renderedConversationId = conversation.id
        next.renderedFingerprint = fingerprint
        next.bulkLoading = true
        return TranscriptRenderSessionStart(
            state: next,
            generation: generation,
            fingerprint: fingerprint,
            shouldReuse: false
        )
    }

    static func beginLoadingShell(state: TranscriptRenderSessionState) -> TranscriptRenderSessionState {
        var next = state
        next.generation += 1
        next.renderedConversationId = nil
        next.renderedFingerprint = nil
        next.bulkLoading = false
        return next
    }

    static func shouldContinue(
        state: TranscriptRenderSessionState,
        generation: Int,
        visibleConversation: Conversation?,
        expectedConversation: Conversation
    ) -> Bool {
        generation == state.generation && visibleConversation === expectedConversation
    }

    static func batchRange(totalCount: Int, startIndex: Int) -> Range<Int>? {
        TranscriptRenderModel.batchRange(totalCount: totalCount, startIndex: startIndex)
    }

    static func finishBulkLoading(state: TranscriptRenderSessionState) -> TranscriptRenderSessionState {
        var next = state
        next.bulkLoading = false
        return next
    }
}
