import Foundation

struct MobileComposerPresentation: Equatable {
    var modelTitle: String
    var placeholder: String
    var sendSymbol: String
    var sendAccessibilityLabel: String
    var canSend: Bool
}

struct MobileToolPresentation: Equatable {
    var title: String
    var output: String
    var showsOutput: Bool
}

enum MobilePresentationModel {
    static func composer(
        model: String,
        harness: Harness,
        input: String,
        sending: Bool
    ) -> MobileComposerPresentation {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let sendState = ComposerModel.sendState(
            streaming: sending,
            trimmedText: trimmed,
            hasAttachments: false
        )
        return MobileComposerPresentation(
            modelTitle: ComposerModel.shortCodexModelName(model),
            placeholder: ComposerModel.placeholder(agent: harness),
            sendSymbol: sendState.symbol,
            sendAccessibilityLabel: sendState.accessibilityDescription,
            canSend: !sending && !trimmed.isEmpty
        )
    }

    static func tool(message: ChatMessage) -> MobileToolPresentation {
        let summary = ShellToolModel.summary(from: message.toolDetail ?? message.text)
        let title = ShellToolModel.title(
            command: summary.command.nilIfEmpty ?? message.text,
            done: message.toolDone
        )
        let displayTitle: String
        if let detail = title.detail, !detail.isEmpty {
            displayTitle = "\(title.action) \(detail)"
        } else {
            displayTitle = title.action
        }
        return MobileToolPresentation(
            title: displayTitle,
            output: summary.output,
            showsOutput: !summary.output.isEmpty
        )
    }
}
