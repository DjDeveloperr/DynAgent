import AppKit

@MainActor
final class ChatComposerSessionCoordinator {
    private let attachments: ComposerAttachmentCoordinator
    private weak var composer: ComposerTextView?
    private weak var placeholder: NSTextField?
    private weak var attachmentStack: NSStackView?
    private weak var attachmentScroll: NSScrollView?
    private weak var attachmentHeightConstraint: NSLayoutConstraint?
    private weak var removeTarget: AnyObject?
    private let removeAction: Selector

    init(
        attachments: ComposerAttachmentCoordinator = ComposerAttachmentCoordinator(),
        composer: ComposerTextView,
        placeholder: NSTextField,
        attachmentStack: NSStackView,
        attachmentScroll: NSScrollView,
        attachmentHeightConstraint: NSLayoutConstraint?,
        removeTarget: AnyObject,
        removeAction: Selector
    ) {
        self.attachments = attachments
        self.composer = composer
        self.placeholder = placeholder
        self.attachmentStack = attachmentStack
        self.attachmentScroll = attachmentScroll
        self.attachmentHeightConstraint = attachmentHeightConstraint
        self.removeTarget = removeTarget
        self.removeAction = removeAction
    }

    var attachmentPaths: [String] { attachments.attachmentPaths }
    var hasAttachments: Bool { attachments.hasAttachments }

    @discardableResult
    func addAttachments(_ urls: [URL], conversation: Conversation?) -> Bool {
        guard attachments.add(urls) else { return false }
        renderAttachments()
        saveDraft(for: conversation)
        return true
    }

    @discardableResult
    func removeAttachment(sender: NSButton, conversation: Conversation?) -> Bool {
        guard attachments.remove(sender: sender) else { return false }
        renderAttachments()
        saveDraft(for: conversation)
        return true
    }

    func saveDraft(for conversation: Conversation?) {
        guard let conversation, let composer else { return }
        attachments.save(text: composer.string, for: conversation)
    }

    func scheduleDraftSave(conversationProvider: @escaping () -> Conversation?) {
        attachments.scheduleSave(
            textProvider: { [weak composer] in composer?.string ?? "" },
            conversationProvider: conversationProvider
        )
    }

    func restoreDraft(for conversation: Conversation, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        let state = attachments.restore(for: conversation, fileExists: fileExists)
        apply(state)
        renderAttachments()
    }

    func clearAfterSend(for conversation: Conversation) {
        apply(attachments.clear(for: conversation))
        renderAttachments()
    }

    func renderAttachments() {
        guard let attachmentStack,
              let attachmentScroll,
              let removeTarget else { return }
        attachments.render(
            into: attachmentStack,
            inside: attachmentScroll,
            heightConstraint: attachmentHeightConstraint,
            target: removeTarget,
            removeAction: removeAction
        )
    }

    private func apply(_ state: ComposerSessionState) {
        composer?.string = state.text
        placeholder?.isHidden = state.placeholderHidden
    }
}
