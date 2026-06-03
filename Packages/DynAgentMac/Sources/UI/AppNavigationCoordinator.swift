import Foundation

struct AppNavigationState: Equatable {
    var canGoBack: Bool
    var canGoForward: Bool
}

final class AppNavigationCoordinator {
    private var history = NavigationHistoryModel<Conversation>()

    var state: AppNavigationState {
        AppNavigationState(canGoBack: history.canGoBack, canGoForward: history.canGoForward)
    }

    func currentConversation(
        displayed: Conversation?,
        localConversations: [Conversation],
        codexStubs: [String: [Conversation]]
    ) -> Conversation? {
        guard let displayed else { return nil }
        if localConversations.contains(where: { $0 === displayed }) { return displayed }
        if codexStubs.values.contains(where: { conversations in
            conversations.contains(where: { $0 === displayed })
        }) {
            return displayed
        }
        return nil
    }

    @discardableResult
    func recordLeaving(
        displayed: Conversation?,
        localConversations: [Conversation],
        codexStubs: [String: [Conversation]],
        to next: Conversation?
    ) -> AppNavigationState {
        history.recordLeaving(
            current: currentConversation(
                displayed: displayed,
                localConversations: localConversations,
                codexStubs: codexStubs
            ),
            to: next
        )
        return state
    }

    func goBack(
        displayed: Conversation?,
        localConversations: [Conversation],
        codexStubs: [String: [Conversation]]
    ) -> Conversation? {
        history.goBack(
            from: currentConversation(
                displayed: displayed,
                localConversations: localConversations,
                codexStubs: codexStubs
            )
        )
    }

    func goForward(
        displayed: Conversation?,
        localConversations: [Conversation],
        codexStubs: [String: [Conversation]]
    ) -> Conversation? {
        history.goForward(
            from: currentConversation(
                displayed: displayed,
                localConversations: localConversations,
                codexStubs: codexStubs
            )
        )
    }
}
