import AppKit

@MainActor
final class ChatTranscriptCoordinator {
    private let interactions: TranscriptInteractionCoordinator
    private let thinking: ChatThinkingCoordinator
    private let scrollCoordinator: TranscriptScrollCoordinator

    init(
        interactions: TranscriptInteractionCoordinator? = nil,
        thinking: ChatThinkingCoordinator? = nil,
        scrollCoordinator: TranscriptScrollCoordinator? = nil
    ) {
        self.interactions = interactions ?? TranscriptInteractionCoordinator()
        self.thinking = thinking ?? ChatThinkingCoordinator()
        self.scrollCoordinator = scrollCoordinator ?? TranscriptScrollCoordinator()
    }

    func reset() {
        interactions.reset()
        thinking.reset()
    }

    func clearRows(from transcript: NSStackView) {
        TranscriptStackChrome.removeAllRows(from: transcript)
    }

    func appendLoadingShell(text: String, to transcript: NSStackView) {
        let container = TranscriptLoadingShellChrome.makeRow(text: text)
        TranscriptStackChrome.appendFullWidthRow(container, to: transcript)
    }

    func appendLargeThreadNotice(maxRenderedMessages: Int, hiddenCount: Int, to transcript: NSStackView) {
        let container = TranscriptRowFactory.largeThreadNotice(
            maxRenderedMessages: maxRenderedMessages,
            hiddenCount: hiddenCount
        )
        TranscriptStackChrome.appendFullWidthRow(container, to: transcript)
    }

    @discardableResult
    func appendRow(
        for message: ChatMessage,
        to transcript: NSStackView,
        markdown: (String) -> NSAttributedString,
        bulkLoading: Bool
    ) -> NSView {
        interactions.appendRow(
            for: message,
            to: transcript,
            markdown: markdown,
            bulkLoading: bulkLoading,
            pinAfterAppend: { [weak self, weak transcript] in
                guard let self, let transcript else { return }
                self.pinThinkingToBottom(in: transcript)
            }
        )
    }

    func appendRowsGrouped(
        _ messages: [ChatMessage],
        collapseCompletedTools: Bool = true,
        to transcript: NSStackView,
        markdown: (String) -> NSAttributedString,
        bulkLoading: Bool
    ) -> [NSView] {
        interactions.appendRowsGrouped(
            messages,
            collapseCompletedTools: collapseCompletedTools,
            to: transcript,
            markdown: markdown,
            bulkLoading: bulkLoading,
            pinAfterAppend: { [weak self, weak transcript] in
                guard let self, let transcript else { return }
                self.pinThinkingToBottom(in: transcript)
            }
        )
    }

    func appendFinalFooter(for message: ChatMessage, to transcript: NSStackView) {
        interactions.appendFinalFooter(for: message, to: transcript)
    }

    @discardableResult
    func addWorkDivider(
        duration: Double?,
        collapsed: Bool = true,
        active: Bool = false,
        to transcript: NSStackView
    ) -> WorkDivider {
        thinking.addWorkDivider(
            duration: duration,
            collapsed: collapsed,
            active: active,
            to: transcript
        )
    }

    func setLiveDivider(_ divider: WorkDivider, for conversationId: String) {
        thinking.setLiveDivider(divider, for: conversationId)
    }

    func ensureLiveDivider(
        for conversationId: String,
        startedAt: Double,
        now: Double,
        transcript: NSStackView
    ) -> WorkDivider {
        thinking.ensureLiveDivider(
            for: conversationId,
            startedAt: startedAt,
            now: now,
            transcript: transcript
        )
    }

    func finishLiveDivider(for conversationId: String, duration: Double?) {
        thinking.finishLiveDivider(for: conversationId, duration: duration)
    }

    func showThinking(in transcript: NSStackView) {
        thinking.showThinking(in: transcript)
    }

    func hideThinking() {
        thinking.hideThinking()
    }

    func pinThinkingToBottom(in transcript: NSStackView) {
        thinking.pinThinkingToBottom(in: transcript)
    }

    func refreshCompletedTool(_ tool: ChatMessage) {
        interactions.label(for: tool)?.setRich(TranscriptToolFormatter.toolString(tool))
        if tool.toolName == "edit", let stats = interactions.editStats(for: tool) {
            let summary = TranscriptToolFormatter.editSummary(tool)
            stats.isHidden = summary.added == 0 && summary.deleted == 0
            stats.setValues(added: summary.added, deleted: summary.deleted)
        }
    }

    func renderLiveAssistant(
        _ assistant: ChatMessage,
        markdown: (String) -> NSAttributedString,
        force: Bool = false,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        guard let label = interactions.label(for: assistant),
              interactions.consumeLiveMarkdownRenderSlot(for: assistant, force: force, now: now) else { return }
        label.setRich(markdown(assistant.text))
    }

    func finalizeAssistant(_ assistant: ChatMessage, markdown: (String) -> NSAttributedString) {
        interactions.label(for: assistant)?.setRich(markdown(assistant.text))
    }

    func scrollToBottom(streaming: Bool, root: NSView, scroll: NSScrollView) {
        scrollCoordinator.scrollToBottom(
            streaming: streaming,
            root: root,
            scroll: scroll
        )
    }
}
