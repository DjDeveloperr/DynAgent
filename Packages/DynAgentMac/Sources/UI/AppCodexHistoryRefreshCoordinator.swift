import Foundation

struct AppCodexHistoryRefreshRequest: Equatable {
    var threadId: String
}

struct AppCodexHistoryRefreshResult: Equatable {
    var threadId: String
    var messageCount: Int
    var status: Conversation.Status
}

final class AppCodexHistoryRefreshCoordinator {
    typealias HistoryLoader = (_ threadId: String) async -> [AgentClient.HistMsg]?

    private let loadHistory: HistoryLoader
    private var inFlight = Set<String>()

    init(loadHistory: @escaping HistoryLoader) {
        self.loadHistory = loadHistory
    }

    convenience init(client: AgentClient) {
        self.init { threadId in
            try? await client.codexThread(id: threadId)
        }
    }

    func startRefresh(
        for conversation: Conversation,
        force: Bool = false
    ) -> AppCodexHistoryRefreshRequest? {
        guard let threadId = AppCodexHistoryModel.refreshThreadId(
            for: conversation,
            force: force,
            inFlight: inFlight
        ) else { return nil }
        inFlight.insert(threadId)
        return AppCodexHistoryRefreshRequest(threadId: threadId)
    }

    func finishRefresh(
        _ request: AppCodexHistoryRefreshRequest,
        applyingTo conversation: Conversation
    ) async -> AppCodexHistoryRefreshResult? {
        defer {
            inFlight.remove(request.threadId)
            conversation.needsLoad = false
        }
        guard let history = await loadHistory(request.threadId) else { return nil }
        let previousUpdatedAt = conversation.updatedAt
        let messages = AppCodexHistoryModel.messages(from: history)
        conversation.messages = messages
        conversation.status = AppCodexHistoryModel.status(afterLoading: messages)
        conversation.updatedAt = previousUpdatedAt
        return AppCodexHistoryRefreshResult(
            threadId: request.threadId,
            messageCount: messages.count,
            status: conversation.status
        )
    }

    func isRefreshing(threadId: String) -> Bool {
        inFlight.contains(threadId)
    }
}
