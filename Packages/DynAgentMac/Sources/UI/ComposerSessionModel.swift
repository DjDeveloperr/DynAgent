import Foundation

struct ComposerSessionState: Equatable {
    var text: String
    var attachments: [ComposerAttachment]

    static let empty = ComposerSessionState(text: "", attachments: [])

    var placeholderHidden: Bool {
        !text.isEmpty
    }
}

enum ComposerSessionModel {
    static func addingAttachments(
        _ urls: [URL],
        to existing: [ComposerAttachment]
    ) -> (attachments: [ComposerAttachment], didChange: Bool) {
        let additions = ComposerModel.attachmentAdditions(existing: existing, incoming: urls)
        guard !additions.isEmpty else { return (existing, false) }
        return (existing + additions, true)
    }

    static func removingAttachment(
        id: UUID,
        from existing: [ComposerAttachment]
    ) -> (attachments: [ComposerAttachment], didChange: Bool) {
        let filtered = existing.filter { $0.id != id }
        return (filtered, filtered.count != existing.count)
    }

    static func restoredState(
        from snapshot: ComposerDraftSnapshot?,
        fileExists: (String) -> Bool
    ) -> ComposerSessionState {
        ComposerSessionState(
            text: snapshot?.text ?? "",
            attachments: ComposerModel.restoredAttachments(from: snapshot, fileExists: fileExists)
        )
    }

    static func clearedAfterSend() -> ComposerSessionState {
        .empty
    }
}
