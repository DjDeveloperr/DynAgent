import AppKit

final class ComposerAttachmentCoordinator {
    private let drafts: ComposerDraftCoordinator
    private var removeIds: [ObjectIdentifier: UUID] = [:]

    init(drafts: ComposerDraftCoordinator = ComposerDraftCoordinator()) {
        self.drafts = drafts
    }

    var attachmentPaths: [String] { drafts.attachmentPaths }
    var hasAttachments: Bool { drafts.hasAttachments }
    var attachments: [ComposerAttachment] { drafts.attachments }

    @discardableResult
    func add(_ urls: [URL]) -> Bool {
        drafts.addAttachments(urls).didChange
    }

    @discardableResult
    func remove(sender: NSButton) -> Bool {
        guard let id = removeIds[ObjectIdentifier(sender)] else { return false }
        return drafts.removeAttachment(id: id).didChange
    }

    func render(
        into stack: NSStackView,
        inside scroll: NSScrollView,
        heightConstraint: NSLayoutConstraint?,
        target: AnyObject,
        removeAction: Selector
    ) {
        removeIds = ComposerAttachmentStripChrome.render(
            attachments: drafts.attachments,
            into: stack,
            inside: scroll,
            heightConstraint: heightConstraint,
            target: target,
            removeAction: removeAction
        )
    }

    func save(text: String, for conversation: Conversation) {
        drafts.save(text: text, for: conversation)
    }

    func scheduleSave(
        textProvider: @escaping () -> String,
        conversationProvider: @escaping () -> Conversation?
    ) {
        drafts.scheduleSave(textProvider: textProvider, conversationProvider: conversationProvider)
    }

    func restore(for conversation: Conversation, fileExists: (String) -> Bool) -> ComposerSessionState {
        drafts.restore(for: conversation, fileExists: fileExists)
    }

    func clear(for conversation: Conversation) -> ComposerSessionState {
        drafts.clear(for: conversation)
    }
}
