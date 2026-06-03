import AppKit

struct TranscriptGroupedToolRow {
    let container: NSView
    let content: NSView
}

enum TranscriptGroupedToolRowChrome {
    @discardableResult
    static func appendShellGroup(messages: [ChatMessage], to transcript: NSStackView) -> TranscriptGroupedToolRow {
        insertShellGroup(messages: messages, at: transcript.arrangedSubviews.count, in: transcript)
    }

    @discardableResult
    static func insertShellGroup(
        messages: [ChatMessage],
        at index: Int,
        in transcript: NSStackView
    ) -> TranscriptGroupedToolRow {
        let items = messages.map { message -> ShellGroupItem in
            let summary = TranscriptToolFormatter.shellSummary(message)
            return ShellGroupItem(
                title: TranscriptToolFormatter.shellTitle(message, summary: summary),
                output: summary.output,
                done: message.toolDone
            )
        }
        let title = TranscriptToolFormatter.shellGroupTitle(messages.map(TranscriptToolFormatter.shellSummary))
        let group = ShellGroupView(title: title, items: items)
        let container = TranscriptStackChrome.insertFullWidthContainer(
            containing: group,
            at: index,
            in: transcript,
            customSpacingAfter: TranscriptStackChrome.toolSpacingAfter
        )
        return TranscriptGroupedToolRow(container: container, content: group)
    }

    @discardableResult
    static func appendEditGroup(
        changes: [EditToolChange],
        to transcript: NSStackView,
        onOpenChange: @escaping (EditToolChange, NSView) -> Void
    ) -> TranscriptGroupedToolRow {
        insertEditGroup(
            changes: changes,
            at: transcript.arrangedSubviews.count,
            in: transcript,
            onOpenChange: onOpenChange
        )
    }

    @discardableResult
    static func insertEditGroup(
        changes: [EditToolChange],
        at index: Int,
        in transcript: NSStackView,
        onOpenChange: @escaping (EditToolChange, NSView) -> Void
    ) -> TranscriptGroupedToolRow {
        let group = EditGroupView(changes: changes)
        group.onOpenChange = onOpenChange
        let container = TranscriptStackChrome.insertFullWidthContainer(
            containing: group,
            at: index,
            in: transcript,
            customSpacingAfter: TranscriptStackChrome.toolSpacingAfter
        )
        return TranscriptGroupedToolRow(container: container, content: group)
    }
}
