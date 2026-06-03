import Foundation

enum AppConversationDisplayMode: Equatable {
    case renderCached
    case loadingShellAndRefresh(force: Bool)
}

enum AppConversationDisplayModel {
    static func mode(needsLoad: Bool, status: Conversation.Status) -> AppConversationDisplayMode {
        guard needsLoad else { return .renderCached }
        return .loadingShellAndRefresh(force: status == .thinking || status == .running)
    }
}
