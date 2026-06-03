import XCTest
@testable import DynAgentUI

final class ConversationTurnMutationModelTests: XCTestCase {
    func testFinishLatestPromptTurnIgnoresEarlierTurnsAndSteers() {
        let firstPrompt = message(.user, "First")
        firstPrompt.turnStatus = "running"
        let oldTool = tool("shell")
        oldTool.turnStatus = "running"
        let secondPrompt = message(.user, "Second")
        secondPrompt.turnStatus = "running"
        let steer = message(.user, "Steer")
        steer.isSteer = true
        steer.turnStatus = "running"
        let activeTool = tool("edit")
        activeTool.turnStatus = "running"

        ConversationTurnMutationModel.finishLatestPromptTurn(in: [firstPrompt, oldTool, secondPrompt, steer, activeTool])

        XCTAssertEqual(firstPrompt.turnStatus, "running")
        XCTAssertFalse(oldTool.toolDone)
        XCTAssertEqual(secondPrompt.turnStatus, "completed")
        XCTAssertEqual(steer.turnStatus, "completed")
        XCTAssertEqual(activeTool.turnStatus, "completed")
        XCTAssertTrue(activeTool.toolDone)
    }

    func testMarkOpenToolsCompletedDoesNotTouchUserMessages() {
        let prompt = message(.user, "Build")
        prompt.turnStatus = "running"
        let openTool = tool("shell")
        openTool.turnStatus = "running"
        let completedTool = tool("edit")
        completedTool.turnStatus = "completed"
        completedTool.toolDone = true

        ConversationTurnMutationModel.markOpenToolsCompleted(in: [prompt, openTool, completedTool])

        XCTAssertEqual(prompt.turnStatus, "running")
        XCTAssertEqual(openTool.turnStatus, "completed")
        XCTAssertTrue(openTool.toolDone)
        XCTAssertEqual(completedTool.turnStatus, "completed")
        XCTAssertTrue(completedTool.toolDone)
    }

    func testApplySteerEventAppendsPendingUserSteerAndDedupesLastMatch() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)

        XCTAssertEqual(ConversationTurnMutationModel.applySteerEvent(to: conversation, text: "Adjust"), .appended)
        XCTAssertEqual(ConversationTurnMutationModel.applySteerEvent(to: conversation, text: "Adjust"), .none)

        XCTAssertEqual(conversation.messages.count, 1)
        XCTAssertEqual(conversation.messages[0].role, .user)
        XCTAssertEqual(conversation.messages[0].text, "Adjust")
        XCTAssertTrue(conversation.messages[0].isSteer ?? false)
        XCTAssertEqual(conversation.messages[0].toolDetail, "pending")
        XCTAssertFalse(conversation.messages[0].toolDone)
    }

    func testApplySteerEventCompletesPendingSteer() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        _ = ConversationTurnMutationModel.applySteerEvent(to: conversation, text: "Keep going")

        XCTAssertEqual(ConversationTurnMutationModel.applySteerEvent(to: conversation), .completedPending)

        XCTAssertEqual(conversation.messages.count, 1)
        XCTAssertNil(conversation.messages[0].toolDetail)
        XCTAssertTrue(conversation.messages[0].toolDone)
    }

    func testApplySteerEventAppendsCompletedNoticeWhenNoPendingSteerExists() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)
        conversation.messages.append(message(.user, "Prompt"))

        XCTAssertEqual(ConversationTurnMutationModel.applySteerEvent(to: conversation), .appended)
        XCTAssertEqual(ConversationTurnMutationModel.applySteerEvent(to: conversation), .none)

        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.messages[1].role, .tool)
        XCTAssertEqual(conversation.messages[1].toolName, "steer")
        XCTAssertEqual(conversation.messages[1].toolDetail, "Steered conversation")
        XCTAssertTrue(conversation.messages[1].toolDone)
    }

    func testBlankSteersAreIgnored() {
        let conversation = Conversation(model: "gpt-5.5", workspace: "/repo", harness: .codex)

        XCTAssertEqual(ConversationTurnMutationModel.applySteerEvent(to: conversation, text: "  \n "), .none)
        XCTAssertTrue(conversation.messages.isEmpty)
    }

    private func message(_ role: Role, _ text: String = "") -> ChatMessage {
        ChatMessage(role: role, text: text)
    }

    private func tool(_ name: String) -> ChatMessage {
        ChatMessage(role: .tool, toolName: name)
    }
}
