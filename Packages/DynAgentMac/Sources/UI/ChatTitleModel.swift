import Foundation

enum ChatTitleModel {
    static let fallbackTitle = "New Chat"

    static func displayTitle(_ rawTitle: String?) -> String {
        rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallbackTitle
    }

    static func displayTitle(for conversation: Conversation?) -> String {
        displayTitle(conversation?.title)
    }
}
