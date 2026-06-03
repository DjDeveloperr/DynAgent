import Foundation

enum ChatSendAction: Equatable {
    case none
    case stop
    case startTurn(text: String)
    case sendCodexSteer(threadId: String, text: String)
    case queueSteer(text: String)

    var clearsComposer: Bool {
        switch self {
        case .startTurn, .sendCodexSteer, .queueSteer:
            return true
        case .none, .stop:
            return false
        }
    }
}

enum ChatSendModel {
    static func action(
        typedText: String,
        attachmentPaths: [String],
        streaming: Bool,
        harness: Harness,
        codexThreadId: String?
    ) -> ChatSendAction {
        let trimmedText = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = ComposerModel.messageText(typedText: trimmedText, attachmentPaths: attachmentPaths)

        guard !text.isEmpty else {
            return streaming ? .stop : .none
        }

        guard streaming else {
            return .startTurn(text: text)
        }

        if harness == .codex, let threadId = codexThreadId?.nilIfEmpty {
            return .sendCodexSteer(threadId: threadId, text: text)
        }
        return .queueSteer(text: text)
    }

    static func queuedSteerTurnText(_ queue: [String]) -> String? {
        guard !queue.isEmpty else { return nil }
        return queue.joined(separator: "\n\n")
    }
}
