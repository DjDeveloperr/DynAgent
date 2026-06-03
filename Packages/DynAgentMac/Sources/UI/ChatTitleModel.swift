import Foundation

enum ChatTitleModel {
    static let fallbackTitle = "New Chat"

    static func displayTitle(_ rawTitle: String?) -> String {
        rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallbackTitle
    }

    static func displayTitle(for conversation: Conversation?) -> String {
        displayTitle(conversation?.title)
    }

    static func acceptedGeneratedTitle(_ rawTitle: String?) -> String? {
        let title = displayTitle(rawTitle)
        return title == fallbackTitle ? nil : title
    }
}
