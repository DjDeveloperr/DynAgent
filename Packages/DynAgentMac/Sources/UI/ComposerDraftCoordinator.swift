import Foundation

final class ComposerDraftCoordinator {
    private let store: ComposerDraftStore
    private var pendingSave: DispatchWorkItem?
    private(set) var attachments: [ComposerAttachment] = []

    init(store: ComposerDraftStore = ComposerDraftStore()) {
        self.store = store
    }

    var hasAttachments: Bool {
        !attachments.isEmpty
    }

    var attachmentPaths: [String] {
        ComposerModel.normalizedAttachmentPaths(attachments)
    }

    func addAttachments(_ urls: [URL]) -> (state: ComposerSessionState, didChange: Bool) {
        let result = ComposerSessionModel.addingAttachments(urls, to: attachments)
        guard result.didChange else {
            return (ComposerSessionState(text: "", attachments: attachments), false)
        }
        attachments = result.attachments
        return (ComposerSessionState(text: "", attachments: attachments), true)
    }

    func removeAttachment(id: UUID) -> (state: ComposerSessionState, didChange: Bool) {
        let result = ComposerSessionModel.removingAttachment(id: id, from: attachments)
        guard result.didChange else {
            return (ComposerSessionState(text: "", attachments: attachments), false)
        }
        attachments = result.attachments
        return (ComposerSessionState(text: "", attachments: attachments), true)
    }

    func restore(for conversation: Conversation, fileExists: (String) -> Bool) -> ComposerSessionState {
        pendingSave?.cancel()
        pendingSave = nil
        let state = ComposerSessionModel.restoredState(
            from: store.snapshot(for: conversation),
            fileExists: fileExists
        )
        attachments = state.attachments
        return state
    }

    func save(text: String, for conversation: Conversation) {
        pendingSave?.cancel()
        pendingSave = nil
        store.save(text: text, attachments: attachments, for: conversation)
    }

    func scheduleSave(
        textProvider: @escaping () -> String,
        conversationProvider: @escaping () -> Conversation?
    ) {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let conversation = conversationProvider() else { return }
            self.store.save(text: textProvider(), attachments: self.attachments, for: conversation)
        }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    func clear(for conversation: Conversation) -> ComposerSessionState {
        pendingSave?.cancel()
        pendingSave = nil
        attachments = []
        store.clear(for: conversation)
        return .empty
    }
}
