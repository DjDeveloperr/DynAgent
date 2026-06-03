import Foundation

struct ComposerDraftStore {
    var defaults: UserDefaults
    var prefix: String

    init(defaults: UserDefaults = .standard, prefix: String = ComposerModel.defaultDraftPrefix) {
        self.defaults = defaults
        self.prefix = prefix
    }

    func key(for conversation: Conversation) -> String {
        ComposerModel.draftKey(for: conversation, prefix: prefix)
    }

    func save(text: String, attachments: [ComposerAttachment], for conversation: Conversation) {
        save(snapshot: ComposerModel.draftSnapshot(text: text, attachments: attachments), for: conversation)
    }

    func save(snapshot: ComposerDraftSnapshot, for conversation: Conversation) {
        let key = key(for: conversation)
        if snapshot.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = ComposerModel.encodeDraftSnapshot(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    func snapshot(for conversation: Conversation) -> ComposerDraftSnapshot? {
        ComposerModel.decodeDraftSnapshot(from: defaults.data(forKey: key(for: conversation)))
    }

    func restoredAttachments(for conversation: Conversation, fileExists: (String) -> Bool) -> [ComposerAttachment] {
        ComposerModel.restoredAttachments(from: snapshot(for: conversation), fileExists: fileExists)
    }

    func clear(for conversation: Conversation) {
        defaults.removeObject(forKey: key(for: conversation))
    }
}
