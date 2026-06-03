import AppKit

@MainActor
final class ChatThinkingCoordinator {
    private var shimmerView: ShimmerLabel?
    private var liveWorkDividerByConversationId: [String: WorkDivider] = [:]

    func reset() {
        shimmerView = nil
        liveWorkDividerByConversationId.removeAll()
    }

    @discardableResult
    func showThinking(in transcript: NSStackView) -> Bool {
        guard shimmerView == nil else { return false }
        let row = TranscriptRowChrome.thinkingRow()
        shimmerView = row.shimmer
        TranscriptStackChrome.appendFullWidthRow(row.container, to: transcript)
        return true
    }

    @discardableResult
    func hideThinking() -> Bool {
        guard let shimmerView else { return false }
        shimmerView.superview?.removeFromSuperview()
        self.shimmerView = nil
        return true
    }

    func pinThinkingToBottom(in transcript: NSStackView) {
        guard let shimmerView, let container = shimmerView.superview else { return }
        TranscriptStackChrome.moveRowToBottom(container, in: transcript)
    }

    @discardableResult
    func addWorkDivider(
        duration: Double?,
        collapsed: Bool = true,
        active: Bool = false,
        to transcript: NSStackView
    ) -> WorkDivider {
        let divider = WorkDivider(duration: duration, collapsed: collapsed, active: active)
        TranscriptStackChrome.appendFullWidthRow(divider, to: transcript)
        pinThinkingToBottom(in: transcript)
        return divider
    }

    func setLiveDivider(_ divider: WorkDivider, for conversationId: String) {
        liveWorkDividerByConversationId[conversationId] = divider
    }

    func ensureLiveDivider(
        for conversationId: String,
        startedAt: Double,
        now: Double,
        transcript: NSStackView
    ) -> WorkDivider {
        if let existing = liveWorkDividerByConversationId[conversationId] { return existing }
        let divider = addWorkDivider(
            duration: now - startedAt,
            collapsed: false,
            active: true,
            to: transcript
        )
        liveWorkDividerByConversationId[conversationId] = divider
        return divider
    }

    @discardableResult
    func finishLiveDivider(for conversationId: String, duration: Double?) -> WorkDivider? {
        guard let divider = liveWorkDividerByConversationId.removeValue(forKey: conversationId) else {
            return nil
        }
        divider.finish(duration: duration)
        return divider
    }
}
