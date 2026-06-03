import AppKit

struct TranscriptRowBuildResult {
    var container: NSView
    var label: MessageTextView?
    var clickableToolView: NSView?
    var editStats: EditStatsView?
    var customSpacingAfter: CGFloat?
}

enum TranscriptRowFactory {
    static func makeRow(
        for message: ChatMessage,
        markdown: (String) -> NSAttributedString
    ) -> TranscriptRowBuildResult {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let content = MessageTextView()
        content.isSelectable = true
        content.translatesAutoresizingMaskIntoConstraints = false

        switch message.role {
        case .assistant:
            content.setRich(markdown(message.text))
            TranscriptRowChrome.installAssistantContent(content, in: container)
            return TranscriptRowBuildResult(container: container, label: content)

        case .user:
            if message.isSteer == true {
                TranscriptRowChrome.installSteerBubble(
                    text: message.text,
                    pending: message.toolDetail == "pending",
                    in: container
                )
                return TranscriptRowBuildResult(container: container, label: content)
            }
            TranscriptRowChrome.installUserBubble(text: message.text, in: container)
            return TranscriptRowBuildResult(container: container, label: content)

        case .tool:
            if message.toolName == "steer" {
                let detail = message.toolDetail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                TranscriptRowChrome.installSteerNotice(
                    detail: detail,
                    pending: message.toolDetail == "pending",
                    in: container
                )
                return TranscriptRowBuildResult(container: container, label: content, customSpacingAfter: 6)
            }
            if message.toolName == "shell" {
                let summary = TranscriptToolFormatter.shellSummary(message)
                let row = ShellToolView(
                    title: TranscriptToolFormatter.shellTitle(message, summary: summary),
                    output: summary.output,
                    done: message.toolDone
                )
                install(row, in: container)
                return TranscriptRowBuildResult(container: container, customSpacingAfter: 6)
            }
            content.isSelectable = false
            content.setRich(TranscriptToolFormatter.toolString(message))
            let inline = TranscriptInlineToolChrome.make(label: content, message: message)
            let row = inline.view
            install(row, in: container)
            return TranscriptRowBuildResult(
                container: container,
                label: content,
                clickableToolView: row,
                editStats: inline.editStats,
                customSpacingAfter: 6
            )
        }
    }

    static func largeThreadNotice(maxRenderedMessages: Int, hiddenCount: Int) -> NSView {
        TranscriptRowChrome.largeThreadNotice(
            maxRenderedMessages: maxRenderedMessages,
            hiddenCount: hiddenCount
        )
    }

    private static func install(_ view: NSView, in container: NSView) {
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}
