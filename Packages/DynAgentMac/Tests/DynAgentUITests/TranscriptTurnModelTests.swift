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
