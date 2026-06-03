import Foundation

struct SidebarArchiveConfirmationState: Equatable {
    var pendingConversationId: String?

    static let idle = SidebarArchiveConfirmationState(pendingConversationId: nil)

    var hasPendingArchive: Bool {
        pendingConversationId != nil
    }
}

enum SidebarArchiveClickAction: Equatable {
    case showConfirmation(SidebarArchiveConfirmationState)
    case confirmArchive(SidebarArchiveConfirmationState)
}

enum SidebarArchiveConfirmationModel {
    static let cancelDelay: TimeInterval = 0.55

    static func isConfirming(conversationId: String, state: SidebarArchiveConfirmationState) -> Bool {
        state.pendingConversationId == conversationId
    }

    static func clickArchive(
        conversationId: String,
        state: SidebarArchiveConfirmationState
    ) -> SidebarArchiveClickAction {
        if state.pendingConversationId == conversationId {
            return .confirmArchive(.idle)
        }
        return .showConfirmation(SidebarArchiveConfirmationState(pendingConversationId: conversationId))
    }

    static func shouldScheduleCancel(
        hovering: Bool,
        conversationId: String,
        state: SidebarArchiveConfirmationState
    ) -> Bool {
        !hovering && state.pendingConversationId == conversationId
    }

    static func shouldCancelScheduledCancel(
        hovering: Bool,
        conversationId: String,
        state: SidebarArchiveConfirmationState
    ) -> Bool {
        hovering && state.pendingConversationId == conversationId
    }

    static func cancel(state: SidebarArchiveConfirmationState) -> (state: SidebarArchiveConfirmationState, shouldReload: Bool) {
        (.idle, state.hasPendingArchive)
    }
}
