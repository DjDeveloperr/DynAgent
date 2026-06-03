@testable import DynAgentUI
import XCTest

final class AppCodexHistoryRefreshCoordinatorTests: XCTestCase {
    func testStartRefreshMarksThreadInFlightAndSuppressesDuplicateUntilFinish() async {
        let conversation = codexConversation(threadId: "thread-1", needsLoad: true)
        let coordinator = AppCodexHistoryRefreshCoordinator { _ in [] }

        let request = coordinator.startRefresh(for: conversation)

        XCTAssertEqual(request, AppCodexHistoryRefreshRequest(threadId: "thread-1"))
        XCTAssertTrue(coordinator.isRefreshing(threadId: "thread-1"))
        XCTAssertNil(coordinator.startRefresh(for: conversation))

        _ = await coordinator.finishRefresh(request!, applyingTo: conversation)

        XCTAssertFalse(coordinator.isRefreshing(threadId: "thread-1"))
        XCTAssertNil(coordinator.startRefresh(for: conversation))
        XCTAssertEqual(coordinator.startRefresh(for: conversation, force: true), request)
    }

    func testFinishRefreshAppliesMappedHistoryAndPreservesUpdatedAt() async {
        let conversation = codexConversation(threadId: "thread-2", needsLoad: true)
        conversation.updatedAt = 42
        let coordinator = AppCodexHistoryRefreshCoordinator { threadId in
            XCTAssertEqual(threadId, "thread-2")
            return [
                hist(role: "user", content: "Prompt", timestamp: 10),
                hist(role: "assistant", content: "Final", timestamp: 11, isFinal: true)
            ]
        }
        let request = coordinator.startRefresh(for: conversation)!

        let result = await coordinator.finishRefresh(request, applyingTo: conversation)

        XCTAssertEqual(result, AppCodexHistoryRefreshResult(
            threadId: "thread-2",
            messageCount: 2,
            status: .idle
        ))
        XCTAssertFalse(conversation.needsLoad)
        XCTAssertEqual(conversation.updatedAt, 42)
        XCTAssertEqual(conversation.messages.map(\.text), ["Prompt", "Final"])
        XCTAssertEqual(conversation.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(conversation.messages.last?.isFinal, true)
    }

    func testFinishRefreshClearsNeedsLoadAndInFlightWhenLoaderFails() async {
        let conversation = codexConversation(threadId: "thread-3", needsLoad: true)
        let coordinator = AppCodexHistoryRefreshCoordinator { _ in nil }
        let request = coordinator.startRefresh(for: conversation)!

        let result = await coordinator.finishRefresh(request, applyingTo: conversation)

        XCTAssertNil(result)
        XCTAssertFalse(conversation.needsLoad)
        XCTAssertFalse(coordinator.isRefreshing(threadId: "thread-3"))
        XCTAssertTrue(conversation.messages.isEmpty)
    }
}

private func codexConversation(threadId: String, needsLoad: Bool) -> Conversation {
    let conversation = Conversation(model: "gpt-5.5", harness: .codex)
    conversation.codexThreadId = threadId
    conversation.needsLoad = needsLoad
    return conversation
}

private func hist(
    role: String,
    content: String,
    timestamp: Double? = nil,
    isFinal: Bool? = nil
) -> AgentClient.HistMsg {
    AgentClient.HistMsg(
        role: role,
        content: content,
        toolName: nil,
        toolDetail: nil,
        toolDone: nil,
        timestamp: timestamp,
        turnDuration: nil,
        turnStartedAt: nil,
        turnStatus: nil,
        isFinal: isFinal,
        isSteer: nil
    )
}
