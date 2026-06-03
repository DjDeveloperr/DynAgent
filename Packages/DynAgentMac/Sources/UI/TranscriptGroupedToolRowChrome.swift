import AppKit

struct TranscriptGroupedToolRow {
    let container: NSView
    let content: NSView
}

enum TranscriptGroupedToolRowChrome {
    @discardableResult
    static func appendShellGroup(messages: [ChatMessage], to transcript: NSStackView) -> TranscriptGroupedToolRow {
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
        let container = TranscriptStackChrome.appendFullWidthContainer(containing: group, to: transcript)
        return TranscriptGroupedToolRow(container: container, content: group)
    }

    @discardableResult
    static func appendEditGroup(
        changes: [EditToolChange],
        to transcript: NSStackView,
        onOpenChange: @escaping (EditToolChange, NSView) -> Void
    ) -> TranscriptGroupedToolRow {
        let group = EditGroupView(changes: changes)
        group.onOpenChange = onOpenChange
        let container = TranscriptStackChrome.appendFullWidthContainer(containing: group, to: transcript)
        return TranscriptGroupedToolRow(container: container, content: group)
    }
}
