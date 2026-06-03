import AppKit

final class TranscriptInteractionCoordinator: NSObject {
    private let registry = TranscriptRowRegistry()
    private let toolPopoverCoordinator: TranscriptToolPopoverCoordinator

    init(toolPopoverCoordinator: TranscriptToolPopoverCoordinator = TranscriptToolPopoverCoordinator()) {
        self.toolPopoverCoordinator = toolPopoverCoordinator
    }

    func reset() {
        registry.reset()
    }

    func label(for message: ChatMessage) -> MessageTextView? {
        registry.label(for: message)
    }

    func editStats(for message: ChatMessage) -> EditStatsView? {
        registry.editStats(for: message)
    }

    func consumeLiveMarkdownRenderSlot(
        for message: ChatMessage,
        force: Bool,
        now: TimeInterval
    ) -> Bool {
        registry.consumeLiveMarkdownRenderSlot(for: message, force: force, now: now)
    }

    @discardableResult
    func appendRow(
        for message: ChatMessage,
        to transcript: NSStackView,
        markdown: (String) -> NSAttributedString,
        bulkLoading: Bool,
        pinAfterAppend: () -> Void
    ) -> NSView {
        let built = TranscriptRowFactory.makeRow(for: message, markdown: markdown)
        let container = built.container
        registry.register(built, for: message)
        if let row = built.clickableToolView {
            row.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toolClicked(_:))))
        }
        TranscriptStackChrome.appendFullWidthRow(container, to: transcript, customSpacingAfter: built.customSpacingAfter)
        if !bulkLoading { pinAfterAppend() }
        return container
    }

    func appendRowsGrouped(
        _ messages: [ChatMessage],
        collapseCompletedTools: Bool = true,
        to transcript: NSStackView,
        markdown: (String) -> NSAttributedString,
        bulkLoading: Bool,
        pinAfterAppend: () -> Void
    ) -> [NSView] {
        TranscriptRenderModel.groupedItems(messages: messages, collapseCompletedTools: collapseCompletedTools).map { item in
            switch item {
            case .message(let message):
                return appendRow(
                    for: message,
                    to: transcript,
                    markdown: markdown,
                    bulkLoading: bulkLoading,
                    pinAfterAppend: pinAfterAppend
                )
            case .editGroup(let changes):
                return appendEditGroup(changes, to: transcript, bulkLoading: bulkLoading, pinAfterAppend: pinAfterAppend)
            case .shellGroup(let shellMessages):
                return appendShellGroup(shellMessages, to: transcript, bulkLoading: bulkLoading, pinAfterAppend: pinAfterAppend)
            }
        }
    }

    @discardableResult
    func appendShellGroup(
        _ messages: [ChatMessage],
        to transcript: NSStackView,
        bulkLoading: Bool,
        pinAfterAppend: () -> Void
    ) -> NSView {
        let row = TranscriptGroupedToolRowChrome.appendShellGroup(messages: messages, to: transcript)
        if !bulkLoading { pinAfterAppend() }
        return row.container
    }

    @discardableResult
    func appendEditGroup(
        _ changes: [EditToolChange],
        to transcript: NSStackView,
        bulkLoading: Bool,
        pinAfterAppend: () -> Void
    ) -> NSView {
        let row = TranscriptGroupedToolRowChrome.appendEditGroup(changes: changes, to: transcript) { [weak self] change, anchor in
            self?.toolPopoverCoordinator.presentEditChanges([change], from: anchor)
        }
        if !bulkLoading { pinAfterAppend() }
        return row.container
    }

    func appendFinalFooter(for message: ChatMessage, to transcript: NSStackView) {
        let footer = TranscriptRowChrome.finalFooter(
            text: message.text,
            timestamp: message.timestamp,
            target: self,
            copyAction: #selector(copyFinal(_:))
        )
        registry.registerCopyText(message.text, for: footer.copyButton)
        TranscriptStackChrome.appendFullWidthRow(footer.view, to: transcript)
    }

    func copyText(for button: NSButton) -> String? {
        registry.copyText(for: button)
    }

    @objc private func copyFinal(_ sender: NSButton) {
        guard let text = registry.copyText(for: sender) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func toolClicked(_ gesture: NSClickGestureRecognizer) {
        guard let view = gesture.view, let message = registry.toolMessage(for: view) else { return }
        toolPopoverCoordinator.present(
            message: message,
            from: view,
            clickPoint: gesture.location(in: view)
        )
    }
}
