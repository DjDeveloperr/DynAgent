@testable import DynAgentUI
import XCTest

final class ChatStreamEventCoordinatorTests: XCTestCase {
    func testTextEventsReuseCachedAssistantUntilCleared() {
        let c = Conversation(model: "gpt-5.5", harness: .codex)
        let coordinator = ChatStreamEventCoordinator(nowProvider: { 10 })

        let first = coordinator.handle(
            .text("hello"),
            conversation: c,
            isVisible: true,
            activeStartedAt: 2,
            consumeStoppingError: { false }
        )
        let second = coordinator.handle(
            .text(" world"),
            conversation: c,
            isVisible: true,
            activeStartedAt: 2,
            consumeStoppingError: { false }
        )

        XCTAssertNotNil(first.createdAssistant)
        XCTAssertNil(second.createdAssistant)
        XCTAssertTrue(first.shouldEmitActivity)
        XCTAssertEqual(second.assistantToRender?.text, "hello world")
        XCTAssertEqual(c.messages.count, 1)
        XCTAssertEqual(c.messages.first?.role, .assistant)
    }

    func testToolEventClosesAssistantCacheAndAppendsRunningTool() {
        let c = Conversation(model: "gpt-5.5", harness: .codex)
        let coordinator = ChatStreamEventCoordinator(nowProvider: { 20 })
        _ = coordinator.handle(.text("working"), conversation: c, isVisible: true, activeStartedAt: 5, consumeStoppingError: { false })

        let tool = coordinator.handle(
            .tool("shell", "$ pwd"),
            conversation: c,
            isVisible: true,
            activeStartedAt: 5,
            consumeStoppingError: { false }
        )
        XCTAssertTrue(tool.shouldFinalizeAssistant)
        XCTAssertEqual(tool.appendedTool?.toolName, "shell")
        XCTAssertEqual(tool.appendedTool?.toolDone, false)
        XCTAssertEqual(tool.appendedTool?.turnStartedAt, 5)
        XCTAssertEqual(c.status, .running)

        let nextText = coordinator.handle(
            .text("done"),
            conversation: c,
            isVisible: true,
            activeStartedAt: 5,
            consumeStoppingError: { false }
        )

        XCTAssertEqual(tool.appendedTool?.toolDone, true)
        XCTAssertNotNil(nextText.createdAssistant)
    }

    func testToolResultCompletesOpenToolAndRequestsForcedRefresh() {
        let c = Conversation(model: "gpt-5.5", harness: .codex)
        let coordinator = ChatStreamEventCoordinator(nowProvider: { 30 })
        _ = coordinator.handle(.tool("edit", "started"), conversation: c, isVisible: true, activeStartedAt: 10, consumeStoppingError: { false })

        let result = coordinator.handle(
            .toolResult("edit", "completed"),
            conversation: c,
            isVisible: true,
            activeStartedAt: 10,
            consumeStoppingError: { false }
        )

        XCTAssertEqual(result.completedTool?.toolName, "edit")
        XCTAssertEqual(result.completedTool?.toolDone, true)
        XCTAssertEqual(result.completedToolRefresh, .completedTool(name: "edit"))
        XCTAssertTrue(result.forceActivity)
        XCTAssertTrue(result.shouldEmitActivity)
    }

    func testDoneFinalizesAssistantWithDeterministicDurationAndFinishesConversation() {
        let c = Conversation(model: "gpt-5.5", harness: .codex)
        let coordinator = ChatStreamEventCoordinator(nowProvider: { 42 })
        _ = ChatStreamMutationModel.appendUserPrompt("prompt", to: c, startedAt: 12)
        _ = coordinator.handle(.text("answer"), conversation: c, isVisible: true, activeStartedAt: 12, consumeStoppingError: { false })

        let done = coordinator.handle(
            .done,
            conversation: c,
            isVisible: true,
            activeStartedAt: 12,
            consumeStoppingError: { false }
        )

        XCTAssertTrue(done.shouldHideThinking)
        XCTAssertTrue(done.shouldFinalizeAssistant)
        XCTAssertTrue(done.shouldFinishConversation)
        XCTAssertTrue(done.shouldScheduleStreamDoneRefresh)
        XCTAssertEqual(done.finalAssistant?.text, "answer")
        XCTAssertEqual(done.finalAssistant?.turnDuration, 30)
        XCTAssertEqual(done.finalAssistant?.turnStatus, "completed")
        XCTAssertEqual(done.finalAssistant?.isFinal, true)
        XCTAssertEqual(c.status, .idle)
    }

    func testStoppingErrorIsSuppressedWithoutMutatingConversationToError() {
        let c = Conversation(model: "gpt-5.5", harness: .codex)
        c.status = .running
        let coordinator = ChatStreamEventCoordinator(nowProvider: { 50 })

        let outcome = coordinator.handle(
            .error("cancelled"),
            conversation: c,
            isVisible: true,
            activeStartedAt: 1,
            consumeStoppingError: { true }
        )

        XCTAssertTrue(outcome.shouldHideThinking)
        XCTAssertTrue(outcome.suppressedStoppingError)
        XCTAssertFalse(outcome.shouldFinishConversation)
        XCTAssertFalse(outcome.shouldScroll)
        XCTAssertEqual(c.status, .running)
        XCTAssertTrue(c.messages.isEmpty)
    }
}
