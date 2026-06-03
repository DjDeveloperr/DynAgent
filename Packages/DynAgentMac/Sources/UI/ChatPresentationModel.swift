import Foundation

enum ChatPresentationModel {
    static func shouldReuseRenderedTranscript(
        wasShowingSameConversation: Bool,
        isActive: Bool,
        renderedConversationId: String?,
        renderedFingerprint: Int?,
        conversationId: String,
        fingerprint: Int
    ) -> Bool {
        wasShowingSameConversation &&
            !isActive &&
            renderedConversationId == conversationId &&
            renderedFingerprint == fingerprint
    }

    static func loadingText(needsLoad: Bool) -> String {
        needsLoad ? "Loading latest thread..." : "Loading conversation..."
    }

    static func emptyState(messages: [ChatMessage], workspace: String?) -> (isHidden: Bool, subtitle: String) {
        let subtitle: String
        if let workspace, !workspace.isEmpty {
            subtitle = (workspace as NSString).lastPathComponent
        } else {
            subtitle = "Workspace"
        }
        return (isHidden: !messages.isEmpty, subtitle: subtitle)
    }
}
