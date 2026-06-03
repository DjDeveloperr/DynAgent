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
        insertRow(
            for: message,
            at: transcript.arrangedSubviews.count,
            in: transcript,
            markdown: markdown,
            bulkLoading: bulkLoading,
            pinAfterAppend: pinAfterAppend
        )
    }

    @discardableResult
    func insertRow(
        for message: ChatMessage,
        at index: Int,
        in transcript: NSStackView,
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
        TranscriptStackChrome.insertFullWidthRow(container, at: index, in: transcript, customSpacingAfter: built.customSpacingAfter)
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
        insertRowsGrouped(
            messages,
            collapseCompletedTools: collapseCompletedTools,
            at: transcript.arrangedSubviews.count,
            in: transcript,
            markdown: markdown,
            bulkLoading: bulkLoading,
            pinAfterAppend: pinAfterAppend
        )
    }

    func insertRowsGrouped(
        _ messages: [ChatMessage],
        collapseCompletedTools: Bool = true,
        at index: Int,
        in transcript: NSStackView,
        markdown: (String) -> NSAttributedString,
        bulkLoading: Bool,
        pinAfterAppend: () -> Void
    ) -> [NSView] {
        var insertionIndex = min(max(0, index), transcript.arrangedSubviews.count)
        return TranscriptRenderModel.groupedItems(messages: messages, collapseCompletedTools: collapseCompletedTools).map { item in
            defer { insertionIndex += 1 }
            switch item {
            case .message(let message):
                return insertRow(
                    for: message,
                    at: insertionIndex,
                    in: transcript,
                    markdown: markdown,
                    bulkLoading: bulkLoading,
                    pinAfterAppend: pinAfterAppend
                )
            case .editGroup(let changes):
                return insertEditGroup(changes, at: insertionIndex, in: transcript, bulkLoading: bulkLoading, pinAfterAppend: pinAfterAppend)
            case .shellGroup(let shellMessages):
                return insertShellGroup(shellMessages, at: insertionIndex, in: transcript, bulkLoading: bulkLoading, pinAfterAppend: pinAfterAppend)
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
        insertShellGroup(
            messages,
            at: transcript.arrangedSubviews.count,
            in: transcript,
            bulkLoading: bulkLoading,
            pinAfterAppend: pinAfterAppend
        )
    }

    @discardableResult
    func insertShellGroup(
        _ messages: [ChatMessage],
        at index: Int,
        in transcript: NSStackView,
        bulkLoading: Bool,
        pinAfterAppend: () -> Void
    ) -> NSView {
        let row = TranscriptGroupedToolRowChrome.insertShellGroup(messages: messages, at: index, in: transcript)
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
        insertEditGroup(
            changes,
            at: transcript.arrangedSubviews.count,
            in: transcript,
            bulkLoading: bulkLoading,
            pinAfterAppend: pinAfterAppend
        )
    }

    @discardableResult
    func insertEditGroup(
        _ changes: [EditToolChange],
        at index: Int,
        in transcript: NSStackView,
        bulkLoading: Bool,
        pinAfterAppend: () -> Void
    ) -> NSView {
        let row = TranscriptGroupedToolRowChrome.insertEditGroup(changes: changes, at: index, in: transcript) { [weak self] change, anchor in
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
