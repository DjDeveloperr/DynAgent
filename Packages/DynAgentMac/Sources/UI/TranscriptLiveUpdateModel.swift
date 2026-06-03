import Foundation

struct TranscriptScrollState: Equatable {
    var lastScrollAt: TimeInterval = 0
    var hasPendingScroll = false
}

enum TranscriptScrollAction: Equatable {
    case perform(layoutBeforeScroll: Bool)
    case schedule(delay: TimeInterval)
    case ignorePending
}

struct TranscriptScrollPlan: Equatable {
    var state: TranscriptScrollState
    var action: TranscriptScrollAction
}

enum TranscriptLiveUpdateModel {
    static let markdownRenderInterval: TimeInterval = 0.45
    static let scrollInterval: TimeInterval = 0.25

    static func shouldRenderMarkdown(
        force: Bool,
        now: TimeInterval,
        lastRenderAt: TimeInterval?,
        interval: TimeInterval = markdownRenderInterval
    ) -> Bool {
        if force { return true }
        guard let lastRenderAt else { return true }
        return now - lastRenderAt >= interval
    }

    static func shouldThrottleScroll(
        streaming: Bool,
        now: TimeInterval,
        lastScrollAt: TimeInterval,
        interval: TimeInterval = scrollInterval
    ) -> Bool {
        streaming && now - lastScrollAt < interval
    }

    static func scrollPlan(
        streaming: Bool,
        now: TimeInterval,
        state: TranscriptScrollState,
        interval: TimeInterval = scrollInterval
    ) -> TranscriptScrollPlan {
        if shouldThrottleScroll(
            streaming: streaming,
            now: now,
            lastScrollAt: state.lastScrollAt,
            interval: interval
        ) {
            guard !state.hasPendingScroll else {
                return TranscriptScrollPlan(state: state, action: .ignorePending)
            }
            var next = state
            next.hasPendingScroll = true
            return TranscriptScrollPlan(state: next, action: .schedule(delay: interval))
        }

        var next = state
        next.lastScrollAt = now
        next.hasPendingScroll = false
        return TranscriptScrollPlan(
            state: next,
            action: .perform(layoutBeforeScroll: !streaming)
        )
    }

    static func pendingScrollFired(state: TranscriptScrollState) -> TranscriptScrollState {
        var next = state
        next.hasPendingScroll = false
        return next
    }
}
