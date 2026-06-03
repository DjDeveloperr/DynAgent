import XCTest
@testable import DynAgentUI

final class TranscriptTurnModelTests: XCTestCase {
    func testSteersDoNotStartNewTurnsButPromptsDo() {
        let firstPrompt = user("Build the app")
        let steer = user("Actually keep the app open", steer: true)
        let assistant = ChatMessage(role: .assistant, text: "Done")
        assistant.isFinal = true
        let secondPrompt = user("Now test it")

        let plan = TranscriptTurnModel.plan(
            messages: [firstPrompt, steer, assistant, secondPrompt],
            maxRenderedMessages: 20,
            isActive: false,
            updatedAt: 100
        )

        XCTAssertEqual(plan.turns.count, 2)
        XCTAssertTrue(plan.turns[0].messages[0] === firstPrompt)
        XCTAssertTrue(plan.turns[0].messages[1] === steer)
        XCTAssertTrue(plan.turns[0].messages[2] === assistant)
        XCTAssertTrue(plan.turns[1].messages[0] === secondPrompt)
    }

    func testActiveLastTurnIsForcedOpenAndNotCollapsed() {
        let prompt = user("Fix it")
        prompt.turnStatus = "running"
        let tool = ChatMessage(role: .tool, toolName: "shell", toolDetail: "$ swift test")
        tool.turnStatus = "running"

        let plan = TranscriptTurnModel.plan(
            messages: [prompt, tool],
            maxRenderedMessages: 20,
            isActive: true,
            updatedAt: 100
        )

        XCTAssertEqual(plan.turns.count, 1)
        XCTAssertFalse(plan.turns[0].allowCollapse)
        XCTAssertTrue(plan.turns[0].forceActive)
    }

    func testCompletedFinalTurnCollapsesAndGetsTimestamp() {
        let prompt = user("Summarize")
        let final = ChatMessage(role: .assistant, text: "Finished")
        final.isFinal = true

        let plan = TranscriptTurnModel.plan(
            messages: [prompt, final],
            maxRenderedMessages: 20,
            isActive: false,
            updatedAt: 1234,
            now: 9999
        )

        XCTAssertEqual(plan.turns.count, 1)
        XCTAssertTrue(plan.turns[0].allowCollapse)
        XCTAssertFalse(plan.turns[0].forceActive)
        XCTAssertEqual(final.timestamp, 1234)
    }

    func testLatestTurnLooksActiveOnlyForRecentIncompletePromptTurns() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        conversation.updatedAt = 1_000
        let prompt = user("Run tests")
        prompt.turnStatus = "running"
        let tool = ChatMessage(role: .tool, toolName: "shell", toolDetail: "$ swift test")
        tool.turnStatus = "running"
        conversation.messages = [prompt, tool]

        XCTAssertTrue(TranscriptTurnModel.latestTurnLooksActive(
            conversation: conversation,
            now: 1_010,
            recentWindow: 60
        ))

        XCTAssertFalse(TranscriptTurnModel.latestTurnLooksActive(
            conversation: conversation,
            now: 1_100,
            recentWindow: 60
        ))
    }

    func testLatestTurnLooksInactiveWhenFinalOrCompletedExists() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        conversation.updatedAt = 1_000
        let prompt = user("Finish")
        prompt.turnStatus = "running"
        let final = ChatMessage(role: .assistant, text: "Done")
        final.isFinal = true
        conversation.messages = [prompt, final]

        XCTAssertFalse(TranscriptTurnModel.latestTurnLooksActive(
            conversation: conversation,
            now: 1_010,
            recentWindow: 60
        ))

        final.isFinal = false
        final.turnStatus = "completed"
        XCTAssertFalse(TranscriptTurnModel.latestTurnLooksActive(
            conversation: conversation,
            now: 1_010,
            recentWindow: 60
        ))
    }

    func testSteersDoNotCreateActivePromptTurn() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        conversation.updatedAt = 1_000
        let steer = user("Adjust that", steer: true)
        steer.turnStatus = "running"
        conversation.messages = [steer]

        XCTAssertFalse(TranscriptTurnModel.latestTurnLooksActive(
            conversation: conversation,
            now: 1_010,
            recentWindow: 60
        ))
    }

    func testActiveStartedAtUsesLatestTurnStartThenFallbackUpdatedAt() {
        let first = ChatMessage(role: .user, text: "First")
        first.turnStartedAt = 100
        let second = ChatMessage(role: .tool, toolName: "shell")
        second.turnStartedAt = 250

        XCTAssertEqual(TranscriptTurnModel.activeStartedAt(messages: [first, second], fallbackUpdatedAt: 999), 250)
        XCTAssertEqual(TranscriptTurnModel.activeStartedAt(messages: [], fallbackUpdatedAt: 999), 999)
        XCTAssertNil(TranscriptTurnModel.activeStartedAt(messages: [], fallbackUpdatedAt: 0))
    }

    func testTrimsToMaxRenderedMessages() {
        let messages = (0..<6).map { user("Prompt \($0)") }

        let plan = TranscriptTurnModel.plan(
            messages: messages,
            maxRenderedMessages: 3,
            isActive: false,
            updatedAt: 100
        )

        XCTAssertEqual(plan.hiddenCount, 3)
        XCTAssertEqual(plan.visibleMessages.map(\.text), ["Prompt 3", "Prompt 4", "Prompt 5"])
        XCTAssertEqual(plan.turns.count, 3)
    }

    private func user(_ text: String, steer: Bool = false) -> ChatMessage {
        let message = ChatMessage(role: .user, text: text)
        message.isSteer = steer
        return message
    }
}
