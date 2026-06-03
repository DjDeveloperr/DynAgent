import AppKit

final class TranscriptRowRegistry {
    private var labels: [ObjectIdentifier: MessageTextView] = [:]
    private var toolMessagesByView: [ObjectIdentifier: ChatMessage] = [:]
    private var editStatsByMessage: [ObjectIdentifier: EditStatsView] = [:]
    private var copyTextByButton: [ObjectIdentifier: String] = [:]
    private var lastLiveMarkdownRender: [ObjectIdentifier: TimeInterval] = [:]

    func reset() {
        labels.removeAll()
        toolMessagesByView.removeAll()
        editStatsByMessage.removeAll()
        copyTextByButton.removeAll()
        lastLiveMarkdownRender.removeAll()
    }

    func register(_ result: TranscriptRowBuildResult, for message: ChatMessage) {
        if let label = result.label {
            labels[ObjectIdentifier(message)] = label
        }
        if let editStats = result.editStats {
            editStatsByMessage[ObjectIdentifier(message)] = editStats
        }
        if let toolView = result.clickableToolView {
            toolMessagesByView[ObjectIdentifier(toolView)] = message
        }
    }

    func label(for message: ChatMessage) -> MessageTextView? {
        labels[ObjectIdentifier(message)]
    }

    func editStats(for message: ChatMessage) -> EditStatsView? {
        editStatsByMessage[ObjectIdentifier(message)]
    }

    func toolMessage(for view: NSView) -> ChatMessage? {
        toolMessagesByView[ObjectIdentifier(view)]
    }

    func registerCopyText(_ text: String, for button: NSButton) {
        copyTextByButton[ObjectIdentifier(button)] = text
    }

    func copyText(for button: NSButton) -> String? {
        copyTextByButton[ObjectIdentifier(button)]
    }

    func consumeLiveMarkdownRenderSlot(
        for message: ChatMessage,
        force: Bool,
        now: TimeInterval
    ) -> Bool {
        let key = ObjectIdentifier(message)
        guard TranscriptLiveUpdateModel.shouldRenderMarkdown(
            force: force,
            now: now,
            lastRenderAt: lastLiveMarkdownRender[key]
        ) else { return false }
        lastLiveMarkdownRender[key] = now
        return true
    }
}
